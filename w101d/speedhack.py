#!/usr/bin/env python3
"""
speedhack.py — Wizard101 hız hilesi (Wine / Mac)

Çalışan Wizard101 prosesine wizwalker üzerinden bağlanır,
oyuncunun move_speed değerini sürekli yazar.

Kullanım:
    python speedhack.py          → 3x hız (varsayılan)
    python speedhack.py 5        → 5x hız
    python speedhack.py 1        → sıfırla (normal hız)
"""
import asyncio
import sys

# Wizard101'in sabit yürüyüş hızı (setup_env.sh ile kurulan
# wizwalker/development bu değeri base alır)
DEFAULT_SPEED = 580.0


async def run(multiplier: float) -> None:
    from wizwalker import ClientHandler

    print(f"[speedhack] Hedef hız : {DEFAULT_SPEED * multiplier:.1f}  ({multiplier}x)")
    print("[speedhack] Wizard101'e bağlanılıyor...")

    async with ClientHandler() as handler:
        # Çalışan tüm Wizard101 pencerelerini tara
        clients = handler.get_new_clients()
        if not clients:
            print("[speedhack] HATA: Çalışan Wizard101 bulunamadı.")
            print("           Önce oyunu aç, sonra bu scripti çalıştır.")
            sys.exit(1)

        client = clients[0]
        print(f"[speedhack] Bağlandı   : PID {client.process_id}")

        # Bellek hook'larını etkinleştir (Body, CurrentPlayer vb.)
        await client.activate_hooks()
        print("[speedhack] Hook'lar   : aktif")
        print("[speedhack] Durdurmak için Ctrl+C\n")

        target = DEFAULT_SPEED * multiplier

        try:
            while True:
                try:
                    body = await client.body()
                    if body is not None:
                        await body.write_move_speed(target)
                except Exception:
                    # Karakter yüklenene kadar / alan geçişlerinde hata verebilir
                    pass
                await asyncio.sleep(0.05)

        except KeyboardInterrupt:
            print("\n[speedhack] Durduruluyor...")
            try:
                body = await client.body()
                if body is not None:
                    await body.write_move_speed(DEFAULT_SPEED)
                    print(f"[speedhack] Hız {DEFAULT_SPEED:.0f}'e döndürüldü.")
            except Exception:
                pass


def main() -> None:
    multiplier = 3.0
    if len(sys.argv) >= 2:
        try:
            multiplier = float(sys.argv[1])
        except ValueError:
            print(f"[speedhack] HATA: Geçersiz çarpan '{sys.argv[1]}' — sayı giriniz.")
            sys.exit(1)

    if multiplier <= 0:
        print("[speedhack] HATA: Çarpan 0'dan büyük olmalı.")
        sys.exit(1)

    asyncio.run(run(multiplier))


if __name__ == "__main__":
    main()
