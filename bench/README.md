# Token benchmark

Measures what `gh-comments` and its `pr-comments` / `issue-comments` skills
cost in an agent's context, against the raw `gh`, REST and GraphQL ways of
reading the same discussion. Costs are in **exact Claude tokens**, counted by
the model, not bytes ÷ 4, which undercounts this kind of text by about 1.7×.
The results and what they mean are in [BENCHMARKS.md](../BENCHMARKS.md).

It is not part of `make check`: every run reads live GitHub data (it needs
`gh` logged in), and counting tokens calls `claude -p`, which costs money.
`make lint` only checks that the scripts parse.

## Running

```bash
cd bench
zsh run-cases.zsh         # every (target, approach) pair → out/, cases.tsv
zsh run-targets.zsh       # land-one-comment flows, sliced from those dumps → targets.tsv
zsh run-fixed.zsh         # the skills' descriptions, SKILL.md and references → out/FIX.*
python3 count_tokens.py   # exact tokens for every out/*.txt via `claude -p` → tokens.tsv
python3 analyze.py        # tables and charts → tables.md
```

Needs `zsh`, `jq`, `gh`, `python3` and the `claude` CLI.

- `run-cases.zsh` runs this checkout's own `gh-comments`, so a run measures
  whatever is checked out: `git checkout v1.0.0` first to measure a release.
  `GH_COMMENTS=/path/to/gh-comments` measures another executable. PR targets
  run with `--pr`, issues with `--issue`.
- `run-fixed.zsh` reads this checkout's `skills/`, which is exactly what the
  Claude Code plugin installs. `SKILLS_DIR` measures another copy, such as
  one an installer stamped with a banner; the banner then gets a row of its
  own.
- `count_tokens.py` sends each distinct output once through
  `claude -p --model claude-opus-5-5` with no tools, and reports the input
  total minus the same call with an empty document. That empty-document
  overhead belongs to the CLI and moves between CLI versions, so it is
  measured again on every run. Per-output counts are cached by content hash
  in `tokens.json`, so a rerun only pays for outputs that changed. The cache
  records the model and is discarded if `MODEL` changes. A full fresh count
  costs about $4.
- A capture that fails, or a slice whose header matches nothing, leaves an
  empty file that would count as 0 tokens and read as a saving. The `exit`
  column records it, and `analyze.py` refuses to run while any row's exit is
  non-zero.
- Outputs are captured off a TTY, which is how an agent's Bash tool receives
  them. `gh` formats differently on a terminal.
- Each case runs once, so treat the `ms` column as indicative only.

## Targets

[`targets.json`](targets.json) lists the PRs and issues, each under a fixed
role label that the tables use. The roles are shapes of discussion, chosen
so each task has a case where the naive reads fall short and a case where
they do not:

| Label | Shape |
|---|---|
| `E1`, `E2` | PR with no comments and no reviews; a short and a long description |
| `R1`, `R2` | PR whose review threads are all resolved, with top-level comments |
| `O1` | PR with many review threads, some still open, including bot reviews |
| `I1` | closed issue with a few comments |
| `I2` | closed issue with no comments |
| `I3` | issue closed by a PR's closing keyword, referenced by other PRs too |
| `I4` | issue closed by hand after the PRs that fixed it merged |

`slices` names the four single items Task 4 lands: a top-level comment and
an inline thread on `R1`, an open thread on `O1`, and the last comment on
`I1`. Every target is public and closed or merged, so anyone can rerun the
benchmark and the discussions move as little as possible.

## Keeping a run

The scripts write `cases.tsv`, `targets.tsv` and `tokens.tsv` here, and
`analyze.py` writes `tables.md` beside them. All of these are git-ignored at
this level, as are `out/`, `tokens.json` and a working `grades.json`. To keep
a run, file it with the targets it used and its own grades:

```bash
d=runs/$(date +%F)
mkdir $d && mv cases.tsv targets.tsv tokens.tsv $d/ && cp targets.json $d/
cp runs/<previous>/grades.json $d/   # then revise every judgment
python3 analyze.py $d --baseline runs/<previous>
```

`analyze.py [<run-dir>] [--baseline <run-dir>]` reads the TSVs, `targets.json`
and `grades.json` from `<run-dir>` (default: here) and writes `tables.md`
there. `--baseline` adds a per-output token delta table and lists every
grade that changed. A filed run's `tables.md` is tracked.

## What drifts, and what is a judgment

The targets are live. Comments get added, threads resolved, and bots
minimize their own posts, so a change in a raw `gh` or REST row between runs
is GitHub moving, not the script. The rows a change to `gh-comments` touches
are its own outputs (`s_*`, `*_slice`) and the fixed costs (`FIX.*`).

The ✓ ◐ ✗ grades and the prose notes are assigned by hand for each run.
Whether an output *answers* the task is a judgment no token count can make,
so the grades live with the run in its `grades.json`, not in `analyze.py`.
Each table's rows are keyed there (`task1` … `task7`, the charts' suffixes,
the ladder's notes); a grade is one string for a whole row or an object per
target. After a behavior change, revise the new run's file and leave the
previous run's alone.
