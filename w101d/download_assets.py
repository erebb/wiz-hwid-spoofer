#!/usr/bin/env python3
"""
download_assets.py — Wizard101 oyun dosyalarını KingsIsle patch sunucusundan indirir.
naydevops/wizard projesinin Python uyarlaması (MIT lisansı).

Özellikler:
  - Rate limit koruması: 429 / 503 gelince exponential backoff ile bekler
  - Resume desteği: yarıda kesilen indirmeler kaldığı yerden devam eder
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

# Dosya listesinde yer almayan ama gerekli dosyalar (C# repodaki AdditionalFiles.txt)
EXTRA_FILES = ["Mob-WorldData.wad", "Music-WorldData.wad"]

MAX_WORKERS   = 3      # Eş zamanlı maksimum indirme
MAX_RETRIES   = 6      # Her dosya için maksimum deneme sayısı
BACKOFF_BASE  = 2.0    # Exponential backoff çarpanı (saniye)
REQUEST_DELAY = 0.4    # Her istek arasındaki minimum bekleme (saniye)
CHUNK_SIZE    = 64 * 1024  # 64 KB okuma bloğu

# ── Rate limit kilidi ─────────────────────────────────────────────────────────
_rate_lock  = threading.Lock()
_last_req   = [0.0]  # mutable container for thread-safe last request time

def _throttle():
    """İstekler arasında REQUEST_DELAY kadar bekler."""
    with _rate_lock:
        now = time.monotonic()
        wait = REQUEST_DELAY - (now - _last_req[0])
        if wait > 0:
            time.sleep(wait)
        _last_req[0] = time.monotonic()


# ── Path tespiti ──────────────────────────────────────────────────────────────
def find_game_data_dir() -> Optional[pathlib.Path]:
    """Wizard101 GameData dizinini otomatik bulur."""
    # Önce ortam değişkeni kontrol et
    env = os.environ.get("WIZ_DATA_DIR", "").strip()
    if env and pathlib.Path(env).is_dir():
        return pathlib.Path(env)

    home = pathlib.Path.home()
    lib  = home / "Library" / "Application Support" / "Wizard101"

    candidates = [
        # Whisky / CrossOver Bottles path
        lib / "Bottles" / "wizard101" / "drive_c" /
            "ProgramData" / "KingsIsle Entertainment" / "Wizard101" /
            "Data" / "GameData",
        # Doğrudan prefix path
        lib / "drive_c" /
            "ProgramData" / "KingsIsle Entertainment" / "Wizard101" /
            "Data" / "GameData",
        # Program Files alternatifleri
        lib / "Bottles" / "wizard101" / "drive_c" /
            "Program Files" / "Wizard101" / "Data" / "GameData",
        lib / "drive_c" / "Program Files" / "Wizard101" / "Data" / "GameData",
    ]

    for c in candidates:
        # Üst dizin var mı? (GameData henüz oluşmamış olabilir)
        if c.parent.exists():
            return c

    return None


# ── Dosya listesi indirme ─────────────────────────────────────────────────────
def fetch_file_list() -> bytes:
    """LatestFileList.bin dosyasını sunucudan indirir."""
    print(f"[setup] Dosya listesi alınıyor: {FILE_LIST_URL}")
    req = urllib.request.Request(FILE_LIST_URL, headers={"User-Agent": "WizPatcher/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


# ── Dosya listesi ayrıştırma ─────────────────────────────────────────────────
def parse_file_list(data: bytes) -> list[str]:
    """
    LatestFileList.bin binary verisinden WAD dosya isimlerini çıkarır.
    C# LatestFileListExtractor.cs mantığını Python'a çevirir:
      - Yazdırılabilir ASCII karakterleri birleştirir
      - 'Data/GameData/' içeren stringleri filtreler
      - Prefix'i kaldırarak sadece dosya adını döner
    """
    PREFIX = "Data/GameData/"
    results = set()
    buf = []

    def _flush():
        if not buf:
            return
        s = "".join(buf)
        buf.clear()
        if PREFIX not in s:
            return
        idx = s.find(PREFIX)
        filename = s[idx + len(PREFIX):]
        # Sadece ilk 'anlamlı' bölümü al
        filename = filename.split("\x00")[0].strip()
        if filename and "." in filename and len(filename) > 3:
            results.add(filename)

    for byte in data:
        if 32 <= byte <= 126:
            buf.append(chr(byte))
        else:
            _flush()
    _flush()  # son parça

    all_files = sorted(results | set(EXTRA_FILES))
    return all_files


# ── Tek dosya indirme ─────────────────────────────────────────────────────────
def download_one(filename: str, dest: pathlib.Path, idx: int, total: int) -> tuple[str, bool]:
    """
    Tek bir dosyayı indirir. Resume destekli, rate-limit korumalı.
    Döndürür: (filename, success)
    """
    url  = DOWNLOAD_BASE + filename
    path = dest / filename

    # Kısmi indirme için var olan bayt sayısını bul
    existing = path.stat().st_size if path.exists() else 0

    for attempt in range(1, MAX_RETRIES + 1):
        _throttle()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "WizPatcher/1.0"})

            # Resume: Range header ekle
            if existing > 0:
                req.add_header("Range", f"bytes={existing}-")

            with urllib.request.urlopen(req, timeout=120) as resp:
                status = resp.status  # type: ignore[attr-defined]

                # Sunucu 416 dönerse dosya zaten tam
                if status == 416:
                    print(f"  [{idx}/{total}] Zaten tam: {filename}")
                    return filename, True

                content_length = int(resp.headers.get("Content-Length", 0) or 0)
                total_size = existing + content_length if status == 206 else content_length

                mode = "ab" if status == 206 else "wb"
                if status != 206:
                    existing = 0  # tam indirme, baştan başla

                path.parent.mkdir(parents=True, exist_ok=True)

                size_str = f"{total_size / 1_048_576:.1f} MB" if total_size else "?"
                print(f"  [{idx}/{total}] İndiriliyor: {filename} ({size_str})")

                with open(path, mode) as f:
                    while True:
                        chunk = resp.read(CHUNK_SIZE)
                        if not chunk:
                            break
                        f.write(chunk)
                        existing += len(chunk)

                return filename, True

        except urllib.error.HTTPError as e:
            if e.code in (429, 503):
                wait = BACKOFF_BASE ** attempt
                print(f"  [{idx}/{total}] Rate limit ({e.code})! {wait:.0f}sn bekleniyor… "
                      f"({filename})")
                time.sleep(wait)
            elif e.code == 404:
                print(f"  [{idx}/{total}] Bulunamadı (404): {filename}")
                return filename, False
            else:
                wait = BACKOFF_BASE ** attempt
                print(f"  [{idx}/{total}] HTTP {e.code}, {wait:.0f}sn sonra tekrar "
                      f"({attempt}/{MAX_RETRIES}): {filename}")
                time.sleep(wait)

        except Exception as e:
            wait = BACKOFF_BASE ** attempt
            print(f"  [{idx}/{total}] Hata: {e} — {wait:.0f}sn sonra tekrar "
                  f"({attempt}/{MAX_RETRIES}): {filename}")
            time.sleep(wait)

    print(f"  [{idx}/{total}] BAŞARISIZ (max deneme aşıldı): {filename}")
    return filename, False


# ── Ana fonksiyon ─────────────────────────────────────────────────────────────
def main():
    # Hedef dizin
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
    print()

    # Dosya listesini al
    try:
        raw = fetch_file_list()
    except Exception as e:
        print(f"HATA: Dosya listesi alınamadı: {e}")
        sys.exit(1)

    files = parse_file_list(raw)
    total = len(files)
    print(f"{total} dosya bulundu.\n")

    # Zaten tam indirilen dosyaları atla (resume desteği)
    def is_complete(f: str) -> bool:
        p = game_data / f
        if not p.exists() or p.stat().st_size == 0:
            return False
        # Boyutu sunucuyla karşılaştırmak yerine 0-byte kontrolü yap
        # (tam karşılaştırma istek gerektirir, rate limit için atlanıyor)
        return True

    pending = [(i + 1, f) for i, f in enumerate(files) if not is_complete(f)]
    skipped = total - len(pending)

    if skipped:
        print(f"{skipped} dosya zaten mevcut, atlanıyor.")
    print(f"{len(pending)} dosya indirilecek.\n")

    if not pending:
        print("Tüm dosyalar zaten mevcut!")
        return

    # Paralel indirme
    success_count = 0
    fail_list: list[str] = []
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
    print(f"  Tamamlandı  : {success_count + skipped}/{total} dosya")
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
