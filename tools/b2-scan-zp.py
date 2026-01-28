#!/usr/bin/env python3
import os
import time
import urllib.request

B2_HOST = os.environ.get("B2_HOST", "127.0.0.1")
B2_PORT = os.environ.get("B2_PORT", "48075")
B2_ID = os.environ.get("B2_ID", "b2")

START = int(os.environ.get("B2_SCAN_START", "0x70"), 0)
LEN = int(os.environ.get("B2_SCAN_LEN", "0x50"), 0)
TARGET = int(os.environ.get("B2_SCAN_TARGET", "0xA5"), 0)
DURATION = float(os.environ.get("B2_SCAN_SECS", "5"))
INTERVAL = float(os.environ.get("B2_SCAN_INTERVAL", "0.05"))


def fetch_bytes(addr, length):
    url = f"http://{B2_HOST}:{B2_PORT}/peek/{B2_ID}/{addr:+#x}/+{length}"
    with urllib.request.urlopen(url, timeout=2) as resp:
        return resp.read()


def main():
    print(f"Scanning ZP {START:#04x}..{START+LEN-1:#04x} for {TARGET:#02x}")
    print(f"B2: {B2_HOST}:{B2_PORT} id={B2_ID}")

    end_time = time.time() + DURATION
    while time.time() < end_time:
        try:
            data = fetch_bytes(START, LEN)
        except Exception as exc:
            print(f"ERR: {exc}")
            time.sleep(INTERVAL)
            continue

        hits = [START + i for i, b in enumerate(data) if b == TARGET]
        if hits:
            print("HIT:", ", ".join(f"{a:#04x}" for a in hits))
            return

        time.sleep(INTERVAL)

    print("No hit found")


if __name__ == "__main__":
    main()
