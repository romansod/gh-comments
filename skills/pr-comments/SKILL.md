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

Invoked as `/gh-comments:pr-comments [<N> [<owner>/<repo>]]` (no `<N>`: the
current branch's PR), or whenever a task needs a PR's comments or reviews.

## The command

```bash
gh-comments <N> --pr [flags]    # or: gh comments <N> --pr
```

`--pr` refuses an issue number; `-R owner/name` reads another repo. It
prints the whole paginated timeline, threads nested in their reviews with
their resolution state, so never add `gh pr view --comments` or `gh api`.

## Steps

1. **Orient with the TOC**, always safe inline: `gh-comments <N> --pr --toc`.
   A counts header, then one line per commit, review, thread and comment.
   For one item, `--toc --only <kind>` is the TOC to start from.
2. **Take the narrowest view that answers the question:**

   | question | flags |
   |---|---|
   | who reviewed, what is there | the TOC |
   | which threads are still open | `--toc --unresolved` |
   | what the open threads say | `--unresolved` |
   | address the latest review | `--latest` (`=<user>` for one reviewer) |
   | what happened since a date | `--since YYYY-MM-DD` |
   | one comment, review or thread | `--toc --only <kind>`, then `--item` |
   | a small PR, everything | no flags |

   `--item` takes the start of the item's TOC line:
   `--item 'comment [alice 2026-09-21 12:47]'`.

3. **Before concluding:** a `… [+N chars]` preview is a cut, never a
   summary. `(0 open)` speaks only for review threads: findings posted as
   top-level prose are invisible to thread state, so read the comments too.

## Load when needed

- [references/flags.md](references/flags.md), every flag and how the
  slices anchor: for a flag not in the table, or a view that surprised you.
- [references/recipes.md](references/recipes.md), grep over a dump and the
  anchor-SHA check: for a PR too big to read inline, or before re-raising
  a finding.
- [references/output.md](references/output.md), what the markers mean
  (`outdated`, `[TRUNCATED …]`, `(hidden: …)`, the counts): when one bears
  on the task.
