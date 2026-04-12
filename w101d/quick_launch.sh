#!/usr/bin/env bash
source detect_wine.sh

# --- BİLGİLERİN ---
USER="KULLANICI_ADIN"
PASS="SIFREN"
# ------------------

WIZ_BIN="/Users/erenozdemir/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin"

if [ -d "$WIZ_BIN" ]; then
    cd "$WIZ_BIN"
    echo "[QuickLaunch] XML hatası onlendi ve oyun baslatılıyor..."
    "$WINE_BIN" WizardGraphicalClient.exe -L login.us.wizard101.com 12000 -u "$USER" -p "$PASS" > /dev/null 2>&1 &
    echo "Basarılı! KingsIsle ekranı birazdan gelir."
else
    echo "HATA: Oyun klasoru bulunamadı!"
fi
