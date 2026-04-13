#!/usr/bin/env bash
# quick_launch.sh — Wizard101'i launcher olmadan direkt başlatır (otomatik giriş).
#
# Auth akışı (cedws/umbra-launcher ve MidasModLoader/Launcher kaynaklarına göre):
#   1. ki_auth.py KI login sunucusuna bağlanır, Twofish-OFB handshake yapar
#   2. uid + ck2 token alır
#   3. Oyun: -L login.us.wizard101.com 12000 -U ..{uid} {ck2} {username}
#
# Streaming fix:
#   WINEPREFIX oyunun kendi Bottles prefix'ine set edilir → registry + data path doğru.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Giriş bilgileri ───────────────────────────────────────────────────────────
WIZ_USER="KULLANICI_ADIN"
WIZ_PASS="SIFREN"

# ── Oyun exe'sini otomatik bul ────────────────────────────────────────────────
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

# ── Bundled Wine binary'sini bul ─────────────────────────────────────────────
# Oyunun kendi Wine'ı (Wizard101.app içindeki) kullanılmalı — böylece
# oyunun prefix'iyle uyumlu wineserver başlar, streaming çalışır.
_find_bundled_wine() {
    # 1. Wizard101.app içinde bilinen yollar
    for b in \
        "/Applications/Wizard101.app/Contents/SharedSupport/wine/bin/wine64" \
        "/Applications/Wizard101.app/Contents/SharedSupport/wine/bin/wine" \
        "/Applications/Wizard101.app/Contents/Resources/wine/bin/wine64" \
        "/Applications/Wizard101.app/Contents/Resources/wine/bin/wine" \
        "/Applications/Wizard101.app/Contents/MacOS/wine64" \
        "/Applications/Wizard101.app/Contents/MacOS/wine"; do
        [[ -x "$b" ]] && echo "$b" && return
    done

    # 2. Wizard101.app içinde tüm wine binary'leri ara
    if [[ -d "/Applications/Wizard101.app" ]]; then
        local found
        found=$(find /Applications/Wizard101.app -type f \
                     \( -name "wine64" -o -name "wine" \) 2>/dev/null \
                | grep -v "wineserver\|winecfg\|wineboot\|winepath" \
                | head -1 || true)
        [[ -n "$found" && -x "$found" ]] && echo "$found" && return
    fi

    # 3. Çalışan wineserver'dan türet (oyun zaten açıksa)
    local ws
    ws=$(ps auxww 2>/dev/null | grep -iE "[Ww]ineserver" | grep -v grep \
         | awk '{print $11}' | head -1 || true)
    if [[ -n "$ws" && -x "$ws" ]]; then
        local bd="${ws%/*}"
        for b in "$bd/wine64" "$bd/wine"; do
            [[ -x "$b" ]] && echo "$b" && return
        done
    fi

    # 4. Fallback: Homebrew Wine (streaming çalışmayabilir ama oyun açılır)
    source "$SCRIPT_DIR/detect_wine.sh"
    echo "$WINE_BIN"
}

# ─────────────────────────────────────────────────────────────────────────────
WIZ_EXE=$(_find_wiz_exe)

if [[ -z "$WIZ_EXE" || ! -f "$WIZ_EXE" ]]; then
    echo "[QuickLaunch] HATA: WizardGraphicalClient.exe bulunamadı!"
    echo "  Wizard101'in kurulu olduğundan ve ~/Library/Application Support/Wizard101"
    echo "  dizininde bulunduğundan emin olun."
    exit 1
fi

WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
WIZ_BIN_DIR=$(dirname "$WIZ_EXE")
WINE_BIN=$(_find_bundled_wine)

# Oyunun kendi prefix'ini kullan → registry + data path'leri doğru → streaming çalışır
export WINEPREFIX="$WIZ_PREFIX"

echo "[QuickLaunch] Exe     : $WIZ_EXE"
echo "[QuickLaunch] Prefix  : $WIZ_PREFIX"
echo "[QuickLaunch] Wine    : $WINE_BIN"

# Wine binary var mı kontrol et
if [[ ! -x "$WINE_BIN" ]]; then
    echo "[QuickLaunch] HATA: Wine binary bulunamadı veya çalıştırılamıyor: $WINE_BIN"
    echo "  Wizard101.app kurulu mu? /Applications/Wizard101.app var mı?"
    exit 1
fi

# ── KI Auth: uid + ck2 token al ──────────────────────────────────────────────
echo "[QuickLaunch] KI sunucusuna bağlanılıyor (ki_auth.py)..."
AUTH_OUT=$(python3 "$SCRIPT_DIR/ki_auth.py" "$WIZ_USER" "$WIZ_PASS" 2>&1) || {
    echo "[QuickLaunch] HATA: Kimlik doğrulama başarısız!"
    echo "  $AUTH_OUT"
    echo "  → Kullanıcı adı/şifre doğru mu? İnternet bağlantısı var mı?"
    echo "  → pycryptodome kurulu mu? (pip3 install pycryptodome)"
    exit 1
}
WIZ_UID=$(echo "$AUTH_OUT" | awk '{print $1}')
WIZ_CK2=$(echo "$AUTH_OUT" | awk '{print $2}')
if [[ -z "$WIZ_UID" || -z "$WIZ_CK2" ]]; then
    echo "[QuickLaunch] HATA: ki_auth.py geçersiz çıktı verdi: $AUTH_OUT"
    exit 1
fi
echo "[QuickLaunch] Auth     : OK (uid=$WIZ_UID)"

echo "[QuickLaunch] Oyun başlatılıyor..."
echo "[QuickLaunch] (İlk 10 saniye Wine çıktısı aşağıda görünür — normal)"
echo ""

cd "$WIZ_BIN_DIR"
# Doğru arg formatı (umbra-launcher + MidasModLoader referansına göre):
#   -L <host> <port> -U ..<uid> <ck2> <username>
# NOT: -u/-p değil, önce token alıp -U ile geçilmeli
"$WINE_BIN" WizardGraphicalClient.exe \
    -L login.us.wizard101.com 12000 \
    -U "..$WIZ_UID" "$WIZ_CK2" "$WIZ_USER" \
    2>&1 | head -40 &

# Oyunun başlayıp başlamadığını kısa süre izle
sleep 6
if ps auxww 2>/dev/null | grep -i "WizardGraphicalClient" | grep -qv grep; then
    echo ""
    echo "[QuickLaunch] Tamam! Oyun başladı."
    echo "             KingsIsle ekranı birazdan gelir."
    echo "             Zone'lara girişte dosya indirme artık çalışmalı."
else
    echo ""
    echo "[QuickLaunch] UYARI: 6 saniye sonra WizardGraphicalClient processi görünmüyor."
    echo "  → Yukarıdaki Wine çıktısında hata var mı kontrol edin."
    echo "  → Wine versiyonu uyumsuzluğu olabilir (bundled vs Homebrew)."
    echo "  → WINEPREFIX: $WINEPREFIX"
    echo "  → WINE_BIN  : $WINE_BIN"
fi
