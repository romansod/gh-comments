# gh-comments flags for a pull request

Loaded on demand from the pr-comments skill, when the task needs a flag
beyond the skill's question → flag table, or a view printed something
unexpected.

```bash
gh-comments <N> --pr [flags]
```

`gh comments <N> --pr` is the same command where gh-comments is installed as
a GitHub CLI extension; `/pr-comments …` invokes the skill where its
directory is installed on its own rather than as the gh-comments plugin.
`--pr` pins the target to a pull request: a number that turns out to be an
issue is refused with its title, never rendered as the wrong thing. With no
`<N>` it uses the current branch's PR.

- `-R owner/name` — another repo (default: the cwd's; needs `<N>`, since "no
  number" means the cwd branch's PR).
- `--toc` — one line per item, no bodies.
- `--only <kind>[,<kind>...]` — only those kinds: `comment`, `body`,
  `review`, `thread`, `commit`, `force-push`. With `--toc` or the full
  render; the counts header is unchanged.
- `--item '<TOC line prefix>'` — exactly one item, whole: a comment, a
  review with its threads, or a thread with its replies. No match, or
  several (listed), is an error; copy more of the line. Takes no other view
  flag but `--hidden`, which must match the `--toc` the line came from.
- `--unresolved` — only reviews with open threads, and those threads. With
  `--toc` it is the cheapest correct answer to which threads are open, and
  it keeps the position of outdated threads that a hand-written query loses
  (`line` is null there; only `originalLine` has it).
- `--latest[=<user>]` — the last substantive review or top-level comment
  (optionally by `<user>`) and everything after it. A bare approval, a
  hidden comment, a review with no body that is not hidden and no thread
  with a comment that is not hidden or with replies past the fetched page
  (with or without `--hidden`), or a bot (without `--bots`) is not the
  anchor; the first three still render if later.
- `--since-last-review[=<user>]` — the last review *object* and everything
  after it, passing over a hidden review with no visible thread comment and
  no thread with replies past the fetched page; never looks at comments.
  Exclusive with `--latest`.
- `--since YYYY-MM-DD[THH:MM[:SS]][Z]` — a time window, UTC.
- `--bots`, `--merges`, `--hidden` — include bot items, merge commits, and
  the bodies of hidden (minimized) comments and reviews; all three are
  filtered by default. The counts header says how many bot and hidden items
  were; merge commits are dropped silently.

When `--latest` or `--since-last-review` matches nothing, the output is the
TOC under a note saying so, not the full timeline — unless `--unresolved` or
`--since` already narrows the view, in which case that view is shown as it
is and the note names it.
