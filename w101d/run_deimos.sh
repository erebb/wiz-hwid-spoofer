#!/usr/bin/env bash
# run_deimos.sh — Wizard101 araçlarını çalıştırır.
#
# Mimari:
#   - Python/Deimos → Homebrew Wine + ~/.w101d_wine prefix
#   - Oyun           → Wizard101.app bundled Wine (ayrı wineserver)
#   - Process bulma  → macOS proc_listallpids() (wineserver bağımsız)
#   - Memory erişim  → task_for_pid (get-task-allow imzalı preloader)
#
# KULLANIM:
#   bash run_deimos.sh              → Deimos
#   bash run_deimos.sh speed [N]    → Nx speedhack
#   bash run_deimos.sh quest        → quest TP
#   bash run_deimos.sh both [N]     → ikisi birden
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"   # WINE_BIN, WINEPREFIX (~/.w101d_wine)

MODE="${1:-deimos}"
MULTIPLIER="${2:-3}"
DEIMOS_DIR="${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}"
WIN_PYTHON="$WINEPREFIX/drive_c/Python313/python.exe"

# ── Kurulum kontrolü ──────────────────────────────────────────────────────────
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run] HATA: Python bulunamadı ($WIN_PYTHON). Önce setup_env.sh çalıştırın." >&2
    exit 1
fi
if [[ "$MODE" == "deimos" && ! -f "$DEIMOS_DIR/Deimos.py" ]]; then
    echo "[run] HATA: Deimos bulunamadı ($DEIMOS_DIR). Önce setup_env.sh çalıştırın." >&2
    exit 1
fi

# Deimos.py: get_deimos.sh çalıştırılınca güncellenir (otomatik değil).

# ── Wizard101 exe'sini dosya sisteminden bul (preloader imzalamak için) ───────
_find_wiz_exe() {
    local candidates=(
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files (x86)/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/Program Files (x86)/Wizard101/Bin/WizardGraphicalClient.exe"
    )
    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && echo "$c" && return
    done
    find "$HOME/Library" -name "WizardGraphicalClient.exe" -maxdepth 12 2>/dev/null \
        | head -1 || true
}

# ── Çalışan wineserver'dan wine binary'sini türet (preloader imzalamak için) ──
_find_wine_from_wineserver() {
    local ws
    ws=$(ps auxww 2>/dev/null | grep -iE "[Ww]ineserver" | grep -v grep \
         | awk '{print $11}' | head -1)
    [[ -z "$ws" || ! -x "$ws" ]] && return 0
    local bin_dir="${ws%/*}"
    for b in "$bin_dir/wine64" "$bin_dir/wine"; do
        [[ -x "$b" ]] && echo "$b" && return
    done
}

# ── Preloader imzala (get-task-allow) ─────────────────────────────────────────
# macOS: task_for_pid hedefe izin vermek için HEDEF imzalı olmalı.
# Bu imza sayesinde Homebrew Wine farklı wineserver'dan memory okuyabilir.
_sign_preloader() {
    local wine_bin="${1:-}"
    [[ -z "$wine_bin" || ! -x "$wine_bin" ]] && return 0
    local real bin_dir
    real=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" \
           "$wine_bin" 2>/dev/null || echo "$wine_bin")
    bin_dir=$(dirname "$real")

    local ent signed=0
    ent=$(mktemp /tmp/wine-ent-XXXXXX.plist)
    cat > "$ent" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.get-task-allow</key>
    <true/>
</dict>
</plist>
PLIST
    for d in "$bin_dir" "$(dirname "$wine_bin")"; do
        for b in "$d/wine64-preloader" "$d/wine-preloader"; do
            [[ -x "$b" ]] || continue
            xattr -d com.apple.quarantine "$b" 2>/dev/null || true
            if codesign --entitlements "$ent" --force -s - "$b" 2>/dev/null; then
                echo "[run] İmzalandı (get-task-allow): $(basename "$b")"
                signed=1
            fi
        done
    done
    rm -f "$ent"
    if [[ "$signed" -eq 0 ]]; then
        echo "[run] UYARI: Preloader imzalanamadı → memory erişimi başarısız olabilir."
    else
        echo "[run] NOT: İmza yeni açılışta geçerli olur → oyunu kapat/aç."
    fi
}

# ── Wizard101 process'i çalışıyor mu? ─────────────────────────────────────────
_wiz_is_running() {
    local out
    out=$(ps auxww 2>/dev/null \
        | grep -iE "(WizardGraphicalClient|KingsIsle)" \
        | grep -v "grep\|run_deimos\|bash\|python" || true)
    [[ -n "$out" ]]
}

# ── Oyunu kapat (crash sonrası temiz başlangıç için) ──────────────────────────
_kill_game() {
    echo "[run] Oyun kapatılıyor..."
    osascript -e 'quit app "Wizard101"' >/dev/null 2>&1 || true
    pkill -f "WizardGraphicalClient" >/dev/null 2>&1 || true
    for _ in $(seq 1 15); do
        if ! _wiz_is_running; then
            echo "[run] Oyun kapandı."
            sleep 2
            return 0
        fi
        sleep 1
    done
    echo "[run] Oyun kapanmadı → zorla sonlandırılıyor (SIGKILL)."
    pkill -9 -f "WizardGraphicalClient" >/dev/null 2>&1 || true
    sleep 3
}

# ── Oyunu aç ve yüklenmesini bekle ────────────────────────────────────────────
# Önce quick_launch.sh (otomatik giriş), olmazsa Wizard101.app launcher.
_launch_game() {
    if _wiz_is_running; then
        return 0
    fi
    if [[ -f "$SCRIPT_DIR/quick_launch.sh" ]]; then
        echo "[run] Oyun quick_launch.sh ile açılıyor (otomatik giriş)..."
        bash "$SCRIPT_DIR/quick_launch.sh" \
            || echo "[run] quick_launch.sh başarısız — Wizard101.app deneniyor."
    fi
    if ! _wiz_is_running; then
        if [[ -d "/Applications/Wizard101.app" ]]; then
            echo "[run] Wizard101.app açılıyor..."
            open -a Wizard101 2>/dev/null || open /Applications/Wizard101.app 2>/dev/null || true
        else
            echo "[run] Lütfen Wizard101'i manuel olarak açın."
        fi
    fi

    echo "[run] Oyunun yüklenmesi bekleniyor..."
    for i in $(seq 1 36); do
        if _wiz_is_running; then
            echo "[run] Wizard101 başladı! Karakter ekranı için bekleniyor..."
            sleep 20
            return 0
        fi
        sleep 5
        echo "[run] Bekleniyor... ($i/36)"
    done
    return 1
}

# ── WIZ_PID'i yeniden bul (oyun yeniden açıldığında PID değişir) ──────────────
_refresh_wiz_pid() {
    local pid
    pid=$(ps auxww 2>/dev/null \
        | grep -i "WizardGraphicalClient" | grep -v grep \
        | awk '{print $2}' | head -1 || true)
    if [[ -n "$pid" ]]; then
        export WIZ_PID="$pid"
        echo "[run] Wizard101 PID: $WIZ_PID (cross-wineserver bağlantı için)"
    else
        unset WIZ_PID || true
        echo "[run] UYARI: Wizard101 PID bulunamadı."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Oyunun wineserver'ından bundled wine binary'sini bul → preloader imzala
#    (Python bu wine'ı KULLANMAZ, sadece preloader imzalamak için buluyoruz)
# ─────────────────────────────────────────────────────────────────────────────
echo "[run] Wizard101 Wine + preloader aranıyor..."
WIZ_EXE=$(_find_wiz_exe)

# WIZ_DATA_DIR: Deimos.py WAD patch'inin oyun dosyalarını bulması için
if [[ -n "$WIZ_EXE" ]]; then
    _wiz_prefix_tmp=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
    _wiz_data_tmp="$_wiz_prefix_tmp/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Data/GameData"
    if [[ -d "$_wiz_data_tmp" ]]; then
        export WIZ_DATA_DIR="$_wiz_data_tmp"
        echo "[run] WIZ_DATA_DIR : $WIZ_DATA_DIR"
    fi
fi

WIZ_WINE=$(_find_wine_from_wineserver)

if [[ -n "$WIZ_WINE" ]]; then
    echo "[run] Bundled Wine preloader imzalanıyor: $WIZ_WINE"
    _sign_preloader "$WIZ_WINE"
elif [[ -n "$WIZ_EXE" ]]; then
    WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
    # Wizard101.app içinde wine binary ara
    for b in \
        "/Applications/Wizard101.app/Contents/SharedSupport/wine/bin/wine64" \
        "/Applications/Wizard101.app/Contents/SharedSupport/wine/bin/wine"; do
        if [[ -x "$b" ]]; then
            echo "[run] Bundled Wine preloader imzalanıyor: $b"
            _sign_preloader "$b"
            break
        fi
    done
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Oyunun çalışmasını bekle / aç
# ─────────────────────────────────────────────────────────────────────────────
if ! _wiz_is_running; then
    echo "[run] Wizard101 çalışmıyor."
    if ! _launch_game; then
        echo "[run] HATA: Zaman aşımı — oyun açılamadı." >&2
        exit 1
    fi
fi

echo "[run] Wizard101 çalışıyor."

# ─────────────────────────────────────────────────────────────────────────────
# 3. Python'u Homebrew Wine + ~/.w101d_wine prefix ile çalıştır
#    Neden: propsys.dll.VariantToString Homebrew Wine'da implemente,
#           bundled Wine'da yok (game-specific stripped build).
#    Process bulma: macOS proc_listallpids() → wineserver bağımsız
#    Memory erişim: task_for_pid (get-task-allow imzalı preloader)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$MODE" != "deimos" ]]; then
    cp "$SCRIPT_DIR/wiz_tools.py" "$WINEPREFIX/drive_c/wiz_tools.py"
fi

# ── macOS yamaları: sitecustomize.py üzerinden uygulanır ─────────────────────
# Deimos.py'e dokunmaz; Wine Python her başladığında otomatik çalışır.
SITE_PKG="$WINEPREFIX/drive_c/Python313/Lib/site-packages"
_SITECUST="$SITE_PKG/sitecustomize.py"
_PATCHES_SRC="$SCRIPT_DIR/macos_patches.py"
if [[ -f "$_PATCHES_SRC" ]]; then
    # sitecustomize.py yoksa oluştur; içeriği farklıysa güncelle
    if ! diff -q "$_PATCHES_SRC" "$_SITECUST" &>/dev/null; then
        cp "$_PATCHES_SRC" "$_SITECUST"
        echo "[run] sitecustomize.py güncellendi (macOS WAD yaması)"
    fi
fi

# ── WIZ_PID cross-wineserver patch (her çalışmada uygula) ────────────────────
# setup_env.sh çalıştırılmadan da patch aktif olsun.
HANDLER_PY="$SITE_PKG/wizwalker/client_handler.py"
if [[ -f "$HANDLER_PY" ]]; then
    python3 -c "
import pathlib
handler = pathlib.Path('$HANDLER_PY')
content = handler.read_text()
PATCH = '''
# -- WIZ_PID cross-wineserver patch (macOS / Homebrew Wine) ------------------
import os as _os

_orig_get_new_clients = ClientHandler.get_new_clients

def _get_new_clients_patched(self):
    _pid_str = _os.environ.get(\"WIZ_PID\", \"\").strip()
    if _pid_str:
        try:
            from wizwalker.client import Client
            _pid = int(_pid_str)
            if not any(c.process_id == _pid for c in self.clients):
                _c = Client(_pid)
                self.clients.append(_c)
                return [_c]
            return []
        except Exception as _e:
            print(f\"[WIZ_PID] Direkt baglanti basarisiz ({_e}), normal kesif deneniyor...\")
    return _orig_get_new_clients(self)

ClientHandler.get_new_clients = _get_new_clients_patched
# ---------------------------------------------------------------------------
'''
if '_get_new_clients_patched' not in content:
    handler.write_text(content + PATCH)
    print('[run] wizwalker WIZ_PID patch uygulandı')
"
fi

# Wizard101 macOS PID'ini bul → Wine içinden task_for_pid ile cross-wineserver erişim
# EnumProcesses yalnızca aynı wineserver'ı görür; PID ile direkt bağlantı bunu atlatır.
_refresh_wiz_pid

# ── Ön kontroller: traversalData + gerekli Python modülleri ──────────────────
# traversalData olmadan WizSprinter zone değiştiremez → questing aynı map'te döner.
TRAVERSAL_URL="https://raw.githubusercontent.com/notfaj/wizsprinter/main/wizwalker/extensions/wizsprinter/traversalData"
TRAVERSAL_FILES="displayZones.txt gates_list.txt interactiveTeleporters.txt objectLocations.txt uniqueObjectLocations.txt zoneMap.txt"

_fill_traversal_dir() {
    local sprinter_dir="$1"
    [[ -d "$sprinter_dir" ]] || return 0
    local tdir="$sprinter_dir/traversalData"
    mkdir -p "$tdir"
    local missing=0 f
    for f in $TRAVERSAL_FILES; do
        [[ -s "$tdir/$f" ]] && continue
        missing=$((missing + 1))
        echo "[run] traversalData eksik: $f → indiriliyor..."
        curl -fsSL --retry 2 --max-time 30 "$TRAVERSAL_URL/$f" -o "$tdir/$f" 2>/dev/null \
            || { rm -f "$tdir/$f"; echo "[run] UYARI: $f indirilemedi (zone geçişi bozulabilir)."; }
    done
    if [[ "$missing" -eq 0 ]]; then
        echo "[run] traversalData tam: $tdir"
    fi
    TRAVERSAL_FOUND=1
}

TRAVERSAL_FOUND=0
if [[ "$MODE" == "deimos" ]]; then
    _fill_traversal_dir "$SITE_PKG/wizwalker/extensions/wizsprinter"
    _fill_traversal_dir "$DEIMOS_DIR/wizwalker/extensions/wizsprinter"
    if [[ "$TRAVERSAL_FOUND" -eq 0 ]]; then
        echo "[run] UYARI: wizsprinter bulunamadı → zone geçişi çalışmayabilir."
    fi
fi

# Deimos v3.13.x `import wizlaunch` yapıyor — eksikse başlangıçta çöker.
_check_python_modules() {
    local out
    out=$(WINEDEBUG=-all "$WINE_BIN" "$WIN_PYTHON" -c "
import importlib
for m in ('wizwalker', 'wizlaunch', 'mss', 'pytesseract'):
    try:
        importlib.import_module(m)
    except Exception as e:
        print(f'EKSIK {m}: {e}')
print('MODUL_KONTROL_TAMAM')
" 2>/dev/null || true)

    if [[ "$out" != *"MODUL_KONTROL_TAMAM"* ]]; then
        echo "[run] UYARI: Python modül kontrolü çalıştırılamadı (atlanıyor)."
        return 0
    fi
    local eksik
    eksik=$(echo "$out" | grep "^EKSIK " || true)
    if [[ -n "$eksik" ]]; then
        echo "$eksik" | while read -r line; do echo "[run] $line"; done
        echo "[run] Kurmak için: \"$WINE_BIN\" \"$WIN_PYTHON\" -m pip install <modül>"
    else
        echo "[run] Python modülleri tam (wizwalker, wizlaunch, mss, pytesseract)."
    fi
}
if [[ "$MODE" == "deimos" ]]; then
    _check_python_modules
fi

echo "[run] Wine       : $WINE_BIN  (Homebrew — tam DLL desteği)"
echo "[run] WINEPREFIX : $WINEPREFIX  (~/.w101d_wine)"
echo "[run] Mod        : $MODE"
echo ""

# FPS / performans: Wine debug output kapat, DXVK log kapat
export WINEDEBUG="-all"
export DXVK_LOG_LEVEL="none"
export WINEESYNC=1
export WINEMSYNC=1

# Ctrl+C → gözetmen yeniden başlatmasın, temiz çık
trap 'echo ""; echo "[run] Durduruldu (Ctrl+C)."; exit 130' INT

# ── Deimos gözetmeni: çökerse oyunu + Deimos'u kapat/aç ──────────────────────
# DEIMOS_NO_RESTART=1  → gözetmeni kapat (tek sefer çalıştır)
# DEIMOS_MAX_RESTARTS  → maksimum yeniden başlatma (varsayılan 20)
_supervise_deimos() {
    local max="${DEIMOS_MAX_RESTARTS:-20}"
    local attempt=0
    local fast_crashes=0   # 20 sn'den kısa sürede çöküşler (genelde kod/modül hatası)
    cd "$DEIMOS_DIR"

    while true; do
        echo "[run] Deimos başlatılıyor... (çalıştırma $((attempt + 1)))"
        local start_ts=$SECONDS rc=0
        set +e
        "$WINE_BIN" "$WIN_PYTHON" Deimos.py
        rc=$?
        set -e
        local ran=$((SECONDS - start_ts))

        if [[ "$rc" -eq 0 ]]; then
            echo "[run] Deimos normal kapandı."
            return 0
        fi
        # 130 = Ctrl+C (SIGINT), 143 = SIGTERM → kullanıcı durdurdu
        if [[ "$rc" -eq 130 || "$rc" -eq 143 ]]; then
            echo "[run] Kullanıcı durdurdu (kod $rc)."
            return 0
        fi

        attempt=$((attempt + 1))
        if [[ "$attempt" -gt "$max" ]]; then
            echo "[run] HATA: $max yeniden başlatma denemesi aşıldı, duruluyor." >&2
            return 1
        fi

        if [[ "$ran" -lt 20 ]]; then
            fast_crashes=$((fast_crashes + 1))
        else
            fast_crashes=0
        fi

        echo ""
        echo "[run] ============================================"
        echo "[run] Deimos ÇÖKTÜ (kod $rc, $ran sn çalıştı)"
        echo "[run] ============================================"
        echo ""

        # Hemen çöküyor + oyun hâlâ ayakta ise sorun Deimos tarafında (modül/kod
        # hatası) — oyunu boşuna kapatma. 3 kez üst üste olursa yine de yenile.
        if [[ "$ran" -lt 20 && "$fast_crashes" -lt 3 ]] && _wiz_is_running; then
            echo "[run] Hızlı çöküş ($fast_crashes/3) — oyun açık bırakılıyor, sadece Deimos yeniden başlatılacak."
        else
            echo "[run] Oyun kapatılıp yeniden açılacak, sonra Deimos başlayacak."
            fast_crashes=0
            _kill_game
            sleep 5
            if ! _launch_game; then
                echo "[run] Oyun açılamadı → 30 sn sonra tekrar denenecek."
                sleep 30
                continue
            fi
            _refresh_wiz_pid
        fi

        # Kısa aralıkla üst üste çöküyorsa bekleme süresini artır
        local backoff=10
        [[ "$ran" -lt 60 ]] && backoff=$((attempt < 5 ? 20 : 60))
        echo "[run] $backoff sn sonra Deimos yeniden başlatılıyor..."
        sleep "$backoff"
    done
}

case "$MODE" in
    deimos)
        if [[ "${DEIMOS_NO_RESTART:-0}" == "1" ]]; then
            echo "[run] Deimos başlatılıyor (gözetmen kapalı)..."
            cd "$DEIMOS_DIR"
            exec "$WINE_BIN" "$WIN_PYTHON" Deimos.py
        fi
        _supervise_deimos
        ;;
    speed|quest|both)
        echo "[run] wiz_tools başlatılıyor ($MODE)..."
        exec "$WINE_BIN" "$WIN_PYTHON" \
            "$WINEPREFIX/drive_c/wiz_tools.py" "$MODE" "$MULTIPLIER"
        ;;
    *)
        echo "[run] HATA: Bilinmeyen mod '$MODE'" >&2; exit 1
        ;;
esac