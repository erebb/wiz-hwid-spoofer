#!/usr/bin/env bash
# run_deimos.sh — Wizard101 araçlarını çalıştırır.
#
# Çalışan Wizard101'in Wine prefix'ini VE Wine binary'sini otomatik tespit eder.
# Oyunu hangi Wine açmışsa (Homebrew, CrossOver, Whisky...) Python'u da
# AYNI binary ile çalıştırır → aynı wineserver → memory erişimi task_for_pid
# gerektirmez, SIP sorunu olmaz.
#
# KULLANIM:
#   bash run_deimos.sh              → Deimos (varsayılan)
#   bash run_deimos.sh speed [N]    → Nx speedhack (varsayılan: 3)
#   bash run_deimos.sh quest        → Enter ile quest TP
#   bash run_deimos.sh both [N]     → Nx speed + quest TP
#
# GEREKSİNİM:
#   - setup_env.sh çalıştırılmış olmalı (Python + Deimos kurulu)
#   - Wizard101 Wine ile açık olmalı
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"   # WINE_BIN fallback için

MODE="${1:-deimos}"
MULTIPLIER="${2:-3}"

OUR_PYTHON="$HOME/.w101d_wine/drive_c/Python313"
DEIMOS_DIR="${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}"

# ── Kurulum kontrolü ──────────────────────────────────────────────────────────
if [[ ! -d "$OUR_PYTHON" ]]; then
    echo "[run] HATA: Python bulunamadı. Önce setup_env.sh çalıştırın." >&2
    exit 1
fi

if [[ "$MODE" == "deimos" && ! -f "$DEIMOS_DIR/Deimos.py" ]]; then
    echo "[run] HATA: '$DEIMOS_DIR/Deimos.py' bulunamadı." >&2
    exit 1
fi

# ── Çalışan Wizard101'den WINEPREFIX + WINELOADER oku ────────────────────────
# Oyunun çalıştığı Wine binary'sini (WINELOADER) de okuyoruz.
# CrossOver → CrossOver'ın Wine'ı, Whisky → Whisky'nin Wine'ı, vb.
# Aynı binary kullanılmazsa "wineserver mismatch" hatası alınır.
_get_wiz_env() {
    local pid
    pid=$(pgrep -f "WizardGraphicalClient.exe" 2>/dev/null | head -1)
    [[ -z "$pid" ]] && return
    ps eww -p "$pid" 2>/dev/null | python3 -c "
import sys, re
txt = sys.stdin.read()
for key in ('WINEPREFIX', 'WINELOADER'):
    m = re.search(rf'{key}=(.*?)(?:\s+[A-Z_][A-Z0-9_]*=|\s*\Z)', txt, re.DOTALL)
    if m: print(f'{key}={m.group(1).strip()}')
" 2>/dev/null
}

# ── Oyunun Wine preloader'ını imzala (ek güvenlik katmanı) ───────────────────
# Aynı wineserver olunca task_for_pid gerekmez ama yine de imzalıyoruz.
_sign_wine_preloader() {
    local wineloader="$1"
    [[ -z "$wineloader" || ! -x "$wineloader" ]] && return
    local real
    real=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" \
           "$wineloader" 2>/dev/null || echo "$wineloader")
    local ent
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
    for d in "$(dirname "$real")" "$(dirname "$wineloader")"; do
        for b in "$d/wine64-preloader" "$d/wine-preloader"; do
            [[ -x "$b" ]] || continue
            xattr -d com.apple.quarantine "$b" 2>/dev/null || true
            codesign --entitlements "$ent" --force -s - "$b" 2>/dev/null \
                && echo "[run] İmzalandı: $(basename "$b")" || true
        done
    done
    rm -f "$ent"
}

# ── Wizard101 ortamını tespit et ──────────────────────────────────────────────
echo "[run] Wizard101 aranıyor..."
WIZ_PREFIX=""
WIZ_LOADER=""

for i in $(seq 1 12); do
    env_info=$(_get_wiz_env)
    while IFS= read -r line; do
        [[ "$line" == WINEPREFIX=* ]] && WIZ_PREFIX="${line#WINEPREFIX=}"
        [[ "$line" == WINELOADER=* ]] && WIZ_LOADER="${line#WINELOADER=}"
    done <<< "$env_info"

    if [[ -n "$WIZ_PREFIX" ]]; then
        echo "[run] Wizard101 bulundu."
        break
    fi
    echo "[run] Bekleniyor... ($i/12) — Wizard101'i aç"
    sleep 5
done

if [[ -z "$WIZ_PREFIX" ]]; then
    echo "[run] HATA: Wizard101 çalışmıyor. Önce oyunu aç." >&2
    exit 1
fi

# Oyunun Wine binary'sini kullan → aynı wineserver → memory erişimi garanti
# Fallback: detect_wine.sh'dan gelen Homebrew Wine
if [[ -n "$WIZ_LOADER" && -x "$WIZ_LOADER" ]]; then
    ACTIVE_WINE="$WIZ_LOADER"
    echo "[run] Oyunun Wine'ı  : $ACTIVE_WINE"
else
    ACTIVE_WINE="$WINE_BIN"
    echo "[run] Homebrew Wine  : $ACTIVE_WINE"
fi

# Oyunun preloader'ını imzala (CrossOver/Whisky dahil)
_sign_wine_preloader "$ACTIVE_WINE"

# ── Python'u Wizard101 prefix'ine kopyala (yoksa) ────────────────────────────
WIN_PYTHON="$WIZ_PREFIX/drive_c/Python313/python.exe"
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run] Python kopyalanıyor → $WIZ_PREFIX/drive_c/Python313"
    cp -r "$OUR_PYTHON" "$WIZ_PREFIX/drive_c/Python313"
fi

# wiz_tools.py'yi prefix'e kopyala (speed/quest/both modları için)
if [[ "$MODE" != "deimos" ]]; then
    cp "$SCRIPT_DIR/wiz_tools.py" "$WIZ_PREFIX/drive_c/wiz_tools.py"
fi

export WINEPREFIX="$WIZ_PREFIX"
echo "[run] WINEPREFIX : $WIZ_PREFIX"
echo "[run] Mod        : $MODE"
echo ""

# ── Çalıştır ─────────────────────────────────────────────────────────────────
case "$MODE" in
    deimos)
        echo "[run] Deimos başlatılıyor..."
        cd "$DEIMOS_DIR"
        exec "$ACTIVE_WINE" "$WIN_PYTHON" Deimos.py
        ;;
    speed|quest|both)
        echo "[run] wiz_tools başlatılıyor ($MODE)..."
        exec "$ACTIVE_WINE" "$WIN_PYTHON" \
            "$WIZ_PREFIX/drive_c/wiz_tools.py" "$MODE" "$MULTIPLIER"
        ;;
    *)
        echo "[run] HATA: Bilinmeyen mod '$MODE'" >&2
        echo "      Kullanım: run_deimos.sh [deimos|speed|quest|both] [çarpan]" >&2
        exit 1
        ;;
esac
