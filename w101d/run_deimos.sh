#!/usr/bin/env bash
# run_deimos.sh — Wizard101 + Deimos'u AYNI Wine prefix'inde başlatır.
# Aynı wineserver = WizWalker Wizard101'in memory'sini görebilir.
#
# ÖNEMLİ: Wizard101.app'in wine'ı (wineserver 930) ile Homebrew wine
# (wineserver 655) uyumsuz → Deimos da Wizard101.app'in wine'ıyla çalışmalı.
# Wizard101 launch: 'open -a Wizard101' (data mount ve patcher için gerekli).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

# ── Argüman parsing ──────────────────────────
DEIMOS_ONLY=0
DEIMOS_DIR_ARG=""
for arg in "$@"; do
    if [[ "$arg" == "--deimos-only" ]]; then
        DEIMOS_ONLY=1
    elif [[ -z "$DEIMOS_DIR_ARG" && "$arg" != --* ]]; then
        DEIMOS_DIR_ARG="$arg"
    fi
done
DEIMOS_DIR="${DEIMOS_DIR_ARG:-${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}}"

# ── WizardGraphicalClient.exe'yi bul ─────────
_find_wiz_exe() {
    local candidates=(
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files (x86)/Wizard101/Bin/WizardGraphicalClient.exe"
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

# ── Wizard101.app'in kendi Wine binary'sini bul ──────────────────────────────
# Wizard101.app kendi Wine'ını içinde barındırır (wineserver 930).
# Homebrew wine (wineserver 655) farklı protokol → wineserver uyumsuzluğu.
# Deimos dahil HER ŞEY bu Wine ile çalışmalı.
_find_wiz_app_wine() {
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
        local found
        found=$(find "$app/Contents" \( -name "wine64" -o -name "wine" \) -type f 2>/dev/null | head -1)
        if [[ -n "$found" && -x "$found" ]]; then
            echo "$found"
            return
        fi
    done

    # Whisky fallback
    local whisky_bin="/Applications/Whisky.app/Contents/Resources/Wine.bundle/Contents/Resources/wine/bin"
    for b in "$whisky_bin/wine64" "$whisky_bin/wine"; do
        [[ -x "$b" ]] && echo "$b" && return
    done
    echo ""
}

WIZ_WINE=$(_find_wiz_app_wine)

if [[ -z "$WIZ_WINE" ]]; then
    echo "[run] UYARI: Wizard101.app içinde Wine binary bulunamadı. Homebrew kullanılıyor." >&2
    WIZ_WINE="$WINE_BIN"
else
    echo "[run] Wizard101 Wine binary: $WIZ_WINE"
fi

# ── WINEPREFIX'i Wizard101'inkine geçir ──────
export WINEPREFIX="$WIZ_PREFIX"
unset WINEARCH
echo "[run] WINEPREFIX: $WINEPREFIX"

# ── propsys.dll fix ───────────────────────────
# Wizard101.app'in wine32on64'ü propsys.dll.VariantToString'i implemente etmemiş.
# Çözüm: mingw-w64 ile minimal stub DLL derle, prefix'e kopyala.

_build_propsys_stub() {
    local out="$1"  # hedef dizin

    # mingw-w64 yoksa kur
    if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
        echo "[run] mingw-w64 kuruluyor (propsys stub için)..."
        brew install mingw-w64 2>/dev/null || {
            echo "[run] HATA: mingw-w64 kurulamadı." >&2
            return 1
        }
    fi

    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN

    # propsys_stub.c — NO headers (propvarutil.h'ı dahil etmemek için)
    # Aksi hâlde propvarutil.h inline çağrıları import tablosuna girer.
    cat > "$tmp/propsys_stub.c" << 'CEOF'
/* propsys minimal stub — NO standard headers */
typedef unsigned short  wchar_t;
typedef long            HRESULT;
typedef unsigned int    UINT;
typedef int             BOOL;
typedef void*           HMODULE;
typedef unsigned long   DWORD;
typedef void*           LPVOID;

HRESULT VariantToString(const void* propvar, wchar_t* psz, UINT cch)
{
    if (psz && cch > 0) *psz = (wchar_t)0;
    return 0; /* S_OK */
}

BOOL __stdcall DllMain(HMODULE h, DWORD r, LPVOID p) { return 1; }
CEOF

    # .def dosyası — export tablosunu doğrudan tanımlar, -nostdlib gerekmez
    # -nostdlib/-nostartfiles PE header'ı bozuyordu (VariantToString yanlış offset'e işaret ediyordu)
    cat > "$tmp/propsys.def" << 'DEOF'
LIBRARY "propsys"
EXPORTS
    VariantToString
DEOF

    local build_log="$tmp/build.log"
    if x86_64-w64-mingw32-gcc -shared -o "$tmp/propsys.dll" \
            "$tmp/propsys_stub.c" "$tmp/propsys.def" \
            -static-libgcc \
            2>"$build_log"; then
        cp "$tmp/propsys.dll" "$out/propsys_stub_v2.dll"
        echo "[run] propsys.dll stub derlendi ve kopyalandı."
        return 0
    else
        echo "[run] HATA: propsys.dll stub derlenemedi:" >&2
        cat "$build_log" >&2
        return 1
    fi
}

_fix_propsys() {
    local prefix="$1"
    local sys32="$prefix/drive_c/windows/system32"
    # v2 = -static-libgcc ile derlendi (libgcc_s.dll bağımlılığı yok)
    local cached_stub="$HOME/.w101d_cache/propsys_stub_v2.dll"

    # NOT: Wine'ın kendi lib dizinlerindeki propsys.dll'leri Wine 6.0'da
    # VariantToString'i implemente etmemiş (sadece "unimplemented relay" içeriyor).
    # Bu yüzden sistem propsys.dll'i ASLA kullanmıyoruz — daima kendi stub'ımız.

    if [[ ! -f "$cached_stub" ]]; then
        echo "[run] propsys.dll stub derleniyor (mingw-w64)..."
        mkdir -p "$HOME/.w101d_cache"
        if ! _build_propsys_stub "$HOME/.w101d_cache"; then
            echo "[run] UYARI: propsys.dll stub derlenemedi — Python crash devam edecek." >&2
            return
        fi
    else
        echo "[run] Önceden derlenmiş propsys.dll stub kullanılıyor (v2)."
    fi

    echo "[run] propsys.dll → $sys32/propsys.dll"
    cp "$cached_stub" "$sys32/propsys.dll"
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+${WINEDLLOVERRIDES};}propsys=n,b"
    echo "[run] WINEDLLOVERRIDES: $WINEDLLOVERRIDES"
}

_fix_propsys "$WINEPREFIX"

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

# ── Wizard101'i başlat ───────────────────────
_wiz_running() {
    pgrep -f "WizardGraphicalClient.exe" > /dev/null 2>&1
}

if [[ "$DEIMOS_ONLY" -eq 0 ]]; then
    if _wiz_running; then
        echo "[run] Wizard101 zaten çalışıyor."
    else
        echo "[run] Wizard101 başlatılıyor (open -a)..."
        # 'open -a' → Mac uygulama mekanizmasıyla açar.
        # '-L login.us.wizard101.com 12000' flag'i data mount'u atladığı için
        # WizardMessages.xml / client.xml bulunamıyor. Patcher akışı gerekli.
        open -a "Wizard101" 2>/dev/null || {
            echo "[run] HATA: 'open -a Wizard101' başarısız." >&2
            echo "[run] Wizard101'i kendiniz açın, sonra: bash run_deimos.sh --deimos-only" >&2
            exit 1
        }

        echo "[run] Wizard101'in açılması bekleniyor (en fazla 120 saniye)..."
        for i in $(seq 1 60); do
            _wiz_running && break
            sleep 2
        done

        if ! _wiz_running; then
            echo "[run] HATA: Wizard101 120sn içinde başlamadı." >&2
            echo "[run] Wizard101'i kendiniz açın, sonra: bash run_deimos.sh --deimos-only" >&2
            exit 1
        fi
        echo "[run] Wizard101 çalışıyor. Login/yükleme tamamlanana kadar bekliyoruz..."
        sleep 10
    fi
else
    echo "[run] --deimos-only: Wizard101 başlatılmıyor."
    if ! _wiz_running; then
        echo "[run] UYARI: WizardGraphicalClient.exe çalışmıyor görünüyor."
        echo "[run] Wizard101'i önce açın, sonra bu scripti tekrar çalıştırın."
    fi
fi

# ── Deimos'u Wizard101'in wine'ıyla başlat ───
# Homebrew wine farklı wineserver protokolü (655 vs 930) → version mismatch.
# Wizard101.app'in wine'ı hem game hem Deimos için → aynı wineserver.
echo "[run] Deimos başlatılıyor (Wizard101 wine: $WIZ_WINE)..."
cd "$DEIMOS_DIR"
WINEPREFIX="$WINEPREFIX" WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-propsys=n,b}" \
    "$WIZ_WINE" "$WIN_PYTHON" Deimos.py
