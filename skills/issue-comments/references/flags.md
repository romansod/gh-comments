# gh-comments flags for an issue

Loaded on demand from the issue-comments skill, when the task needs a flag
beyond the skill's question → flag table, or a view printed something
unexpected.

```bash
gh-comments <N> --issue [flags]
```

`gh comments <N> --issue` is the same command where gh-comments is installed
as a GitHub CLI extension; `/issue-comments …` invokes the skill where its
directory is installed on its own rather than as the gh-comments plugin.
`--issue` is optional — the tool resolves the type from the API, since a
repository numbers issues and PRs in one sequence — but pass it when you
*know* it should be an issue: a number that turns out to be a PR is then
refused by name, not rendered as a PR dump you did not ask for.

- `-R owner/name` — another repo.
- `--toc` — one line per item, no bodies.
- `--only <kind>[,<kind>...]` — only those kinds: `comment`, `body`, `xref`,
  `closed`, `reopened`, `renamed`; the counts header is unchanged.
- `--item '<TOC line prefix>'` — exactly one item, whole; no match, or
  several, listed, is an error; takes no other view flag but `--hidden`,
  which must match the `--toc` the line came from.
- `--closure` — why it was closed and by what: the header, the
  `closed`/`reopened` lines with their closer, and the PR cross-references,
  nothing else; refused on an issue never closed, and takes no other view
  flag.
- `--since YYYY-MM-DD[THH:MM[:SS]][Z]` — a time window, UTC.
- `--bots`, `--hidden`, `--events` — include bot comments, the bodies of
  hidden comments, and label/assignee/milestone events; all filtered by
  default, and the counts header says how many were.

The PR-only flags (`--unresolved`, `--since-last-review`, `--latest`,
`--merges`) are an error on an issue, not a no-op.
