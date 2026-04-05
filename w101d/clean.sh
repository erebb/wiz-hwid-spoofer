#!/usr/bin/env bash
# clean.sh — setup_env.sh ve run_deimos.sh tarafından oluşturulan
#            her şeyi tamamen siler.
#
# Silinenler:
#   ~/.w101d_wine      → Deimos için oluşturulan Wine prefix
#   ~/.w101d_cache     → Python installer, wizwalker, wizsprinter, Deimos repoları
#
# Silinmeyenler:
#   Homebrew / wine-stable / winetricks  (sistem geneli, biz kurmadık sayılır)
#   Wizard101'in kendi Whisky prefix'i   (bizim işimiz değil)
set -euo pipefail

DEIMOS_WINE="$HOME/.w101d_wine"
CACHE="$HOME/.w101d_cache"

# Wizard101'in prefix'ine kopyaladığımız Python'u da sil
# run_deimos.sh bunu WIZ_PREFIX/drive_c/Python313'e kopyalar.
# Nereye kopyalandığını bilmiyoruz; kullanıcıya soralım.

echo "========================================"
echo "  w101d Temizleyici"
echo "========================================"
echo ""
echo "Şunlar silinecek:"
echo "  $DEIMOS_WINE"
echo "  $CACHE"
echo ""

# Wizard101 prefix'ine kopyalanan Python'u da silmek istiyor mu?
EXTRA_PYTHON=""
read -r -p "Wizard101'in Wine prefix'indeki Python kopyasını da silmek ister misiniz? (e/H): " ans
if [[ "$ans" =~ ^[Ee]$ ]]; then
    echo ""
    echo "WizardGraphicalClient.exe'nin yolunu girin (boş bırakırsanız atlanır):"
    echo "Örnek: /Users/kullanici/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/..."
    read -r WIZ_EXE_PATH
    if [[ -n "$WIZ_EXE_PATH" && -f "$WIZ_EXE_PATH" ]]; then
        WIZ_PREFIX=$(echo "$WIZ_EXE_PATH" | sed 's|/drive_c/.*||')
        EXTRA_PYTHON="$WIZ_PREFIX/drive_c/Python313"
        echo "  $EXTRA_PYTHON"
    fi
fi

echo ""
read -r -p "Emin misiniz? Bu işlem geri alınamaz. (e/H): " confirm
if [[ ! "$confirm" =~ ^[Ee]$ ]]; then
    echo "İptal edildi."
    exit 0
fi

echo ""

if [[ -d "$DEIMOS_WINE" ]]; then
    echo "[clean] Siliniyor: $DEIMOS_WINE"
    rm -rf "$DEIMOS_WINE"
    echo "[clean] Tamam."
else
    echo "[clean] Zaten yok: $DEIMOS_WINE"
fi

if [[ -d "$CACHE" ]]; then
    echo "[clean] Siliniyor: $CACHE"
    rm -rf "$CACHE"
    echo "[clean] Tamam."
else
    echo "[clean] Zaten yok: $CACHE"
fi

if [[ -n "$EXTRA_PYTHON" ]]; then
    if [[ -d "$EXTRA_PYTHON" ]]; then
        echo "[clean] Siliniyor: $EXTRA_PYTHON"
        rm -rf "$EXTRA_PYTHON"
        echo "[clean] Tamam."
    else
        echo "[clean] Zaten yok: $EXTRA_PYTHON"
    fi
fi

echo ""
echo "[clean] Temizlik tamamlandı."
echo "Tekrar kullanmak için: bash setup_env.sh"
