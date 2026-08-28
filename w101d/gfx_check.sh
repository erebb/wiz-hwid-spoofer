#!/usr/bin/env bash
# gfx_check.sh — Grafik/FPS teşhisi. Hiçbir şeyi DEĞİŞTİRMEZ, sadece raporlar.
#
# Neden gerekli: FPS tweak'lerinin çoğu "zaten açık", "kurulu değil" veya
# "bu Wine build'inde yok" olduğu için hiçbir işe yaramıyor olabilir.
# Bu script neyin gerçekten aktif olduğunu söyler.
#
# Kullanım: bash w101d/gfx_check.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"   # WINE_BIN, WINEPREFIX (~/.w101d_wine)

_hdr() { echo ""; echo "── $* ────────────────────────────────────"; }
_ok()   { echo "  [+] $*"; }
_warn() { echo "  [!] $*"; }
_info() { echo "      $*"; }

echo "================================================"
echo "  Wizard101 / Wine grafik teşhisi"
echo "================================================"
_info "Wine      : $WINE_BIN"
_info "Prefix    : $WINEPREFIX"

# ── 1. DXVK kurulu mu? ───────────────────────────────────────────────────────
# Oyunu quick_launch.sh Homebrew Wine + ~/.w101d_wine ile açıyor.
# DXVK yoksa render wined3d (D3D9→OpenGL) üzerinden gider; macOS'ta OpenGL
# deprecated ve GL 4.1'de kilitli → tüm DXVK_* env'leri sessizce etkisiz olur.
_hdr "1. DXVK (d3d9.dll)"
_D3D9="$WINEPREFIX/drive_c/windows/system32/d3d9.dll"
if [[ -f "$_D3D9" ]]; then
    _sz=$(stat -f%z "$_D3D9" 2>/dev/null || stat -c%s "$_D3D9" 2>/dev/null || echo 0)
    if strings "$_D3D9" 2>/dev/null | grep -qi "dxvk"; then
        _ok "DXVK KURULU (d3d9.dll, $_sz bayt)"
        _ver=$(strings "$_D3D9" 2>/dev/null | grep -oE "v?[0-9]+\.[0-9]+(\.[0-9]+)?" | sort -u | tail -3 | tr '\n' ' ')
        _info "Olası sürüm izleri: $_ver"
        _info "Kesin sürüm: DXVK_LOG_LEVEL=info ile başlat, 'DXVK: <sürüm>' satırına bak"
        _info "veya oyunu DXVK_HUD=version ile aç."
    else
        _warn "d3d9.dll var ama DXVK DEĞİL ($_sz bayt) → wined3d/OpenGL yolu"
    fi
else
    _warn "d3d9.dll YOK → oyun wined3d (D3D9→OpenGL) ile çalışıyor"
    _info "Bu durumda DXVK_FRAME_RATE / DXVK_STATE_CACHE / dxvk.conf ETKİSİZ."
fi

# DllOverrides: d3d9 native (DXVK) olarak yönlendirilmiş mi?
_OVR=$("$WINE_BIN" reg query 'HKCU\Software\Wine\DllOverrides' 2>/dev/null \
       | grep -i "d3d9\|dxgi" || true)
if [[ -n "$_OVR" ]]; then
    _ok "DllOverrides:"
    echo "$_OVR" | sed 's/^/      /'
else
    _warn "d3d9 için DllOverrides kaydı yok (builtin wined3d kullanılıyor olabilir)"
fi

# ── 2. MoltenVK / Vulkan ─────────────────────────────────────────────────────
# DXVK macOS'ta Vulkan ister; Vulkan da MoltenVK (Metal köprüsü) ister.
_hdr "2. MoltenVK / Vulkan"
_mvk_found=0
for p in /opt/homebrew/lib/libMoltenVK.dylib /usr/local/lib/libMoltenVK.dylib; do
    [[ -f "$p" ]] && { _ok "MoltenVK: $p"; _mvk_found=1; }
done
if [[ "$_mvk_found" -eq 0 ]]; then
    _warn "MoltenVK bulunamadı → DXVK kurulsa bile çalışmaz"
    _info "Kurmak için: brew install molten-vk"
fi
for p in /opt/homebrew/share/vulkan/icd.d /usr/local/share/vulkan/icd.d; do
    [[ -d "$p" ]] && _ok "Vulkan ICD dizini: $p"
done
[[ -f "$WINEPREFIX/drive_c/windows/system32/winevulkan.dll" ]] \
    && _ok "winevulkan.dll prefix'te mevcut" \
    || _warn "winevulkan.dll yok"

# ── 3. Retina modu ───────────────────────────────────────────────────────────
# HKCU\Software\Wine\Mac Driver → RetinaMode ("y"/"n"), VARSAYILAN KAPALI.
# Açıksa Wine ekran/pencere boyutunu 2x bildirir → 4x piksel → büyük FPS kaybı.
# (Wine kaynağı: dlls/winemac.drv/display.c → width *= 2; height *= 2)
_hdr "3. Retina modu (2x çözünürlük = 4x piksel)"
_check_retina() {
    local label="$1" prefix="$2"
    [[ -d "$prefix" ]] || return 0
    local val
    val=$(grep -A20 '\[Software\\\\Wine\\\\Mac Driver\]' "$prefix/user.reg" 2>/dev/null \
          | grep -i '"RetinaMode"' | head -1 || true)
    if [[ -z "$val" ]]; then
        _ok "$label: RetinaMode ayarlanmamış → KAPALI (varsayılan, iyi)"
    elif echo "$val" | grep -qiE '"(y|1|t)'; then
        _warn "$label: RetinaMode AÇIK → 4x piksel render ediliyor!"
        _info "Kapatmak için:"
        _info "  WINEPREFIX=\"$prefix\" \"$WINE_BIN\" reg add 'HKCU\\Software\\Wine\\Mac Driver' /v RetinaMode /t REG_SZ /d n /f"
    else
        _ok "$label: RetinaMode kapalı"
    fi
}
_check_retina "Deimos prefix" "$WINEPREFIX"
for b in "$HOME/Library/Application Support/Wizard101/Bottles/wizard101" \
         "$HOME/Library/Application Support/Wizard101"; do
    [[ -f "$b/user.reg" ]] && { _check_retina "Oyun bottle" "$b"; break; }
done

# ── 4. Sanal masaüstü (çözünürlük sınırlama) ─────────────────────────────────
_hdr "4. Sanal masaüstü / çözünürlük"
_DESK=$("$WINE_BIN" reg query 'HKCU\Software\Wine\Explorer' /v Desktop 2>/dev/null \
        | grep -i desktop || true)
if [[ -n "$_DESK" ]]; then
    _ok "Sanal masaüstü aktif: $(echo "$_DESK" | awk '{print $NF}')"
    "$WINE_BIN" reg query 'HKCU\Software\Wine\Explorer\Desktops' 2>/dev/null \
        | sed 's/^/      /' || true
else
    _info "Sanal masaüstü kapalı (oyun kendi çözünürlüğünü seçiyor)"
fi
_info "Render çözünürlüğünü düşürmenin en doğrudan yolu:"
_info "  WIZ_RES=1280x720 bash w101d/quick_launch.sh    (-SR argümanı)"

# ── 5. Env var gerçeklik kontrolü ────────────────────────────────────────────
# Bu değişkenler yamalı Wine build'lerine ait; stok Homebrew wine-stable'da yok.
_hdr "5. Env var gerçeklik kontrolü"
if strings "$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$WINE_BIN")" 2>/dev/null \
     | grep -qi "WINEMSYNC\|msync"; then
    _ok "Wine build'i msync destekliyor → WINEMSYNC=1 anlamlı"
else
    _warn "WINEESYNC / WINEMSYNC / WINE_LARGE_ADDRESS_AWARE: stok wine-stable'da YOK"
    _info "Bunlar Proton/Lutris/CrossOver yamalarına ait — burada etkisiz (zararsız)."
    _info "msync istersen: Whisky, CrossOver veya Gcenx wine-crossover build'i gerekir."
fi

# ── 6. Oyun tarafı ───────────────────────────────────────────────────────────
_hdr "6. Wizard101 client"
_info "Doğrulanmış render argümanı sadece: -SR <GENİŞLİKxYÜKSEKLİK>"
_info "Grafik ayarlarının nerede saklandığı belgelenmemiş. Bulmak için:"
_info "  1) user.reg'i yedekle  2) oyunda bir grafik ayarını değiştir"
_info "  3) düzgün çık  4) diff al:"
for b in "$HOME/Library/Application Support/Wizard101/Bottles/wizard101" \
         "$HOME/Library/Application Support/Wizard101"; do
    if [[ -f "$b/user.reg" ]]; then
        _info "     cp '$b/user.reg' /tmp/before.reg"
        _info "     diff /tmp/before.reg '$b/user.reg'"
        break
    fi
done
_info "Client sınıflarını dökmek (grafik seçenek adlarını görmek) için:"
_info "     WizardGraphicalClient.exe -X dump.txt"

echo ""
echo "================================================"
echo "  Teşhis bitti — hiçbir ayar değiştirilmedi."
echo "================================================"
