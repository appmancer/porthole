#!/usr/bin/env python3
import argparse
import time
import urllib.request


_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def fetch_bytes(url: str, nbytes: int) -> bytes:
    # B2 /peek responses may not always terminate the HTTP stream promptly.
    # Read only the bytes we need so we don't block waiting for EOF.
    with _opener.open(url, timeout=2.0) as resp:
        return resp.read(nbytes)


def b(x: int) -> str:
    return f"{x:02X}"


def main() -> int:
    ap = argparse.ArgumentParser(
        description=(
            "Poll B2 /peek and log key+portal state transitions. "
            "Designed for debugging missed A/S portal placement."
        )
    )
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", default=48075, type=int)
    ap.add_argument("--id", default="b2")
    ap.add_argument("--interval-ms", default=50, type=int)
    ap.add_argument("--seconds", default=120, type=int)
    ap.add_argument("--out", default=".tmp/b2-monitor-input.log")
    args = ap.parse_args()

    # We fetch a single ZP range that covers everything we care about.
    # Base: &008E (keys_held)
    # End : &00D9 (portal_b_orient)
    addr = 0x008E
    length = (0x00D9 - 0x008E) + 1
    # NOTE: B2 /peek expects address in hex, but length in decimal.
    url = f"http://{args.host}:{args.port}/peek/{args.id}/{addr:x}/+{length}"

    def zp(off: int, data: bytes) -> int:
        return data[off]

    def stamp_ms() -> int:
        return int(time.time() * 1000)

    # Offsets into the fetched block.
    OFF_KEYS_HELD = 0x008E - addr
    OFF_KEYS_PRESSED = 0x008F - addr
    OFF_PORTAL_LATCH = 0x0095 - addr
    OFF_RETICLE_X = 0x00B8 - addr
    OFF_RETICLE_Y = 0x00B9 - addr
    OFF_RETICLE_STATE = 0x00BA - addr
    OFF_RETICLE_ACTIVE = 0x00BB - addr
    OFF_RETICLE_REASON = 0x00C8 - addr
    OFF_PORTAL_PENDING = 0x00C9 - addr
    OFF_PORTAL_KIND = 0x00CA - addr
    OFF_PORTAL_B_ENABLED = 0x00D5 - addr
    OFF_PORTAL_B_ROOM = 0x00D6 - addr
    OFF_PORTAL_B_X = 0x00D7 - addr
    OFF_PORTAL_B_Y = 0x00D8 - addr
    OFF_PORTAL_B_ORIENT = 0x00D9 - addr

    # Bits.
    BIT_PORTAL_A = 1 << 6  # keys_held bit6
    BIT_PORTAL_B = 1 << 7  # keys_held bit7

    # State for detecting failures.
    last = None
    last_press_ms = None
    last_press_xy = None
    last_press_b_state = None

    end_time = time.time() + max(1, args.seconds)
    interval_s = max(1, args.interval_ms) / 1000.0

    # Ensure output dir exists.
    try:
        import os

        os.makedirs(os.path.dirname(args.out), exist_ok=True)
    except Exception:
        pass

    with open(args.out, "a", encoding="ascii") as f:
        f.write(f"# url={url}\n")
        f.write(f"# interval_ms={args.interval_ms} seconds={args.seconds}\n")
        f.flush()

        successes = 0
        failures = 0
        next_err_ms = stamp_ms()

        while time.time() < end_time:
            try:
                data = fetch_bytes(url, length)
            except Exception as e:
                failures += 1
                now_ms = stamp_ms()
                if now_ms >= next_err_ms:
                    f.write(
                        f"{now_ms} ERROR peek_failed failures={failures} err={type(e).__name__}:{e}\n"
                    )
                    f.flush()
                    next_err_ms = now_ms + 1000
                time.sleep(interval_s)
                continue

            if len(data) < length:
                failures += 1
                time.sleep(interval_s)
                continue

            successes += 1

            keys_held = zp(OFF_KEYS_HELD, data)
            keys_pressed = zp(OFF_KEYS_PRESSED, data)
            portal_req = zp(OFF_PORTAL_LATCH, data)
            rx = zp(OFF_RETICLE_X, data)
            ry = zp(OFF_RETICLE_Y, data)
            rstate = zp(OFF_RETICLE_STATE, data)
            ractive = zp(OFF_RETICLE_ACTIVE, data)
            rreason = zp(OFF_RETICLE_REASON, data)
            ppending = zp(OFF_PORTAL_PENDING, data)
            pkind = zp(OFF_PORTAL_KIND, data)
            pb_en = zp(OFF_PORTAL_B_ENABLED, data)
            pb_room = zp(OFF_PORTAL_B_ROOM, data)
            pb_x = zp(OFF_PORTAL_B_X, data)
            pb_y = zp(OFF_PORTAL_B_Y, data)
            pb_o = zp(OFF_PORTAL_B_ORIENT, data)

            now_ms = stamp_ms()
            b_state = (pb_en, pb_room, pb_x, pb_y, pb_o)

            snap = (
                keys_held,
                keys_pressed,
                portal_req,
                ractive,
                rstate,
                rreason,
                rx,
                ry,
                ppending,
                pkind,
                b_state,
            )

            if last is None:
                last = {
                    "keys_held": keys_held,
                    "rx": rx,
                    "ry": ry,
                    "b_state": b_state,
                    "snapshot": snap,
                }
                f.write(
                    f"{now_ms} INIT held={b(keys_held)} pressed={b(keys_pressed)} req={b(portal_req)} "
                    f"ractive={b(ractive)} rstate={b(rstate)} reason={b(rreason)} rx={b(rx)} ry={b(ry)} "
                    f"ppending={b(ppending)} pkind={b(pkind)} "
                    f"pb={b(pb_en)},{b(pb_room)},{b(pb_x)},{b(pb_y)},{b(pb_o)}\n"
                )
                f.flush()
                time.sleep(interval_s)
                continue

            if snap != last["snapshot"]:
                f.write(
                    f"{now_ms} CHG held={b(keys_held)} pressed={b(keys_pressed)} req={b(portal_req)} "
                    f"ractive={b(ractive)} rstate={b(rstate)} reason={b(rreason)} rx={b(rx)} ry={b(ry)} "
                    f"ppending={b(ppending)} pkind={b(pkind)} "
                    f"pb={b(pb_en)},{b(pb_room)},{b(pb_x)},{b(pb_y)},{b(pb_o)}\n"
                )

            # Detect reticle moved.
            if (rx, ry) != (last["rx"], last["ry"]):
                line = f"{now_ms} RETICLE_MOVE x={rx} y={ry}\n"
                f.write(line)

            # Detect Portal B state change (this is our strongest "stamp happened" signal).
            if b_state != last["b_state"]:
                line = (
                    f"{now_ms} PORTAL_B_STATE en={b(pb_en)} room={b(pb_room)} "
                    f"x={b(pb_x)} y={b(pb_y)} o={b(pb_o)}\n"
                )
                f.write(line)

            # Detect S key press/release via keys_held bit7.
            prev_held = last["keys_held"]
            held_s = (keys_held & BIT_PORTAL_B) != 0
            prev_held_s = (prev_held & BIT_PORTAL_B) != 0
            if held_s and not prev_held_s:
                last_press_ms = now_ms
                last_press_xy = (rx, ry)
                last_press_b_state = b_state
                line = (
                    f"{now_ms} PRESS_S held={b(keys_held)} pressed={b(keys_pressed)} "
                    f"req={b(portal_req)} ractive={b(ractive)} rstate={b(rstate)} reason={b(rreason)} "
                    f"rx={b(rx)} ry={b(ry)} ppending={b(ppending)} pkind={b(pkind)} "
                    f"pb(en,room,x,y,o)={b(pb_en)},{b(pb_room)},{b(pb_x)},{b(pb_y)},{b(pb_o)}\n"
                )
                f.write(line)

            if (not held_s) and prev_held_s:
                line = f"{now_ms} RELEASE_S held={b(keys_held)} req={b(portal_req)}\n"
                f.write(line)

            # After a press, if reticle didn't move and portal B didn't change for a bit, call it out.
            if last_press_ms is not None and (now_ms - last_press_ms) >= 500:
                if last_press_xy == (rx, ry) and last_press_b_state == b_state:
                    line = (
                        f"{now_ms} S_NO_STAMP_AFTER_500MS rx={b(rx)} ry={b(ry)} "
                        f"ractive={b(ractive)} rstate={b(rstate)} reason={b(rreason)} held={b(keys_held)} req={b(portal_req)}\n"
                    )
                    f.write(line)
                last_press_ms = None
                last_press_xy = None
                last_press_b_state = None

            last["keys_held"] = keys_held
            last["rx"] = rx
            last["ry"] = ry
            last["b_state"] = b_state
            last["snapshot"] = snap

            f.flush()

            time.sleep(interval_s)

        f.write(f"# done successes={successes} failures={failures}\n")
        f.flush()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
