"""
macos_patches.py — macOS Wine ortamı için Deimos/wizwalker yamaları.

Bu dosya Wine Python'ın site-packages/sitecustomize.py'sine kopyalanır.
Python başladığında otomatik çalışır — Deimos.py'e dokunmadan yamalar uygulanır.

Yamalar:
  1. Wad.from_game_data  → WIZ_DATA_DIR env üzerinden macOS game data yolu
  2. PIL.ImageGrab.grab  → mss (CoreGraphics) ile değiştirilir
                           DXVK/Metal render → GDI siyah döndürür, mss çalışır
  3. Tesseract           → macOS native binary yolu + OCR crash koruması
  4. GameStats memory    → bellek okuma hatalarında crash yerine 1000 döndür
  5. Teleport timeout    → should_update beklemesini atla + wait_on_inuse=False
"""

import os
import pathlib
import sys

try:
    from loguru import logger
except Exception:  # loguru yoksa sessiz logger
    class _NullLogger:
        def __getattr__(self, _):
            return lambda *a, **k: None
    logger = _NullLogger()


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


# ── 3. Tesseract macOS native yolu + OCR crash koruması ─────────────────────
# pytesseract Windows yolu arar; Wine içinden macOS brew tesseract'ı Z:\ ile
# erişilir. Ayrıca OCR hatası autoquest'i çökertmesin diye boş string döndür.
def _apply_tesseract_patch():
    try:
        import pytesseract

        mac_silicon_path = r"Z:\opt\homebrew\bin\tesseract"
        mac_intel_path = r"Z:\usr\local\bin\tesseract"
        if os.path.exists(mac_silicon_path):
            pytesseract.pytesseract.tesseract_cmd = mac_silicon_path
            logger.debug(f"[macOS] Tesseract (Silicon): {mac_silicon_path}")
        elif os.path.exists(mac_intel_path):
            pytesseract.pytesseract.tesseract_cmd = mac_intel_path
            logger.debug(f"[macOS] Tesseract (Intel): {mac_intel_path}")
        else:
            pytesseract.pytesseract.tesseract_cmd = "tesseract"

        if not hasattr(pytesseract, "_orig_image_to_string"):
            pytesseract._orig_image_to_string = pytesseract.image_to_string

            def _safe_image_to_string(*args, **kwargs):
                try:
                    return pytesseract._orig_image_to_string(*args, **kwargs)
                except Exception as e:
                    logger.debug(f"[macOS] Tesseract OCR hatası atlandı: {e}")
                    return ""

            pytesseract.image_to_string = _safe_image_to_string
    except Exception:
        pass


_apply_tesseract_patch()


# ── 4. GameStats bellek okuma kalkanı ───────────────────────────────────────
# macOS'ta cross-process bellek okuması bazen başarısız olur (HP/mana vs.).
# Hata durumunda crash yerine güvenli bir değer (1000) döndür → ölümsüz his +
# auto_potion / questing çökmesini önler.
def _apply_memory_shield_patch():
    try:
        from wizwalker.memory.memory_objects.game_stats import GameStats

        if hasattr(GameStats, "_orig_read_value_from_offset"):
            return
        GameStats._orig_read_value_from_offset = GameStats.read_value_from_offset

        async def _safe_read(self, offset, data_type, *args, **kwargs):
            try:
                return await self._orig_read_value_from_offset(offset, data_type, *args, **kwargs)
            except Exception:
                return 1000

        GameStats.read_value_from_offset = _safe_read
        logger.debug("[macOS] GameStats bellek kalkanı aktif")
    except Exception:
        pass


_apply_memory_shield_patch()


# ── 5. Teleport timeout bypass ──────────────────────────────────────────────
# Oyun penceresi odakta değilken should_update beklemesi timeout veriyordu.
# (a) maybe_wait_for_value_with_timeout → should_update için anında dön.
# (b) Client.teleport → her zaman wait_on_inuse=False ile çağır.
def _apply_teleport_patch():
    try:
        import wizwalker.utils as _wwutils

        if not getattr(_wwutils.maybe_wait_for_value_with_timeout, "_macos_patched", False):
            _orig_wait = _wwutils.maybe_wait_for_value_with_timeout

            async def _selective_wait(coro, *args, **kwargs):
                name = getattr(coro, "__name__", "") or ""
                if "should_update" in name:
                    try:
                        return await coro()
                    except Exception:
                        return True
                return await _orig_wait(coro, *args, **kwargs)

            _selective_wait._macos_patched = True
            _wwutils.maybe_wait_for_value_with_timeout = _selective_wait
            # client modülü ismi de import etmiş olabilir → orada da değiştir
            try:
                import wizwalker.client as _wwclient
                if hasattr(_wwclient, "maybe_wait_for_value_with_timeout"):
                    _wwclient.maybe_wait_for_value_with_timeout = _selective_wait
            except Exception:
                pass
            logger.debug("[macOS] should_update bypass aktif")
    except Exception:
        pass

    try:
        from wizwalker.client import Client as _WClient

        if not getattr(_WClient.teleport, "_macos_patched", False):
            _orig_teleport = _WClient.teleport

            async def _teleport_nowait(self, xyz, yaw=None, wait_on_inuse=True, **kwargs):
                try:
                    return await _orig_teleport(self, xyz, yaw=yaw, wait_on_inuse=False, **kwargs)
                except Exception as e:
                    logger.warning(f"[macOS] teleport hatası: {e}")

            _teleport_nowait._macos_patched = True
            _WClient.teleport = _teleport_nowait
            logger.debug("[macOS] Client.teleport wait_on_inuse=False aktif")
    except Exception:
        pass


_apply_teleport_patch()
