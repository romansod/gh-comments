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
| `pr-comments` SKILL.md | each invocation | 5,486 | 2,074 |
| `issue-comments` SKILL.md | each invocation | 4,670 | 1,745 |
| `pr-comments` references/output.md | when a marker needs interpreting | 4,173 | 1,425 |
| `issue-comments` references/output.md | when a marker needs interpreting | 3,505 | 1,273 |

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

Only `O1` has open threads. The naive pair returns all 17 threads with no way to tell the 10 resolved ones apart, so an agent would re-litigate settled feedback. `--unresolved` also prints the body of each review that holds an open thread. On `O1` that is the CHANGES_REQUESTED review, whose body is about half the output and carries two `[Blocker]` findings written as prose, which the GraphQL query never reads. Both are graded ✓ because the task is what the open threads say; an agent addressing the review needs the body as well.

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
| cli#14483 last comment | 772 ✓ | 772 | 905 | **449** | 2,194 | 158 | 37 |

```
Task 4 — tokens to land one comment (each ▓ ≈ 1k tokens)
  cli#13946 top-level comment
    naive complete           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓»» 41,606
    gh-comments full         ▓▓▓▓▓▓▓▓                    8,147
    TOC + slice + SKILL.md   ▓▓▓▓                        4,106
    TOC + slice              ▓▓                          2,032
    expert list → fetch      ▓                             372
    the comment itself       ▓                             347
  cli#13946 inline thread
    naive complete           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓»» 41,606
    gh-comments full         ▓▓▓▓▓▓▓▓                    8,147
    TOC + slice + SKILL.md   ▓▓▓▓                        3,941
    TOC + slice              ▓▓                          1,867
    expert list → fetch      ▓                             816
    the comment itself       ▓                             182
  cli#14104 open thread
    naive complete           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓»» 65,734
    gh-comments full         ▓▓▓▓▓▓▓▓▓                   8,502
    TOC + slice + SKILL.md   ▓▓▓▓                        4,486
    TOC + slice              ▓▓                          2,412
    expert list → fetch      ▓                           1,104
    the comment itself       ▓                             334
  cli#14483 last comment
    naive complete           ▓                             772
    gh-comments full         ▓                             905
    TOC + slice + SKILL.md   ▓▓                          2,194
    TOC + slice              ▓                             449
    expert list → fetch      ▓                             158
    the comment itself       ▓                              37
```

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
| REST issue + timeline (raw JSON) | 24,516 ✓ | 8,354 ✓ | 39,120 ✓ | 39,679 ✓ |
| **`gh-comments`** | 905 ✓ | 747 ✓ | 809 ✓ | 811 ✓ |
| **`gh-comments --toc`** (orientation only) | 412 – | 279 – | 505 – | 548 – |

### Task 7 — why was the issue closed, and by what

`closedByPullRequestsReferences` is filled only when a PR's closing keyword closed the issue. `I4` was closed by hand after its fix merged, so the cheap JSON names no PR, and only the timeline shows that the fix was reverted after the issue closed. `I3` lists the PR that closed it but not the earlier PR whose review the issue came out of. `I1` was closed by its author after a comment explaining the cause, which only the comments carry. `gh-comments` now reads the closed event's `closer`, which only GraphQL records: on `I3` the closed line names #13927 as the closer beside the two PR xrefs, and on `I4` it says `no closer recorded` between the fix and its revert, which is the answer, so both the TOC and `--closure` are ✓ there. The REST timeline still cannot tell the two apart, hence ◐. `--closure` prints the header, the closed/reopened lines and the PR xrefs and nothing else; on `I1` that says no PR closed it but not why, which only the comments carry, hence ◐ there against the TOC's ✓.

| Approach | I1 | I3 | I4 |
|---|--:|--:|--:|
| `gh issue view` | 612 ✗ | 475 ✗ | 434 ✗ |
| `gh issue view --json state,stateReason,closedAt,closedByPullRequestsReferences` | 63 ✗ | 211 ◐ | 63 ✗ |
| REST timeline (raw JSON) | 22,594 ✓ | 37,018 ◐ | 37,055 ◐ |
| **`gh-comments --toc`** | 412 ✓ | 505 ✓ | 548 ✓ |
| **`gh-comments --closure`** | 58 ◐ | 347 ✓ | 256 ✓ |

### The multiplier, revisited

How many times more tokens the alternative costs than the script's narrowest correct form for that task (>1× = script cheaper). SKILL.md is excluded here and treated in the break-even section.

```
open threads, cli#13946: REST inline vs --toc --unresolved              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓»  473.8×  REST can't answer
why closed, cli#14411: REST timeline vs --closure                       │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓    144.7×  REST names no closer (◐); --closure says none was recorded (✓)
open threads, cli#14104: REST inline vs --toc --unresolved              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓    125.5×  REST can't answer
one inline thread, cli#13946: naive vs TOC+slice                        │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓               22.3×  
read all, cli#14104: REST trio vs full                                  │▓▓▓▓▓▓▓▓▓▓▓▓                    9.2×  
read all, cli#13946: gh view + REST inline vs full                      │▓▓▓▓▓▓▓▓▓                       5.4×  
open threads, cli#14104: hand GraphQL vs --toc --unresolved             │▓▓▓▓                            2.0×  
read all, cli#14141: gh pr view vs full                                 │▓                               1.2×  
open bodies, cli#14104: hand GraphQL vs --unresolved                   ░│                                0.8×  --unresolved adds the review body, with 2 prose blockers
one comment, cli#13946: gh pr view --comments vs TOC+slice            ░░│                                0.7×  
one comment, cli#14483: expert vs TOC+slice                        ░░░░░│                                0.4×  the TOC grew by 3 xrefs from this repo's own issues since the last run
                                                            0.1         1           10          100  
                                                            ░ alternative cheaper    ▓ script cheaper (log scale)
```

### Break-even: does loading the skill pay for itself?

The two descriptions cost **530 tokens in every session**, whether or not either skill is used. Invoking a skill then adds its SKILL.md (2,074 for `pr-comments`, 1,745 for `issue-comments`). Against the realistic naive path for the same task:

| Task | naive tokens | skill flow + SKILL.md | net per invocation |
|---|--:|--:|--:|
| cli#14104 read all (naive: gh view + REST inline) | 67,570 | 12,654 | saves 54,916 |
| cli#14104 which threads open (naive: REST inline) | 59,629 | 2,549 | saves 57,080 |
| cli#13946 read all (naive: gh view + REST inline) | 43,666 | 11,906 | saves 31,760 |
| cli#13946 one inline thread (naive: gh view --comments + REST inline) | 41,606 | 3,941 | saves 37,665 |
| cli#13946 one top-level comment (naive: gh pr view --comments) | 1,333 | 4,106 | costs 2,773 |
| cli#14141 read all (naive: gh pr view) | 732 | 2,849 | costs 2,117 |
| cli#14411 read all (naive: gh issue view ×2) | 1,133 | 3,104 | costs 1,971 |
| cli#14483 one comment (naive: gh issue view --comments) | 772 | 2,194 | costs 1,422 |

```
net tokens per invocation (skill flow incl. SKILL.md vs naive)   ▓ saved  ░ spent
                              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  +54,916  cli#14104 read all
                              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ +57,080  cli#14104 which threads open
                              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓             +31,760  cli#13946 read all
                              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓           +37,665  cli#13946 one inline thread
                             ░│                             − 2,773  cli#13946 one top-level comment
                             ░│                             − 2,117  cli#14141 read all
                             ░│                             − 1,971  cli#14411 read all
                             ░│                             − 1,422  cli#14483 one comment
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
| raw JSON (gh api) | 600,979 | 269,459 | 2.23 | 1.8× |
| gh … view text | 47,407 | 18,212 | 2.60 | 1.5× |
| gh-comments output | 160,481 | 63,743 | 2.52 | 1.6× |
| skill files | 19,262 | 7,047 | 2.73 | 1.5× |

```
  raw JSON (gh api)        ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░ 2.23 bytes/token
  gh … view text           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░ 2.60 bytes/token
  gh-comments output       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░ 2.52 bytes/token
  skill files              ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░ 2.73 bytes/token
  the bytes ÷ 4 rule       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 4.00 bytes/token
```

### Wall-clock (one run each)

```
  gh pr view --comments           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░  1,145 ms
  REST pulls/N/comments           ▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░    563 ms
  GraphQL thread metadata         ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░    517 ms
  gh-comments (full)              ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  1,892 ms
  gh-comments --toc --unresolved  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░  1,315 ms
  gh issue view (cli#14411)       ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░    741 ms
  gh-comments (cli#14411)         ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░    880 ms
```

### Delta vs baseline

Tokens per output, this run against `../2026-10-09`, largest change first. Rows named `s_*`, `*_slice` and `FIX.*` are the script and skill outputs the fixes touch; the rest are raw `gh`/REST captures of live targets and move when GitHub does.

| Output | baseline | now | delta |
|---|--:|--:|--:|
| `I4.rest_tl` | 15,239 | 37,055 | +21,816 (+143%) |
| `I1.rest_tl` | 6,640 | 22,594 | +15,954 (+240%) |
| `I3.rest_tl` | 26,762 | 37,018 | +10,256 (+38%) |
| `FIX.issue_ref` | 988 | 1,273 | +285 (+29%) |
| `FIX.issue_skillmd` | 1,469 | 1,745 | +276 (+19%) |
| `I4.s_events` | 640 | 911 | +271 (+42%) |
| `I4.s_full` | 540 | 811 | +271 (+50%) |
| `I4.s_toc` | 277 | 548 | +271 (+98%) |
| `I1.s_events` | 762 | 955 | +193 (+25%) |
| `I1.s_full` | 712 | 905 | +193 (+27%) |
| `I1.s_toc` | 219 | 412 | +193 (+88%) |
| `I3.s_events` | 764 | 929 | +165 (+22%) |
| `I3.s_full` | 644 | 809 | +165 (+26%) |
| `I3.s_toc` | 340 | 505 | +165 (+49%) |
| `I2.s_events` | 748 | 797 | +49 (+7%) |
| `I2.s_full` | 698 | 747 | +49 (+7%) |
| `I2.s_toc` | 230 | 279 | +49 (+21%) |
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
| `FIX.pr_desc` | 278 | 278 | 0 (+0%) |
| `FIX.pr_ref` | 1,425 | 1,425 | 0 (+0%) |
| `FIX.pr_skillmd` | 2,074 | 2,074 | 0 (+0%) |
| `I1.gh_json_close` | 63 | 63 | 0 (+0%) |
| `I1.gh_view` | 612 | 612 | 0 (+0%) |
| `I1.gh_view_c` | 772 | 772 | 0 (+0%) |
| `I1.rest_ic` | 3,513 | 3,513 | 0 (+0%) |
| `I1.rest_issue` | 1,922 | 1,922 | 0 (+0%) |
| `I2.gh_json_close` | 212 | 212 | 0 (+0%) |
| `I2.gh_view` | 622 | 622 | 0 (+0%) |
| `I2.gh_view_c` | 0 | 0 | 0 |
| `I2.rest_ic` | 3 | 3 | 0 (+0%) |
| `I2.rest_issue` | 1,951 | 1,951 | 0 (+0%) |
| `I2.rest_tl` | 6,403 | 6,403 | 0 (+0%) |
| `I3.gh_json_close` | 211 | 211 | 0 (+0%) |
| `I3.gh_view` | 475 | 475 | 0 (+0%) |
| `I3.gh_view_c` | 671 | 671 | 0 (+0%) |
| `I3.rest_ic` | 3,732 | 3,732 | 0 (+0%) |
| `I3.rest_issue` | 2,102 | 2,102 | 0 (+0%) |
| `I4.gh_json_close` | 63 | 63 | 0 (+0%) |
| `I4.gh_view` | 434 | 434 | 0 (+0%) |
| `I4.gh_view_c` | 699 | 699 | 0 (+0%) |
| `I4.rest_ic` | 2,111 | 2,111 | 0 (+0%) |
| `I4.rest_issue` | 2,624 | 2,624 | 0 (+0%) |
| `O1.gh_view` | 1,836 | 1,836 | 0 (+0%) |
| `O1.gh_view_c` | 6,105 | 6,105 | 0 (+0%) |
| `O1.gql_meta` | 930 | 930 | 0 (+0%) |
| `O1.gql_open` | 2,126 | 2,126 | 0 (+0%) |
| `O1.rest_ic` | 1,563 | 1,563 | 0 (+0%) |
| `O1.rest_rc` | 59,629 | 59,629 | 0 (+0%) |
| `O1.rest_rv` | 16,891 | 16,891 | 0 (+0%) |
| `O1.s_full` | 8,502 | 8,502 | 0 (+0%) |
| `O1.s_latest` | 1,576 | 1,576 | 0 (+0%) |
| `O1.s_since` | 7,764 | 7,764 | 0 (+0%) |
| `O1.s_slr` | 1,576 | 1,576 | 0 (+0%) |
| `O1.s_toc` | 2,078 | 2,078 | 0 (+0%) |
| `O1.s_toc_unres` | 475 | 475 | 0 (+0%) |
| `O1.s_unres` | 2,614 | 2,614 | 0 (+0%) |
| `R1.gh_view` | 2,060 | 2,060 | 0 (+0%) |
| `R1.gh_view_c` | 1,333 | 1,333 | 0 (+0%) |
| `R1.gql_meta` | 781 | 781 | 0 (+0%) |
| `R1.gql_open` | 0 | 0 | 0 |
| `R1.rest_ic` | 1,051 | 1,051 | 0 (+0%) |
| `R1.rest_rc` | 40,273 | 40,273 | 0 (+0%) |
| `R1.rest_rv` | 10,707 | 10,707 | 0 (+0%) |
| `R1.s_full` | 8,147 | 8,147 | 0 (+0%) |
| `R1.s_latest` | 2,105 | 2,105 | 0 (+0%) |
| `R1.s_since` | 7,651 | 7,651 | 0 (+0%) |
| `R1.s_slr` | 2,105 | 2,105 | 0 (+0%) |
| `R1.s_toc` | 1,685 | 1,685 | 0 (+0%) |
| `R1.s_toc_unres` | 85 | 85 | 0 (+0%) |
| `R1.s_unres` | 85 | 85 | 0 (+0%) |
| `R2.gh_view` | 560 | 560 | 0 (+0%) |
| `R2.gh_view_c` | 1,024 | 1,024 | 0 (+0%) |
| `R2.gql_meta` | 226 | 226 | 0 (+0%) |
| `R2.gql_open` | 0 | 0 | 0 |
| `R2.rest_ic` | 2,558 | 2,558 | 0 (+0%) |
| `R2.rest_rc` | 4,981 | 4,981 | 0 (+0%) |
| `R2.rest_rv` | 4,367 | 4,367 | 0 (+0%) |
| `R2.s_full` | 1,153 | 1,153 | 0 (+0%) |
| `R2.s_latest` | 553 | 553 | 0 (+0%) |
| `R2.s_since` | 588 | 588 | 0 (+0%) |
| `R2.s_slr` | 588 | 588 | 0 (+0%) |
| `R2.s_toc` | 466 | 466 | 0 (+0%) |
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

New in this run: `I1.s_closure`, `I2.s_closure`, `I3.s_closure`, `I4.s_closure`

### Grade changes vs baseline

| Cell | baseline | now |
|---|:-:|:-:|
| `task7/s_toc/I3` | ◐ | ✓ |
| `task7/s_toc/I4` | ◐ | ✓ |

Graded in this run only: `task7/s_closure/I1`, `task7/s_closure/I3`, `task7/s_closure/I4`
