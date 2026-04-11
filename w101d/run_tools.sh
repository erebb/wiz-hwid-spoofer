#!/usr/bin/env bash
# run_tools.sh — wiz_tools.py'yi çalışan Wizard101'in Wine prefix'inde başlatır.
# Oyunun WINELOADER'ını okuyarak aynı Wine binary'sini kullanır (CrossOver/Whisky uyumlu).
#
# KULLANIM:
#   bash run_tools.sh            → menü
#   bash run_tools.sh speed 3    → 3x speedhack
#   bash run_tools.sh quest      → quest TP
#   bash run_tools.sh both 3     → ikisi birden
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Çalışan Wizard101'den WINEPREFIX + WINELOADER oku ────────────────────────
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

# ── Wizard101'in Wine'ı gömülü mü? (bundled Wine Python'u crash eder) ────────
_is_bundled_wine() {
    local l="${1:-}"
    [[ "$l" == *"Wizard101.app"* || "$l" == *"wizard101.app"* ]]
}

# ── HEDEF preloader'ı imzala (Wizard101'in çalıştığı Wine) ───────────────────
# macOS güvenlik kuralı: okunan (hedef) program imzalı olmalı, okuyan değil.
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
                echo "[tools] Hedef imzalandı (get-task-allow): $(basename "$b")"
                signed=1
            fi
        done
    done
    rm -f "$ent"
    if [[ "$signed" -eq 0 ]]; then
        echo "[tools] UYARI: Preloader imzalanamadı → memory erişimi başarısız olabilir."
    else
        echo "[tools] NOT: İmza etkili olması için oyunun bir sonraki AÇILIŞINDA geçerli olur."
    fi
}

echo "[tools] Wizard101 aranıyor..."
WIZ_PREFIX=""
WIZ_LOADER=""

for i in $(seq 1 12); do
    env_info=$(_get_wiz_env)
    while IFS= read -r line; do
        [[ "$line" == WINEPREFIX=* ]] && WIZ_PREFIX="${line#WINEPREFIX=}"
        [[ "$line" == WINELOADER=* ]] && WIZ_LOADER="${line#WINELOADER=}"
    done <<< "$env_info"
    if [[ -n "$WIZ_PREFIX" ]]; then echo "[tools] Wizard101 bulundu."; break; fi
    echo "[tools] Bekleniyor... ($i/12) — Wizard101'i aç"
    sleep 5
done

if [[ -z "$WIZ_PREFIX" ]]; then
    echo "[tools] HATA: Wizard101 çalışmıyor." >&2; exit 1
fi

# Oyunun preloader'ını imzala (hedef = Wizard101'in wine64-preloader'ı)
_sign_target_preloader "$WIZ_LOADER"

# ── Python için Wine seç ──────────────────────────────────────────────────────
# Gömülü Wine (Wizard101.app içi) → Homebrew Wine kullan
# CrossOver / Whisky / Homebrew   → AYNI Wine'ı kullan → aynı wineserver
if [[ -n "$WIZ_LOADER" && -x "$WIZ_LOADER" ]] && ! _is_bundled_wine "$WIZ_LOADER"; then
    ACTIVE_WINE="$WIZ_LOADER"
    echo "[tools] Oyunun Wine'ı kullanılıyor : $ACTIVE_WINE"
else
    # Fallback: Homebrew Wine
    ACTIVE_WINE=""
    for c in "/opt/homebrew/bin/wine64" "/opt/homebrew/bin/wine" \
              "/usr/local/bin/wine64"    "/usr/local/bin/wine"; do
        [[ -x "$c" ]] && ACTIVE_WINE="$c" && break
    done
    if [[ -z "$ACTIVE_WINE" ]]; then
        echo "[tools] HATA: Wine bulunamadı." >&2; exit 1
    fi
    if _is_bundled_wine "${WIZ_LOADER:-}"; then
        echo "[tools] Homebrew Wine kullanılıyor (gömülü Wine Python için uyumsuz)"
    else
        echo "[tools] Homebrew Wine kullanılıyor : $ACTIVE_WINE"
    fi
fi

WIN_PYTHON="$WIZ_PREFIX/drive_c/Python313/python.exe"
WIN_TOOLS="$WIZ_PREFIX/drive_c/wiz_tools.py"

if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[tools] HATA: Python bulunamadı → $WIN_PYTHON" >&2
    echo "[tools]       setup_single.sh veya setup_env.sh çalıştırın." >&2
    exit 1
fi

cp "$SCRIPT_DIR/wiz_tools.py" "$WIN_TOOLS"
export WINEPREFIX="$WIZ_PREFIX"

echo "[tools] Wine       : $ACTIVE_WINE"
echo "[tools] WINEPREFIX : $WIZ_PREFIX"
echo ""

exec "$ACTIVE_WINE" "$WIN_PYTHON" "$WIN_TOOLS" "$@"
