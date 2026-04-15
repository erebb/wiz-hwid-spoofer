"""
macos_patches.py — macOS Wine ortamı için Deimos/wizwalker yamaları.

Bu dosya Wine Python'ın site-packages/sitecustomize.py'sine kopyalanır.
Python başladığında otomatik çalışır — Deimos.py'e dokunmadan yamalar uygulanır.

Yamalar:
  1. Wad.from_game_data  → WIZ_DATA_DIR env üzerinden macOS game data yolu
  2. PIL.ImageGrab.grab  → mss (CoreGraphics) ile değiştirilir
                           DXVK/Metal render → GDI siyah döndürür, mss çalışır
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


# ── 2. PIL.ImageGrab → mss (CoreGraphics) yaması ────────────────────────────
# DXVK/Metal render altında Wine GDI ekran yakalama siyah döndürür.
# mss, macOS CoreGraphics API'sini kullanır → DXVK ile çalışır.
# Deimos autoquest is_visible_by_path() bu patch sayesinde doğru ekran alır.
def _apply_imagegrab_mss_patch():
    try:
        import mss as _mss_lib
        from PIL import ImageGrab as _ig, Image as _Image

        if getattr(_ig.grab, "_mss_patched", False):
            return  # zaten uygulandı

        def _mss_grab(bbox=None, include_layered_windows=False, all_screens=False, xdisplay=None):
            with _mss_lib.mss() as sct:
                if bbox is not None:
                    mon = {
                        "left":   int(bbox[0]),
                        "top":    int(bbox[1]),
                        "width":  int(bbox[2] - bbox[0]),
                        "height": int(bbox[3] - bbox[1]),
                    }
                else:
                    # Tüm ekran (birden fazla monitör varsa hepsini kapsar)
                    mon = sct.monitors[0]
                raw = sct.grab(mon)
                # mss BGRA döndürür → RGB'ye çevir
                return _Image.frombytes("RGB", raw.size, raw.bgra, "raw", "BGRX")

        _mss_grab._mss_patched = True
        _ig.grab = _mss_grab
    except Exception:
        pass  # mss kurulu değilse sessizce geç (pip install mss ile kurulabilir)


_apply_imagegrab_mss_patch()
