#!/usr/bin/env bash
# run_deimos.sh — Wizard101 + Deimos'u AYNI Wine prefix'inde başlatır.
# Aynı wineserver = WizWalker Wizard101'in memory'sini görebilir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

DEIMOS_DIR="${1:-${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}}"

# ── WizardGraphicalClient.exe'yi bul ─────────
_find_wiz_exe() {
    local candidates=(
        # Whisky (Mac Wine manager) — Bottles yapısı
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files (x86)/Wizard101/Bin/WizardGraphicalClient.exe"
        # Bottles olmadan
        "$HOME/Library/Application Support/Wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
    )
    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && echo "$c" && return
    done
    find "$HOME/Library" -name "WizardGraphicalClient.exe" 2>/dev/null | head -1
}

WIZ_EXE=$(_find_wiz_exe)

if [[ -z "$WIZ_EXE" ]]; then
    echo "[run] WizardGraphicalClient.exe otomatik bulunamadı."
    echo "[run] Lütfen exe'nin tam yolunu girin:"
    read -r WIZ_EXE
    if [[ ! -f "$WIZ_EXE" ]]; then
        echo "[run] HATA: Dosya bulunamadı: $WIZ_EXE" >&2
        exit 1
    fi
fi

echo "[run] Wizard101 bulundu: $WIZ_EXE"

# Exe'nin bulunduğu Wine prefix'ini tespit et (drive_c üstü)
WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
echo "[run] Wizard101 Wine prefix: $WIZ_PREFIX"

# ── Prefix mimarisini tespit et ──────────────
_prefix_arch() {
    local reg="$1/system.reg"
    if [[ -f "$reg" ]] && grep -q '#arch=win32' "$reg" 2>/dev/null; then
        echo "win32"
    else
        echo "win64"
    fi
}

WIZ_ARCH=$(_prefix_arch "$WIZ_PREFIX")
echo "[run] Wizard101 prefix mimarisi: $WIZ_ARCH"

# ── Wizard101 için Wine binary'sini seç ──────
# Önce Whisky'nin kendi Wine'ını ara — tam WOW64 desteği var
_find_whisky_wine() {
    local bundle="/Applications/Whisky.app/Contents/Resources/Wine.bundle/Contents/Resources/wine/bin"
    for bin in "$bundle/wine64" "$bundle/wine"; do
        [[ -x "$bin" ]] && echo "$bin" && return
    done
    # Whisky farklı path'te olabilir
    find /Applications/Whisky.app -name "wine64" 2>/dev/null | head -1
    find /Applications/Whisky.app -name "wine"   2>/dev/null | head -1
}

WIZ_WINE="$WINE_BIN"
if [[ -d "/Applications/Whisky.app" ]]; then
    _whisky_wine=$(_find_whisky_wine 2>/dev/null || true)
    if [[ -n "$_whisky_wine" && -x "$_whisky_wine" ]]; then
        WIZ_WINE="$_whisky_wine"
        echo "[run] Whisky Wine kullanılıyor: $WIZ_WINE"
    fi
fi

# ── WINEPREFIX'i Wizard101'inkine geçir ──────
# WINEARCH'ı kaldır — prefix'teki system.reg'den otomatik algılanır.
# detect_wine.sh'in win64 değeri burada çakışma yaratırdı.
export WINEPREFIX="$WIZ_PREFIX"
unset  WINEARCH

echo "[run] Wine binary  : $WIZ_WINE"
echo "[run] WINEPREFIX   : $WINEPREFIX"

# ── Python313'ü Wizard101 prefix'ine kopyala ─
# setup_env.sh bunu ~/.w101d_wine'a kurdu, şimdi Wizard101'in prefix'ine de lazım.
OUR_PYTHON="$HOME/.w101d_wine/drive_c/Python313"
WIN_PYTHON="$WINEPREFIX/drive_c/Python313/python.exe"

if [[ ! -f "$WIN_PYTHON" && -d "$OUR_PYTHON" ]]; then
    echo "[run] Python313, Wizard101 prefix'ine kopyalanıyor..."
    cp -r "$OUR_PYTHON" "$WINEPREFIX/drive_c/Python313"
fi

if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run] HATA: Wine içinde Python bulunamadı. Önce setup_env.sh çalıştırın." >&2
    exit 1
fi

if [[ ! -f "$DEIMOS_DIR/Deimos.py" ]]; then
    echo "[run] HATA: '$DEIMOS_DIR/Deimos.py' bulunamadı." >&2
    exit 1
fi

# ── vcrun2019 — Wizard101 prefix'inde kontrol et ──
if command -v winetricks &>/dev/null; then
    if ! WINEPREFIX="$WINEPREFIX" winetricks --list-installed 2>/dev/null | grep -q vcrun2019; then
        echo "[run] vcrun2019 Wizard101 prefix'ine kuruluyor..."
        WINEPREFIX="$WINEPREFIX" winetricks --unattended vcrun2019 2>/dev/null || true
    fi
fi

# ── Wizard101'i başlat ───────────────────────
echo "[run] Wizard101 başlatılıyor..."
"$WIZ_WINE" "$WIZ_EXE" -L login.us.wizard101.com 12000 &
WIZ_PID=$!

# ── Wizard101'in açılmasını bekle ────────────
echo "[run] Wizard101 yükleniyor, bekleniyor (20 saniye)..."
sleep 20

# Wizard101 hâlâ çalışıyor mu?
if ! kill -0 "$WIZ_PID" 2>/dev/null; then
    echo "[run] HATA: Wizard101 başlamadan kapandı." >&2
    echo "[run] Wine çıktısını yukarıda kontrol edin." >&2
    exit 1
fi

# ── Deimos'u aynı prefix'te başlat ──────────
echo "[run] Deimos başlatılıyor..."
cd "$DEIMOS_DIR"
"$WIZ_WINE" "$WIN_PYTHON" Deimos.py
