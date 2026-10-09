#!/usr/bin/env python3
"""Turn cases.tsv / targets.tsv / tokens.tsv into the report's tables and charts.

    python3 analyze.py [<run-dir>] [--baseline <run-dir>]

Reads the three TSVs and grades.json from <run-dir> (default: this directory,
where the run scripts write them) and writes tables.md beside them. With
--baseline, a final section lists every output's token count against the same
output in the baseline run, and every grade that changed. Grades (✓ ◐ ✗) and
the prose notes are hand-assigned per run — they are judgments about whether
an output answers the task, which no number can make — so they live with the
run, in its grades.json, keyed by the table rows below; a run without one
renders blank grades and says so at the top. Copy the previous run's file and
revisit it after a behavior change.
"""
import csv, json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RUN, BASE = HERE, None
argv = sys.argv[1:]
while argv:
    a = argv.pop(0)
    if a == "--baseline":
        BASE = os.path.abspath(argv.pop(0))
    else:
        RUN = os.path.abspath(a)


def load(name, where=None):
    with open(os.path.join(where or RUN, name)) as f:
        return list(csv.DictReader(f, delimiter="\t"))


def load_grades(where):
    path = os.path.join(where, "grades.json")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)


J = load_grades(RUN)
if J is None:
    print(f"analyze: no grades.json in {RUN}; grades and notes are blank "
          f"(copy the previous run's grades.json there and revise it)", file=sys.stderr)
    J = {}


def G(section, row):
    """A row's grade: one string, or a {target: grade} object."""
    return J.get(section, {}).get("grades", {}).get(row, "")


def N(section):
    return J.get(section, {}).get("note", "")


def CH(section, row):
    """The suffix a chart row carries, e.g. '◐ 6 of 7'."""
    return J.get(section, {}).get("chart", {}).get(row, "")


def LN(key):
    return J.get("ladder", {}).get("notes", {}).get(key, "")


def flat_grades(j):
    """section/row[/target] → grade, for comparing two runs' judgments."""
    cells = {}
    for section, body in j.items():
        if not isinstance(body, dict):
            continue
        for row, g in body.get("grades", {}).items():
            if isinstance(g, dict):
                for T, v in g.items():
                    cells[f"{section}/{row}/{T}"] = v
            else:
                cells[f"{section}/{row}"] = g
    return cells


# The concrete PR or issue behind each role label (E1, R1, O1, I1, ...) is in
# targets.json; a run keeps a copy beside its TSVs, so a filed run renders with
# the targets it was captured against even after targets.json moves on.
TARGETS_FILE = os.path.join(RUN, "targets.json")
if not os.path.exists(TARGETS_FILE):
    TARGETS_FILE = os.path.join(HERE, "targets.json")
with open(TARGETS_FILE) as f:
    TARGETS = json.load(f)
NAME = {t["label"]: t["name"] for t in TARGETS["prs"] + TARGETS["issues"]}

TOK = {r["id"]: int(r["tokens"]) for r in load("tokens.tsv")}
BYT = {r["id"]: int(r["bytes"]) for r in load("tokens.tsv")}
RUNS = load("cases.tsv") + load("targets.tsv")
MS = {r["id"]: int(r["ms"]) for r in RUNS}
# A capture that failed, or a slice that matched nothing, is an empty file that
# count_tokens.py counts as 0 tokens — the same as a legitimately empty answer.
# The exit column is the only thing that tells them apart, so refuse to build
# tables on top of one rather than print a saving that is a missing number.
FAILED = sorted(r["id"] for r in RUNS if r["exit"] != "0")
if FAILED:
    sys.exit(f"analyze: {len(FAILED)} capture(s) exited non-zero, fix or rerun them first: "
             + ", ".join(FAILED))
OK, PART, BAD, NA = "✓", "◐", "✗", "–"
SKILL_PR, SKILL_IS = TOK["FIX.pr_skillmd"], TOK["FIX.issue_skillmd"]


def tok(ids):
    return sum(TOK[i] for i in ids)


def fmt(n):
    return f"{n:,}"


def bar(v, vmax, width=30, log=False):
    if v <= 0:
        return "·" + " " * (width - 1)
    if log:
        frac = max(math.log10(v) / math.log10(vmax), 0.02)
    else:
        frac = v / vmax
    n = max(1, round(frac * width))
    return "▓" * n + "░" * (width - n)


out = []
P = out.append
if not J:
    P("_No grades.json in this run: grades and notes are blank. Copy the previous "
      "run's beside the TSVs and revise it._\n")


def matrix(title, targets, rows, note=""):
    """rows: (label, fn(T)->[ids] or None, {T: grade} or grade)."""
    P(f"### {title}\n")
    if note:
        P(note + "\n")
    P("| Approach | " + " | ".join(targets) + " |")
    P("|---|" + "--:|" * len(targets))
    for label, fn, grades in rows:
        cells = []
        for T in targets:
            ids = fn(T)
            if ids is None:
                cells.append("")
                continue
            g = grades.get(T, "") if isinstance(grades, dict) else grades
            cells.append(f"{fmt(tok(ids))} {g}")
        P(f"| {label} | " + " | ".join(cells) + " |")
    P("")


def chart(title, rows, log=False, unit="tok"):
    """rows: (label, value, suffix)"""
    P("```")
    P(title)
    vmax = max(v for _, v, _ in rows) or 1
    w = max(len(l) for l, _, _ in rows)
    for label, v, suf in rows:
        P(f"  {label:<{w}}  {bar(v, vmax, 30, log)} {fmt(v):>7} {suf}")
    if log:
        P(f"  {'':<{w}}  (log scale)")
    P("```\n")


# ── Targets ──────────────────────────────────────────────────────────────────
P("### Targets\n")
P("| Label | Target | Shape |")
P("|---|---|---|")
for t in TARGETS["prs"] + TARGETS["issues"]:
    P(f"| {t['label']} | [{t['name']}](https://github.com/{t['repo']}/{'pull' if t in TARGETS['prs'] else 'issues'}/{t['number']}) | {t['shape']} |")
P("")

# ── Fixed costs ──────────────────────────────────────────────────────────────
P("### Fixed costs\n")
P("| Item | Paid | Bytes | Tokens |")
P("|---|---|--:|--:|")
for k, label, when in [("pr_desc", "`pr-comments` description", "every session, used or not"),
                       ("issue_desc", "`issue-comments` description", "every session, used or not"),
                       ("pr_skillmd", "`pr-comments` SKILL.md", "each invocation"),
                       ("issue_skillmd", "`issue-comments` SKILL.md", "each invocation"),
                       # The reference files are loaded only when an output marker needs
                       # interpreting; they exist from the skills-slim change on, so a run
                       # captured before it has no row for them.
                       ("pr_ref", "`pr-comments` references/output.md", "when a marker needs interpreting"),
                       ("issue_ref", "`issue-comments` references/output.md", "when a marker needs interpreting")]:
    if "FIX." + k in TOK:
        P(f"| {label} | {when} | {fmt(BYT['FIX.' + k])} | {fmt(TOK['FIX.' + k])} |")
P("")

# ── PR: read everything ──────────────────────────────────────────────────────
PRS = ["E1", "E2", "R1", "R2", "O1"]
has_thr = {"R1", "R2", "O1"}
matrix("Task 1 — read a PR's whole discussion", PRS, [
    ("`gh pr view --comments`", lambda T: [f"{T}.gh_view_c"], G("task1", "gh_view_c")),
    ("`gh pr view` + `gh pr view --comments`", lambda T: [f"{T}.gh_view", f"{T}.gh_view_c"],
        G("task1", "gh_view+gh_view_c")),
    ("… + REST `pulls/N/comments`", lambda T: [f"{T}.gh_view", f"{T}.gh_view_c", f"{T}.rest_rc"],
        G("task1", "gh_view+gh_view_c+rest_rc")),
    ("REST comments + reviews + inline (raw JSON)", lambda T: [f"{T}.rest_ic", f"{T}.rest_rv", f"{T}.rest_rc"],
        G("task1", "rest_trio")),
    ("**`gh-comments`**", lambda T: [f"{T}.s_full"], G("task1", "s_full")),
    ("**`gh-comments --toc`** (orientation only)", lambda T: [f"{T}.s_toc"], G("task1", "s_toc")),
], note=N("task1"))

C = "O1"
chart(f"{NAME['O1']} — read everything", [
    ("gh pr view --comments", tok([f"{C}.gh_view_c"]), CH("task1", "gh_view_c")),
    ("+ gh pr view", tok([f"{C}.gh_view", f"{C}.gh_view_c"]), CH("task1", "gh_view+gh_view_c")),
    ("+ REST pulls/N/comments", tok([f"{C}.gh_view", f"{C}.gh_view_c", f"{C}.rest_rc"]), CH("task1", "gh_view+gh_view_c+rest_rc")),
    ("REST trio, raw JSON", tok([f"{C}.rest_ic", f"{C}.rest_rv", f"{C}.rest_rc"]), CH("task1", "rest_trio")),
    ("gh-comments", tok([f"{C}.s_full"]), CH("task1", "s_full")),
    ("gh-comments --toc", tok([f"{C}.s_toc"]), CH("task1", "s_toc")),
])

# ── PR: which threads are open ───────────────────────────────────────────────
matrix("Task 2 — which review threads are still open, and where", ["R1", "R2", "O1"], [
    ("`gh pr view --comments`", lambda T: [f"{T}.gh_view_c"], G("task2", "gh_view_c")),
    ("REST `pulls/N/comments`", lambda T: [f"{T}.rest_rc"], G("task2", "rest_rc")),
    ("hand-written GraphQL (metadata)", lambda T: [f"{T}.gql_meta"], G("task2", "gql_meta")),
    ("**`gh-comments --toc --unresolved`**", lambda T: [f"{T}.s_toc_unres"], G("task2", "s_toc_unres")),
    ("**`gh-comments --toc`**", lambda T: [f"{T}.s_toc"], G("task2", "s_toc")),
], note=N("task2"))

chart(f"{NAME['O1']} — which threads are open", [
    ("REST pulls/N/comments", tok([f"{C}.rest_rc"]), CH("task2", "rest_rc")),
    ("gh pr view --comments", tok([f"{C}.gh_view_c"]), CH("task2", "gh_view_c")),
    ("gh-comments --toc", tok([f"{C}.s_toc"]), CH("task2", "s_toc")),
    ("hand GraphQL metadata", tok([f"{C}.gql_meta"]), CH("task2", "gql_meta")),
    ("gh-comments --toc --unresolved", tok([f"{C}.s_toc_unres"]), CH("task2", "s_toc_unres")),
], log=True)

matrix("Task 3 — what the open threads say", ["O1"], [
    ("`gh pr view --comments` + REST inline", lambda T: [f"{T}.gh_view_c", f"{T}.rest_rc"], G("task3", "gh_view_c+rest_rc")),
    ("hand-written GraphQL, open threads with bodies", lambda T: [f"{T}.gql_open"], G("task3", "gql_open")),
    ("**`gh-comments --unresolved`**", lambda T: [f"{T}.s_unres"], G("task3", "s_unres")),
], note=N("task3"))

# ── Targeted retrieval ───────────────────────────────────────────────────────
TG = [("TA", "R1", f"{NAME['R1']} top-level comment", G("task4", "TA"), SKILL_PR),
      ("TB", "R1", f"{NAME['R1']} inline thread", G("task4", "TB"), SKILL_PR),
      ("TC", "O1", f"{NAME['O1']} open thread", G("task4", "TC"), SKILL_PR),
      ("TD", "I1", f"{NAME['I1']} last comment", G("task4", "TD"), SKILL_IS)]
P("### Task 4 — land one specific comment in context\n")
P("The skill's documented flow is TOC first, dump to a file, then slice the one item out. "
  "The expert flow is the same shape by hand: list with `--jq`, then fetch the one body. "
  "Both arms land the same comment text; the slice also carries the item's header line and the renderer's two-space indent, "
  "which is the few dozen bytes between the payload column and the expert fetch. "
  "The `+ SKILL.md` column adds the cost of loading the skill, paid once per invocation.\n")
P("| Target | `gh … view --comments` | naive complete | `gh-comments` full | **TOC + slice** | + SKILL.md | expert list → fetch | payload |")
P("|---|--:|--:|--:|--:|--:|--:|--:|")
tg_rows = []
for key, T, label, ghg, sk in TG:
    lazy_gh = tok([f"{T}.gh_view_c"])
    naive = tok([f"{T}.gh_view_c", f"{T}.rest_rc"]) if T != "I1" else lazy_gh
    full = tok([f"{T}.s_full"])
    flow = tok([f"{T}.s_toc", f"{key}.skill_slice"])
    exp = tok([f"{key}.expert_list", f"{key}.expert_fetch"])
    payload = tok([f"{key}.skill_slice"])
    tg_rows.append((label, lazy_gh, ghg, naive, full, flow, flow + sk, exp, payload))
    P(f"| {label} | {fmt(lazy_gh)} {ghg} | {fmt(naive)} | {fmt(full)} | **{fmt(flow)}** | {fmt(flow + sk)} | {fmt(exp)} | {fmt(payload)} |")
P("")
P("```")
P("Task 4 — tokens to land one comment (each ▓ ≈ 1k tokens)")
for label, lazy_gh, ghg, naive, full, flow, flowsk, exp, payload in tg_rows:
    P(f"  {label}")
    for name, v in [("naive complete", naive), ("gh-comments full", full), ("TOC + slice + SKILL.md", flowsk),
                    ("TOC + slice", flow), ("expert list → fetch", exp), ("the comment itself", payload)]:
        n = max(1, round(v / 1000)) if v else 0
        b = "▓" * n if n <= 26 else "▓" * 24 + "»»"
        P(f"    {name:<24} {b:<26} {fmt(v):>6}")
P("```\n")

# ── Latest review ────────────────────────────────────────────────────────────
matrix("Task 5 — address the most recent review", ["R1", "R2", "O1", "E1", "E2"], [
    ("`gh pr view --comments`", lambda T: [f"{T}.gh_view_c"], G("task5", "gh_view_c")),
    ("`gh-comments` full", lambda T: [f"{T}.s_full"], G("task5", "s_full")),
    ("**`gh-comments --since-last-review`**", lambda T: [f"{T}.s_slr"], G("task5", "s_slr")),
    ("**`gh-comments --latest`**", lambda T: [f"{T}.s_latest"], G("task5", "s_latest")),
], note=N("task5"))

# ── Issues ───────────────────────────────────────────────────────────────────
ISS = ["I1", "I2", "I3", "I4"]
matrix("Task 6 — read an issue in full", ISS, [
    ("`gh issue view` + `gh issue view --comments`", lambda T: [f"{T}.gh_view", f"{T}.gh_view_c"], G("task6", "gh_view+gh_view_c")),
    ("REST issue + comments (raw JSON)", lambda T: [f"{T}.rest_issue", f"{T}.rest_ic"], G("task6", "rest_issue+rest_ic")),
    ("REST issue + timeline (raw JSON)", lambda T: [f"{T}.rest_issue", f"{T}.rest_tl"], G("task6", "rest_issue+rest_tl")),
    ("**`gh-comments`**", lambda T: [f"{T}.s_full"], G("task6", "s_full")),
    ("**`gh-comments --toc`** (orientation only)", lambda T: [f"{T}.s_toc"], G("task6", "s_toc")),
], note=N("task6"))

matrix("Task 7 — why was the issue closed, and by what", ["I1", "I3", "I4"], [
    ("`gh issue view`", lambda T: [f"{T}.gh_view"], G("task7", "gh_view")),
    ("`gh issue view --json state,stateReason,closedByPullRequestsReferences`", lambda T: [f"{T}.gh_json_close"],
        G("task7", "gh_json_close")),
    ("REST timeline (raw JSON)", lambda T: [f"{T}.rest_tl"], G("task7", "rest_tl")),
    ("**`gh-comments --toc`**", lambda T: [f"{T}.s_toc"], G("task7", "s_toc")),
], note=N("task7"))

# ── Ratio ladder ─────────────────────────────────────────────────────────────
P("### The multiplier, revisited\n")
P("How many times more tokens the alternative costs than the script's narrowest correct form for that task "
  "(>1× = script cheaper). SKILL.md is excluded here and treated in the break-even section.\n")
def ratio(alt, script):
    """alt ÷ script, or None when the script's output was empty (0 tokens): a
    ratio against nothing is not a multiplier, and log10 of it is not a bar."""
    a, s = tok(alt), tok(script)
    return a / s if s else None


# The third field names the row in grades.json's ladder notes.
ladder = [
    (f"open threads, {NAME['O1']}: REST inline vs --toc --unresolved", ratio([f"{C}.rest_rc"], [f"{C}.s_toc_unres"]), LN("open-threads-o1-rest")),
    (f"open threads, {NAME['R1']}: REST inline vs --toc --unresolved", ratio(["R1.rest_rc"], ["R1.s_toc_unres"]), LN("open-threads-r1-rest")),
    (f"read all, {NAME['O1']}: REST trio vs full", ratio([f"{C}.rest_ic", f"{C}.rest_rv", f"{C}.rest_rc"], [f"{C}.s_full"]), LN("read-all-o1-rest")),
    (f"why closed, {NAME['I4']}: REST timeline vs --toc", ratio(["I4.rest_tl"], ["I4.s_toc"]), LN("why-closed-i4-rest")),
    (f"one inline thread, {NAME['R1']}: naive vs TOC+slice", ratio(["R1.gh_view_c", "R1.rest_rc"], ["R1.s_toc", "TB.skill_slice"]), LN("one-thread-r1-naive")),
    (f"read all, {NAME['R1']}: gh view + REST inline vs full", ratio(["R1.gh_view", "R1.gh_view_c", "R1.rest_rc"], ["R1.s_full"]), LN("read-all-r1-naive")),
    (f"one comment, {NAME['R1']}: gh pr view --comments vs TOC+slice", ratio(["R1.gh_view_c"], ["R1.s_toc", "TA.skill_slice"]), LN("one-comment-r1-ghview")),
    (f"open threads, {NAME['O1']}: hand GraphQL vs --toc --unresolved", ratio([f"{C}.gql_meta"], [f"{C}.s_toc_unres"]), LN("open-threads-o1-gql")),
    (f"read all, {NAME['E2']}: gh pr view vs full", ratio(["E2.gh_view"], ["E2.s_full"]), LN("read-all-e2-ghview")),
    (f"one comment, {NAME['I1']}: expert vs TOC+slice", ratio(["TD.expert_list", "TD.expert_fetch"], ["I1.s_toc", "TD.skill_slice"]), LN("one-comment-i1-expert")),
    (f"open bodies, {NAME['O1']}: hand GraphQL vs --unresolved", ratio([f"{C}.gql_open"], [f"{C}.s_unres"]), LN("open-bodies-o1-gql")),
    (f"why closed, {NAME['I4']}: --json closedBy vs --toc", ratio(["I4.gh_json_close"], ["I4.s_toc"]), LN("why-closed-i4-json")),
]
ladder.sort(key=lambda r: -(r[1] if r[1] is not None else -1))
P("```")
w = max(len(l) for l, _, _ in ladder)
lo, hi = math.log10(0.1), math.log10(200)
def pos(x):
    # The axis is fixed at 0.1–200× so runs compare visually; a ratio outside it
    # is pinned to the end cell (and marked with » below) rather than indexing
    # past the 41-cell line, which a 230× ratio would.
    return min(max(round((math.log10(x) - lo) / (hi - lo) * 40), 0), 40)
one = pos(1)
for label, r, note in ladder:
    if r is None:
        P(f"{label:<{w}} {'':41}    n/a   script output empty")
        continue
    p = pos(r)
    line = [" "] * 41
    line[one] = "│"
    if p >= one:
        for k in range(one + 1, p + 1):
            line[k] = "▓"
    else:
        for k in range(p, one):
            line[k] = "░"
    if r > 200 or r < 0.1:
        line[p] = "»"
    P(f"{label:<{w}} {''.join(line)} {r:6.1f}×  {note}")
axis = [" "] * 41
for v, s in [(0.1, "0.1"), (1, "1"), (10, "10"), (100, "100")]:
    k = pos(v)
    for j, ch in enumerate(s):
        if k + j < 41:
            axis[k + j] = ch
P(f"{'':<{w}} {''.join(axis)}")
P(f"{'':<{w}} ░ alternative cheaper    ▓ script cheaper (log scale)")
P("```\n")

# ── Break-even ───────────────────────────────────────────────────────────────
desc = TOK["FIX.pr_desc"] + TOK["FIX.issue_desc"]
P("### Break-even: does loading the skill pay for itself?\n")
P(f"The two descriptions cost **{desc} tokens in every session**, whether or not either skill is used. "
  f"Invoking a skill then adds its SKILL.md ({fmt(SKILL_PR)} for `pr-comments`, {fmt(SKILL_IS)} for `issue-comments`). "
  "Against the realistic naive path for the same task:\n")
P("| Task | naive tokens | skill flow + SKILL.md | net per invocation |")
P("|---|--:|--:|--:|")
be = [
    (f"{NAME['O1']} read all (naive: gh view + REST inline)", tok([f"{C}.gh_view", f"{C}.gh_view_c", f"{C}.rest_rc"]), tok([f"{C}.s_toc", f"{C}.s_full"]) + SKILL_PR),
    (f"{NAME['O1']} which threads open (naive: REST inline)", tok([f"{C}.rest_rc"]), tok([f"{C}.s_toc_unres"]) + SKILL_PR),
    (f"{NAME['R1']} read all (naive: gh view + REST inline)", tok(["R1.gh_view", "R1.gh_view_c", "R1.rest_rc"]), tok(["R1.s_toc", "R1.s_full"]) + SKILL_PR),
    (f"{NAME['R1']} one inline thread (naive: gh view --comments + REST inline)", tok(["R1.gh_view_c", "R1.rest_rc"]), tok(["R1.s_toc", "TB.skill_slice"]) + SKILL_PR),
    (f"{NAME['R1']} one top-level comment (naive: gh pr view --comments)", tok(["R1.gh_view_c"]), tok(["R1.s_toc", "TA.skill_slice"]) + SKILL_PR),
    (f"{NAME['E2']} read all (naive: gh pr view)", tok(["E2.gh_view"]), tok(["E2.s_toc", "E2.s_full"]) + SKILL_PR),
    (f"{NAME['I4']} read all (naive: gh issue view ×2)", tok(["I4.gh_view", "I4.gh_view_c"]), tok(["I4.s_toc", "I4.s_full"]) + SKILL_IS),
    (f"{NAME['I1']} one comment (naive: gh issue view --comments)", tok(["I1.gh_view_c"]), tok(["I1.s_toc", "TD.skill_slice"]) + SKILL_IS),
]
for label, naive, flow in be:
    d = naive - flow
    P(f"| {label} | {fmt(naive)} | {fmt(flow)} | {'saves' if d > 0 else 'costs'} {fmt(abs(d))} |")
P("")
P("```")
P("net tokens per invocation (skill flow incl. SKILL.md vs naive)   ▓ saved  ░ spent")
m = max(abs(n - f) for _, n, f in be)
for label, naive, flow in be:
    d = naive - flow
    n = max(1, round(abs(d) / m * 28))
    left = ("░" * n).rjust(28) if d < 0 else " " * 28
    right = "▓" * n if d > 0 else ""
    P(f"  {left}│{right:<28} {'+' if d > 0 else '−'}{fmt(abs(d)):>6}  {label.split(' (')[0]}")
P("```\n")

# ── Heatmap ──────────────────────────────────────────────────────────────────
P("### Heatmap: tokens by target × approach\n")
cols = [("gh_view", "ghview"), ("gh_view_c", "ghv -c"), ("rest_ic", "rst ic"), ("rest_rv", "rst rv"),
        ("rest_rc", "rst rc"), ("gql_meta", "gql md"), ("s_full", "s full"), ("s_toc", "s toc"),
        ("s_unres", "s unr"), ("s_toc_unres", "s tocU"), ("s_slr", "s slr")]
def shade(v):
    if v == 0: return "·"
    for lim, ch in [(250, "░"), (1000, "▒"), (4000, "▓"), (16000, "▓▓"), (10**9, "▓▓▓")]:
        if v < lim:
            return ch
P("```")
P("        " + "".join(f"{c:^8}" for _, c in cols))
for T in ["E1", "E2", "R1", "R2", "O1"]:
    P(f"{T:<8}" + "".join(f"{shade(TOK.get(f'{T}.{a}', 0)):^8}" for a, _ in cols))
P("")
P("· 0   ░ <250   ▒ <1k   ▓ <4k   ▓▓ <16k   ▓▓▓ ≥16k  tokens")
P("ghview/ghv -c: gh pr view [--comments]   rst ic/rv/rc: REST issue comments/reviews/inline")
P("gql md: GraphQL thread metadata   s *: gh-comments full/--toc/--unresolved/--toc --unresolved/--since-last-review")
P("```\n")

# ── Bytes per token ──────────────────────────────────────────────────────────
P("### Bytes per token, by content type\n")
groups = [
    ("raw JSON (gh api)", lambda i: any(k in i for k in (".rest_", ".gql_", ".gh_json", "expert_list"))),
    ("gh … view text", lambda i: ".gh_view" in i),
    ("gh-comments output", lambda i: ".s_" in i or "slice" in i),
    ("SKILL.md + descriptions", lambda i: i.startswith("FIX")),
]
P("| Content | Bytes | Tokens | Bytes/token | bytes ÷ 4 undercounts by |")
P("|---|--:|--:|--:|--:|")
gr = []
for name, pred in groups:
    ids = [i for i in TOK if pred(i) and TOK[i] > 0]
    b, t = sum(BYT[i] for i in ids), sum(TOK[i] for i in ids)
    gr.append((name, b / t))
    P(f"| {name} | {fmt(b)} | {fmt(t)} | {b/t:.2f} | {t/(b/4):.1f}× |")
P("")
P("```")
for name, r in gr + [("the bytes ÷ 4 rule", 4.0)]:
    P(f"  {name:<24} {bar(r, 4, 32)} {r:.2f} bytes/token")
P("```\n")

# ── Latency ──────────────────────────────────────────────────────────────────
P("### Wall-clock (one run each)\n")
lat = [("gh pr view --comments", f"{C}.gh_view_c"), ("REST pulls/N/comments", f"{C}.rest_rc"),
       ("GraphQL thread metadata", f"{C}.gql_meta"), ("gh-comments (full)", f"{C}.s_full"),
       ("gh-comments --toc --unresolved", f"{C}.s_toc_unres"), (f"gh issue view ({NAME['I4']})", "I4.gh_view"),
       (f"gh-comments ({NAME['I4']})", "I4.s_full")]
P("```")
lm = max(MS[i] for _, i in lat)
w = max(len(n) for n, _ in lat)
for name, i in lat:
    P(f"  {name:<{w}}  {bar(MS[i], lm, 30)} {fmt(MS[i]):>6} ms")
P("```\n")

# ── Delta vs baseline ────────────────────────────────────────────────────────
# Token counts only. The targets are live GitHub data, so a raw `gh` or REST
# row moving is GitHub moving, not the script; the rows the fixes touch are the
# script's own outputs (`s_*`, `*_slice`) and the fixed costs (`FIX.*`).
if BASE:
    BTOK = {r["id"]: int(r["tokens"]) for r in load("tokens.tsv", BASE)}
    P("### Delta vs baseline\n")
    P(f"Tokens per output, this run against `{os.path.relpath(BASE, RUN)}`, largest change first. "
      "Rows named `s_*`, `*_slice` and `FIX.*` are the script and skill outputs the fixes touch; "
      "the rest are raw `gh`/REST captures of live targets and move when GitHub does.\n")
    P("| Output | baseline | now | delta |")
    P("|---|--:|--:|--:|")
    both = sorted(((i, BTOK[i], TOK[i]) for i in TOK if i in BTOK), key=lambda r: -abs(r[2] - r[1]))
    for i, b, n in both:
        d = n - b
        pct = f" ({d / b * 100:+.0f}%)" if b else ""
        P(f"| `{i}` | {fmt(b)} | {fmt(n)} | {'+' if d > 0 else ''}{fmt(d)}{pct} |")
    P("")
    gone = sorted(set(BTOK) - set(TOK))
    new = sorted(set(TOK) - set(BTOK))
    if gone:
        P("In the baseline only: " + ", ".join(f"`{i}`" for i in gone) + "\n")
    if new:
        P("New in this run: " + ", ".join(f"`{i}`" for i in new) + "\n")
    # Grades are judgments, so a changed one is the headline of a rerun: it
    # says a fix landed (◐ → ✓) or something regressed, which no token delta can.
    BJ = load_grades(BASE)
    if BJ is None:
        P("_The baseline has no grades.json, so grade changes cannot be listed._\n")
    else:
        bg, ng = flat_grades(BJ), flat_grades(J)
        changed = [(k, bg[k], ng[k]) for k in sorted(bg) if k in ng and bg[k] != ng[k]]
        if changed:
            P("### Grade changes vs baseline\n")
            P("| Cell | baseline | now |")
            P("|---|:-:|:-:|")
            for k, b, n in changed:
                P(f"| `{k}` | {b} | {n} |")
            P("")
        else:
            P("No grade changed against the baseline.\n")
        gone_g = sorted(set(bg) - set(ng))
        new_g = sorted(set(ng) - set(bg))
        if gone_g:
            P("Graded in the baseline only: " + ", ".join(f"`{k}`" for k in gone_g) + "\n")
        if new_g:
            P("Graded in this run only: " + ", ".join(f"`{k}`" for k in new_g) + "\n")

open(os.path.join(RUN, "tables.md"), "w").write("\n".join(out))
print(f"{len(out)} lines")
