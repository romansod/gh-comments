# Reading gh-comments output for a pull request

Loaded on demand from the pr-comments skill. Every item starts at column 0
with a stable prefix; the notes below explain what the markers on those lines
mean and which ones change what you should do.

## The header and counts

- The counts line is authoritative and pre-filter. `inline threads: 0` means
  the PR has no thread machinery at all (all discussion is top-level), which
  is different from `inline threads: N (0 open)` (all resolved).
- `(+N bot filtered)` says how many lines the default view held back;
  `(incl. N bot)` appears when `--bots` puts them back. `(N hidden)` is
  different: those lines *are* rendered, as markers without a body, and the
  number already counts them — so it matches a count of `comment` lines, and
  reads the same under `--hidden`. Merge commits are filtered silently unless
  `--merges`.
- A REST review count higher than the number of `review` lines is expected,
  not data loss: the empty review object GitHub creates when someone replies
  inside a thread never appears in the timeline; its comment surfaces inside
  the thread it answers.

## The opening post

- `body` is the PR description, rendered first. It is what the author says
  the change does, which is not always what the diff does — a claim to check,
  not a finding. On a PR whose description was never written it is a bare
  header line. It is omitted under `--unresolved`, which renders threads only.

## Threads

- `OPEN` (uppercase) means unaddressed; `resolved` means a reviewer resolved
  it — do not re-litigate resolved threads.
- `outdated` means the code under the thread changed since; the fix likely
  already landed — verify with the anchor-SHA diff before re-raising.
- `@<sha>` on a thread header is the commit the thread was anchored to;
  `git diff <sha>..HEAD -- <path>` shows what has touched the code since.
- `[TRUNCATED: showing N of M replies]` means the reply list is incomplete —
  fetch that thread's remaining replies via the API if they matter.
- `threads with no parent review:` holds threads opened outside any review.
  `threads in filtered bot reviews:` holds the threads of a bot review that
  the default view filtered; with `--bots` they nest under their review
  instead. Threads are never filtered, whoever opened them.

## Comments

- `… [+N chars]` on a TOC line means the body continues for N more
  characters — a preview cut mid-comment, never a summary.
- `(hidden: <reason>)` marks a comment GitHub has minimized (outdated, spam,
  resolved, off-topic, duplicate). Its body is withheld by default; `--hidden`
  shows it. Treat it as stale unless the task is about why it was hidden.
- Commits are interleaved at their timeline position: a fix commit right after
  a review is usually the response to it.

## Slices

- `--since-last-review` and `--latest` are a window from the anchor on, and
  nothing before it: timeline items from the anchor, a filtered bot review's
  threads when that review sits after the anchor, an orphan thread when one
  of its comments is dated at or after it. `--unresolved` keeps the same
  window, so with a slicing flag it can omit open threads the header still
  counts (and says so). A newer reply nested under an *older* review's
  thread is outside the slice and will not appear. For "everything still
  open regardless of age" use `--unresolved` without a slicing flag.
  (`--since` does include old reviews whose threads received replies in the
  window.)
- `note: no matching … — showing the TOC instead` means the anchor was not
  found; what follows is exactly the `--toc` output.

## Misc

- Rich-text HTML pastes are converted to markdown; HTML inside a code fence
  is left alone.
- A deleted account renders as `ghost`.
- Timestamps are UTC.
