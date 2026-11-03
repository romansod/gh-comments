### Targets

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

### Fixed costs

| Item | Paid | Bytes | Tokens |
|---|---|--:|--:|
| `pr-comments` description | every session, used or not | 752 | 278 |
| `issue-comments` description | every session, used or not | 676 | 252 |
| `pr-comments` SKILL.md | each invocation | 2,834 | 1,096 |
| `issue-comments` SKILL.md | each invocation | 2,671 | 1,007 |
| `pr-comments` references/flags.md | for a flag beyond the skill's table | 2,825 | 1,017 |
| `issue-comments` references/flags.md | for a flag beyond the skill's table | 1,785 | 675 |
| `pr-comments` references/recipes.md | for a dump read in slices, or a finding to re-check | 1,078 | 454 |
| `issue-comments` references/recipes.md | for a dump read in slices, or before acting | 1,013 | 409 |
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
| cli#13946 top-level comment | 1,369 ✓ | 42,162 | 8,191 | 2,288 | 3,838 | **477** | 1,573 | 372 | 347 |
| cli#13946 inline thread | 1,369 ✗ | 42,162 | 8,191 | 2,123 | 3,673 | **977** | 2,073 | 816 | 182 |
| cli#14104 open thread | 6,105 ✗ | 66,488 | 8,502 | 2,721 | 4,271 | **1,249** | 2,345 | 1,104 | 334 |
| cli#14483 last comment | 772 ✓ | 772 | 907 | 451 | 1,867 | **182** | 1,189 | 158 | 37 |

```
Task 4 — tokens to land one comment (each ▓ ≈ 1k tokens)
  cli#13946 top-level comment
    naive complete           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓»» 42,162
    gh-comments full         ▓▓▓▓▓▓▓▓                    8,191
    TOC + slice + SKILL.md   ▓▓▓▓                        3,838
    TOC + slice              ▓▓                          2,288
    --only + --item + SKILL.md ▓▓                          1,573
    --only + --item          ▓                             477
    expert list → fetch      ▓                             372
    the comment itself       ▓                             347
  cli#13946 inline thread
    naive complete           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓»» 42,162
    gh-comments full         ▓▓▓▓▓▓▓▓                    8,191
    TOC + slice + SKILL.md   ▓▓▓▓                        3,673
    TOC + slice              ▓▓                          2,123
    --only + --item + SKILL.md ▓▓                          2,073
    --only + --item          ▓                             977
    expert list → fetch      ▓                             816
    the comment itself       ▓                             182
  cli#14104 open thread
    naive complete           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓»» 66,488
    gh-comments full         ▓▓▓▓▓▓▓▓▓                   8,502
    TOC + slice + SKILL.md   ▓▓▓▓                        4,271
    TOC + slice              ▓▓▓                         2,721
    --only + --item + SKILL.md ▓▓                          2,345
    --only + --item          ▓                           1,249
    expert list → fetch      ▓                           1,104
    the comment itself       ▓                             334
  cli#14483 last comment
    naive complete           ▓                             772
    gh-comments full         ▓                             907
    TOC + slice + SKILL.md   ▓▓                          1,867
    TOC + slice              ▓                             451
    --only + --item + SKILL.md ▓                           1,189
    --only + --item          ▓                             182
    expert list → fetch      ▓                             158
    the comment itself       ▓                              37
```

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

```
net tokens per invocation (skill flow incl. SKILL.md vs naive)   ▓ saved  ░ spent
                              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  +56,339  cli#14104 read all
                              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ +58,673  cli#14104 which threads open
                              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓             +33,004  cli#13946 read all
                              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓          +40,089  cli#13946 one inline thread
                             ░│                             −   204  cli#13946 one top-level comment
                             ░│                             − 1,139  cli#14141 read all
                             ░│                             − 1,351  cli#14411 read all
                             ░│                             −   417  cli#14483 one comment
```

### Heatmap: tokens by target × approach

```
         ghview  ghv -c  rst ic  rst rv  rst rc  gql md  s full  s toc   s unr   s tocU  s slr  
E1         ▒       ·       ░       ░       ░       ░       ░       ░       ░       ░       ░    
E2         ▒       ·       ░       ░       ░       ░       ▒       ░       ░       ░       ░    
R1         ▓       ▓       ▓       ▓▓     ▓▓▓      ▒       ▓▓      ▓       ░       ░       ▓    
R2         ▒       ▓       ▓       ▓▓      ▓▓      ░       ▓       ▒       ░       ░       ▒    
O1         ▓       ▓▓      ▓      ▓▓▓     ▓▓▓      ▒       ▓▓      ▓       ▓       ▒       ▓    

· 0   ░ <250   ▒ <1k   ▓ <4k   ▓▓ <16k   ▓▓▓ ≥16k  tokens
ghview/ghv -c: gh pr view [--comments]   rst ic/rv/rc: REST issue comments/reviews/inline
gql md: GraphQL thread metadata   s *: gh-comments full/--toc/--unresolved/--toc --unresolved/--since-last-review
```

### Bytes per token, by content type

| Content | Bytes | Tokens | Bytes/token | bytes ÷ 4 undercounts by |
|---|--:|--:|--:|--:|
| raw JSON (gh api) | 643,735 | 286,588 | 2.25 | 1.8× |
| gh … view text | 47,509 | 18,258 | 2.60 | 1.5× |
| gh-comments output | 162,924 | 65,062 | 2.50 | 1.6× |
| skill files | 22,067 | 8,143 | 2.71 | 1.5× |

```
  raw JSON (gh api)        ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░ 2.25 bytes/token
  gh … view text           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░ 2.60 bytes/token
  gh-comments output       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░ 2.50 bytes/token
  skill files              ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░ 2.71 bytes/token
  the bytes ÷ 4 rule       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 4.00 bytes/token
```

### Wall-clock (one run each)

```
  gh pr view --comments           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░  1,331 ms
  REST pulls/N/comments           ▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░    596 ms
  GraphQL thread metadata         ▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░    429 ms
  gh-comments (full)              ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  1,382 ms
  gh-comments --toc --unresolved  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░  1,283 ms
  gh issue view (cli#14411)       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░    821 ms
  gh-comments (cli#14411)         ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░    867 ms
```

### Delta vs baseline

Tokens per output, this run against `../2026-10-22`, largest change first. Rows named `s_*`, `*_slice` and `FIX.*` are the script and skill outputs the fixes touch; the rest are raw `gh`/REST captures of live targets and move when GitHub does.

| Output | baseline | now | delta |
|---|--:|--:|--:|
| `I3.rest_tl` | 37,018 | 44,277 | +7,259 (+20%) |
| `I4.rest_tl` | 37,055 | 43,789 | +6,734 (+18%) |
| `R1.rest_rv` | 10,707 | 11,812 | +1,105 (+10%) |
| `FIX.pr_skillmd` | 2,074 | 1,096 | -978 (-47%) |
| `FIX.issue_skillmd` | 1,804 | 1,007 | -797 (-44%) |
| `O1.rest_rc` | 59,629 | 60,383 | +754 (+1%) |
| `R1.rest_rc` | 40,273 | 40,793 | +520 (+1%) |
| `O1.rest_rv` | 16,891 | 17,351 | +460 (+3%) |
| `O1.s_toc` | 2,078 | 2,387 | +309 (+15%) |
| `R1.s_toc` | 1,685 | 1,941 | +256 (+15%) |
| `O1.s_toc_unres` | 475 | 614 | +139 (+29%) |
| `FIX.pr_ref` | 1,425 | 1,561 | +136 (+10%) |
| `R2.rest_rv` | 4,367 | 4,503 | +136 (+3%) |
| `R2.rest_rc` | 4,981 | 5,085 | +104 (+2%) |
| `I3.s_events` | 929 | 988 | +59 (+6%) |
| `I3.s_full` | 809 | 868 | +59 (+7%) |
| `I3.s_toc` | 505 | 564 | +59 (+12%) |
| `I4.s_events` | 911 | 970 | +59 (+6%) |
| `I4.s_full` | 811 | 870 | +59 (+7%) |
| `I4.s_toc` | 548 | 607 | +59 (+11%) |
| `I3.s_closure` | 347 | 405 | +58 (+17%) |
| `I4.s_closure` | 256 | 314 | +58 (+23%) |
| `R2.s_toc` | 466 | 511 | +45 (+10%) |
| `R1.s_full` | 8,147 | 8,191 | +44 (+1%) |
| `R1.s_since` | 7,651 | 7,695 | +44 (+1%) |
| `I1.rest_tl` | 22,594 | 22,633 | +39 (+0%) |
| `R1.gh_view_c` | 1,333 | 1,369 | +36 (+3%) |
| `R1.gh_view` | 2,060 | 2,070 | +10 (+0%) |
| `I1.rest_ic` | 3,513 | 3,519 | +6 (+0%) |
| `I3.rest_ic` | 3,732 | 3,738 | +6 (+0%) |
| `I4.rest_ic` | 2,111 | 2,117 | +6 (+0%) |
| `R1.s_latest` | 2,105 | 2,108 | +3 (+0%) |
| `R1.s_slr` | 2,105 | 2,108 | +3 (+0%) |
| `I1.s_events` | 955 | 957 | +2 (+0%) |
| `I1.s_full` | 905 | 907 | +2 (+0%) |
| `I1.s_toc` | 412 | 414 | +2 (+0%) |
| `E1.gh_view` | 277 | 277 | 0 (+0%) |
| `E1.gh_view_c` | 0 | 0 | 0 |
| `E1.gql_meta` | 66 | 66 | 0 (+0%) |
| `E1.gql_open` | 0 | 0 | 0 |
| `E1.rest_ic` | 3 | 3 | 0 (+0%) |
| `E1.rest_rc` | 3 | 3 | 0 (+0%) |
| `E1.rest_rv` | 3 | 3 | 0 (+0%) |
| `E1.s_full` | 245 | 245 | 0 (+0%) |
| `E1.s_latest` | 180 | 180 | 0 (+0%) |
| `E1.s_since` | 245 | 245 | 0 (+0%) |
| `E1.s_slr` | 180 | 180 | 0 (+0%) |
| `E1.s_toc` | 161 | 161 | 0 (+0%) |
| `E1.s_toc_unres` | 77 | 77 | 0 (+0%) |
| `E1.s_unres` | 77 | 77 | 0 (+0%) |
| `E2.gh_view` | 732 | 732 | 0 (+0%) |
| `E2.gh_view_c` | 0 | 0 | 0 |
| `E2.gql_meta` | 66 | 66 | 0 (+0%) |
| `E2.gql_open` | 0 | 0 | 0 |
| `E2.rest_ic` | 3 | 3 | 0 (+0%) |
| `E2.rest_rc` | 3 | 3 | 0 (+0%) |
| `E2.rest_rv` | 3 | 3 | 0 (+0%) |
| `E2.s_full` | 622 | 622 | 0 (+0%) |
| `E2.s_latest` | 172 | 172 | 0 (+0%) |
| `E2.s_since` | 622 | 622 | 0 (+0%) |
| `E2.s_slr` | 172 | 172 | 0 (+0%) |
| `E2.s_toc` | 153 | 153 | 0 (+0%) |
| `E2.s_toc_unres` | 80 | 80 | 0 (+0%) |
| `E2.s_unres` | 80 | 80 | 0 (+0%) |
| `FIX.issue_desc` | 252 | 252 | 0 (+0%) |
| `FIX.issue_ref` | 1,394 | 1,394 | 0 (+0%) |
| `FIX.pr_desc` | 278 | 278 | 0 (+0%) |
| `I1.gh_json_close` | 63 | 63 | 0 (+0%) |
| `I1.gh_view` | 612 | 612 | 0 (+0%) |
| `I1.gh_view_c` | 772 | 772 | 0 (+0%) |
| `I1.rest_issue` | 1,922 | 1,922 | 0 (+0%) |
| `I1.s_closure` | 58 | 58 | 0 (+0%) |
| `I2.gh_json_close` | 212 | 212 | 0 (+0%) |
| `I2.gh_view` | 622 | 622 | 0 (+0%) |
| `I2.gh_view_c` | 0 | 0 | 0 |
| `I2.rest_ic` | 3 | 3 | 0 (+0%) |
| `I2.rest_issue` | 1,951 | 1,951 | 0 (+0%) |
| `I2.rest_tl` | 6,403 | 6,403 | 0 (+0%) |
| `I2.s_closure` | 190 | 190 | 0 (+0%) |
| `I2.s_events` | 797 | 797 | 0 (+0%) |
| `I2.s_full` | 747 | 747 | 0 (+0%) |
| `I2.s_toc` | 279 | 279 | 0 (+0%) |
| `I3.gh_json_close` | 211 | 211 | 0 (+0%) |
| `I3.gh_view` | 475 | 475 | 0 (+0%) |
| `I3.gh_view_c` | 671 | 671 | 0 (+0%) |
| `I3.rest_issue` | 2,102 | 2,102 | 0 (+0%) |
| `I4.gh_json_close` | 63 | 63 | 0 (+0%) |
| `I4.gh_view` | 434 | 434 | 0 (+0%) |
| `I4.gh_view_c` | 699 | 699 | 0 (+0%) |
| `I4.rest_issue` | 2,624 | 2,624 | 0 (+0%) |
| `O1.gh_view` | 1,836 | 1,836 | 0 (+0%) |
| `O1.gh_view_c` | 6,105 | 6,105 | 0 (+0%) |
| `O1.gql_meta` | 930 | 930 | 0 (+0%) |
| `O1.gql_open` | 2,126 | 2,126 | 0 (+0%) |
| `O1.rest_ic` | 1,563 | 1,563 | 0 (+0%) |
| `O1.s_full` | 8,502 | 8,502 | 0 (+0%) |
| `O1.s_latest` | 1,576 | 1,576 | 0 (+0%) |
| `O1.s_since` | 7,764 | 7,764 | 0 (+0%) |
| `O1.s_slr` | 1,576 | 1,576 | 0 (+0%) |
| `O1.s_unres` | 2,614 | 2,614 | 0 (+0%) |
| `R1.gql_meta` | 781 | 781 | 0 (+0%) |
| `R1.gql_open` | 0 | 0 | 0 |
| `R1.rest_ic` | 1,051 | 1,051 | 0 (+0%) |
| `R1.s_toc_unres` | 85 | 85 | 0 (+0%) |
| `R1.s_unres` | 85 | 85 | 0 (+0%) |
| `R2.gh_view` | 560 | 560 | 0 (+0%) |
| `R2.gh_view_c` | 1,024 | 1,024 | 0 (+0%) |
| `R2.gql_meta` | 226 | 226 | 0 (+0%) |
| `R2.gql_open` | 0 | 0 | 0 |
| `R2.rest_ic` | 2,558 | 2,558 | 0 (+0%) |
| `R2.s_full` | 1,153 | 1,153 | 0 (+0%) |
| `R2.s_latest` | 553 | 553 | 0 (+0%) |
| `R2.s_since` | 588 | 588 | 0 (+0%) |
| `R2.s_slr` | 588 | 588 | 0 (+0%) |
| `R2.s_toc_unres` | 94 | 94 | 0 (+0%) |
| `R2.s_unres` | 94 | 94 | 0 (+0%) |
| `TA.expert_fetch` | 319 | 319 | 0 (+0%) |
| `TA.expert_list` | 53 | 53 | 0 (+0%) |
| `TA.skill_slice` | 347 | 347 | 0 (+0%) |
| `TB.expert_fetch` | 149 | 149 | 0 (+0%) |
| `TB.expert_list` | 667 | 667 | 0 (+0%) |
| `TB.skill_slice` | 182 | 182 | 0 (+0%) |
| `TC.expert_fetch` | 315 | 315 | 0 (+0%) |
| `TC.expert_list` | 789 | 789 | 0 (+0%) |
| `TC.skill_slice` | 334 | 334 | 0 (+0%) |
| `TC.unres_slice` | 334 | 334 | 0 (+0%) |
| `TD.expert_fetch` | 18 | 18 | 0 (+0%) |
| `TD.expert_list` | 140 | 140 | 0 (+0%) |
| `TD.skill_slice` | 37 | 37 | 0 (+0%) |

New in this run: `FIX.issue_flags`, `FIX.issue_recipes`, `FIX.pr_flags`, `FIX.pr_recipes`, `TA.item`, `TA.only_toc`, `TB.item`, `TB.only_toc`, `TC.item`, `TC.only_toc`, `TD.item`, `TD.only_toc`

No grade changed against the baseline.
