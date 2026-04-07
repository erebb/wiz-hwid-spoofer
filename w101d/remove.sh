#!/usr/bin/env bash
# remove.sh — Bu araç tarafından kurulan HER ŞEYİ kaldırır.
# Çalışan process'leri durdurur, prefix'leri, cache'i ve eklenen DLL'leri siler.
set -uo pipefail

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║     Deimos/W101d Tam Temizleme Aracı            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "UYARI: Bu işlem geri alınamaz."
echo "Silinecekler:"
echo "  • ~/.w101d_wine          (Deimos Wine prefix)"
echo "  • ~/.w101d_cache         (Python, wizwalker, propsys stub, vb.)"
echo "  • Wizard101 prefix'ine kopyalanan Python313"
echo "  • Wizard101 prefix'ine kopyalanan propsys.dll"
echo "  • Çalışan Wine/Python process'leri (sadece Deimos'a ait)"
echo ""

read -rp "Devam etmek istiyor musunuz? [e/H]: " confirm
if [[ "${confirm,,}" != "e" && "${confirm,,}" != "evet" ]]; then
    echo "İptal edildi."
    exit 0
fi

echo ""

# ── 1. Çalışan Process'leri Durdur ───────────────────────────
echo "[ 1/7 ] Deimos ve Wine process'leri durduruluyor..."

# python.exe (Deimos) — sadece w101d_cache altındakileri
pkill -f "Python313.*Deimos.py"   2>/dev/null && echo "       Deimos (python.exe) durduruldu." || true
pkill -f "Deimos\.py"             2>/dev/null || true

# Deimos prefix'i için wineserver
if [[ -d "$HOME/.w101d_wine" ]]; then
    WINEPREFIX="$HOME/.w101d_wine" wineserver -k 2>/dev/null && \
        echo "       ~/.w101d_wine wineserver durduruldu." || true
fi

# Wizard101 prefix'i için wineserver — DİKKAT: bu Wizard101 oyununu da durdurur
WIZ_PREFIX=""
for candidate in \
    "$HOME/Library/Application Support/Wizard101/Bottles/wizard101" \
    "$HOME/Library/Application Support/Wizard101"; do
    [[ -d "$candidate/drive_c" ]] && WIZ_PREFIX="$candidate" && break
done

if [[ -n "$WIZ_PREFIX" ]]; then
    # Sadece python.exe'yi durdur, oyunun kendisine dokunma
    pkill -f "Python313" 2>/dev/null || true
    echo "       Wine Python process'leri durduruldu."
fi

sleep 1

# ── 2. Wizard101 Prefix'inden Kopyalanan Python313'ü Kaldır ──
echo "[ 2/7 ] Wizard101 prefix'indeki Python313 kaldırılıyor..."
if [[ -n "$WIZ_PREFIX" ]]; then
    WIZ_PY="$WIZ_PREFIX/drive_c/Python313"
    if [[ -d "$WIZ_PY" ]]; then
        rm -rf "$WIZ_PY"
        echo "       Kaldırıldı: $WIZ_PY"
    else
        echo "       Zaten yok: $WIZ_PY"
    fi
fi

# ── 3. Wizard101 Prefix'inden propsys.dll'i Kaldır ──────────
echo "[ 3/7 ] Wizard101 prefix'indeki propsys.dll stub kaldırılıyor..."
if [[ -n "$WIZ_PREFIX" ]]; then
    WIZ_PROPSYS="$WIZ_PREFIX/drive_c/windows/system32/propsys.dll"
    if [[ -f "$WIZ_PROPSYS" ]]; then
        # Orijinal Wine builtin değil mi kontrol et (boyut < 50KB ise stub'dır)
        FILE_SIZE=$(stat -f%z "$WIZ_PROPSYS" 2>/dev/null || stat -c%s "$WIZ_PROPSYS" 2>/dev/null || echo 0)
        if [[ "$FILE_SIZE" -lt 51200 ]]; then
            rm -f "$WIZ_PROPSYS"
            echo "       Kaldırıldı: $WIZ_PROPSYS (stub, ${FILE_SIZE} bytes)"
        else
            echo "       Atlandı: $WIZ_PROPSYS büyük dosya (${FILE_SIZE} bytes) — orijinal olabilir."
        fi
    else
        echo "       Zaten yok: $WIZ_PROPSYS"
    fi
    # syswow64 versiyonu
    WIZ_PROPSYS_WOW="$WIZ_PREFIX/drive_c/windows/syswow64/propsys.dll"
    if [[ -f "$WIZ_PROPSYS_WOW" ]]; then
        FILE_SIZE=$(stat -f%z "$WIZ_PROPSYS_WOW" 2>/dev/null || stat -c%s "$WIZ_PROPSYS_WOW" 2>/dev/null || echo 0)
        if [[ "$FILE_SIZE" -lt 51200 ]]; then
            rm -f "$WIZ_PROPSYS_WOW"
            echo "       Kaldırıldı: $WIZ_PROPSYS_WOW (stub)"
        fi
    fi
fi

# ── 4. Deimos Wine Prefix'ini Kaldır (~/.w101d_wine) ─────────
echo "[ 4/7 ] Deimos Wine prefix'i kaldırılıyor (~/.w101d_wine)..."
if [[ -d "$HOME/.w101d_wine" ]]; then
    rm -rf "$HOME/.w101d_wine"
    echo "       Kaldırıldı: ~/.w101d_wine"
else
    echo "       Zaten yok: ~/.w101d_wine"
fi

# ── 5. Cache Dizinini Kaldır (~/.w101d_cache) ────────────────
echo "[ 5/7 ] Cache kaldırılıyor (~/.w101d_cache)..."
if [[ -d "$HOME/.w101d_cache" ]]; then
    du -sh "$HOME/.w101d_cache" 2>/dev/null | awk '{print "       Boyut: " $1}'
    rm -rf "$HOME/.w101d_cache"
    echo "       Kaldırıldı: ~/.w101d_cache"
else
    echo "       Zaten yok: ~/.w101d_cache"
fi

# ── 6. İsteğe Bağlı: Homebrew Paketleri ─────────────────────
echo "[ 6/7 ] Homebrew paketleri (isteğe bağlı)..."
echo ""
echo "  Kaldırılabilecek Homebrew paketleri:"
echo "    • wine-stable  (Homebrew Wine)"
echo "    • mingw-w64    (propsys stub derlemek için)"
echo ""
read -rp "  Bu Homebrew paketlerini de kaldırmak istiyor musunuz? [e/H]: " brew_confirm
if [[ "${brew_confirm,,}" == "e" || "${brew_confirm,,}" == "evet" ]]; then
    if command -v brew &>/dev/null; then
        brew uninstall --cask wine-stable 2>/dev/null && \
            echo "       wine-stable kaldırıldı." || echo "       wine-stable kaldırılamadı (zaten yok olabilir)."
        brew uninstall mingw-w64 2>/dev/null && \
            echo "       mingw-w64 kaldırıldı." || echo "       mingw-w64 kaldırılamadı (zaten yok olabilir)."
    else
        echo "       Homebrew bulunamadı, atlanıyor."
    fi
else
    echo "       Atlandı."
fi

# ── 7. Kalan Dosya/Dizin Kontrol ─────────────────────────────
echo "[ 7/7 ] Kalan dosyalar kontrol ediliyor..."
LEFTOVER=0
for path in \
    "$HOME/.w101d_wine" \
    "$HOME/.w101d_cache"; do
    if [[ -e "$path" ]]; then
        echo "       UYARI: Hâlâ mevcut: $path"
        LEFTOVER=1
    fi
done
if [[ "$LEFTOVER" -eq 0 ]]; then
    echo "       Temiz — hiçbir kalıntı yok."
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║              Temizleme Tamamlandı               ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "NOT: Wizard101 oyununun kendisi bu işlemden ETKİLENMEDİ."
echo "     Sadece Deimos'a ait bileşenler kaldırıldı."
echo ""
