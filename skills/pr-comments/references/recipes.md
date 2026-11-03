# Reading a big PR from a dump, and checking a finding

Loaded on demand from the pr-comments skill: for a PR too big to read
inline, for many items at once, or before re-raising a finding.

## Slice a dump with grep/sed

Dump once to a temp file (never the repo) and read slices. Each item starts
at column 0 with a stable prefix
(`body`/`commit`/`comment`/`review`/`thread`/`force-push`), and
`<!-- finding:ID -->` markers are promoted onto thread header lines:

```bash
f="${TMPDIR:-/tmp}/pr.txt"
gh-comments <N> --pr > "$f"
grep '^commit \|^review \|^force-push' "$f"   # timeline skeleton
grep 'thread.*OPEN' "$f"                      # unaddressed inline threads
grep -A 30 '\[B-M1\]' "$f"                    # one finding + its discussion
grep -A 15 '^\(comment\|review\) *\[<user>' "$f"   # everything one reviewer said
```

## Verify a finding against the anchor SHA

Before re-raising anything, check what has touched the code since the thread
was anchored: the thread header carries that commit (`@0f5aef9`).

```bash
git diff <anchor-sha>..HEAD -- <thread-path>
```
