"""Replay Claude Code transcripts under two cache policies and compare cost.

Policy A, 1h: every write at 2x input. Gaps over 55 min either tick (one read per 55 min) or
go cold (one re-write of the context), whichever is cheaper.
Policy B, 5m + keep-alive: every write at 1.25x input. Gaps over 5 min get a ping every 4.5 min
or go cold, whichever is cheaper. Two ping prices: "ideal" (API max_tokens:0, one cache read)
and "cc" (a Claude Code turn: the read plus ~300 tokens written and ~300 output tokens).

Usage: python3 -I ttl_sim.py <transcript.jsonl>... ; prints one row per transcript and totals.
"""
import json, math, sys
from datetime import datetime

PRICES = {  # input, output, read per MTok
    "sonnet": (2.0, 10.0, 0.20),
    "opus": (4.0, 20.0, 0.20),
    "fable": (10.0, 50.0, 0.25),
}
PING_TAIL, PING_OUT = 300, 300


def family(model):
    for k in PRICES:
        if k in (model or ""):
            return k
    return None


def requests(path):
    seen, out = set(), []
    for line in open(path):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") != "assistant":
            continue
        m = d.get("message", {})
        key = (m.get("id"), d.get("requestId"))
        u = m.get("usage")
        fam = family(m.get("model"))
        if not u or not fam or key in seen:
            continue
        seen.add(key)
        t = datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00")).timestamp()
        read = u.get("cache_read_input_tokens", 0) or 0
        write = u.get("cache_creation_input_tokens", 0) or 0
        inp = u.get("input_tokens", 0) or 0
        out.append((t, fam, read, write, inp))
    out.sort()
    return out


def simulate(reqs):
    a = b_ideal = b_cc = 0.0
    writes = idle_min = 0.0
    prev = None
    for t, fam, read, write, inp in reqs:
        i, o, r = (p / 1e6 for p in PRICES[fam])
        ctx = read + write + inp
        # A miss in the real transcript (big write, little read) is replaced by the gap model below.
        if prev is not None and write > 0.5 * ctx and write > 20000:
            write = max(0, ctx - prev[1])
        writes += write
        a += write * 2 * i
        b_ideal += write * 1.25 * i
        b_cc += write * 1.25 * i
        if prev is not None:
            gap = (t - prev[0]) / 60
            c = prev[1]
            if gap > 5:
                idle_min += gap
                pings = math.floor(gap / 4.5)
                cold5 = c * 1.25 * i
                b_ideal += min(pings * c * r, cold5)
                b_cc += min(pings * (c * r + PING_TAIL * 1.25 * i + PING_OUT * o), cold5)
            if gap > 55:
                ticks = math.floor(gap / 55)
                a += min(ticks * (c * r + PING_TAIL * 2 * i + PING_OUT * o), c * 2 * i)
        prev = (t, ctx)
    return a, b_ideal, b_cc, writes, idle_min


def main():
    tot = [0.0] * 5
    print(f"{'transcript':42} {'model':6} {'hours':>6} {'idle h':>6} {'avgctx':>7} {'written':>9} "
          f"{'1h $':>7} {'5m+ideal':>8} {'5m+cc':>7}")
    for p in sys.argv[1:]:
        reqs = requests(p)
        if len(reqs) < 5:
            continue
        a, bi, bc, w, idle = simulate(reqs)
        hours = (reqs[-1][0] - reqs[0][0]) / 3600
        avgctx = sum(x[2] + x[3] + x[4] for x in reqs) / len(reqs)
        fams = sorted({x[1] for x in reqs})
        print(f"{p[-42:]:42} {'/'.join(fams):6} {hours:6.1f} {idle/60:6.1f} {avgctx/1000:6.0f}k "
              f"{w/1000:8.0f}k {a:7.2f} {bi:8.2f} {bc:7.2f}")
        for k, v in enumerate((a, bi, bc, w, idle)):
            tot[k] += v
    print(f"TOTAL 1h ${tot[0]:.2f}  5m+ideal ${tot[1]:.2f}  5m+cc ${tot[2]:.2f}  "
          f"written {tot[3]/1e6:.1f}M  idle {tot[4]/60:.1f}h")


main()
