#!/usr/bin/env bash
# run_deimos.sh — Wizard101 araçlarını çalıştırır.
#
# Mac/Wine memory erişim mimarisi:
#   - Oyun (WizardGraphicalClient.exe) kendi Wine'ında çalışır
#   - Python/Deimos Homebrew Wine ile çalışır (bundled Wine Python'u crash eder)
#   - Bellek erişimi: oyunun wine64-preloader'ını get-task-allow ile imzalarız
#     → macOS task_for_pid izin verir → pymem cross-process okuyabilir
#   - CrossOver/Whisky kullanıcıları: WINELOADER alınır, Python ile aynı
#     Wine kullanılır (aynı wineserver = memory erişimi daha güvenilir)
#
# KULLANIM:
#   bash run_deimos.sh              → Deimos
#   bash run_deimos.sh speed [N]    → Nx speedhack
#   bash run_deimos.sh quest        → quest TP
#   bash run_deimos.sh both [N]     → ikisi birden
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"   # WINE_BIN (Homebrew Wine)

MODE="${1:-deimos}"
MULTIPLIER="${2:-3}"
OUR_PYTHON="$HOME/.w101d_wine/drive_c/Python313"
DEIMOS_DIR="${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}"

# ── Kurulum kontrolü ──────────────────────────────────────────────────────────
if [[ ! -d "$OUR_PYTHON" ]]; then
    echo "[run] HATA: Python bulunamadı. Önce setup_env.sh çalıştırın." >&2; exit 1
fi
if [[ "$MODE" == "deimos" && ! -f "$DEIMOS_DIR/Deimos.py" ]]; then
    echo "[run] HATA: Deimos bulunamadı." >&2; exit 1
fi

# ── Çalışan Wizard101'den WINEPREFIX + WINELOADER oku ────────────────────────
# ps auxww: pgrep'ten farklı olarak çok uzun komut satırlarını da yakalar
_get_wiz_env() {
    local pid
    pid=$(ps auxww | grep -i "WizardGraphicalClient.exe" | grep -v grep \
          | awk '{print $2}' | head -1)
    [[ -z "$pid" ]] && return
    # Python regex: boşluklu yolları (Application Support vb.) doğru okur
    ps eww -p "$pid" 2>/dev/null | python3 -c "
import sys, re
txt = sys.stdin.read()
for key in ('WINEPREFIX', 'WINELOADER'):
    m = re.search(rf'{key}=(.*?)(?:\s+[A-Z_][A-Z0-9_]*=|\s*\Z)', txt, re.DOTALL)
    if m: print(f'{key}={m.group(1).strip()}')
" 2>/dev/null
}

# Bundled Wine (Wizard101.app) WINELOADER set etmeyebilir → ps'ten wine64-preloader yolunu çek
_find_bundled_preloader() {
    ps auxww 2>/dev/null \
        | grep -i "wine64-preloader" | grep -iv grep \
        | grep -i "Wizard101" \
        | awk '{print $11}' | head -1
}

# ── Wizard101'in Wine'ı gömülü mü? (bundled Wine Python'u crash eder) ────────
_is_bundled_wine() {
    local l="${1:-}"
    # Wizard101'in kendi app bundle'ı içindeki wine = gömülü/stripped Wine
    [[ "$l" == *"Wizard101.app"* || "$l" == *"wizard101.app"* ]]
}

# ── HEDEF preloader'ı imzala (Wizard101'in çalıştığı Wine) ───────────────────
# macOS güvenlik kuralı: okunan (hedef) program imzalı olmalı, okuyan değil.
# Bu yüzden oyunun Wine preloader'ını imzalıyoruz, Homebrew'un değil.
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
                echo "[run] Hedef imzalandı (get-task-allow): $(basename "$b")"
                signed=1
            fi
        done
    done
    rm -f "$ent"
    if [[ "$signed" -eq 0 ]]; then
        echo "[run] UYARI: Preloader imzalanamadı → memory erişimi başarısız olabilir."
        echo "[run]        Oyunu kapatıp setup_env.sh'ı tekrar çalıştır, sonra oyunu aç."
    else
        echo "[run] NOT: İmza etkili olması için oyunun bir sonraki AÇILIŞINDA geçerli olur."
    fi
}

# ── Wizard101'i bul ───────────────────────────────────────────────────────────
echo "[run] Wizard101 aranıyor..."
WIZ_PREFIX=""
WIZ_LOADER=""

for i in $(seq 1 12); do
    env_info=$(_get_wiz_env)
    while IFS= read -r line; do
        [[ "$line" == WINEPREFIX=* ]] && WIZ_PREFIX="${line#WINEPREFIX=}"
        [[ "$line" == WINELOADER=* ]] && WIZ_LOADER="${line#WINELOADER=}"
    done <<< "$env_info"
    if [[ -n "$WIZ_PREFIX" ]]; then echo "[run] Wizard101 bulundu."; break; fi
    echo "[run] Bekleniyor... ($i/12) — Wizard101'i aç"
    sleep 5
done

[[ -z "$WIZ_PREFIX" ]] && { echo "[run] HATA: Wizard101 çalışmıyor." >&2; exit 1; }

# Bundled Wine WINELOADER set etmeyebilir → ps'ten wine64-preloader yolunu bul
if [[ -z "$WIZ_LOADER" ]]; then
    WIZ_LOADER=$(_find_bundled_preloader)
    [[ -n "$WIZ_LOADER" ]] && echo "[run] Preloader ps'ten bulundu: $WIZ_LOADER"
fi

# Oyunun preloader'ını imzala (hedef = Wizard101'in wine64-preloader'ı)
_sign_target_preloader "$WIZ_LOADER"

# ── Python için Wine seç ──────────────────────────────────────────────────────
# Kural:
#   • Gömülü Wine (Wizard101.app içi) → Homebrew Wine kullan, task_for_pid ile eri
#   • CrossOver / Whisky / Homebrew   → AYNI Wine'ı kullan → aynı wineserver → daha güvenilir
if [[ -n "$WIZ_LOADER" && -x "$WIZ_LOADER" ]] && ! _is_bundled_wine "$WIZ_LOADER"; then
    ACTIVE_WINE="$WIZ_LOADER"
    echo "[run] Oyunun Wine'ı kullanılıyor : $ACTIVE_WINE"
    echo "[run] (Aynı wineserver → memory erişimi garantili)"
else
    ACTIVE_WINE="$WINE_BIN"
    if _is_bundled_wine "${WIZ_LOADER:-}"; then
        echo "[run] Homebrew Wine kullanılıyor (gömülü Wine Python için uyumsuz)"
        echo "[run] → Memory erişimi task_for_pid ile sağlanıyor (imzalama gerekli)"
    else
        echo "[run] Homebrew Wine kullanılıyor : $ACTIVE_WINE"
    fi
fi

# ── Python'u oyunun prefix'ine kopyala (yoksa) ───────────────────────────────
WIN_PYTHON="$WIZ_PREFIX/drive_c/Python313/python.exe"
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run] Python kopyalanıyor → $WIZ_PREFIX/drive_c/Python313"
    cp -r "$OUR_PYTHON" "$WIZ_PREFIX/drive_c/Python313"
fi
if [[ "$MODE" != "deimos" ]]; then
    cp "$SCRIPT_DIR/wiz_tools.py" "$WIZ_PREFIX/drive_c/wiz_tools.py"
fi

export WINEPREFIX="$WIZ_PREFIX"
echo "[run] WINEPREFIX : $WIZ_PREFIX"
echo "[run] Mod        : $MODE"
echo ""

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
        echo "[run] HATA: Bilinmeyen mod '$MODE'" >&2; exit 1
        ;;
esac
