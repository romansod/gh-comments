# Reading a long issue from a dump, and acting on one

Loaded on demand from the issue-comments skill: for an issue too long to
read inline, or before acting on what an issue describes.

## Slice a dump with grep/sed

Dump once to a temp file (never the repo) and read slices. Each item starts
at column 0 with a stable prefix
(`body`/`comment`/`closed`/`reopened`/`xref`/`renamed`, plus
`label`/`assign`/`milestone` under `--events`):

```bash
f="${TMPDIR:-/tmp}/issue.txt"
gh-comments <N> --issue > "$f"
grep '^xref\|^closed\|^reopened' "$f"   # what happened to it
grep -A 15 '^comment \[<user>' "$f"     # everything one person said
sed -n '1,40p' "$f"                     # the opening post, no refetch
```

## Before acting on an issue, check the cross-references

The `closed … by #N` line is authoritative for what closed it. An `xref`
line marked `(closes)` only names a PR that claimed the issue; `MERGED` on
it means the work may already be done — `gh pr diff <xref-number>` shows
what it changed.
