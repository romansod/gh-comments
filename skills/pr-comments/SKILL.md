---
name: pr-comments
description: >
  Read a GitHub PR's comments, reviews, and inline threads via the
  gh-comments tool instead of raw gh/API calls. Invoke BEFORE
  `gh pr view --comments`, `gh api .../comments|reviews`, or any GraphQL query
  that reads PR discussion. Use when the user says "address the review
  comments", "address the latest review", "what did reviewers say on PR N",
  "any unresolved review threads", or invokes /gh-comments:pr-comments <N>.
  For issues use
  issue-comments; both drive the same tool. The raw approaches are wrong,
  not merely costly: `gh pr view --comments` omits inline threads entirely
  (and off a TTY prints nothing on a PR with no comments), REST cannot see
  thread resolution state, and raw `gh api` without --paginate stops at 30.
---

You are executing the pr-comments skill.

## Invocation

```
/gh-comments:pr-comments <N>            — PR N in the current repo
/gh-comments:pr-comments                — the current branch's PR
/gh-comments:pr-comments <N> <o>/<r>    — PR N in another repo
```

(`/pr-comments …` where the skill directory is installed on its own rather
than as the gh-comments plugin.)

Also invoke implicitly whenever a task needs PR comments, reviews or review
threads — reviewing feedback, addressing findings, checking what is open.

## The command

```bash
gh-comments <N> --pr [flags]
```

`gh comments <N> --pr` is the same command where gh-comments is installed as
a GitHub CLI extension. `--pr` pins the target to a pull request: a number
that turns out to be an issue is refused with its title, never rendered as
the wrong thing. With no `<N>` it uses the current branch's PR.

Flags:
- `-R owner/name` — another repo (default: the cwd's).
- `--toc` — one line per item, no bodies.
- `--unresolved` — only reviews with open threads, and those threads.
- `--latest[=<user>]` — the last substantive review or top-level comment
  (optionally by `<user>`) and everything after it. A bare approval, a
  hidden comment, or a bot (without `--bots`) is not the anchor; the first
  two still render if later.
- `--since-last-review[=<user>]` — the last review *object* and everything
  after it; never looks at comments. Exclusive with `--latest`.
- `--since YYYY-MM-DD[THH:MM[:SS]][Z]` — a time window, UTC.
- `--bots`, `--merges`, `--hidden` — include bot items, merge commits, and
  the bodies of hidden (minimized) comments; all three are filtered by
  default. The counts header says how many bot and hidden items were;
  merge commits are dropped silently.

When `--latest` or `--since-last-review` matches nothing, the output is the
TOC under a note saying so, not the full timeline — unless `--unresolved` or
`--since` already narrows the view, in which case that view is shown as it
is and the note names it.

It renders the whole timeline — commits, reviews with their inline threads
nested in place, comments, force-pushes — paginated, with thread resolution
state. Do not supplement it with `gh pr view --comments` or
`gh api .../comments`; it already covers those surfaces.

## Steps

1. **Orient with the TOC** — always safe to read inline:

   ```bash
   gh-comments <N> --pr --toc
   ```

   A counts header (`reviews: N · inline threads: N (N open) · top-level
   comments: N`, with what was filtered stated), then one line per commit,
   review, thread and comment.

2. **Take the narrowest view that answers the question:**
   - Structural facts (who reviewed, which threads are `OPEN`) — the TOC is
     the answer. Never conclude from a `… [+N chars]` preview: it is a cut,
     not a summary. Findings pasted as top-level prose are invisible to
     thread state; `(0 open)` speaks only for review threads.
   - "Which threads are still open" — `--toc --unresolved`. The cheapest
     correct answer, and it keeps the position of outdated threads that a
     hand-written query loses (`line` is null there; only `originalLine`
     has it).
   - "What do the open threads say" — `--unresolved`, an order of magnitude
     more. Reach for it once you need the discussion, not to learn whether
     there is any.
   - "Address the latest review" — `--latest`. A time window — `--since`.
   - Small PR — the full render, inline. Big PR, or repeated consultation —
     dump once to a temp file (never the repo) and read slices.

3. **Slice with grep/sed** — every item starts at column 0 with a stable
   prefix (`body`/`commit`/`comment`/`review`/`thread`/`force-push`), and
   `<!-- finding:ID -->` markers are promoted onto thread header lines:

   ```bash
   grep '^commit \|^review \|^force-push' pr.txt   # timeline skeleton
   grep 'thread.*OPEN' pr.txt                      # unaddressed inline threads
   grep -A 30 '\[B-M1\]' pr.txt                    # one finding + its discussion
   grep -A 15 '^\(comment\|review\) *\[<user>' pr.txt   # everything one reviewer said
   ```

4. **Verify findings against the anchor SHA** on the thread header
   (`@0f5aef9`) before re-raising anything:

   ```bash
   git diff <anchor-sha>..HEAD -- <thread-path>
   ```

## Reading the output

The markers — `OPEN`/`resolved`/`outdated`, `[TRUNCATED …]`, `(hidden: …)`,
`threads in filtered bot reviews:`, the reply-wrapper discrepancy, what a
slice cannot show — are explained in
[references/output.md](references/output.md). Load it only when one of them
bears on the task.
