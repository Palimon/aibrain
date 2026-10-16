"""Replay Fable main-session transcripts under four cache policies, with full session cost.

P1 5m, no keep-alive: a gap over 5 min re-writes the whole context at 1.25x input.
P2 5m + keep-alive every 4.5 min: one read of the context per ping (gaps over ~4.5 h go cold
   instead when that is cheaper).
P3 1h, no keep-alive: a gap over 60 min re-writes the context at 2x input.
P4 1h + keep-alive every 55 min.
Pings are priced two ways: "ideal" (API max_tokens:0, one cache read) and "cc" (a Claude Code
turn: the read plus PING_TAIL tokens written and PING_OUT output tokens).
Base cost (same under every policy): output, uncached input, and warm cache reads.

Usage: python3 -I orch_sim.py <transcript.jsonl>...
"""
import json, math, sys
from datetime import datetime

I, O, R = 10 / 1e6, 50 / 1e6, 0.25 / 1e6  # Fable 5.1
PING_TAIL, PING_OUT = 300, 300


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
        if not u or key in seen or not m.get("model"):
            continue
        seen.add(key)
        t = datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00")).timestamp()
        out.append((t, m["model"], u.get("cache_read_input_tokens", 0) or 0,
                    u.get("cache_creation_input_tokens", 0) or 0, u.get("input_tokens", 0) or 0,
                    u.get("output_tokens", 0) or 0))
    out.sort()
    return out


def run(reqs):
    c = dict(base=0.0, writes=0.0, hours=(reqs[-1][0] - reqs[0][0]) / 3600, n=len(reqs),
             p1=0.0, p2i=0.0, p2c=0.0, p3=0.0, p4i=0.0, p4c=0.0, ctx=0.0,
             g5_30=0, g30_60=0, g60=0, idle=0.0)
    ping_i = lambda ctx: ctx * R
    ping_c = lambda ctx: ctx * R + PING_TAIL * 1.25 * I + PING_OUT * O
    prev = None
    for t, model, read, write, inp, out in reqs:
        ctx = read + write + inp
        c["ctx"] += ctx
        if prev is not None and write > 0.5 * ctx and write > 20000:
            write = max(0, ctx - prev[1])  # a real miss: the gap model below prices it instead
            read = ctx - write - inp
        c["writes"] += write
        c["base"] += out * O + inp * I + read * R
        if prev is not None:
            gap, pc = (t - prev[0]) / 60, prev[1]
            if gap > 5:
                c["idle"] += gap
                c["g5_30" if gap <= 30 else "g30_60" if gap <= 60 else "g60"] += 1
                cold5, n5 = pc * 1.25 * I, math.floor(gap / 4.5)
                c["p1"] += cold5
                c["p2i"] += min(n5 * ping_i(pc), cold5)
                c["p2c"] += min(n5 * ping_c(pc), cold5)
            if gap > 60:
                cold1, n1 = pc * 2 * I, math.floor(gap / 55)
                c["p3"] += cold1
                c["p4i"] += min(n1 * ping_i(pc), cold1)
                c["p4c"] += min(n1 * ping_c(pc), cold1)
        prev = (t, ctx)
    w5, w1 = c["writes"] * 1.25 * I, c["writes"] * 2 * I
    c.update(p1=c["p1"] + w5, p2i=c["p2i"] + w5, p2c=c["p2c"] + w5,
             p3=c["p3"] + w1, p4i=c["p4i"] + w1, p4c=c["p4c"] + w1)
    c["ctx"] /= c["n"]
    return c


def main():
    keys = ["hours", "n", "idle", "writes", "base", "p1", "p2i", "p2c", "p3", "p4i", "p4c",
            "g5_30", "g30_60", "g60"]
    tot = dict.fromkeys(keys, 0.0)
    ctxw = 0.0
    for p in sys.argv[1:]:
        if "/subagents/" in p:
            continue
        reqs = requests(p)
        if len(reqs) < 20 or sum("fable" in r[1] for r in reqs) < 0.8 * len(reqs):
            continue
        c = run(reqs)
        print(f"{p[-24:]:24} {c['hours']:5.1f}h req {c['n']:4} ctx {c['ctx']/1e3:4.0f}k "
              f"wrote {c['writes']/1e3:5.0f}k gaps 5-30:{c['g5_30']:3} 30-60:{c['g30_60']:2} "
              f">60:{c['g60']:2} base ${c['base']:6.2f} | P1 {c['p1']:6.2f} P2 {c['p2i']:5.2f}/"
              f"{c['p2c']:5.2f} P3 {c['p3']:5.2f} P4 {c['p4i']:5.2f}/{c['p4c']:5.2f}")
        for k in keys:
            tot[k] += c[k]
        ctxw += c["ctx"] * c["hours"]
    h = tot["hours"]
    print(f"\nTOTAL {h:.1f}h, {tot['n']:.0f} requests, avg ctx {ctxw/h/1e3:.0f}k, "
          f"written {tot['writes']/1e3:.0f}k ({tot['writes']/h/1e3:.0f}k/h), idle {tot['idle']/60:.1f}h, "
          f"gaps 5-30 {tot['g5_30']:.0f}, 30-60 {tot['g30_60']:.0f}, >60 {tot['g60']:.0f}")
    print("per 36h:  base {:.0f}".format(tot["base"] / h * 36))
    for k, name in [("p1", "P1 5m no ping"), ("p2i", "P2 5m+4.5min ideal"), ("p2c", "P2 5m+4.5min cc"),
                    ("p3", "P3 1h no ping"), ("p4i", "P4 1h+55min ideal"), ("p4c", "P4 1h+55min cc")]:
        print(f"  {name:20} cache ${tot[k]/h*36:7.2f}   total ${(tot[k]+tot['base'])/h*36:7.2f}")


main()
