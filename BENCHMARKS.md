# Benchmarks

How many tokens it costs an agent to read a GitHub discussion with
`gh-comments`, compared with the usual ways of reading it: `gh pr view`,
`gh issue view`, the REST API and a hand-written GraphQL query. Every number
is an exact Claude token count of what the command printed, so it is what an
agent actually pays to read the output.

Run 2026-10-09 against `gh-comments` v1.0.0, on nine public PRs and issues
in [cli/cli](https://github.com/cli/cli). Tokens were counted with
`claude-opus-5-5`. The harness, the targets and the raw run are in
[`bench/`](bench/README.md); the full generated report, with a heatmap and
timings, is [`bench/runs/2026-10-09/tables.md`](bench/runs/2026-10-09/tables.md).

## Summary

- **Open review threads.** Asking which threads are still open on
  cli/cli#14104 costs 475 tokens with `--toc --unresolved`. REST cannot
  answer at any cost, because review comments carry no resolved state, and
  `gh pr view --comments` shows no inline threads at all.
- **Reading a whole PR.** `gh-comments` renders all 17 threads of
  cli/cli#14104, each marked open or resolved, in 8,502 tokens. The raw REST
  reads cost 67,570 to 78,083 tokens and still lack the resolved state.
- **Why an issue closed.** The table of contents shows every cross-reference
  and the `closed` line in a few hundred tokens. `gh issue view --json
  closedByPullRequestsReferences` is cheaper but names no PR when an issue was
  closed by hand, and the full REST timeline costs 6,600 to 27,000 tokens.
- **Where it does not pay.** On small discussions the plain `gh` command is
  cheaper once the skill's own instructions are counted. Reading one
  top-level comment on cli/cli#13946 costs 1,333 tokens with
  `gh pr view --comments` and 4,106 through the skill. The plugin's two skill
  descriptions also cost 518 tokens in every session, whether or not they are
  used.
- **Bytes ÷ 4 undercounts.** Raw JSON runs at 2.2 bytes per token and this
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
the run's [`grades.json`](bench/runs/2026-10-09/grades.json).

The skill rows add the cost of loading the skill. A Claude Code session pays
for both skill descriptions every time, and invoking a skill adds its
`SKILL.md`.

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
| `pr-comments` description | every session, used or not | 740 | 272 |
| `issue-comments` description | every session, used or not | 664 | 246 |
| `pr-comments` SKILL.md | each invocation | 5,486 | 2,074 |
| `issue-comments` SKILL.md | each invocation | 3,906 | 1,469 |
| `pr-comments` references/output.md | when a marker needs interpreting | 4,173 | 1,425 |
| `issue-comments` references/output.md | when a marker needs interpreting | 2,718 | 988 |

### Task 1 — read a PR's whole discussion

Tokens per approach; ✓ complete, ◐ partial, ✗ wrong or missing, – not an answer by itself. `E1`/`E2` have no comments or reviews, so `gh pr view --comments` prints **nothing**, not even the description. On the PRs with reviews it shows review bodies and top-level comments but none of the inline threads. Adding REST `pulls/N/comments` brings the thread comments back as raw JSON with no resolved or open state, so the reader cannot tell settled feedback from live feedback.

| Approach | E1 | E2 | R1 | R2 | O1 |
|---|--:|--:|--:|--:|--:|
| `gh pr view --comments` | 0 ✗ | 0 ✗ | 1,333 ✗ | 1,024 ✗ | 6,105 ✗ |
| `gh pr view` + `gh pr view --comments` | 277 ✓ | 732 ✓ | 3,393 ✗ | 1,584 ✗ | 7,941 ✗ |
| … + REST `pulls/N/comments` | 280 ✓ | 735 ✓ | 43,666 ◐ | 6,565 ◐ | 67,570 ◐ |
| REST comments + reviews + inline (raw JSON) | 9 ✗ | 9 ✗ | 52,031 ◐ | 11,906 ◐ | 78,083 ◐ |
| **`gh-comments`** | 245 ✓ | 622 ✓ | 8,147 ✓ | 1,153 ✓ | 8,502 ✓ |
| **`gh-comments --toc`** (orientation only) | 161 – | 153 – | 1,685 – | 466 – | 2,078 – |

```
cli#14104 — read everything
  gh pr view --comments    ▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░   6,105 ✗ no inline threads
  + gh pr view             ▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░   7,941 ✗ no inline threads
  + REST pulls/N/comments  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░  67,570 ◐ no open/resolved
  REST trio, raw JSON      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  78,083 ◐ no open/resolved
  gh-comments              ▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░   8,502 ✓ all 17 threads
  gh-comments --toc        ▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   2,078 – map only
```

### Task 2 — which review threads are still open, and where

REST review comments carry no resolution field, so REST cannot answer this at any cost. On `R1`/`R2` the right answer is "none: every thread is resolved". On `O1` it is 7 of 17, one of them in a bot review that the default view filters; it is listed under `threads in filtered bot reviews:`.

| Approach | R1 | R2 | O1 |
|---|--:|--:|--:|
| `gh pr view --comments` | 1,333 ✗ | 1,024 ✗ | 6,105 ✗ |
| REST `pulls/N/comments` | 40,273 ✗ | 4,981 ✗ | 59,629 ✗ |
| hand-written GraphQL (metadata) | 781 ✓ | 226 ✓ | 930 ✓ |
| **`gh-comments --toc --unresolved`** | 85 ✓ | 94 ✓ | 475 ✓ |
| **`gh-comments --toc`** | 1,685 ✓ | 466 ✓ | 2,078 ✓ |

```
cli#14104 — which threads are open
  REST pulls/N/comments           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  59,629 ✗ cannot tell
  gh pr view --comments           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░   6,105 ✗ no threads
  gh-comments --toc               ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░   2,078 ✓ 7 of 7
  hand GraphQL metadata           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░     930 ✓
  gh-comments --toc --unresolved  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░     475 ✓ 7 of 7
                                  (log scale)
```

### Task 3 — what the open threads say

Only `O1` has open threads. The naive pair returns all 17 threads with no way to tell the 10 resolved ones apart, so an agent would re-litigate settled feedback.

| Approach | O1 |
|---|--:|
| `gh pr view --comments` + REST inline | 65,734 ✗ |
| hand-written GraphQL, open threads with bodies | 2,126 ✓ |
| **`gh-comments --unresolved`** | 2,614 ✓ |

### Task 4 — land one specific comment in context

The skill's documented flow is TOC first, dump to a file, then slice the one item out. The expert flow is the same shape by hand: list with `--jq`, then fetch the one body. Both arms land the same comment text; the slice also carries the item's header line and the renderer's two-space indent, which is the few dozen bytes between the payload column and the expert fetch. The `+ SKILL.md` column adds the cost of loading the skill, paid once per invocation.

| Target | `gh … view --comments` | naive complete | `gh-comments` full | **TOC + slice** | + SKILL.md | expert list → fetch | payload |
|---|--:|--:|--:|--:|--:|--:|--:|
| cli#13946 top-level comment | 1,333 ✓ | 41,606 | 8,147 | **2,032** | 4,106 | 372 | 347 |
| cli#13946 inline thread | 1,333 ✗ | 41,606 | 8,147 | **1,867** | 3,941 | 816 | 182 |
| cli#14104 open thread | 6,105 ✗ | 65,734 | 8,502 | **2,412** | 4,486 | 1,104 | 334 |
| cli#14483 last comment | 772 ✓ | 772 | 712 | **256** | 1,725 | 158 | 37 |

### Task 5 — address the most recent review

On all three reviewed PRs the most recent review is an approval with a short body. `--since-last-review` anchors on it everywhere, and so does `--latest` on `R1` and `O1`, since it skips only reviews and comments with no text and "LGTM" has text; on `R2` it anchors on the comment posted with the approval. On `O1` the 7 open threads come from earlier reviews, so neither slice shows them; `gh pr view --comments` shows the approval but not those threads either, hence its ✗ there. `--unresolved` is the flag for what is still open regardless of age. `E1`/`E2` have no reviews: both slicing flags print a note and fall back to the TOC, while `gh pr view --comments` prints nothing at all.

| Approach | R1 | R2 | O1 | E1 | E2 |
|---|--:|--:|--:|--:|--:|
| `gh pr view --comments` | 1,333 ✓ | 1,024 ✓ | 6,105 ✗ | 0 ✗ | 0 ✗ |
| `gh-comments` full | 8,147 ✓ | 1,153 ✓ | 8,502 ✓ | 245 ✓ | 622 ✓ |
| **`gh-comments --since-last-review`** | 2,105 ✓ | 588 ✓ | 1,576 ✓ | 180 ✓ | 172 ✓ |
| **`gh-comments --latest`** | 2,105 ✓ | 553 ✓ | 1,576 ✓ | 180 ✓ | 172 ✓ |

### Task 6 — read an issue in full

◐: no cross-reference events, so neither can say which PRs worked on the issue. `I1` has none, so nothing is missing there. Off a TTY, `gh issue view --comments` prints the comments without the issue body, hence two calls, and on `I2`, which has no comments, it prints nothing.

| Approach | I1 | I2 | I3 | I4 |
|---|--:|--:|--:|--:|
| `gh issue view` + `gh issue view --comments` | 1,384 ✓ | 622 ◐ | 1,146 ◐ | 1,133 ◐ |
| REST issue + comments (raw JSON) | 5,435 ✓ | 1,954 ◐ | 5,834 ◐ | 4,735 ◐ |
| REST issue + timeline (raw JSON) | 8,562 ✓ | 8,354 ✓ | 28,864 ✓ | 17,863 ✓ |
| **`gh-comments`** | 712 ✓ | 698 ✓ | 644 ✓ | 540 ✓ |
| **`gh-comments --toc`** (orientation only) | 219 – | 230 – | 340 – | 277 – |

### Task 7 — why was the issue closed, and by what

`closedByPullRequestsReferences` is filled only when a PR's closing keyword closed the issue. `I4` was closed by hand after its fix merged, so the cheap JSON names no PR, and only the timeline shows that the fix was reverted after the issue closed. `I3` lists the PR that closed it but not the earlier PR whose review the issue came out of. `I1` was closed by its author after a comment explaining the cause, which only the comments carry. The TOC shows every `xref`, every comment's first line and the `closed` line.

| Approach | I1 | I3 | I4 |
|---|--:|--:|--:|
| `gh issue view` | 612 ✗ | 475 ✗ | 434 ✗ |
| `gh issue view --json state,stateReason,closedByPullRequestsReferences` | 63 ✗ | 211 ◐ | 63 ✗ |
| REST timeline (raw JSON) | 6,640 ✓ | 26,762 ✓ | 15,239 ✓ |
| **`gh-comments --toc`** | 219 ✓ | 340 ✓ | 277 ✓ |

### The multiplier, revisited

How many times more tokens the alternative costs than the script's narrowest correct form for that task (>1× = script cheaper). SKILL.md is excluded here and treated in the break-even section.

```
open threads, cli#13946: REST inline vs --toc --unresolved              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓»  473.8×  REST can't answer
open threads, cli#14104: REST inline vs --toc --unresolved              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓    125.5×  REST can't answer
why closed, cli#14411: REST timeline vs --toc                           │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓          55.0×  
one inline thread, cli#13946: naive vs TOC+slice                        │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓               22.3×  
read all, cli#14104: REST trio vs full                                  │▓▓▓▓▓▓▓▓▓▓▓▓                    9.2×  
read all, cli#13946: gh view + REST inline vs full                      │▓▓▓▓▓▓▓▓▓                       5.4×  
open threads, cli#14104: hand GraphQL vs --toc --unresolved             │▓▓▓▓                            2.0×  
read all, cli#14141: gh pr view vs full                                 │▓                               1.2×  
open bodies, cli#14104: hand GraphQL vs --unresolved                   ░│                                0.8×  
one comment, cli#13946: gh pr view --comments vs TOC+slice            ░░│                                0.7×  
one comment, cli#14483: expert vs TOC+slice                           ░░│                                0.6×  
why closed, cli#14411: --json closedBy vs --toc                 ░░░░░░░░│                                0.2×  but --json names no PR
                                                            0.1         1           10          100  
                                                            ░ alternative cheaper    ▓ script cheaper (log scale)
```

### Break-even: does loading the skill pay for itself?

The two descriptions cost **518 tokens in every session**, whether or not either skill is used. Invoking a skill then adds its SKILL.md (2,074 for `pr-comments`, 1,469 for `issue-comments`). Against the realistic naive path for the same task:

| Task | naive tokens | skill flow + SKILL.md | net per invocation |
|---|--:|--:|--:|
| cli#14104 read all (naive: gh view + REST inline) | 67,570 | 12,654 | saves 54,916 |
| cli#14104 which threads open (naive: REST inline) | 59,629 | 2,549 | saves 57,080 |
| cli#13946 read all (naive: gh view + REST inline) | 43,666 | 11,906 | saves 31,760 |
| cli#13946 one inline thread (naive: gh view --comments + REST inline) | 41,606 | 3,941 | saves 37,665 |
| cli#13946 one top-level comment (naive: gh pr view --comments) | 1,333 | 4,106 | costs 2,773 |
| cli#14141 read all (naive: gh pr view) | 732 | 2,849 | costs 2,117 |
| cli#14411 read all (naive: gh issue view ×2) | 1,133 | 2,286 | costs 1,153 |
| cli#14483 one comment (naive: gh issue view --comments) | 772 | 1,725 | costs 953 |

## Caveats

- **Live data.** The targets are real PRs and issues, all merged or closed so
  they change as little as possible. A new comment or a resolved thread still
  moves the numbers, so a rerun can differ from these for reasons that have
  nothing to do with `gh-comments`.
- **One run each.** Timings vary between runs, so the generated report's
  wall-clock section is only indicative. Token counts do not vary for the same
  output.
- **One model.** Counts are for `claude-opus-5-5`'s tokenizer. Another model
  counts differently, though the ratios between approaches should hold.
- **The grades are judgments.** Whether an output answers a task is decided by
  reading it, and the reasons are written down beside each grade so they can
  be checked.

## Reproducing

```bash
git checkout v1.0.0     # or whatever you want to measure
cd bench
zsh run-cases.zsh && zsh run-targets.zsh && zsh run-fixed.zsh
python3 count_tokens.py # calls claude -p; a full count costs a few dollars
python3 analyze.py
```

It needs `gh` logged in and the `claude` CLI. See
[`bench/README.md`](bench/README.md) for filing a run and comparing it with
this one.
