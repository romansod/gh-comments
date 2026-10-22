# Reading gh-comments output for an issue

Loaded on demand from the issue-comments skill. Every item starts at column 0
with a stable prefix; the notes below explain what the markers mean and which
ones change what you should do.

## The header and counts

- The header line carries state and, when GitHub set one, the state reason:
  `[CLOSED completed]` is finished work, `[CLOSED not_planned]` is a decision
  not to do it, `[OPEN reopened]` means it came back. Labels and assignees
  follow when present; `labels:a,b (+5 more)` means the label list was cut,
  and everything else in the header is complete.
- The counts line is authoritative: `comments: 3 (+1 bot filtered) (1
  hidden)` means four comments exist, three are rendered, and one of those
  three is a marker without a body. `(incl. N bot)` appears when `--bots`
  puts the bot comments back; `(N hidden)` reads the same under `--hidden`,
  which only adds the bodies.
- **`events: N (+M housekeeping filtered)` is the one to read carefully.**
  Label, assignee and milestone churn is held back by default because it
  buries the events that change meaning; pass `--events` if the task is
  about triage state.
- `--bots` hides bot *comments* only. Timeline events are never filtered by
  author, so a stale bot's `closed` line and a Dependabot `xref` are in the
  default view — usually they are the answer to why the issue ended.

## Items

- `body` is the opening post — the issue itself. It is always shown,
  including under `--since`, which narrows the discussion rather than what
  is being discussed.
- `… [+N chars]` on a TOC line means the body continues for N more
  characters — a preview cut mid-comment, never a summary.
- `(hidden: <reason>)` marks a comment GitHub has minimized (outdated, spam,
  resolved, off-topic, duplicate). Its body is withheld by default; `--hidden`
  shows it. Treat it as stale unless the task is about why it was hidden.
- `xref` lines name the referencing PR or issue, its state and its title; a
  cross-repo reference is qualified as `owner/repo#N`, a same-repo one as
  plain `#N`. `(closes)` means the PR declared it would close this issue (a
  closing keyword); whether it did is on the `closed` line.
- `closed … as <reason>` / `reopened` are the events that end or revive the
  issue. The `closed` line ends with what closed it, as GitHub recorded it:
  `by #N PR MERGED "title"` (a PR in another repository is `owner/name#N`),
  `by commit <sha>` (`by commit owner/name@<sha>` for a commit in another
  repository), `by a project` (a Projects workflow closed it; naming
  the project needs the `read:project` scope, which the query does not ask
  for), `, no closer recorded`, or `, closer not visible to this token`.
  `no closer recorded` states only that the API returned null — an issue
  closed by hand reads so, and so may one whose closer GitHub withheld
  without saying so — so never turn it into "closed by hand", and never
  infer the closer from an `xref (closes)` line: that is the PR's claim,
  not the record. `not visible` is the case where GitHub did say so: it
  answered that one field with an access error for this token (a closer in
  a repository it cannot read, or a project it cannot see) and the rest of
  the issue rendered; a token with access would see the closer. Under `--closure` those lines, the
  `reopened` lines and the PR `xref` lines are the whole output.
- `renamed` shows both titles — useful when the scope drifted and the early
  comments answer a different question than the current title asks.
- A deleted account renders as `ghost`. Rich-text HTML pastes are converted
  to markdown; HTML inside a code fence is left alone. Timestamps are UTC.

## Not fetched

Pin, lock, transfer, duplicate and sub-issue events. If the task genuinely
turns on one of those, fall back to
`gh api repos/<o>/<r>/issues/<N>/timeline`.
