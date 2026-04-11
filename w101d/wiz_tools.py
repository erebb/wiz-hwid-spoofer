#!/usr/bin/env python3
"""
wiz_tools.py — Wizard101 Mac/Wine araç seti
============================================
Özellikler:
  [1] Speedhack  — oyuncu hareket hızını çarpanla artırır
  [2] Quest TP   — aktif quest hedefine ışınlanır (Enter ile)
  [3] Her ikisi  — aynı anda çalışır

Nasıl çalışır (Mac/Wine):
  - setup_single.sh ile wine64-preloader get-task-allow ile imzalanır
  - Bu sayede pymem, Wizard101 prosesinin memory'sini okuyabilir (sudo yok)
  - wizwalker Wine içinde çalışarak aynı wineserver üzerinden bağlanır

Kullanım (run_tools.sh üzerinden):
  bash run_tools.sh          →  menü
  bash run_tools.sh speed 3  →  doğrudan 3x speedhack
  bash run_tools.sh quest    →  doğrudan quest TP
  bash run_tools.sh both 3   →  3x speed + quest TP
"""
import asyncio
import sys

DEFAULT_SPEED = 580.0   # Wizard101 varsayılan yürüyüş hızı (float)
POLL_INTERVAL = 0.05    # saniye — speedhack yazma aralığı


# ── Yardımcı: sadece bir kez TP ─────────────────────────────────────────────
async def _tp_to_quest(client) -> str:
    """Quest hedefine ışınlan, konum stringini döndür."""
    pos = await client.quest_position.position()
    await client.teleport(pos)
    return f"x={pos.x:.1f}  y={pos.y:.1f}  z={pos.z:.1f}"


# ── Speedhack döngüsü ────────────────────────────────────────────────────────
async def speedhack_loop(client, multiplier: float, stop_event: asyncio.Event):
    target = DEFAULT_SPEED * multiplier
    print(f"[speed] Aktif → {target:.0f}  ({multiplier}x)  |  Ctrl+C ile dur")
    try:
        while not stop_event.is_set():
            try:
                body = await client.body()
                if body is not None:
                    await body.write_move_speed(target)
            except Exception:
                pass   # alan geçişi / karakter yüklenmesi sırasında beklenen hata
            await asyncio.sleep(POLL_INTERVAL)
    finally:
        # Durdurulunca orijinal hızı geri yaz
        try:
            body = await client.body()
            if body is not None:
                await body.write_move_speed(DEFAULT_SPEED)
            print(f"[speed] Hız sıfırlandı → {DEFAULT_SPEED:.0f}")
        except Exception:
            pass


# ── Quest TP döngüsü ─────────────────────────────────────────────────────────
async def quest_tp_loop(client, stop_event: asyncio.Event):
    loop = asyncio.get_event_loop()
    print("[quest] Aktif  |  Enter → ışınlan  |  Ctrl+C → çık")
    try:
        while not stop_event.is_set():
            # Blocking input'u thread pool'da çalıştır (asyncio'yu bloklamaz)
            try:
                await loop.run_in_executor(None, sys.stdin.readline)
            except EOFError:
                break
            if stop_event.is_set():
                break
            try:
                konum = await _tp_to_quest(client)
                print(f"[quest] Işınlandı → {konum}")
            except Exception as e:
                print(f"[quest] Hata: {e}")
    finally:
        print("[quest] Durduruldu.")


# ── Menü ─────────────────────────────────────────────────────────────────────
def _menu() -> tuple:
    """(mod: str, çarpan: float) döndür."""
    print()
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("   Wizard101 Mac Tools")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  [1]  Speedhack")
    print("  [2]  Quest TP")
    print("  [3]  İkisi birden")
    print("  [q]  Çık")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    while True:
        sec = input("Seçim: ").strip().lower()
        if sec == "q":
            sys.exit(0)
        if sec in ("1", "2", "3"):
            break
        print("  → 1, 2, 3 veya q gir.")

    mod_map = {"1": "speed", "2": "quest", "3": "both"}
    mod = mod_map[sec]

    mult = DEFAULT_SPEED  # kullanılmaz eğer quest-only ise
    if mod in ("speed", "both"):
        while True:
            raw = input(f"Hız çarpanı (varsayılan 3): ").strip()
            if raw == "":
                mult = 3.0
                break
            try:
                mult = float(raw)
                if mult > 0:
                    break
                print("  → 0'dan büyük bir sayı gir.")
            except ValueError:
                print("  → Geçerli bir sayı gir (örn: 3 veya 2.5).")

    return mod, mult


# ── Ana giriş noktası ────────────────────────────────────────────────────────
async def _run(mod: str, mult: float):
    from wizwalker import ClientHandler

    print("\n[tools] Wizard101'e bağlanılıyor...")

    async with ClientHandler() as handler:
        clients = handler.get_new_clients()
        if not clients:
            print("[tools] HATA: Çalışan Wizard101 bulunamadı.")
            print("        Önce oyunu Wine ile aç, sonra bu scripti çalıştır.")
            sys.exit(1)

        client = clients[0]
        print(f"[tools] Bağlandı  |  PID: {client.process_id}")

        await client.activate_hooks()
        print("[tools] Hook'lar aktif.\n")

        stop = asyncio.Event()
        tasks = []

        if mod in ("speed", "both"):
            tasks.append(asyncio.create_task(speedhack_loop(client, mult, stop)))

        if mod in ("quest", "both"):
            tasks.append(asyncio.create_task(quest_tp_loop(client, stop)))

        try:
            await asyncio.gather(*tasks)
        except (KeyboardInterrupt, asyncio.CancelledError):
            pass
        finally:
            stop.set()
            for t in tasks:
                t.cancel()
            # Görevlerin temizlenmesini bekle
            await asyncio.gather(*tasks, return_exceptions=True)
            print("\n[tools] Çıkış yapıldı.")


def main():
    # Komut satırı argümanları varsa menüyü atla
    if len(sys.argv) >= 2:
        arg = sys.argv[1].lower()
        if arg in ("speed", "quest", "both"):
            mod = arg
            try:
                mult = float(sys.argv[2]) if len(sys.argv) >= 3 else 3.0
            except ValueError:
                print(f"[tools] Geçersiz çarpan: {sys.argv[2]}")
                sys.exit(1)
        else:
            print(f"[tools] Bilinmeyen mod: {arg}")
            print("        Kullanım: wiz_tools.py [speed|quest|both] [çarpan]")
            sys.exit(1)
    else:
        mod, mult = _menu()

    try:
        asyncio.run(_run(mod, mult))
    except KeyboardInterrupt:
        print("\n[tools] Çıkış.")


if __name__ == "__main__":
    main()
