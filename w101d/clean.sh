#!/usr/bin/env bash
# clean.sh — w101d tarafından kurulan/oluşturulan HER ŞEYİ siler.
#
# Silinenler:
#   ~/.w101d_wine          → Deimos Wine prefix
#   ~/.w101d_cache         → Python installer, git repoları
#   WIZ_PREFIX/Python313   → Wizard101 prefix'e kopyalanan Python (bulunursa)
#   wine-stable (cask)     → brew tarafından kurulmuş wine
#   winetricks             → brew tarafından kurulmuş winetricks
#   Homebrew               → sadece istenirse (dikkatli: sistem geneli)

set -uo pipefail   # -e yok: brew uninstall hataları scripti durdurmasın

# ── Renkler ──────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'

_ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
_warn() { echo -e "${YELLOW}[!]${NC} $*"; }
_del()  { echo -e "${RED}[-]${NC} $*"; }

echo ""
echo "════════════════════════════════════════"
echo "   w101d TAM TEMİZLEYİCİ"
echo "════════════════════════════════════════"
echo ""
_warn "Bu script şunları silecek:"
echo "   • ~/.w101d_wine      (Deimos Wine prefix)"
echo "   • ~/.w101d_cache     (indirilen dosyalar, git repoları)"
echo "   • wine-stable        (Homebrew cask)"
echo "   • winetricks         (Homebrew formula)"
echo "   • Python313 kopyası  (Wizard101 prefix'inde varsa)"
echo ""
_warn "Homebrew'un kendisi de isteğe bağlı silinebilir."
echo ""
read -r -p "Devam etmek istiyor musunuz? (e/H): " confirm
if [[ ! "$confirm" =~ ^[Ee]$ ]]; then
    echo "İptal edildi."
    exit 0
fi

# ── Homebrew'u sil mü? ───────────────────────
REMOVE_BREW=0
echo ""
read -r -p "Homebrew'un kendisini de silmek ister misiniz? (Sisteminizde başka brew uygulamaları varsa HAYIR deyin) (e/H): " ans_brew
if [[ "$ans_brew" =~ ^[Ee]$ ]]; then
    REMOVE_BREW=1
fi

# ── Wizard101 prefix Python kopyası ──────────
EXTRA_PYTHON=""
echo ""
read -r -p "Wizard101'in Wine prefix'ine kopyalanan Python313'ü de silmek ister misiniz? (e/H): " ans_py
if [[ "$ans_py" =~ ^[Ee]$ ]]; then
    # Otomatik bul
    WIZ_EXE=$(find "$HOME/Library" -name "WizardGraphicalClient.exe" 2>/dev/null | head -1 || true)
    if [[ -n "$WIZ_EXE" ]]; then
        WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
        EXTRA_PYTHON="$WIZ_PREFIX/drive_c/Python313"
        echo "   Bulundu: $EXTRA_PYTHON"
    else
        echo "   WizardGraphicalClient.exe bulunamadı, bu adım atlanacak."
    fi
fi

echo ""
echo "════════════════════════════════════════"
echo "   Silme işlemi başlıyor..."
echo "════════════════════════════════════════"
echo ""

# ── 1. Deimos Wine prefix ─────────────────────
if [[ -d "$HOME/.w101d_wine" ]]; then
    _del "Siliniyor: ~/.w101d_wine"
    rm -rf "$HOME/.w101d_wine"
    _ok "~/.w101d_wine silindi."
else
    _ok "~/.w101d_wine zaten yok."
fi

# ── 2. Cache (Python installer + repolar) ─────
if [[ -d "$HOME/.w101d_cache" ]]; then
    _del "Siliniyor: ~/.w101d_cache"
    rm -rf "$HOME/.w101d_cache"
    _ok "~/.w101d_cache silindi."
else
    _ok "~/.w101d_cache zaten yok."
fi

# ── 3. Wizard101 prefix Python kopyası ────────
if [[ -n "$EXTRA_PYTHON" ]]; then
    if [[ -d "$EXTRA_PYTHON" ]]; then
        _del "Siliniyor: $EXTRA_PYTHON"
        rm -rf "$EXTRA_PYTHON"
        _ok "Python313 kopyası silindi."
    else
        _ok "Python313 kopyası zaten yok: $EXTRA_PYTHON"
    fi
fi

# ── 4. Wine & winetricks (Homebrew) ───────────
if command -v brew &>/dev/null; then
    # wine-stable (cask)
    if brew list --cask wine-stable &>/dev/null 2>&1; then
        _del "wine-stable kaldırılıyor..."
        brew uninstall --cask --force wine-stable 2>/dev/null && _ok "wine-stable kaldırıldı." || _warn "wine-stable kaldırılamadı (zaten yok olabilir)."
    else
        _ok "wine-stable zaten kurulu değil."
    fi

    # winetricks (formula)
    if brew list winetricks &>/dev/null 2>&1; then
        _del "winetricks kaldırılıyor..."
        brew uninstall --force winetricks 2>/dev/null && _ok "winetricks kaldırıldı." || _warn "winetricks kaldırılamadı."
    else
        _ok "winetricks zaten kurulu değil."
    fi

    # ── 5. Homebrew'un kendisi ─────────────────
    if [[ "$REMOVE_BREW" -eq 1 ]]; then
        _del "Homebrew kaldırılıyor (bu birkaç dakika sürebilir)..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" -- --force 2>/dev/null \
            && _ok "Homebrew kaldırıldı." \
            || _warn "Homebrew kaldırma scripti hata verdi; manuel kontrol edin."
    fi
else
    _ok "Homebrew kurulu değil, bu adım atlandı."
fi

echo ""
echo "════════════════════════════════════════"
_ok "Temizlik tamamlandı."
echo "════════════════════════════════════════"
echo ""
echo "Tekrar kurmak için: bash setup_env.sh"
