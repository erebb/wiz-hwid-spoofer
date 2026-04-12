#!/usr/bin/env python3
"""
download_assets.py — Wizard101 oyun dosyalarını KingsIsle patch sunucusundan indirir.
naydevops/wizard projesinin Python uyarlaması (MIT lisansı).

Özellikler:
  - Rate limit koruması: 429 / 503 gelince exponential backoff ile bekler
  - Crash-safe resume: indirme .tmp dosyasına yazılır, bitince rename edilir
      → Program kapansa bile tamamlananlar korunur, yarımdakiler kaldığı yerden devam
  - Paralel indirme: MAX_WORKERS kadar eş zamanlı bağlantı (varsayılan 3)
  - macOS otomatik path tespiti (Whisky / Bottles / doğrudan prefix)

Kullanım:
  python3 w101d/download_assets.py          # otomatik path
  python3 w101d/download_assets.py /path/to/GameData
"""

import os
import sys
import time
import pathlib
import threading
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Optional

# ── Ayarlar ──────────────────────────────────────────────────────────────────
PATCH_HOST    = "versionak.us.wizard101.com"
FILE_LIST_URL = f"http://{PATCH_HOST}/Windows/LatestFileList.bin"
DOWNLOAD_BASE = f"http://{PATCH_HOST}/LatestBuild/Data/GameData/"

# Dosya listesinde yer almayan ama gerekli dosyalar (AdditionalFiles.txt'ten)
EXTRA_FILES = ["Mob-WorldData.wad", "Music-WorldData.wad"]

MAX_WORKERS   = 3      # Eş zamanlı maksimum indirme
MAX_RETRIES   = 6      # Her dosya için maksimum deneme sayısı
BACKOFF_BASE  = 2.0    # Exponential backoff çarpanı (saniye)
REQUEST_DELAY = 0.4    # Her istek arasındaki minimum bekleme (saniye)
CHUNK_SIZE    = 64 * 1024  # 64 KB okuma bloğu

# ── Rate limit kilidi ─────────────────────────────────────────────────────────
_rate_lock = threading.Lock()
_last_req  = [0.0]

def _throttle():
    """İstekler arasında REQUEST_DELAY kadar bekler."""
    with _rate_lock:
        now  = time.monotonic()
        wait = REQUEST_DELAY - (now - _last_req[0])
        if wait > 0:
            time.sleep(wait)
        _last_req[0] = time.monotonic()


# ── Path tespiti ──────────────────────────────────────────────────────────────
def find_game_data_dir() -> Optional[pathlib.Path]:
    """Wizard101 GameData dizinini otomatik bulur."""
    env = os.environ.get("WIZ_DATA_DIR", "").strip()
    if env and pathlib.Path(env).is_dir():
        return pathlib.Path(env)

    home = pathlib.Path.home()
    lib  = home / "Library" / "Application Support" / "Wizard101"

    candidates = [
        lib / "Bottles" / "wizard101" / "drive_c" /
            "ProgramData" / "KingsIsle Entertainment" / "Wizard101" / "Data" / "GameData",
        lib / "drive_c" /
            "ProgramData" / "KingsIsle Entertainment" / "Wizard101" / "Data" / "GameData",
        lib / "Bottles" / "wizard101" / "drive_c" /
            "Program Files" / "Wizard101" / "Data" / "GameData",
        lib / "drive_c" / "Program Files" / "Wizard101" / "Data" / "GameData",
    ]
    for c in candidates:
        if c.parent.exists():
            return c
    return None


# ── Dosya listesi indirme ─────────────────────────────────────────────────────
def fetch_file_list() -> bytes:
    print(f"[setup] Dosya listesi alınıyor: {FILE_LIST_URL}")
    req = urllib.request.Request(FILE_LIST_URL, headers={"User-Agent": "WizPatcher/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


# ── Dosya listesi ayrıştırma ─────────────────────────────────────────────────
def parse_file_list(data: bytes) -> list:
    """LatestFileList.bin'den Data/GameData/ dosya isimlerini çıkarır."""
    PREFIX  = "Data/GameData/"
    results = set()
    buf     = []

    def _flush():
        if not buf:
            return
        s = "".join(buf)
        buf.clear()
        if PREFIX not in s:
            return
        idx      = s.find(PREFIX)
        filename = s[idx + len(PREFIX):].split("\x00")[0].strip()
        if filename and "." in filename and len(filename) > 3:
            results.add(filename)

    for byte in data:
        if 32 <= byte <= 126:
            buf.append(chr(byte))
        else:
            _flush()
    _flush()

    return sorted(results | set(EXTRA_FILES))


# ── Tek dosya indirme ─────────────────────────────────────────────────────────
def download_one(filename: str, dest: pathlib.Path, idx: int, total: int) -> tuple:
    """
    Tek bir dosyayı crash-safe indirir.

    Strateji (.tmp yaklaşımı):
      - İndirme sırasında {filename}.tmp dosyasına yazılır
      - Tamamlanınca {filename}.tmp → {filename} rename edilir (atomik)
      - Yeniden başlatınca:
          * {filename} var → tamamlanmış, atla
          * {filename}.tmp var → yarıda kesilmiş, kaldığı yerden devam et (Range)
          * ikisi de yok → sıfırdan başla

    Program kapansa bile tamamlanan dosyalar silinmez, yarımdakiler kaybolmaz.
    """
    url      = DOWNLOAD_BASE + filename
    path     = dest / filename
    tmp_path = dest / (filename + ".tmp")

    # Tamamlanmış dosyayı atla
    if path.exists() and path.stat().st_size > 0:
        return filename, True

    # Yarıda kesilmiş .tmp varsa kaldığı yerden devam et
    existing = tmp_path.stat().st_size if tmp_path.exists() else 0

    path.parent.mkdir(parents=True, exist_ok=True)

    for attempt in range(1, MAX_RETRIES + 1):
        _throttle()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "WizPatcher/1.0"})

            if existing > 0:
                req.add_header("Range", f"bytes={existing}-")

            with urllib.request.urlopen(req, timeout=120) as resp:
                status = resp.status  # type: ignore[attr-defined]

                # 416 = sunucu "zaten sende var" diyor → rename et
                if status == 416:
                    if tmp_path.exists():
                        tmp_path.rename(path)
                    print(f"  [{idx}/{total}] Zaten tam: {filename}")
                    return filename, True

                content_length = int(resp.headers.get("Content-Length", 0) or 0)

                if status == 206:
                    # Kısmi yanıt → append modunda devam
                    total_size = existing + content_length
                    mode       = "ab"
                    action     = "Devam ediyor"
                elif status == 200:
                    # Range desteklenmiyor → baştan yaz
                    total_size = content_length
                    mode       = "wb"
                    existing   = 0
                    action     = "İndiriliyor"
                else:
                    raise Exception(f"Beklenmedik HTTP status: {status}")

                size_str = f"{total_size / 1_048_576:.1f} MB" if total_size else "?"
                print(f"  [{idx}/{total}] {action}: {filename} ({size_str})")

                # .tmp'ye yaz — crash olsa bile tamamlananlar korunur
                with open(tmp_path, mode) as f:
                    while True:
                        chunk = resp.read(CHUNK_SIZE)
                        if not chunk:
                            break
                        f.write(chunk)
                        existing += len(chunk)

                # Tamamlandı → atomik rename
                tmp_path.rename(path)
                return filename, True

        except urllib.error.HTTPError as e:
            if e.code in (429, 503):
                wait = BACKOFF_BASE ** attempt
                print(f"  [{idx}/{total}] Rate limit ({e.code})! {wait:.0f}sn bekleniyor… ({filename})")
                time.sleep(wait)
            elif e.code == 404:
                print(f"  [{idx}/{total}] Bulunamadı (404): {filename}")
                return filename, False
            else:
                wait = BACKOFF_BASE ** attempt
                print(f"  [{idx}/{total}] HTTP {e.code}, {wait:.0f}sn sonra tekrar ({attempt}/{MAX_RETRIES}): {filename}")
                time.sleep(wait)

        except Exception as e:
            wait = BACKOFF_BASE ** attempt
            print(f"  [{idx}/{total}] Hata: {e} — {wait:.0f}sn sonra tekrar ({attempt}/{MAX_RETRIES}): {filename}")
            time.sleep(wait)

    print(f"  [{idx}/{total}] BAŞARISIZ (max deneme aşıldı): {filename}")
    return filename, False


# ── Ana fonksiyon ─────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) >= 2:
        game_data = pathlib.Path(sys.argv[1])
    else:
        game_data = find_game_data_dir()

    if not game_data:
        print("HATA: Wizard101 GameData dizini bulunamadı!")
        print("Kullanım: python3 download_assets.py [/path/to/GameData]")
        print("Ya da WIZ_DATA_DIR ortam değişkenini ayarlayın.")
        sys.exit(1)

    game_data.mkdir(parents=True, exist_ok=True)
    print(f"Hedef dizin : {game_data}")
    print(f"Sunucu      : {PATCH_HOST}")
    print(f"Paralel     : {MAX_WORKERS} eş zamanlı indirme")
    print(f"Resume      : .tmp dosyaları var (program kapanırsa kaldığı yerden devam)")
    print()

    # Dosya listesi
    try:
        raw = fetch_file_list()
    except Exception as e:
        print(f"HATA: Dosya listesi alınamadı: {e}")
        sys.exit(1)

    files = parse_file_list(raw)
    total = len(files)
    print(f"{total} dosya bulundu.\n")

    # Tamamlanmış (final isimde duran) dosyaları say
    complete  = [f for f in files if (game_data / f).exists() and (game_data / f).stat().st_size > 0]
    resumable = [f for f in files if (game_data / (f + ".tmp")).exists()]
    pending   = [(i + 1, f) for i, f in enumerate(files)
                 if not ((game_data / f).exists() and (game_data / f).stat().st_size > 0)]

    if complete:
        print(f"  {len(complete)} dosya tamamlanmış → atlanıyor")
    if resumable:
        print(f"  {len(resumable)} dosya yarıda kesilmiş → kaldığı yerden devam edilecek")
    print(f"  {len(pending)} dosya indirilecek\n")

    if not pending:
        print("Tüm dosyalar zaten mevcut!")
        return

    success_count = 0
    fail_list: list = []
    start = time.monotonic()

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {
            pool.submit(download_one, fname, game_data, idx, total): fname
            for idx, fname in pending
        }
        for fut in as_completed(futures):
            fname, ok = fut.result()
            if ok:
                success_count += 1
            else:
                fail_list.append(fname)

    elapsed = time.monotonic() - start
    print()
    print("━" * 50)
    print(f"  Tamamlandı  : {success_count + len(complete)}/{total} dosya")
    print(f"  Başarısız   : {len(fail_list)}")
    print(f"  Süre        : {elapsed / 60:.1f} dakika")
    if fail_list:
        print(f"\n  Başarısız dosyalar ({len(fail_list)}):")
        for f in fail_list:
            print(f"    - {f}")
        print("\n  Tekrar denemek için scripti yeniden çalıştırın.")
    print("━" * 50)


if __name__ == "__main__":
    main()
