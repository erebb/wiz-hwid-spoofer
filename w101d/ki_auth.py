#!/usr/bin/env python3
"""
ki_auth.py — KingsIsle Wizard101 login authentication.

KingsIsle'ın özel DML/TCP protokolü üzerinden login sunucusuna bağlanır,
username/password ile kimlik doğrular ve oyunu başlatmak için gereken
CK2 token + UserID'yi döndürür.

Protocol kaynakları (MIT):
  cedws/w101-client-go  — Go protokol implementasyonu
  cedws/w101-proto-go   — DML mesaj tanımları (login.go, UserAuthenV3 = svc 7, order 27)
  MidasModLoader/Launcher — Rust referans implementasyonu

Kullanım:
  python3 w101d/ki_auth.py USERNAME PASSWORD
  → stdout: <userID> <ck2_token>

Oyun başlatma:
  wine WizardGraphicalClient.exe -L login.us.wizard101.com 12000 \\
       -U ..<userID> <ck2> <username>

Bağımlılık:
  pip3 install pycryptodome   (Twofish-OFB için)
  VEYA pip3 install twofish

AccountClientMismatch hatası alıyorsanız:
  KI sunucusu UserAuthenV3'teki Version alanını kontrol eder.
  WINEPREFIX registry'den otomatik okunur; bulunamazsa:
  export WIZ_GAME_VERSION='V_rXXXXXX.Wizard101_1_XXX'
"""

import sys
import os
import re
import socket
import struct
import hashlib
import base64

# ── Twofish-OFB şifreleme ─────────────────────────────────────────────────────
# KI rec1 encryption: Twofish cipher, Output Feedback (OFB) mode.
# pycryptodome önce denenir; yoksa pure-Python twofish paketi kullanılır.

def _twofish_ofb_xor(data: bytes, key: bytes, iv: bytes) -> bytes:
    """Twofish-OFB akış şifresi. Şifreleme == Şifre çözme (OFB simetrik)."""
    try:
        from Crypto.Cipher import Twofish as _TF
        cipher = _TF.new(key, _TF.MODE_OFB, iv)
        return cipher.encrypt(data)
    except ImportError:
        pass
    try:
        import twofish as _tw
        tf = _tw.Twofish(key)
        result = bytearray()
        block  = bytearray(iv)
        for i in range(0, len(data), 16):
            block  = bytearray(tf.encrypt(bytes(block)))
            chunk  = data[i:i + 16]
            result.extend(b ^ k for b, k in zip(chunk, block))
        return bytes(result)
    except ImportError:
        pass
    print(
        "[ki_auth] HATA: Twofish kütüphanesi bulunamadı.\n"
        "  Kurmak için: pip3 install pycryptodome",
        file=sys.stderr,
    )
    sys.exit(1)


# ── Oyun versiyonu okuma ─────────────────────────────────────────────────────
# KI sunucusu UserAuthenV3'teki Version alanını doğrular.
# AccountClientMismatch hatası: Version boş veya yanlış gönderilince oluşur.

def _read_game_version() -> str:
    """
    Oyun versiyonunu şu sırala okur:
      1. WIZ_GAME_VERSION ortam değişkeni
      2. WINEPREFIX/user.reg  → [Software\\KingsIsle Entertainment\\Wizard101]
      3. WINEPREFIX/system.reg
      4. Boş string (son çare — AccountClientMismatch olabilir)
    """
    # 1. Manuel override
    v = os.environ.get("WIZ_GAME_VERSION", "").strip()
    if v:
        return v

    # 2 & 3. WINEPREFIX registry dosyaları
    wineprefix = os.environ.get("WINEPREFIX", "").strip()
    if wineprefix:
        for reg_name in ("user.reg", "system.reg"):
            reg_path = os.path.join(wineprefix, reg_name)
            if not os.path.isfile(reg_path):
                continue
            try:
                text = open(reg_path, encoding="utf-8", errors="ignore").read()
                # Wine registry formatı:
                #   [Software\\KingsIsle Entertainment\\Wizard101]
                #   "Version"="V_r717268.Wizard101_1_521"
                m = re.search(
                    r'\[Software\\\\KingsIsle Entertainment\\\\Wizard101[^\]]*\]'
                    r'[^\[]*?"Version"="([^"]+)"',
                    text, re.DOTALL | re.IGNORECASE,
                )
                if m:
                    return m.group(1)
            except Exception:
                pass

    return ""


# ── Oturum kripto ─────────────────────────────────────────────────────────────
# Tüm sabitler cedws/w101-client-go login/rec1.go'dan alınmıştır.

def _derive_key(sid: int, time_secs: int, time_millis: int) -> bytes:
    """32-byte Twofish anahtarı: temel dizi 0x17+i, oturum parametreleriyle güncellenir."""
    key = bytearray([0x17 + i for i in range(32)])
    # sid (u16 LE) → key[4]=lo, key[5]=0, key[6]=hi
    key[4]  =  sid          & 0xFF
    key[5]  =  0
    key[6]  = (sid  >>   8) & 0xFF
    # time_secs (u32 LE) → key[8]=b0, key[9]=b2, key[12]=b1, key[13]=b3
    key[8]  =  time_secs         & 0xFF
    key[9]  = (time_secs  >> 16) & 0xFF
    key[12] = (time_secs  >>  8) & 0xFF
    key[13] = (time_secs  >> 24) & 0xFF
    # time_millis (u32 LE) → key[14]=b0, key[15]=b1
    key[14] =  time_millis        & 0xFF
    key[15] = (time_millis >>  8) & 0xFF
    return bytes(key)


def _derive_iv() -> bytes:
    """16-byte OFB IV: [0xB6, 0xB5, ..., 0xA7]"""
    return bytes([0xB6 - i for i in range(16)])


def gen_ck1(password: str, sid: int, time_secs: int, time_millis: int) -> str:
    """
    CK1 = base64(SHA-512(base64(SHA-512(password)) + str(sid) + str(time_secs) + str(time_millis)))
    Test vektörü (ck_test.go): password="1", sid=3258, ts=1617815695, tm=805
    → "+FO9W7DLYNuvLdwvnMaxtJrSD+/h7HHfpzSNKv6G4UomKKoy+uwknGbqrtz4KNHSIS6McowtSTXtQBwwq7bwSQ=="
    """
    h1 = base64.b64encode(hashlib.sha512(password.encode()).digest()).decode()
    h2 = hashlib.sha512(f"{h1}{sid}{time_secs}{time_millis}".encode()).digest()
    return base64.b64encode(h2).decode()


def encrypt_rec1(sid: int, username: str, ck1: str,
                 time_secs: int, time_millis: int) -> bytes:
    """Düz metin = "{sid} {username} {ck1}", Twofish-OFB ile şifreler."""
    plain = f"{sid} {username} {ck1}".encode()
    return _twofish_ofb_xor(plain, _derive_key(sid, time_secs, time_millis), _derive_iv())


def decrypt_rec1(data: bytes, sid: int, time_secs: int, time_millis: int) -> str:
    """Sunucunun rec1 yanıtını çözer → CK2 token string."""
    raw = _twofish_ofb_xor(data, _derive_key(sid, time_secs, time_millis), _derive_iv())
    return raw.rstrip(b"\x00").decode("latin-1").strip()


# ── TCP yardımcı ──────────────────────────────────────────────────────────────

def _recv_exact(sock: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("Sunucu bağlantıyı kapattı")
        buf += chunk
    return buf


# ── KI çerçeve (frame) G/Ç ───────────────────────────────────────────────────
# Proto: cedws/w101-client-go proto/frame.go
#
# Kablo formatı (normal uzunluk):
#   [F00D u16 LE] [length u16 LE] [is_ctrl u8] [opcode u8] [0 u8] [0 u8] [data...] [0x00]
#   length = 4 + len(data) + 1   (frame header + data + trailing null)

FRAME_MAGIC = 0xF00D


def _write_frame(sock: socket.socket, is_control: bool, opcode: int, message_data: bytes):
    raw    = bytes([1 if is_control else 0, opcode, 0, 0]) + message_data
    length = len(raw) + 1   # trailing null dahil
    sock.sendall(struct.pack("<HH", FRAME_MAGIC, length) + raw + b"\x00")


def _read_frame(sock: socket.socket):
    """(is_control, opcode, message_data) döndürür.  message_data trailing null içerir."""
    hdr          = _recv_exact(sock, 4)
    magic, length = struct.unpack_from("<HH", hdr)
    if magic != FRAME_MAGIC:
        raise ValueError(f"Geçersiz frame magic: {magic:#06x}")

    if length >= 0x8000:
        real_length = struct.unpack_from("<I", _recv_exact(sock, 4))[0]
    else:
        real_length = length

    raw        = _recv_exact(sock, real_length)
    is_control = raw[0] == 1
    opcode     = raw[1]
    data       = raw[4:]    # trailing null dahil
    return is_control, opcode, data


# ── KI DML string kodlaması ───────────────────────────────────────────────────
# codegen/codegen_helper.go: WriteString = u16 LE len + bytes; ReadString aynı.

def _str_encode(s: str) -> bytes:
    b = s.encode("latin-1")
    return struct.pack("<H", len(b)) + b


def _str_decode(data: bytes, offset: int):
    length = struct.unpack_from("<H", data, offset)[0]
    offset += 2
    return data[offset:offset + length].decode("latin-1"), offset + length


# ── DML mesaj kodlaması ───────────────────────────────────────────────────────
# proto/proto.go DMLMessage.Marshal / Unmarshal

def _dml_encode(service_id: int, order: int, packet: bytes) -> bytes:
    """DML mesajını çerçeve MessageData olarak kodlar."""
    data_len = 4 + len(packet)      # 2(svc+order) + 2(bu alan) + len(packet)
    return bytes([service_id, order]) + struct.pack("<H", data_len) + packet


def _dml_decode(data: bytes):
    """(service_id, order, packet) döndürür."""
    svc      = data[0]
    order    = data[1]
    data_len = struct.unpack_from("<H", data, 2)[0] + 1  # Go kaynağıyla aynı (+1)
    packet   = data[4:data_len]
    return svc, order, packet


# ── Kontrol paketleri ─────────────────────────────────────────────────────────
# proto/control/control.go

OPC_SESSION_OFFER   = 0x00
OPC_SESSION_ACCEPT  = 0x05
OPC_KEEPALIVE       = 0x03
OPC_KEEPALIVE_RSP   = 0x04

# Login service (w101-proto-go pkg/login/login.go)
SVC_LOGIN       = 7
MSG_AUTHEN_V3   = 27   # UserAuthenV3   → client gönderir
MSG_AUTHEN_RSP  = 14   # UserAuthenRsp  ← sunucu gönderir


def _parse_session_offer(data: bytes):
    """SessionOffer verisinden (sid, time_secs, time_millis) çıkarır."""
    # control.go SessionOffer.Unmarshal:
    #   [sid u16][skip 4 bytes][time_secs u32][time_millis u32][...]
    sid        = struct.unpack_from("<H", data,  0)[0]
    time_secs  = struct.unpack_from("<I", data,  6)[0]
    time_millis = struct.unpack_from("<I", data, 10)[0]
    return sid, time_secs, time_millis


def _make_session_accept(sid: int, time_secs: int, time_millis: int) -> bytes:
    """SessionAccept payload oluşturur (control.go SessionAccept.Marshal)."""
    # [6 sıfır bayt][time_secs u32][time_millis u32][sid u16]
    # [data_len=1 u32][0x00 şifreli mesaj][0x00 null terminator]
    return (b"\x00" * 6
            + struct.pack("<I", time_secs)
            + struct.pack("<I", time_millis)
            + struct.pack("<H", sid)
            + struct.pack("<I", 1)
            + b"\x00"
            + b"\x00")


# ── UserAuthenV3 DML paketi ───────────────────────────────────────────────────
# w101-proto-go pkg/login/login.go — UserAuthenV3.Marshal() alan sırası:
#   Rec1 STR, Version STR, Revision STR, DataRevision STR, CRC STR,
#   MachineID u64, Locale STR, PatchClientID STR, IsSteamPatcher u32, ConsoleType u8

def _build_authen_v3(rec1_bytes: bytes, version: str = "",
                     locale: str = "English", is_steam: bool = False) -> bytes:
    p  = _str_encode(rec1_bytes.decode("latin-1"))   # Rec1 (binary → latin-1 string)
    p += _str_encode(version)                         # Version — registry/env'den okunur
    p += _str_encode("")                              # Revision
    p += _str_encode("")                              # DataRevision
    p += _str_encode("")                              # CRC
    p += struct.pack("<Q", 0)                         # MachineID
    p += _str_encode(locale)                          # Locale
    p += _str_encode("")                              # PatchClientID
    # IsSteamPatcher: Steam hesabı için 1, normal KI hesabı için 0
    # WIZ_IS_STEAM=1 ile kontrol edilir (quick_launch.sh veya env)
    p += struct.pack("<I", 1 if is_steam else 0)
    p += struct.pack("<B", 0)                         # ConsoleType
    return p


# ── UserAuthenRsp DML ayrıştırma ──────────────────────────────────────────────
# w101-proto-go pkg/login/login.go — UserAuthenRsp.Unmarshal() alan sırası:
#   Error i32, UserID u64, Rec1 STR, Reason STR, TimeStamp STR,
#   PayingUser i32, Flags i32, SupportID STR

def _parse_authen_rsp(pkt: bytes):
    off        = 0
    error_code = struct.unpack_from("<i", pkt, off)[0];  off += 4
    user_id    = struct.unpack_from("<Q", pkt, off)[0];  off += 8
    rec1,  off = _str_decode(pkt, off)
    reason,off = _str_decode(pkt, off)
    return error_code, user_id, rec1, reason


# ── Kimlik doğrulama akışı ────────────────────────────────────────────────────

def authenticate(
    username: str,
    password: str,
    login_host: str = "login.us.wizard101.com",
    login_port: int = 12000,
    timeout:   float = 20.0,
):
    """
    Tam KI auth akışı:
      1. TCP bağlantı → SessionOffer alır
      2. SessionAccept gönderir
      3. UserAuthenV3 gönderir (rec1 = Twofish-OFB şifreli token)
      4. UserAuthenRsp alır → ck2 token + userID döndürür

    Returns: (user_id: int, ck2: str)
    """
    sock = socket.create_connection((login_host, login_port), timeout=timeout)
    sock.settimeout(timeout)
    print(f"[ki_auth] {login_host}:{login_port} bağlandı", file=sys.stderr)

    sid = time_secs = time_millis = None

    # --- Faz 1: SessionOffer bekle, SessionAccept gönder ---
    while sid is None:
        is_ctrl, opcode, data = _read_frame(sock)
        if not is_ctrl:
            continue
        if opcode == OPC_SESSION_OFFER:
            sid, time_secs, time_millis = _parse_session_offer(data)
            print(f"[ki_auth] Oturum: sid={sid}  ts={time_secs}  tm={time_millis}", file=sys.stderr)
            _write_frame(sock, True, OPC_SESSION_ACCEPT,
                         _make_session_accept(sid, time_secs, time_millis))
        elif opcode == OPC_KEEPALIVE:
            _write_frame(sock, True, OPC_KEEPALIVE_RSP, b"")

    # --- Faz 2: UserAuthenV3 gönder ---
    ck1     = gen_ck1(password, sid, time_secs, time_millis)
    rec1     = encrypt_rec1(sid, username, ck1, time_secs, time_millis)
    version  = _read_game_version()
    is_steam = os.environ.get("WIZ_IS_STEAM", "0").strip() in ("1", "true", "yes")
    if version:
        print(f"[ki_auth] Oyun versiyonu: {version}", file=sys.stderr)
    else:
        print("[ki_auth] UYARI: Oyun versiyonu bulunamadı — AccountClientMismatch olabilir.",
              file=sys.stderr)
        print("[ki_auth]   Düzeltmek için: export WIZ_GAME_VERSION='V_rXXXXXX.Wizard101_1_XXX'",
              file=sys.stderr)
    if is_steam:
        print("[ki_auth] Mod: Steam hesabı (IsSteamPatcher=1)", file=sys.stderr)
    payload = _build_authen_v3(rec1, version=version, locale="English", is_steam=is_steam)
    _write_frame(sock, False, 0, _dml_encode(SVC_LOGIN, MSG_AUTHEN_V3, payload))
    print("[ki_auth] UserAuthenV3 gönderildi, yanıt bekleniyor...", file=sys.stderr)

    # --- Faz 3: UserAuthenRsp bekle ---
    for _ in range(64):
        is_ctrl, opcode, data = _read_frame(sock)
        if is_ctrl:
            if opcode == OPC_KEEPALIVE:
                _write_frame(sock, True, OPC_KEEPALIVE_RSP, b"")
            continue
        # DML mesajı
        try:
            svc, order, pkt = _dml_decode(data)
        except Exception:
            continue
        if svc == SVC_LOGIN and order == MSG_AUTHEN_RSP:
            err, user_id, server_rec1, reason = _parse_authen_rsp(pkt)
            sock.close()
            if err != 0:
                reason_str = reason or "bilinmeyen hata"
                if "ClientMismatch" in reason_str or "Mismatch" in reason_str:
                    hint = (
                        "\n  → AccountClientMismatch: KI sunucusu oyun versiyonunu reddetti."
                        "\n  → WINEPREFIX'te kayıt defteri versiyonu okunabildi mi kontrol edin."
                        "\n  → Manuel düzeltme: quick_launch.sh'a şunu ekleyin:"
                        "\n     export WIZ_GAME_VERSION='V_rXXXXXX.Wizard101_1_XXX'"
                        "\n  → Versiyonu bulmak için: wine reg query"
                        r" 'HKLM\SOFTWARE\KingsIsle Entertainment\Wizard101'"
                        "\n  → Kullanıcı adı/şifre de yanlış olabilir."
                    )
                else:
                    hint = "\n  → Kullanıcı adı/şifre yanlış olabilir."
                raise RuntimeError(
                    f"Auth başarısız (error={err}): {reason_str}{hint}"
                )
            ck2 = decrypt_rec1(server_rec1.encode("latin-1"), sid, time_secs, time_millis)
            print(f"[ki_auth] Kimlik doğrulandı — UserID: {user_id}", file=sys.stderr)
            return user_id, ck2

    sock.close()
    raise TimeoutError("Sunucudan auth yanıtı alınamadı (timeout).")


# ── Giriş noktası ─────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 3:
        print("Kullanım: ki_auth.py <kullanici_adi> <sifre>", file=sys.stderr)
        sys.exit(1)

    username = sys.argv[1]
    password = sys.argv[2]

    try:
        user_id, ck2 = authenticate(username, password)
        # stdout: "<userID> <ck2>" — quick_launch.sh bunu parse eder
        print(f"{user_id} {ck2}")
    except Exception as e:
        print(f"[ki_auth] HATA: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
