#!/usr/bin/env bash
# remove.sh — Bu araç tarafından kurulan HER ŞEYİ kaldırır.
# Mac'in kendi native Python'u KORUNUR.
# Wine (tüm versiyonlar), Homebrew ve tüm ilgili process'ler silinir.
set -uo pipefail

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        Deimos/W101d Tam Temizleme Aracı              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "UYARI: Bu işlem GERİ ALINAMAZ."
echo ""
echo "Silinecekler:"
echo "  • Tüm Wine process'leri (wineserver, wine, wine64, wine32on64)"
echo "  • Tüm Windows Python process'leri (wine içindeki python.exe)"
echo "  • ~/.w101d_wine          (Deimos Wine prefix)"
echo "  • ~/.w101d_cache         (Python313, propsys stub, cache)"
echo "  • Wizard101 prefix'inden Python313 ve propsys.dll stub"
echo "  • Homebrew wine-stable / wine-crossover (cask)"
echo "  • Homebrew mingw-w64"
echo "  [Homebrew'un kendisi ayrıca sorulacak]"
echo ""
echo "Korunacaklar:"
echo "  • Mac'in kendi /usr/bin/python3 (system Python)"
echo "  • /opt/homebrew/bin/python3 (Homebrew Python — ayrıca sorulacak)"
echo "  • Wizard101.app'in kendisi"
echo "  • Wizard101'in oyun verileri"
echo ""

read -rp "Devam etmek istiyor musunuz? [e/H]: " confirm
if [[ "${confirm,,}" != "e" && "${confirm,,}" != "evet" ]]; then
    echo "İptal edildi."
    exit 0
fi

echo ""

# ── 1. Tüm Wine ve Windows Python Process'lerini Durdur ─────────
echo "[ 1/9 ] Tüm Wine ve Windows Python process'leri durduruluyor..."

# Windows python.exe (wine içinde çalışan — Mac'in python3'ü değil)
pkill -f "wine.*python\.exe" 2>/dev/null && echo "       wine python.exe durduruldu." || true
pkill -f "Python313.*Deimos\.py" 2>/dev/null || true
pkill -f "Deimos\.py" 2>/dev/null || true

# Tüm wine process'leri (wine, wine64, wine32on64-preloader vb.)
for proc in wineserver wine64 wine32on64-preloader "wine-preloader" winedevice.exe services.exe; do
    pkill -f "$proc" 2>/dev/null || true
done
# "wine" binary'sini ayrıca durdur (kısa isimle)
pkill -x wine 2>/dev/null || true
pkill -x wine64 2>/dev/null || true
echo "       Wine process'leri durduruldu."

# Tüm wineserver'ları durdur (her prefix için)
echo "       Tüm wineserver soketleri kapatılıyor..."
for prefix in \
    "$HOME/.w101d_wine" \
    "$HOME/Library/Application Support/Wizard101/Bottles/wizard101" \
    "$HOME/Library/Application Support/Wizard101" \
    "$HOME/.wine"; do
    if [[ -d "$prefix" ]]; then
        WINEPREFIX="$prefix" wineserver -k 2>/dev/null || true
    fi
done

sleep 2

# ── 2. Wizard101 Prefix'inden Python313'ü Kaldır ────────────────
echo "[ 2/9 ] Wizard101 prefix'indeki Python313 kaldırılıyor..."
WIZ_PREFIX=""
for candidate in \
    "$HOME/Library/Application Support/Wizard101/Bottles/wizard101" \
    "$HOME/Library/Application Support/Wizard101"; do
    [[ -d "$candidate/drive_c" ]] && WIZ_PREFIX="$candidate" && break
done

if [[ -n "$WIZ_PREFIX" ]]; then
    WIZ_PY="$WIZ_PREFIX/drive_c/Python313"
    if [[ -d "$WIZ_PY" ]]; then
        rm -rf "$WIZ_PY"
        echo "       Kaldırıldı: $WIZ_PY"
    else
        echo "       Zaten yok: $WIZ_PY"
    fi
else
    echo "       Wizard101 prefix bulunamadı, atlanıyor."
fi

# ── 3. Wizard101 Prefix'inden propsys.dll Stub'ı Kaldır ─────────
echo "[ 3/9 ] Wizard101 prefix'indeki propsys.dll stub kaldırılıyor..."
if [[ -n "$WIZ_PREFIX" ]]; then
    for dll_path in \
        "$WIZ_PREFIX/drive_c/windows/system32/propsys.dll" \
        "$WIZ_PREFIX/drive_c/windows/syswow64/propsys.dll"; do
        if [[ -f "$dll_path" ]]; then
            FILE_SIZE=$(stat -f%z "$dll_path" 2>/dev/null || stat -c%s "$dll_path" 2>/dev/null || echo 0)
            if [[ "$FILE_SIZE" -lt 51200 ]]; then
                rm -f "$dll_path"
                echo "       Kaldırıldı: $dll_path (stub, ${FILE_SIZE} bytes)"
            else
                echo "       Atlandı: $dll_path (${FILE_SIZE} bytes — orijinal olabilir)"
            fi
        else
            echo "       Zaten yok: $dll_path"
        fi
    done
fi

# ── 4. Deimos Wine Prefix'ini Kaldır ────────────────────────────
echo "[ 4/9 ] Deimos Wine prefix'i kaldırılıyor (~/.w101d_wine)..."
if [[ -d "$HOME/.w101d_wine" ]]; then
    rm -rf "$HOME/.w101d_wine"
    echo "       Kaldırıldı: ~/.w101d_wine"
else
    echo "       Zaten yok: ~/.w101d_wine"
fi

# ── 5. Cache Dizinini Kaldır ─────────────────────────────────────
echo "[ 5/9 ] Cache kaldırılıyor (~/.w101d_cache)..."
if [[ -d "$HOME/.w101d_cache" ]]; then
    du -sh "$HOME/.w101d_cache" 2>/dev/null | awk '{print "       Boyut: " $1}' || true
    rm -rf "$HOME/.w101d_cache"
    echo "       Kaldırıldı: ~/.w101d_cache"
else
    echo "       Zaten yok: ~/.w101d_cache"
fi

# ── 6. Homebrew Wine ve mingw-w64 Kaldır ────────────────────────
echo "[ 6/9 ] Homebrew Wine paketleri kaldırılıyor..."
if command -v brew &>/dev/null; then
    # wine-stable (cask)
    if brew list --cask wine-stable &>/dev/null 2>&1; then
        brew uninstall --cask --force wine-stable 2>/dev/null && \
            echo "       wine-stable kaldırıldı." || \
            echo "       wine-stable kaldırılamadı."
    else
        echo "       wine-stable zaten kurulu değil."
    fi

    # wine-crossover (cask) — varsa
    if brew list --cask wine-crossover &>/dev/null 2>&1; then
        brew uninstall --cask --force wine-crossover 2>/dev/null && \
            echo "       wine-crossover kaldırıldı." || true
    fi

    # mingw-w64 (formula)
    if brew list mingw-w64 &>/dev/null 2>&1; then
        brew uninstall --force mingw-w64 2>/dev/null && \
            echo "       mingw-w64 kaldırıldı." || \
            echo "       mingw-w64 kaldırılamadı."
    else
        echo "       mingw-w64 zaten kurulu değil."
    fi

    # Homebrew'un Wine için indirdiği önbelleği temizle
    brew cleanup --prune=all 2>/dev/null || true
    echo "       Homebrew önbelleği temizlendi."
else
    echo "       Homebrew bulunamadı, atlanıyor."
fi

# ── 7. Homebrew Python Kaldır (opsiyonel) ───────────────────────
echo "[ 7/9 ] Homebrew Python (isteğe bağlı)..."
echo ""
echo "  Mac'in kendi /usr/bin/python3'ü KORUNACAK."
echo "  Homebrew Python (brew install python) kaldırılmak isteniyor mu?"
echo ""

if command -v brew &>/dev/null; then
    # Kurulu Homebrew Python versiyonlarını listele
    BREW_PYTHONS=$(brew list --formula 2>/dev/null | grep "^python" || true)
    if [[ -n "$BREW_PYTHONS" ]]; then
        echo "  Kurulu Homebrew Python versiyonları:"
        echo "$BREW_PYTHONS" | while read -r pkg; do
            echo "    • $pkg"
        done
        echo ""
        read -rp "  Bunları kaldırmak istiyor musunuz? [e/H]: " py_confirm
        if [[ "${py_confirm,,}" == "e" || "${py_confirm,,}" == "evet" ]]; then
            echo "$BREW_PYTHONS" | while read -r pkg; do
                brew uninstall --force "$pkg" 2>/dev/null && \
                    echo "       $pkg kaldırıldı." || \
                    echo "       $pkg kaldırılamadı."
            done
        else
            echo "       Homebrew Python korundu."
        fi
    else
        echo "  Homebrew Python kurulu değil."
    fi
else
    echo "  Homebrew bulunamadı, atlanıyor."
fi

# ── 8. Homebrew'un Kendisini Kaldır (opsiyonel) ─────────────────
echo "[ 8/9 ] Homebrew (isteğe bağlı)..."
echo ""
echo "  UYARI: Homebrew tamamen kaldırılırsa kurulu TÜM Homebrew paketleri gider."
echo ""

if command -v brew &>/dev/null; then
    read -rp "  Homebrew'u tamamen kaldırmak istiyor musunuz? [e/H]: " brew_rm_confirm
    if [[ "${brew_rm_confirm,,}" == "e" || "${brew_rm_confirm,,}" == "evet" ]]; then
        echo "  Homebrew kaldırılıyor (bu birkaç dakika sürebilir)..."
        NONINTERACTIVE=1 /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" \
            2>/dev/null && \
            echo "       Homebrew kaldırıldı." || \
            echo "       Homebrew kaldırılamadı — manuel kaldırma gerekebilir."
    else
        echo "       Homebrew korundu."
    fi
else
    echo "  Homebrew zaten kurulu değil."
fi

# ── 9. Kalan Dosya/Dizin Kontrol ────────────────────────────────
echo "[ 9/9 ] Kalan dosyalar kontrol ediliyor..."
LEFTOVER=0
for path in \
    "$HOME/.w101d_wine" \
    "$HOME/.w101d_cache"; do
    if [[ -e "$path" ]]; then
        echo "       UYARI: Hâlâ mevcut: $path"
        LEFTOVER=1
    fi
done

# Kalan wine process'leri kontrol et
if pgrep -f "wineserver" &>/dev/null || pgrep -x "wine64" &>/dev/null; then
    echo "       UYARI: Hâlâ çalışan Wine process'leri var:"
    pgrep -af "wine" 2>/dev/null | grep -v grep | while read -r line; do
        echo "         $line"
    done
    LEFTOVER=1
fi

if [[ "$LEFTOVER" -eq 0 ]]; then
    echo "       Temiz — hiçbir kalıntı yok."
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║               Temizleme Tamamlandı                   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Korunanlar:"
echo "  • /usr/bin/python3          (Mac sistem Python)"
echo "  • /Applications/Wizard101.app (oyunun kendisi)"
echo "  • Wizard101 oyun verileri   (save data, prefix içindeki oyun dosyaları)"
echo ""
