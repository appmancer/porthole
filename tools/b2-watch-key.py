#!/usr/bin/env python3
import os
import time
import urllib.request

B2_HOST = os.environ.get("B2_HOST", "127.0.0.1")
B2_PORT = os.environ.get("B2_PORT", "48075")
B2_ID = os.environ.get("B2_ID", "b2")

ADDR = int(os.environ.get("B2_WATCH_ADDR", "0x8A"), 0)
LEN = int(os.environ.get("B2_WATCH_LEN", "1"), 0)
DURATION = float(os.environ.get("B2_WATCH_SECS", "20"))
INTERVAL = float(os.environ.get("B2_WATCH_INTERVAL", "0.05"))


def fetch_bytes():
    url = f"http://{B2_HOST}:{B2_PORT}/peek/{B2_ID}/{ADDR:+#x}/+{LEN}"
    with urllib.request.urlopen(url, timeout=2) as resp:
        return resp.read()


def main():
    end_time = time.time() + DURATION
    last = None

    print(f"Watching {ADDR:#04x} for {DURATION:.1f}s (interval {INTERVAL:.3f}s)")
    print(f"B2: {B2_HOST}:{B2_PORT} id={B2_ID}")

    while time.time() < end_time:
        try:
            data = fetch_bytes()
        except Exception as exc:
            print(f"ERR: {exc}")
            time.sleep(INTERVAL)
            continue

        if data != last:
            hexbytes = " ".join(f"{b:02X}" for b in data)
            print(f"{time.time():.3f}  {hexbytes}")
            last = data

        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
