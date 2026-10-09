#!/usr/bin/env python3
"""Exact Claude token counts for every out/*.txt, via `claude -p` usage.

Each file's content is sent once inside a fixed wrapper; its token count is the
reported input total (uncached + cache-write + cache-read) minus the same
wrapper's total with an empty document. Identical contents are counted once.
Results are cached in tokens.json so reruns only count new files.

The empty-document total is the CLI's own overhead and it moves between CLI
versions (401 on 2026-10-01, 418 two days later), so it is re-measured on every
run — one call, a fraction of a cent — and never read back from the cache: a
count taken against a stale overhead would shift exactly the rows a rerun
recounts while the unchanged rows kept their old numbers. The cached counts
themselves are net of the overhead measured alongside them, so they survive a
CLI upgrade; they do not survive a model change, which can change the
tokenizer, so the cache records the model it was counted with and is discarded
when MODEL differs.
"""
import hashlib, json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

MODEL = "claude-opus-5-5"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
CACHE = os.path.join(HERE, "tokens.json")


def wrap(text):
    return f"<doc>\n{text}\n</doc>\nReply with the single word OK."


def total_input(text):
    r = subprocess.run(
        ["claude", "-p", "--model", MODEL, "--tools", "", "--system-prompt", "x",
         "--no-session-persistence", "--strict-mcp-config", "--disable-slash-commands",
         "--setting-sources", "", "--output-format", "json"],
        input=wrap(text), capture_output=True, text=True, timeout=600, cwd="/tmp")
    j = json.loads(r.stdout)
    if j.get("is_error"):
        raise RuntimeError(j.get("result"))
    u = j["usage"]
    n = u["input_tokens"] + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0)
    return n, j.get("total_cost_usd", 0.0)


def main():
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    if cache and cache.get("_model") != MODEL:
        print(f"cache was counted with {cache.get('_model') or 'an unrecorded model'}, "
              f"not {MODEL}: discarding it", file=sys.stderr)
        cache = {}
    base, cost = total_input("")
    if "_baseline" in cache and cache["_baseline"] != base:
        print(f"wrapper overhead moved: {cache['_baseline']} -> {base} tokens "
              "(cached counts are net of it and stay valid)", file=sys.stderr)
    cache["_model"], cache["_baseline"] = MODEL, base
    cache["_cost"] = cache.get("_cost", 0) + cost
    files = sorted(f for f in os.listdir(OUT) if f.endswith(".txt"))
    by_hash, todo = {}, {}
    for f in files:
        data = open(os.path.join(OUT, f), encoding="utf-8", errors="replace").read()
        h = hashlib.sha256(data.encode()).hexdigest()
        by_hash[f] = h
        if data.strip() == "":
            cache.setdefault(h, 0)
        elif h not in cache:
            todo[h] = data
    print(f"{len(files)} files, {len(todo)} distinct contents to count, "
          f"wrapper overhead={base} tokens, model={MODEL}", file=sys.stderr)
    json.dump(cache, open(CACHE, "w"))

    def work(item):
        h, data = item
        n, cost = total_input(data)
        return h, n - base, cost

    with ThreadPoolExecutor(max_workers=6) as ex:
        for h, n, cost in ex.map(work, todo.items()):
            cache[h] = n
            cache["_cost"] = cache.get("_cost", 0) + cost
            json.dump(cache, open(CACHE, "w"))
    with open(os.path.join(HERE, "tokens.tsv"), "w") as fh:
        fh.write("id\tbytes\ttokens\n")
        for f in files:
            fh.write(f"{f[:-4]}\t{os.path.getsize(os.path.join(OUT, f))}\t{cache[by_hash[f]]}\n")
    print(f"done; cumulative counting cost ${cache['_cost']:.2f}", file=sys.stderr)


if __name__ == "__main__":
    main()
