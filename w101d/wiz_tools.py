#!/usr/bin/env python3
"""
wiz_tools.py — Wizard101 Mac/Wine araç seti
============================================
Deimos/wizwalker kodu baz alınarak Mac/Wine için uyarlandı.

Özellikler:
  speed  — client_object.speed_multiplier üzerinden hız çarpanı
             (Deimos'un kullandığı aynı yöntem, int16: değer = (çarpan-1)*100)
  quest  — client.quest_position.position() → client.teleport() ile quest TP
  both   — ikisi aynı anda

Mac/Wine notu:
  setup_single.sh veya setup_env.sh wine64-preloader'ı get-task-allow ile
  imzalar; bu sayede pymem cross-process memory okuyabilir, sudo gerekmez.

Kullanım (run_deimos.sh veya run_tools.sh üzerinden çalıştır):
  bash run_deimos.sh speed 3   → 3x speedhack
  bash run_deimos.sh quest     → Enter ile quest TP
  bash run_deimos.sh both 3    → ikisi birden
"""
import asyncio
import sys

POLL_SEC = 0.1   # speedhack yazma aralığı (alan geçişlerinde değer sıfırlanır)


# ── Speedhack ────────────────────────────────────────────────────────────────
async def speedhack_loop(client, multiplier: float, stop: asyncio.Event):
    """
    Deimos tarzı hız hilesi.
    client_object.speed_multiplier → int16
    Formül: değer = (çarpan - 1) * 100   örn: 3x → 200, 5x → 400
    Sıfırlama: 0 yaz (= normal hız)
    """
    target = int((multiplier - 1) * 100)
    original = 0

    print(f"[speed] Aktif  →  {multiplier}x  (multiplier değeri: {target})")
    print(f"[speed] Ctrl+C ile dur")

    try:
        try:
            original = await client.client_object.speed_multiplier()
        except Exception:
            original = 0

        while not stop.is_set():
            try:
                await client.client_object.write_speed_multiplier(target)
            except Exception:
                pass   # alan geçişinde beklenen hata
            await asyncio.sleep(POLL_SEC)

    finally:
        try:
            await client.client_object.write_speed_multiplier(original)
            print(f"[speed] Hız sıfırlandı (multiplier={original})")
        except Exception:
            pass


# ── Quest TP ─────────────────────────────────────────────────────────────────
async def quest_tp_loop(client, stop: asyncio.Event):
    """
    wizwalker quest TP:
      client.quest_position.position() → XYZ
      client.teleport(xyz)
    Kullanıcı Enter'a basınca bir kez ışınlanır.
    """
    loop = asyncio.get_event_loop()
    print("[quest] Aktif  |  Enter → quest hedefine ışınlan  |  Ctrl+C → çık")

    try:
        while not stop.is_set():
            try:
                await loop.run_in_executor(None, sys.stdin.readline)
            except EOFError:
                break
            if stop.is_set():
                break
            try:
                xyz = await client.quest_position.position()
                await client.teleport(xyz)
                print(f"[quest] Işınlandı  →  x={xyz.x:.1f}  y={xyz.y:.1f}  z={xyz.z:.1f}")
            except Exception as e:
                print(f"[quest] Hata: {e}")
    finally:
        print("[quest] Durduruldu.")


# ── Bağlantı + ana döngü ─────────────────────────────────────────────────────
async def _run(mod: str, multiplier: float):
    import os
    from wizwalker import ClientHandler

    wiz_pid_env = os.environ.get("WIZ_PID", "").strip()
    print("\n[tools] Wizard101'e bağlanılıyor...")

    async with ClientHandler() as handler:
        clients = handler.get_new_clients()
        if not clients and wiz_pid_env:
            print(f"[tools] ClientHandler bulamadı, PID {wiz_pid_env} ile direkt deneniyor...")
            try:
                from wizwalker.client import Client
                client = Client(int(wiz_pid_env))
                handler.clients.append(client)
                clients = [client]
            except Exception as e:
                print(f"[tools] Direkt bağlantı başarısız: {e}")
        if not clients:
            print("[tools] HATA: Çalışan Wizard101 bulunamadı.")
            print("        Önce oyunu Wine ile aç, sonra tekrar çalıştır.")
            sys.exit(1)

        client = clients[0]
        print(f"[tools] Bağlandı  |  PID: {client.process_id}")

        await client.activate_hooks()
        print("[tools] Memory hook'ları aktif.\n")

        stop = asyncio.Event()
        tasks = []

        if mod in ("speed", "both"):
            tasks.append(asyncio.create_task(speedhack_loop(client, multiplier, stop)))
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
            await asyncio.gather(*tasks, return_exceptions=True)
            print("\n[tools] Çıkış yapıldı.")


# ── Menü ─────────────────────────────────────────────────────────────────────
def _menu():
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
        s = input("Seçim: ").strip().lower()
        if s == "q":
            sys.exit(0)
        if s in ("1", "2", "3"):
            break

    mod = {"1": "speed", "2": "quest", "3": "both"}[s]
    mult = 3.0
    if mod in ("speed", "both"):
        while True:
            r = input("Hız çarpanı (varsayılan 3): ").strip()
            if r == "":
                mult = 3.0
                break
            try:
                mult = float(r)
                if mult > 0:
                    break
            except ValueError:
                pass
            print("  → Geçerli bir sayı gir.")
    return mod, mult


def main():
    if len(sys.argv) >= 2:
        mod = sys.argv[1].lower()
        if mod not in ("speed", "quest", "both"):
            print(f"Kullanım: wiz_tools.py [speed|quest|both] [çarpan]")
            sys.exit(1)
        try:
            mult = float(sys.argv[2]) if len(sys.argv) >= 3 else 3.0
        except ValueError:
            print(f"Geçersiz çarpan: {sys.argv[2]}")
            sys.exit(1)
    else:
        mod, mult = _menu()

    try:
        asyncio.run(_run(mod, mult))
    except KeyboardInterrupt:
        print("\n[tools] Çıkış.")


if __name__ == "__main__":
    main()
