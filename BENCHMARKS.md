# Benchmarks

How many tokens it costs an agent to read a GitHub discussion with
`gh-comments`, compared with the usual ways of reading it: `gh pr view`,
`gh issue view`, the REST API and a hand-written GraphQL query. Every number
is an exact Claude token count of what the command printed, so it is what an
agent actually pays to read the output.

Run 2026-11-03 against `gh-comments` at the commit that trimmed both
SKILL.md files (#7), which carries every change since v1.0.0: the closer and
`--closure` (#5), hidden reviews (#9), and `--only`/`--item` with the thread
opener on each thread's `--toc` line (#6). The targets are nine public PRs
and issues in [cli/cli](https://github.com/cli/cli), and tokens were counted
with `claude-opus-5-5`. The skill files were re-measured after the review
fixes that followed changed them, so their fixed costs are the branch's
final ones; every other output is as captured. The harness, the targets and the raw run are in
[`bench/`](bench/README.md); the full generated report, with a heatmap,
timings and a per-output delta against the 2026-10-22 run, is
[`bench/runs/2026-11-03/tables.md`](bench/runs/2026-11-03/tables.md).

## Summary

- **Open review threads.** Asking which threads are still open on
  cli/cli#14104 costs 614 tokens with `--toc --unresolved`. REST cannot
  answer at any cost, because review comments carry no resolved state, and
  `gh pr view --comments` shows no inline threads at all.
- **Reading a whole PR.** `gh-comments` renders all 17 threads of
  cli/cli#14104, each marked open or resolved, in 8,502 tokens. Adding the
  REST review comments to `gh pr view` costs 68,324 tokens, the raw REST reads
  79,297, and both still lack the resolved state.
- **Why an issue closed.** `--closure` prints the header, the `closed`
  line with what closed the issue, and the PR cross-references, in 58 to
  405 tokens. Only GraphQL's `closer` field records the closer, and
  `gh-comments` now reads it: on cli/cli#13898 the closed line names
  #13927, on cli/cli#14411 it says `no closer recorded` between the fix and
  its revert. `gh issue view --json closedByPullRequestsReferences` is
  cheaper still but names no PR when an issue was closed by hand, and the
  full REST timeline costs 23,000 to 44,000 tokens and cannot name the closer
  at all: its `closed` event carries no PR.
- **Where it does not pay.** On small discussions the plain `gh` command is
  still cheaper once the skill's own instructions are counted, but by much
  less. Trimming each SKILL.md to about 1,000 tokens (from 2,074 and 1,804)
  and the `--only`/`--item` flow cut the four losses from 1,481–2,773 tokens
  to 204–1,351. Reading one top-level comment on cli/cli#13946 now costs
  1,369 tokens with `gh pr view --comments` and 1,573 through the skill,
  down from 4,106; reading all of cli/cli#14141 costs 732 with `gh pr view`
  and 1,871 through the skill. The plugin's two skill descriptions also cost
  530 tokens in every session, whether or not they are used.
- **Bytes ÷ 4 undercounts.** Raw JSON runs at 2.25 bytes per token and this
  kind of text at 2.5 to 2.7, so the common rule of four bytes per token
  undercounts by 1.5 to 1.8 times.

## Method

Each approach is run once per target, with its output captured off a
terminal, the way an agent's Bash tool receives it. Each distinct output is
then sent through `claude -p` inside a fixed wrapper, and its token count is
the input total minus that of the same wrapper with an empty document.

Every output is also graded by hand: ✓ answers the task completely, ◐
answers part of it, ✗ is wrong or missing, and – is not an answer by itself,
such as a table of contents. A cheap answer that is wrong is not a saving, so
the grade matters as much as the count. The grades and their reasons are in
the run's [`grades.json`](bench/runs/2026-11-03/grades.json).

The skill rows add the cost of loading the skill. A Claude Code session pays
for both skill descriptions every time, and invoking a skill adds its
`SKILL.md`. Its `references/` files load only when the SKILL.md's pointer
to one applies, so they are listed with what triggers them and left out of
the flows, except where a reference teaches the flow: Task 4's TOC + slice
adds `references/recipes.md`, where the dump recipes live.

The targets are labelled by the shape of their discussion:

| Label | Target | Shape |
|---|---|---|
| E1 | [cli#6775](https://github.com/cli/cli/pull/6775) | merged, no comments and no reviews, short description |
| E2 | [cli#14141](https://github.com/cli/cli/pull/14141) | merged, no comments and no reviews, longer description |
| R1 | [cli#13946](https://github.com/cli/cli/pull/13946) | merged, 12 review threads from human reviews, all resolved; one top-level comment |
| R2 | [cli#14056](https://github.com/cli/cli/pull/14056) | merged, a dismissed review and an approval, one human and one bot thread, both resolved; one top-level comment and a bot one |
| O1 | [cli#14104](https://github.com/cli/cli/pull/14104) | merged, 17 review threads, 7 still open, one of them in a bot review |
| I1 | [cli#14483](https://github.com/cli/cli/issues/14483) | closed by hand, two comments, no linked PR |
| I2 | [cli#13727](https://github.com/cli/cli/issues/13727) | closed through a PR, no comments |
| I3 | [cli#13898](https://github.com/cli/cli/issues/13898) | closed by one PR's closing keyword; another merged PR referenced it too |
| I4 | [cli#14411](https://github.com/cli/cli/issues/14411) | closed by hand after the fixing PR merged, so nothing records a closing PR |

## Results

### Fixed costs of the skills

| Item | Paid | Bytes | Tokens |
|---|---|--:|--:|
| `pr-comments` description | every session, used or not | 752 | 278 |
| `issue-comments` description | every session, used or not | 676 | 252 |
| `pr-comments` SKILL.md | each invocation | 2,834 | 1,096 |
| `issue-comments` SKILL.md | each invocation | 2,671 | 1,007 |
| `pr-comments` references/flags.md | for a flag beyond the skill's table | 2,825 | 1,017 |
| `issue-comments` references/flags.md | for a flag beyond the skill's table | 1,785 | 675 |
| `pr-comments` references/recipes.md | for a dump read in slices, or a finding to re-check | 1,408 | 641 |
| `issue-comments` references/recipes.md | for a dump read in slices, or before acting | 1,310 | 567 |
| `pr-comments` references/output.md | when a marker needs interpreting | 4,537 | 1,561 |
| `issue-comments` references/output.md | when a marker needs interpreting | 3,896 | 1,394 |

### Task 1 — read a PR's whole discussion

Tokens per approach; ✓ complete, ◐ partial, ✗ wrong or missing, – not an answer by itself. `E1`/`E2` have no comments or reviews, so `gh pr view --comments` prints **nothing**, not even the description. On the PRs with reviews it shows review bodies and top-level comments but none of the inline threads. Adding REST `pulls/N/comments` brings the thread comments back as raw JSON with no resolved or open state, so the reader cannot tell settled feedback from live feedback.

| Approach | E1 | E2 | R1 | R2 | O1 |
|---|--:|--:|--:|--:|--:|
| `gh pr view --comments` | 0 ✗ | 0 ✗ | 1,369 ✗ | 1,024 ✗ | 6,105 ✗ |
| `gh pr view` + `gh pr view --comments` | 277 ✓ | 732 ✓ | 3,439 ✗ | 1,584 ✗ | 7,941 ✗ |
| … + REST `pulls/N/comments` | 280 ✓ | 735 ✓ | 44,232 ◐ | 6,669 ◐ | 68,324 ◐ |
| REST comments + reviews + inline (raw JSON) | 9 ✗ | 9 ✗ | 53,656 ◐ | 12,146 ◐ | 79,297 ◐ |
| **`gh-comments`** | 245 ✓ | 622 ✓ | 8,191 ✓ | 1,153 ✓ | 8,502 ✓ |
| **`gh-comments --toc`** (orientation only) | 161 – | 153 – | 1,941 – | 511 – | 2,387 – |

```
cli#14104 — read everything
  gh pr view --comments    ▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░   6,105 ✗ no inline threads
  + gh pr view             ▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░   7,941 ✗ no inline threads
  + REST pulls/N/comments  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░  68,324 ◐ no open/resolved
  REST trio, raw JSON      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  79,297 ◐ no open/resolved
  gh-comments              ▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░   8,502 ✓ all 17 threads
  gh-comments --toc        ▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   2,387 – map only
```

### Task 2 — which review threads are still open, and where

REST review comments carry no resolution field, so REST cannot answer this at any cost. On `R1`/`R2` the right answer is "none: every thread is resolved". On `O1` it is 7 of 17, one of them in a bot review that the default view filters; it is listed under `threads in filtered bot reviews:`.

| Approach | R1 | R2 | O1 |
|---|--:|--:|--:|
| `gh pr view --comments` | 1,369 ✗ | 1,024 ✗ | 6,105 ✗ |
| REST `pulls/N/comments` | 40,793 ✗ | 5,085 ✗ | 60,383 ✗ |
| hand-written GraphQL (metadata) | 781 ✓ | 226 ✓ | 930 ✓ |
| **`gh-comments --toc --unresolved`** | 85 ✓ | 94 ✓ | 614 ✓ |
| **`gh-comments --toc`** | 1,941 ✓ | 511 ✓ | 2,387 ✓ |

```
cli#14104 — which threads are open
  REST pulls/N/comments           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  60,383 ✗ cannot tell
  gh pr view --comments           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░   6,105 ✗ no threads
  gh-comments --toc               ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░   2,387 ✓ 7 of 7
  hand GraphQL metadata           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░     930 ✓
  gh-comments --toc --unresolved  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░     614 ✓ 7 of 7
                                  (log scale)
```

### Task 3 — what the open threads say

Only `O1` has open threads. The naive pair returns all 17 threads with no way to tell the 10 resolved ones apart, so an agent would re-litigate settled feedback. `--unresolved` also prints the body of each review that holds an open thread. On `O1` that is the CHANGES_REQUESTED review, whose body is about half the output and carries two `[Blocker]` findings written as prose, which the GraphQL query never reads. Both are graded ✓ because the task is what the open threads say; an agent addressing the review needs the body as well.

| Approach | O1 |
|---|--:|
| `gh pr view --comments` + REST inline | 66,488 ✗ |
| hand-written GraphQL, open threads with bodies | 2,126 ✓ |
| **`gh-comments --unresolved`** | 2,614 ✓ |

### Task 4 — land one specific comment in context

The skill's documented flow for one item needs no dump: a TOC narrowed to the item's kind (`--toc --only <kind>`), then the one item by its TOC line (`--item`). TOC + slice is the earlier flow, TOC first, dump to a file, then slice the one item out, which the skill keeps for many items at once. The expert flow is the same shape by hand: list with `--jq`, then fetch the one body. Every arm lands the same comment text; the slice and `--item` also carry the item's header line and the renderer's two-space indent, which is the few dozen bytes between the payload column and the expert fetch. Each `+ SKILL.md` column adds the cost of loading the skill to the flow before it, paid once per invocation; for TOC + slice it also adds `references/recipes.md`, where the skill keeps that flow.

| Target | `gh … view --comments` | naive complete | `gh-comments` full | TOC + slice | + SKILL.md | **`--only` + `--item`** | + SKILL.md | expert list → fetch | payload |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| cli#13946 top-level comment | 1,369 ✓ | 42,162 | 8,191 | 2,288 | 4,025 | **477** | 1,573 | 372 | 347 |
| cli#13946 inline thread | 1,369 ✗ | 42,162 | 8,191 | 2,123 | 3,860 | **977** | 2,073 | 816 | 182 |
| cli#14104 open thread | 6,105 ✗ | 66,488 | 8,502 | 2,721 | 4,458 | **1,249** | 2,345 | 1,104 | 334 |
| cli#14483 last comment | 772 ✓ | 772 | 907 | 451 | 2,025 | **182** | 1,189 | 158 | 37 |

### Task 5 — address the most recent review

On `R2` and `O1` the most recent review is an approval with a short body. `--since-last-review` anchors on it on both, and so does `--latest` on `O1`, since it skips only reviews and comments with no text and "LGTM" has text; on `R2` it anchors on the comment posted with the approval. On `R1` a COMMENTED review ("Awesome") arrived after the approval since the last run, and both slices anchor on it. On `O1` the 7 open threads come from earlier reviews, so neither slice shows them; `gh pr view --comments` shows the approval but not those threads either, hence its ✗ there. `--unresolved` is the flag for what is still open regardless of age. `E1`/`E2` have no reviews: both slicing flags print a note and fall back to the TOC, while `gh pr view --comments` prints nothing at all.

| Approach | R1 | R2 | O1 | E1 | E2 |
|---|--:|--:|--:|--:|--:|
| `gh pr view --comments` | 1,369 ✓ | 1,024 ✓ | 6,105 ✗ | 0 ✗ | 0 ✗ |
| `gh-comments` full | 8,191 ✓ | 1,153 ✓ | 8,502 ✓ | 245 ✓ | 622 ✓ |
| **`gh-comments --since-last-review`** | 2,108 ✓ | 588 ✓ | 1,576 ✓ | 180 ✓ | 172 ✓ |
| **`gh-comments --latest`** | 2,108 ✓ | 553 ✓ | 1,576 ✓ | 180 ✓ | 172 ✓ |

### Task 6 — read an issue in full

◐: no cross-reference events, so neither can say which PRs worked on the issue. `I1` has none, so nothing is missing there. Off a TTY, `gh issue view --comments` prints the comments without the issue body, hence two calls, and on `I2`, which has no comments, it prints nothing.

| Approach | I1 | I2 | I3 | I4 |
|---|--:|--:|--:|--:|
| `gh issue view` + `gh issue view --comments` | 1,384 ✓ | 622 ◐ | 1,146 ◐ | 1,133 ◐ |
| REST issue + comments (raw JSON) | 5,441 ✓ | 1,954 ◐ | 5,840 ◐ | 4,741 ◐ |
| REST issue + timeline (raw JSON) | 24,555 ✓ | 8,354 ✓ | 46,379 ✓ | 46,413 ✓ |
| **`gh-comments`** | 907 ✓ | 747 ✓ | 868 ✓ | 870 ✓ |
| **`gh-comments --toc`** (orientation only) | 414 – | 279 – | 564 – | 607 – |

### Task 7 — why was the issue closed, and by what

`closedByPullRequestsReferences` is filled only when a PR's closing keyword closed the issue. `I4` was closed by hand after its fix merged, so the cheap JSON names no PR, and only the timeline shows that the fix was reverted after the issue closed. `I3` lists the PR that closed it but not the earlier PR whose review the issue came out of. `I1` was closed by its author after a comment explaining the cause, which only the comments carry. `gh-comments` now reads the closed event's `closer`, which only GraphQL records: on `I3` the closed line names #13927 as the closer beside the two PR xrefs, and on `I4` it says `no closer recorded` between the fix and its revert, which is the answer, so both the TOC and `--closure` are ✓ there. The REST timeline still cannot tell the two apart, hence ◐. `--closure` prints the header, the closed/reopened lines and the PR xrefs and nothing else; on `I1` that says no PR closed it but not why, which only the comments carry, hence ◐ there against the TOC's ✓.

| Approach | I1 | I3 | I4 |
|---|--:|--:|--:|
| `gh issue view` | 612 ✗ | 475 ✗ | 434 ✗ |
| `gh issue view --json state,stateReason,closedAt,closedByPullRequestsReferences` | 63 ✗ | 211 ◐ | 63 ✗ |
| REST timeline (raw JSON) | 22,633 ✓ | 44,277 ◐ | 43,789 ◐ |
| **`gh-comments --toc`** | 414 ✓ | 564 ✓ | 607 ✓ |
| **`gh-comments --closure`** | 58 ◐ | 405 ✓ | 314 ✓ |

### The multiplier, revisited

How many times more tokens the alternative costs than the script's narrowest correct form for that task (>1× = script cheaper). SKILL.md is excluded here and treated in the break-even section.

```
open threads, cli#13946: REST inline vs --toc --unresolved                 │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓»  479.9×  REST can't answer
why closed, cli#14411: REST timeline vs --closure                          │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓    139.5×  REST names no closer (◐); --closure says none was recorded (✓)
open threads, cli#14104: REST inline vs --toc --unresolved                 │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓       98.3×  REST can't answer
one inline thread, cli#13946: naive vs TOC+slice                           │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓               19.9×  
read all, cli#14104: REST trio vs full                                     │▓▓▓▓▓▓▓▓▓▓▓▓                    9.3×  
read all, cli#13946: gh view + REST inline vs full                         │▓▓▓▓▓▓▓▓▓                       5.4×  
one comment, cli#13946: gh pr view --comments vs --only+--item             │▓▓▓▓▓▓                          2.9×  
open threads, cli#14104: hand GraphQL vs --toc --unresolved                │▓▓                              1.5×  
read all, cli#14141: gh pr view vs full                                    │▓                               1.2×  
one comment, cli#14483: expert vs --only+--item                           ░│                                0.9×  
open bodies, cli#14104: hand GraphQL vs --unresolved                      ░│                                0.8×  --unresolved adds the review body, with 2 prose blockers
one comment, cli#13946: gh pr view --comments vs TOC+slice              ░░░│                                0.6×  
one comment, cli#14483: expert vs TOC+slice                           ░░░░░│                                0.4×  the TOC carries 3 xrefs from this repo's own issues
                                                               0.1         1           10          100  
                                                               ░ alternative cheaper    ▓ script cheaper (log scale)
```

### Break-even: does loading the skill pay for itself?

The two descriptions cost **530 tokens in every session**, whether or not either skill is used. Invoking a skill then adds its SKILL.md (1,096 for `pr-comments`, 1,007 for `issue-comments`). Against the realistic naive path for the same task, with each one-item task taking the skill's `--toc --only` then `--item` flow:

| Task | naive tokens | skill flow + SKILL.md | net per invocation |
|---|--:|--:|--:|
| cli#14104 read all (naive: gh view + REST inline) | 68,324 | 11,985 | saves 56,339 |
| cli#14104 which threads open (naive: REST inline) | 60,383 | 1,710 | saves 58,673 |
| cli#13946 read all (naive: gh view + REST inline) | 44,232 | 11,228 | saves 33,004 |
| cli#13946 one inline thread (naive: gh view --comments + REST inline) | 42,162 | 2,073 | saves 40,089 |
| cli#13946 one top-level comment (naive: gh pr view --comments) | 1,369 | 1,573 | costs 204 |
| cli#14141 read all (naive: gh pr view) | 732 | 1,871 | costs 1,139 |
| cli#14411 read all (naive: gh issue view ×2) | 1,133 | 2,484 | costs 1,351 |
| cli#14483 one comment (naive: gh issue view --comments) | 772 | 1,189 | costs 417 |

## Caveats

- **Live data.** The targets are real PRs and issues, all merged or closed so
  they change as little as possible. A new comment or a resolved thread still
  moves the numbers, so a rerun can differ from these for reasons that have
  nothing to do with `gh-comments`.
- **This repository moved the issue targets.** Since the 2026-10-09 run,
  this repository's own issues and pull requests have linked three of the
  issue targets, which now carry `xref` lines from romansod/gh-comments and
  romansod/agent-evals (three on cli/cli#14483 and cli/cli#13898, five on
  cli/cli#14411). The REST timelines embed those issues' full bodies, so
  they grew again in this run, by about 7,000 tokens each on cli/cli#13898
  and cli/cli#14411. On cli/cli#13946 a new review arrived after the
  approval, which moved where `--latest` and `--since-last-review` anchor.
  The delta table in the run's `tables.md` lists every output that changed.
- **One run each.** Timings vary between runs, so the generated report's
  wall-clock section is only indicative. Token counts do not vary for the same
  output.
- **One model.** Counts are for `claude-opus-5-5`'s tokenizer. Another model
  counts differently, though the ratios between approaches should hold.
- **The grades are judgments.** Whether an output answers a task is decided by
  reading it, and the reasons are written down beside each grade so they can
  be checked.

## Reproducing

The published run measured this checkout's own `gh-comments` and `skills/`,
which is what the scripts run with no variables set:

```bash
cd bench
zsh run-cases.zsh
zsh run-targets.zsh
zsh run-fixed.zsh
python3 count_tokens.py   # calls claude -p; a full count costs a few dollars
python3 analyze.py
```

To measure a release instead, check its tag out beside this checkout and
point the scripts at it. `v1.0.0` predates the harness and has no
`--closure`, so its four `s_closure` cases exit 1 there and `analyze.py`
refuses the run (and cannot analyze it with those rows dropped either, since
the Task 7 table and the why-closed ladder read them unconditionally); its
other rows, read by hand from `cases.tsv` and `tokens.tsv`, are a baseline,
not a reproduction of these tables:

```bash
git worktree add /tmp/gh-comments-v1.0.0 v1.0.0
GH_COMMENTS=/tmp/gh-comments-v1.0.0/gh-comments zsh run-cases.zsh
zsh run-targets.zsh
SKILLS_DIR=/tmp/gh-comments-v1.0.0/skills zsh run-fixed.zsh
```

It needs `gh` logged in and the `claude` CLI. See
[`bench/README.md`](bench/README.md) for filing a run and comparing it with
this one.
