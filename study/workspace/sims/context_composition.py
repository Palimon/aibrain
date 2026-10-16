"""Context composition of main-session transcripts (chars/4, images excluded, up to the first
compaction), split into orchestrators (>=5 Agent/Task spawns) and the rest.

Usage: python3 -I context_composition.py <transcript.jsonl>...
"""
import json, sys
from collections import Counter

def size(c):
    if isinstance(c, str):
        return len(c), 0
    n = imgs = 0
    for b in c or []:
        if b.get("type") == "image":
            imgs += 1
        elif b.get("type") == "text":
            n += len(b.get("text", ""))
        else:
            n += len(json.dumps(b))
    return n, imgs

groups = {"orchestrator": Counter(), "other": Counter()}
counts = Counter()
for path in sys.argv[1:]:
    c, spawns = Counter(), 0
    for line in open(path):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("isCompactSummary") or d.get("subtype") == "compact_boundary":
            break
        if d.get("type") not in ("user", "assistant") or d.get("isSidechain"):
            continue
        content = d.get("message", {}).get("content")
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        for b in content or []:
            t = b.get("type")
            if t == "tool_result":
                n, i = size(b.get("content"))
                name = "agent results" if "agentId" in str(b.get("content"))[:4000] else "tool results"
                c[name] += n; c["images"] += i
            elif t == "tool_use":
                if b.get("name") in ("Agent", "Task"):
                    spawns += 1
                c["tool calls"] += len(json.dumps(b.get("input", {})))
            elif t == "text":
                s = b.get("text", "")
                if d["type"] == "assistant":
                    c["assistant text"] += len(s)
                elif "<task-notification>" in s:
                    c["subagent notices"] += len(s)
                else:
                    c["user text"] += len(s)
    g = "orchestrator" if spawns >= 5 else "other"
    groups[g].update(c); counts[g] += 1
for g, c in groups.items():
    imgs = c.pop("images", 0)
    tot = sum(c.values()) or 1
    print(f"{g}: {counts[g]} sessions, ~{tot/4/1e6:.1f}M tokens (chars/4), {imgs} images excluded")
    for k, v in c.most_common():
        print(f"  {k:18} {100*v/tot:5.1f}%")
