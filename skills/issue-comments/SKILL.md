---
name: issue-comments
description: >
  Read a GitHub issue's body, comments, and timeline via the gh-comments
  tool instead of raw gh/API calls. Invoke BEFORE `gh issue view
  [--comments]`, `gh api .../issues/N/comments`, or any GraphQL query that
  reads issue discussion. Use when the user says "what's on issue N", "catch
  me up on issue N", "why was issue N closed", "what PR closed issue N",
  "what's left on issue N", or invokes /gh-comments:issue-comments <N>.
  `gh issue view
  --comments` shows no timeline events — it cannot say who closed the issue,
  why, or which PR references it — and off a TTY omits the issue body. For
  pull requests use pr-comments; both drive the same tool.
---

You are executing the issue-comments skill.

## Invocation

```
/gh-comments:issue-comments <N>            — issue N in the current repo
/gh-comments:issue-comments <N> <o>/<r>    — issue N in another repo
```

(`/issue-comments …` where the skill directory is installed on its own
rather than as the gh-comments plugin.)

Also invoke implicitly whenever a task needs an issue's discussion — picking
up work it describes, checking what was decided, finding out why it was
closed, or seeing which PR already addressed it.

## The command

```bash
gh-comments <N> --issue [flags]
```

`gh comments <N> --issue` is the same command where gh-comments is installed
as a GitHub CLI extension. `--issue` is optional — the tool resolves the type
from the API, since a repository numbers issues and PRs in one sequence — but
pass it when you *know* it should be an issue: a number that turns out to be
a PR is then refused by name, not rendered as a PR dump you did not ask for.

Flags: `-R owner/name`; `--toc` (one line per item, no bodies);
`--since YYYY-MM-DD[THH:MM[:SS]][Z]` (UTC); `--bots`, `--hidden`,
`--events` (include bot comments, the bodies of hidden comments, and
label/assignee/milestone events; all filtered by default, and the counts
header says how many were).
The PR-only flags (`--unresolved`, `--since-last-review`, `--latest`,
`--merges`) are an error on an issue, not a no-op.

## Steps

1. **Orient with the TOC** — always safe to read inline:

   ```bash
   gh-comments <N> --issue --toc
   ```

   A counts header (`comments: N · cross-refs: N · events: N`, with what was
   filtered stated), then the opening post and one line per comment and
   event.

2. **Take the narrowest view that answers the question:**
   - Structural facts (is it closed, who closed it, which PR references it,
     how many people weighed in) — the TOC is the answer. Never conclude from
     a `… [+N chars]` preview: it is a cut, not a summary.
   - Most issues are small — if the TOC fits on a screen, the full render,
     inline. There is no thread machinery to explode.
   - A long issue — `--since <date>` for "what changed this week", or dump
     once to a temp file (never the repo) and read slices.

3. **Slice with grep/sed** — every item starts at column 0 with a stable
   prefix (`body`/`comment`/`closed`/`reopened`/`xref`/`renamed`, plus
   `label`/`assign`/`milestone` under `--events`):

   ```bash
   grep '^xref\|^closed\|^reopened' issue.txt   # what happened to it
   grep -A 15 '^comment \[<user>' issue.txt     # everything one person said
   sed -n '1,40p' issue.txt                     # the opening post, no refetch
   ```

4. **Before acting on an issue, check the cross-references.** An `xref` line
   marked `(closes)` names a PR that claimed the issue; `MERGED` on it means
   the work may already be done — `gh pr diff <xref-number>` shows what it
   changed.

## Reading the output

The header's state reason, the counts line, `xref`/`renamed`/`closed` lines,
`(hidden: …)`, housekeeping events and what is never fetched are explained
in [references/output.md](references/output.md). Load it only when one of
them bears on the task.
