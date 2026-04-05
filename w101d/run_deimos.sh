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
        # Resmi Mac Wizard101 uygulaması (kendi Wine'ı + prefix'i var)
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

# ── Wizard101 uygulamasının kendi Wine binary'sini bul ────────────────────────
# Mac Wizard101 uygulaması kendi Wine'ını içinde barındırır.
# SADECE bu Wine o prefix ile uyumludur — Homebrew wine kullanmak DLL hatası verir.
#
# Prefix yolu örn: ~/Library/Application Support/Wizard101/Bottles/wizard101
# Uygulama yolu  : /Applications/Wizard101.app  (veya özel ad)
_find_wiz_app_wine() {
    # Prefix path'inden uygulama adını çıkarmaya çalış
    # ~/Library/Application Support/Wizard101/Bottles/... → Wizard101
    local app_name
    app_name=$(echo "$WIZ_PREFIX" | grep -oE 'Application Support/[^/]+' | cut -d/ -f2 || true)

    local search_dirs=()
    [[ -n "$app_name" ]] && search_dirs+=("/Applications/${app_name}.app")
    search_dirs+=(
        "/Applications/Wizard101.app"
        "/Applications/KingsIsle Wizard101.app"
    )

    for app in "${search_dirs[@]}"; do
        [[ -d "$app" ]] || continue
        # wine64 önce dene (64-bit), yoksa wine (32-bit)
        local found
        found=$(find "$app/Contents" \( -name "wine64" -o -name "wine" \) -type f 2>/dev/null | head -1)
        if [[ -n "$found" && -x "$found" ]]; then
            echo "$found"
            return
        fi
    done

    # Whisky de dene (kullanıcı Whisky üzerinden kurmuş olabilir)
    local whisky_bin="/Applications/Whisky.app/Contents/Resources/Wine.bundle/Contents/Resources/wine/bin"
    for b in "$whisky_bin/wine64" "$whisky_bin/wine"; do
        [[ -x "$b" ]] && echo "$b" && return
    done

    echo ""
}

WIZ_WINE=$(_find_wiz_app_wine)

if [[ -z "$WIZ_WINE" ]]; then
    echo "[run] UYARI: Wizard101.app içinde Wine binary bulunamadı."
    echo "[run] Homebrew Wine deneniyor: $WINE_BIN"
    echo "[run] DLL hataları alırsanız Wizard101'i Whisky üzerinden başlatın,"
    echo "[run]   sonra bu scripti aşağıdaki flag ile tekrar çalıştırın:"
    echo "[run]   bash run_deimos.sh --deimos-only"
    WIZ_WINE="$WINE_BIN"
else
    echo "[run] Wizard101 Wine binary: $WIZ_WINE"
fi

# ── WINEPREFIX ve WINEARCH'ı ayarla ──────────
# detect_wine.sh WINEARCH=win64 set etti — bunu kaldır.
# Wine binary'si prefix'teki system.reg'den mimariyi otomatik algılar.
export WINEPREFIX="$WIZ_PREFIX"
unset WINEARCH

echo "[run] WINEPREFIX: $WINEPREFIX"

# ── Python313'ü Wizard101 prefix'ine kopyala ─
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

# ── --deimos-only modu: Wizard101'i başlatma ─
DEIMOS_ONLY=0
for arg in "$@"; do
    [[ "$arg" == "--deimos-only" ]] && DEIMOS_ONLY=1
done

if [[ "$DEIMOS_ONLY" -eq 0 ]]; then
    echo "[run] Wizard101 başlatılıyor..."
    # Oyun kendi dizininden çalışmalı — aksi hâlde ./client.xml vb. bulunamaz
    WIZ_DIR=$(dirname "$WIZ_EXE")
    (cd "$WIZ_DIR" && WINEPREFIX="$WINEPREFIX" "$WIZ_WINE" "$WIZ_EXE" -L login.us.wizard101.com 12000) &
    WIZ_PID=$!

    echo "[run] Wizard101 yükleniyor, bekleniyor (20 saniye)..."
    sleep 20

    if ! kill -0 "$WIZ_PID" 2>/dev/null; then
        echo "[run] HATA: Wizard101 başlamadan kapandı." >&2
        echo "[run] Eğer DLL hatası aldıysanız, Wizard101'i normal şekilde (Whisky/app üzerinden)" >&2
        echo "[run] açın ve ardından: bash run_deimos.sh --deimos-only" >&2
        exit 1
    fi
else
    echo "[run] --deimos-only: Wizard101 başlatılmıyor, sadece Deimos başlatılıyor."
    if ! pgrep -f "WizardGraphicalClient.exe" > /dev/null 2>&1; then
        echo "[run] UYARI: WizardGraphicalClient.exe çalışmıyor görünüyor."
        echo "[run] Wizard101'i önce açın, sonra bu scripti tekrar çalıştırın."
    fi
fi

# ── Deimos'u aynı prefix'te başlat ──────────
echo "[run] Deimos başlatılıyor..."
cd "$DEIMOS_DIR"
WINEPREFIX="$WINEPREFIX" "$WIZ_WINE" "$WIN_PYTHON" Deimos.py
