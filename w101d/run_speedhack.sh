#!/usr/bin/env bash
# run_speedhack.sh — speedhack.py'yi çalışan Wizard101'in Wine prefix'inde başlatır.
#
# KULLANIM:
#   bash run_speedhack.sh          → 3x hız
#   bash run_speedhack.sh 5        → 5x hız
#   bash run_speedhack.sh 1        → sıfırla (normal hız)
#
# GEREKSINIM:
#   - Wizard101 Wine ile çalışıyor olmalı
#   - setup_env.sh daha önce çalıştırılmış olmalı
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

MULTIPLIER="${1:-3}"
OUR_PYTHON="$HOME/.w101d_wine/drive_c/Python313"

if [[ ! -d "$OUR_PYTHON" ]]; then
    echo "[speedhack] HATA: Python bulunamadı. Önce setup_env.sh çalıştırın." >&2
    exit 1
fi

# ── Çalışan Wizard101'den WINEPREFIX + WINELOADER oku ────────────────────────
# ps auxww: pgrep'ten farklı olarak çok uzun komut satırlarını da yakalar
_get_wiz_env() {
    local pid
    pid=$(ps auxww | grep -i "WizardGraphicalClient.exe" | grep -v grep \
          | awk '{print $2}' | head -1)
    [[ -z "$pid" ]] && return
    ps eww -p "$pid" 2>/dev/null | python3 -c "
import sys, re
txt = sys.stdin.read()
for key in ('WINEPREFIX', 'WINELOADER'):
    m = re.search(rf'{key}=(.*?)(?:\s+[A-Z_][A-Z0-9_]*=|\s*\Z)', txt, re.DOTALL)
    if m: print(f'{key}={m.group(1).strip()}')
" 2>/dev/null
}

# Bundled Wine WINELOADER set etmeyebilir → ps'ten wine64-preloader yolunu çek
_find_bundled_preloader() {
    ps auxww 2>/dev/null \
        | grep -i "wine64-preloader" | grep -iv grep \
        | grep -i "Wizard101" \
        | awk '{print $11}' | head -1
}

# ── Wizard101'in Wine'ı gömülü mü? ───────────────────────────────────────────
_is_bundled_wine() {
    local l="${1:-}"
    [[ "$l" == *"Wizard101.app"* || "$l" == *"wizard101.app"* ]]
}

# ── HEDEF preloader'ı imzala (Wizard101'in çalıştığı Wine) ───────────────────
_sign_target_preloader() {
    local wineloader="${1:-}"
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
    local signed=0
    for d in "$(dirname "$real")" "$(dirname "$wineloader")"; do
        for b in "$d/wine64-preloader" "$d/wine-preloader"; do
            [[ -x "$b" ]] || continue
            xattr -d com.apple.quarantine "$b" 2>/dev/null || true
            if codesign --entitlements "$ent" --force -s - "$b" 2>/dev/null; then
                echo "[speedhack] Hedef imzalandı (get-task-allow): $(basename "$b")"
                signed=1
            fi
        done
    done
    rm -f "$ent"
    [[ "$signed" -eq 0 ]] && echo "[speedhack] UYARI: Preloader imzalanamadı → memory erişimi başarısız olabilir."
}

echo "[speedhack] Wizard101 aranıyor..."

WIZ_PREFIX=""
WIZ_LOADER=""
for i in $(seq 1 12); do
    env_info=$(_get_wiz_env)
    while IFS= read -r line; do
        [[ "$line" == WINEPREFIX=* ]] && WIZ_PREFIX="${line#WINEPREFIX=}"
        [[ "$line" == WINELOADER=* ]] && WIZ_LOADER="${line#WINELOADER=}"
    done <<< "$env_info"
    if [[ -n "$WIZ_PREFIX" ]]; then
        echo "[speedhack] Wizard101 bulundu."
        break
    fi
    echo "[speedhack] Bekleniyor... ($i/12) — Wizard101'i önce Wine ile aç"
    sleep 5
done

if [[ -z "$WIZ_PREFIX" ]]; then
    echo "[speedhack] HATA: Wizard101 çalışmıyor." >&2
    exit 1
fi

# Bundled Wine WINELOADER set etmeyebilir → ps'ten wine64-preloader yolunu bul
if [[ -z "$WIZ_LOADER" ]]; then
    WIZ_LOADER=$(_find_bundled_preloader)
    [[ -n "$WIZ_LOADER" ]] && echo "[speedhack] Preloader ps'ten bulundu: $WIZ_LOADER"
fi

# Oyunun preloader'ını imzala
_sign_target_preloader "$WIZ_LOADER"

# ── Python için Wine seç ──────────────────────────────────────────────────────
if [[ -n "$WIZ_LOADER" && -x "$WIZ_LOADER" ]] && ! _is_bundled_wine "$WIZ_LOADER"; then
    WINE_BIN="$WIZ_LOADER"
    echo "[speedhack] Oyunun Wine'ı kullanılıyor : $WINE_BIN"
else
    if _is_bundled_wine "${WIZ_LOADER:-}"; then
        echo "[speedhack] Homebrew Wine kullanılıyor (gömülü Wine Python için uyumsuz)"
    fi
fi

# ── Python'u Wizard101 prefix'ine kopyala (henüz yoksa) ──────────────────────
WIN_PYTHON="$WIZ_PREFIX/drive_c/Python313/python.exe"
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[speedhack] Python kopyalanıyor → $WIZ_PREFIX/drive_c/Python313"
    cp -r "$OUR_PYTHON" "$WIZ_PREFIX/drive_c/Python313"
fi

export WINEPREFIX="$WIZ_PREFIX"

echo "[speedhack] WINEPREFIX : $WIZ_PREFIX"
echo "[speedhack] Wine       : $WINE_BIN"
echo "[speedhack] Çarpan     : ${MULTIPLIER}x"
echo ""

"$WINE_BIN" "$WIN_PYTHON" "$SCRIPT_DIR/speedhack.py" "$MULTIPLIER"
