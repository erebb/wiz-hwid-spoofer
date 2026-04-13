"""
macos_patches.py — macOS Wine ortamı için Deimos/wizwalker yamaları.

Bu dosya Wine Python'ın site-packages/sitecustomize.py'sine kopyalanır.
Python başladığında otomatik çalışır — Deimos.py'e dokunmadan yamalar uygulanır.

Yamalar:
  1. Wad.from_game_data  → WIZ_DATA_DIR env üzerinden macOS game data yolu
"""

import os
import pathlib
import sys


# ── 1. WAD dosya okuma yaması ────────────────────────────────────────────────
# Deimos/wizwalker, WAD dosyalarını Windows registry'den bulunan yolla okur.
# macOS'ta bu yol yanlış prefix'e işaret edebilir.
# WIZ_DATA_DIR (run_deimos.sh tarafından export edilir) gerçek yolu gösterir.
def _apply_wad_patch():
    try:
        import wizwalker.file_readers.wad as _wad_mod

        if getattr(_wad_mod.Wad.from_game_data, "_macos_patched", False):
            return  # zaten uygulandı

        _orig = _wad_mod.Wad.from_game_data

        def _patched(cls, name, *args, **kwargs):
            # 1. WIZ_DATA_DIR: run_deimos.sh'dan
            wiz_data = os.environ.get("WIZ_DATA_DIR", "").strip()
            if wiz_data:
                p = pathlib.Path(wiz_data) / f"{name}.wad"
                if p.exists():
                    return cls(str(p))
            # 2. Çalışma dizininde yerel override
            local = pathlib.Path(os.getcwd()) / f"{name}.wad"
            if local.exists():
                return cls(str(local))
            # 3. Orijinal wizwalker implementasyonu
            return _orig.__func__(cls, name, *args, **kwargs)

        _patched._macos_patched = True
        _wad_mod.Wad.from_game_data = classmethod(_patched)
    except Exception:
        pass  # wizwalker henüz import edilmemiş olabilir — Deimos import'u halleder


_apply_wad_patch()
