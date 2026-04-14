#!/usr/bin/env bash
# get_deimos.sh — w101d/Deimos.py'yi Deimos cache'ine kopyalar.
#
# Çalıştırınca: erebb/wiz-hwid-spoofer'daki Deimos.py aktif olur.
# run_deimos.sh otomatik güncellemez — sadece bu script çalıştırılınca değişir.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEIMOS_DIR="${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}"

SRC="$SCRIPT_DIR/Deimos.py"
DST="$DEIMOS_DIR/Deimos.py"

if [[ ! -f "$SRC" ]]; then
    echo "[get_deimos] HATA: $SRC bulunamadı." >&2
    exit 1
fi
if [[ ! -d "$DEIMOS_DIR" ]]; then
    echo "[get_deimos] HATA: Deimos dizini yok: $DEIMOS_DIR" >&2
    echo "  Önce setup_env.sh çalıştırın." >&2
    exit 1
fi

cp "$SRC" "$DST"
echo "[get_deimos] Güncellendi: $DST"
