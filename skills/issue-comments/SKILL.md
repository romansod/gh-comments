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

Invoked as `/gh-comments:issue-comments <N> [<owner>/<repo>]`, or whenever a
task needs an issue's discussion: picking up its work, what was decided,
why it closed, which PR addressed it.

## The command

```bash
gh-comments <N> --issue [flags]    # or: gh comments <N> --issue
```

`--issue` refuses a PR number; `-R owner/name` reads another repo. It
prints the body, comments and timeline events (closes, cross-references,
renames) that `gh issue view` does not.

## Steps

1. **Orient with the TOC**, always safe inline:
   `gh-comments <N> --issue --toc`. A counts header, then the opening post
   and one line per comment and event.
2. **Take the narrowest view that answers the question:**

   | question | flags |
   |---|---|
   | is it closed, which PR references it | the TOC |
   | why it closed, and by what | `--closure` |
   | one comment | `--toc --only comment`, then `--item` |
   | what changed since a date | `--since YYYY-MM-DD` |
   | most issues: everything | no flags |

   `--item` takes the start of the item's TOC line:
   `--item 'comment [alice 2026-09-21 12:47]'`.

3. **Before concluding:** a `… [+N chars]` preview is a cut, never a
   summary. The `closed` line is the record of what closed it; an `xref`
   marked `(closes)` is only a PR's claim. `no closer recorded` means the
   API returned null, never "closed by hand" on its own.

## Load when needed

- [references/flags.md](references/flags.md), every flag: for a flag not in
  the table, or a view that surprised you.
- [references/recipes.md](references/recipes.md), grep over a dump and the
  cross-reference check: for an issue too long to read inline, or before
  acting on one.
- [references/output.md](references/output.md), what the markers mean (the
  state reason, the counts, `closed … by`, `(hidden: …)`): when one bears on
  the task.
