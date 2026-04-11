#!/usr/bin/env bash
# resign_wine.sh — brew upgrade wine-stable sonrası Wine'ı yeniden imzalar.
#
# brew upgrade wine-stable çalıştırıldığında imza sıfırlanır.
# Bu scripti çalıştırarak speedhack'ın memory erişim iznini geri ver.
#
# Kullanım: bash w101d/resign_wine.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

echo "================================================"
echo "  Wine Memory Erişim İmzalayıcı"
echo "================================================"
echo ""
echo "Wine : $WINE_BIN"
echo ""

# Gerçek binary dizinini bul
real_wine=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$WINE_BIN" 2>/dev/null || echo "$WINE_BIN")
bin_dir=$(dirname "$real_wine")

# Entitlements plist
ent=$(mktemp /tmp/wine-ent-XXXXXX.plist)
cat > "$ent" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.get-task-allow</key>
    <true/>
</dict>
</plist>
PLIST

ok=0
for bin in \
    "$bin_dir/wine64-preloader" \
    "$bin_dir/wine-preloader" \
    "$real_wine" \
    "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64-preloader" \
    "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine-preloader"; do
    [[ -x "$bin" ]] || continue
    echo -n "İmzalanıyor: $bin ... "
    if codesign --entitlements "$ent" --force -s - "$bin" 2>/dev/null; then
        echo "OK"
        ok=1
    else
        echo "BAŞARISIZ"
    fi
done

rm -f "$ent"

echo ""
if [[ "$ok" -eq 1 ]]; then
    echo "Tamamlandı. speedhack artık çalışır."
else
    echo "HATA: Hiçbir binary imzalanamadı."
    echo "Wine kurulu mu? brew install --cask wine-stable"
    exit 1
fi
