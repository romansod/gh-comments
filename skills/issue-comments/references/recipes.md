# Reading a long issue from a dump, and acting on one

Loaded on demand from the issue-comments skill: for an issue too long to
read inline, or before acting on what an issue describes.

## Slice a dump with grep/sed

Dump once to a temp file (never the repo) and read slices. Each item starts
at column 0 with a stable prefix
(`body`/`comment`/`closed`/`reopened`/`xref`/`renamed`, plus
`label`/`assign`/`milestone` under `--events`):

```bash
gh-comments <N> --issue > "${TMPDIR:-/tmp}/issue.txt"
grep '^xref\|^closed\|^reopened' "${TMPDIR:-/tmp}/issue.txt"   # what happened to it
grep -A 15 '^comment \[<user>' "${TMPDIR:-/tmp}/issue.txt"     # everything one person said
sed -n '1,40p' "${TMPDIR:-/tmp}/issue.txt"                     # the opening post, no refetch
```

## Before acting on an issue, check the cross-references

The `closed … by #N` line is authoritative for what closed it. An `xref`
line marked `(closes)` only names a PR that claimed the issue; `MERGED` on
it means the work may already be done — `gh pr diff <xref-number>` shows
what it changed.
