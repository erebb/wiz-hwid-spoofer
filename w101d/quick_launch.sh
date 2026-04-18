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

# Steam hesabı: 1 olarak ayarla (normal KI hesabı için 0)
# AccountClientMismatch alıyorsanız bu değeri değiştirin.
export WIZ_IS_STEAM=1

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

# ── Homebrew Wine kullan (Deimos ile aynı wineserver → Deimos oyunu görür) ───
# Bundled Wine kullanmak Deimos'u kör eder (farklı wineserver).
# Homebrew Wine + ~/.w101d_wine = Deimos ile aynı prefix+wineserver.
source "$SCRIPT_DIR/detect_wine.sh"   # WINE_BIN (Homebrew), WINEPREFIX (~/.w101d_wine)
DEIMOS_PREFIX="$WINEPREFIX"           # ~/.w101d_wine

# Oyun data dizinini Deimos prefix'ine symlink et
# Böylece game registry'deki C:\ProgramData\... yolu ~/.w101d_wine içinden çözümlenir.
_setup_game_symlinks() {
    local src_c="$WIZ_PREFIX/drive_c"
    local dst_c="$DEIMOS_PREFIX/drive_c"
    local linked=0
    for item in \
        "ProgramData/KingsIsle Entertainment" \
        "users/Public/Games/KingsIsle Entertainment"; do
        local src="$src_c/$item"
        local dst="$dst_c/$item"
        if [[ -d "$src" && ! -e "$dst" ]]; then
            mkdir -p "$(dirname "$dst")"
            ln -sf "$src" "$dst"
            echo "[QuickLaunch] Symlink : $item → Bottles"
            linked=1
        fi
    done
    # Game registry: ~/.w101d_wine/system.reg'e Bottles'tan KingsIsle key'leri yoksa ekle
    if ! grep -qi "KingsIsle" "$DEIMOS_PREFIX/system.reg" 2>/dev/null; then
        python3 -c "
import re, os
bottles_reg = '$WIZ_PREFIX/system.reg'
deimos_reg  = '$DEIMOS_PREFIX/system.reg'
try:
    src = open(bottles_reg, errors='ignore').read()
    m = re.search(r'(\[Software\\\\\\\\KingsIsle.*?)(?=\n\[|\Z)', src, re.DOTALL|re.I)
    if m:
        open(deimos_reg, 'a').write('\n' + m.group(1) + '\n')
        print('[QuickLaunch] Registry: KingsIsle key aktarıldı')
except Exception as e:
    print(f'[QuickLaunch] Registry aktarım atlandı: {e}')
" 2>/dev/null || true
    fi
}
_setup_game_symlinks

# Artık Homebrew Wine + ~/.w101d_wine kullan
# WINEPREFIX detect_wine.sh'dan geldi (~/.w101d_wine) — değiştirme
export WINEPREFIX="$DEIMOS_PREFIX"

echo "[QuickLaunch] Exe     : $WIZ_EXE"
echo "[QuickLaunch] Prefix  : $WINEPREFIX  (Homebrew — Deimos ile aynı wineserver)"
echo "[QuickLaunch] Wine    : $WINE_BIN"

# Wine binary var mı kontrol et
if [[ ! -x "$WINE_BIN" ]]; then
    echo "[QuickLaunch] HATA: Homebrew Wine bulunamadı: $WINE_BIN"
    echo "  Kurmak için: brew install --cask wine-stable"
    exit 1
fi

# ── Oyun versiyonunu registry'den oku (AccountClientMismatch önlemek için) ───
# ki_auth.py de WINEPREFIX'ten okur; bu blok ek bir Wine reg sorgusu ile
# doğrudan shell'de bulunursa da kullanılabilir.
if [[ -z "${WIZ_GAME_VERSION:-}" ]]; then
    _REG_VER=$(
        grep -i '"Version"' "$WIZ_PREFIX/user.reg" "$WIZ_PREFIX/system.reg" \
             2>/dev/null \
        | grep -i "KingsIsle\|Wizard101" \
        | grep -oP '"Version"="\K[^"]+' \
        | head -1 || true
    )
    # Alternatif: section'a göre ara
    if [[ -z "$_REG_VER" ]]; then
        _REG_VER=$(
            python3 -c "
import re, sys
for f in ['$WIZ_PREFIX/user.reg','$WIZ_PREFIX/system.reg']:
    try:
        t = open(f, errors='ignore').read()
        m = re.search(r'\[Software\\\\\\\\KingsIsle Entertainment\\\\\\\\Wizard101[^\]]*\][^\[]*?\"Version\"=\"([^\"]+)\"', t, re.DOTALL|re.I)
        if m: print(m.group(1)); sys.exit(0)
    except: pass
" 2>/dev/null || true
        )
    fi
    if [[ -n "$_REG_VER" ]]; then
        export WIZ_GAME_VERSION="$_REG_VER"
        echo "[QuickLaunch] Versiyon : $WIZ_GAME_VERSION"
    else
        echo "[QuickLaunch] UYARI: Oyun versiyonu registry'den bulunamadı."
        echo "  AccountClientMismatch alırsanız:"
        echo "  export WIZ_GAME_VERSION='V_rXXXXXX.Wizard101_1_XXX'"
        echo "  Versiyonu bulmak: wine reg query 'HKLM\\SOFTWARE\\KingsIsle Entertainment\\Wizard101'"
    fi
fi

# ── KI Auth: uid + ck2 token al ──────────────────────────────────────────────
echo "[QuickLaunch] KI sunucusuna bağlanılıyor (ki_auth.py)..."
# ÖNEMLI: 2>&1 KULLANMA — stderr (log satırları) stdout'a karışır, uid yanlış parse edilir.
# stderr terminale akar (kullanıcı görür), sadece stdout (uid ck2) yakalanır.
_AUTH_STDERR=$(mktemp)
AUTH_OUT=$(python3 "$SCRIPT_DIR/ki_auth.py" "$WIZ_USER" "$WIZ_PASS" 2>"$_AUTH_STDERR")
_AUTH_EXIT=$?
cat "$_AUTH_STDERR" >&2   # ki_auth.py log satırlarını terminale yaz
rm -f "$_AUTH_STDERR"
if [[ $_AUTH_EXIT -ne 0 ]] || [[ -z "$AUTH_OUT" ]]; then
    echo "[QuickLaunch] HATA: Kimlik doğrulama başarısız!"
    echo "  → Kullanıcı adı/şifre doğru mu? İnternet bağlantısı var mı?"
    echo "  → pycryptodome kurulu mu? (pip3 install pycryptodome)"
    exit 1
fi
# ki_auth.py stdout: "<uid> <ck2_token>" — ck2 boşluk içerebilir, cut -f2- kullan
WIZ_UID=$(echo "$AUTH_OUT" | cut -d' ' -f1)
WIZ_CK2=$(echo "$AUTH_OUT" | cut -d' ' -f2-)
if [[ -z "$WIZ_UID" || -z "$WIZ_CK2" ]]; then
    echo "[QuickLaunch] HATA: ki_auth.py geçersiz çıktı: '$AUTH_OUT'"
    exit 1
fi
echo "[QuickLaunch] Auth     : OK (uid=$WIZ_UID)"

# ── BaseMessages.wad varlık kontrolü ─────────────────────────────────────────
# Oyun bu dosyayı bulamazsa: "LoadMessageModule BaseMessages" crash'i verir.
# Normal launcher (Wizard101.app) eksik dosyaları patch server'dan indirir.
_WIZ_DATA="$WIZ_PREFIX/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Data/GameData"
if [[ ! -f "$_WIZ_DATA/BaseMessages.wad" ]]; then
    echo ""
    echo "[QuickLaunch] UYARI: BaseMessages.wad bulunamadı: $_WIZ_DATA"
    echo "  → Oyunu bir kez Wizard101.app üzerinden başlatıp tam patch'in inmesini bekleyin."
    echo "  → Sonra bu scripti tekrar çalıştırın."
    echo "  (Devam ediliyor — crash olabilir)"
    echo ""
fi

echo "[QuickLaunch] Oyun başlatılıyor..."
echo ""

# FPS / performans: Wine + MoltenVK debug output kapat
export WINEDEBUG="-all"
export DXVK_LOG_LEVEL="none"
export WINEESYNC=1
export WINEMSYNC=1
export DXVK_ASYNC=1
export MVK_CONFIG_LOG_LEVEL=0        # MoltenVK [mvk-info] mesajlarını kapat
export MVK_CONFIG_DEBUG_MODE=0

cd "$WIZ_BIN_DIR"
# Doğru arg formatı (umbra-launcher + MidasModLoader referansına göre):
#   -L <host> <port> -U ..<uid> <ck2> <username>
# NOT: -u/-p değil, önce token alıp -U ile geçilmeli
"$WINE_BIN" WizardGraphicalClient.exe \
    -L login.us.wizard101.com 12000 \
    -U "..$WIZ_UID" "$WIZ_CK2" "$WIZ_USER" \
    >/dev/null 2>&1 &

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
