# gh-comments

Read a GitHub pull request's or issue's discussion as compact, grep-friendly
text: reviews with their inline threads nested in place and marked
`OPEN`/`resolved`, top-level comments, commits, force-pushes, and on an issue
the events that explain it — who closed it, why, and which PR references it.
One command, one paginated fetch, output an agent or a human can slice with
`grep`.

## The problem

`gh pr view --comments` shows top-level comments and review summaries. It
omits inline review threads entirely, and nothing in the REST API can tell
you whether a thread was resolved. So "which review comments are still open"
has no answer short of a hand-written GraphQL query — and a hand-written
`reviewThreads { path line }` query silently reports no location for every
outdated thread, because `line` is null there and only `originalLine` has it.

On a real PR, [cli/cli#14104](https://github.com/cli/cli/pull/14104), the
difference looks like this.

`gh pr view 14104 -R cli/cli --comments` begins with a bot review's summary
table and never mentions a single inline thread:

```
author:	Copilot (AI)
association:	contributor
edited:	false
status:	commented
--
## Pull request overview

This draft PR continues the `api_host` rollout by moving remaining direct …
```

`gh-comments 14104 -R cli/cli --toc` is one line per item, every thread in
its review, with its state and the commit it was anchored to:

```
PR #14104 Honour api_host across the CLI, and give api.Client a flexible request surface [MERGED base:trunk]
reviews: 5 (+1 bot filtered) · inline threads: 17 (7 open) · top-level comments: 1

body [williammartin 2026-08-07 15:20] Relates to https://github.com/cli/cli/issues/13717 Fixes https://githu… [+3.7k chars]
force-push  7366aab..9869df6  [2026-08-07 15:45]
review  [williammartin 2026-08-07 18:26] COMMENTED, 2 threads (2 open)
thread  api/http_client.go:19 OPEN @ec71021
thread  docs/api-host-test-harness.md:71 OPEN,outdated @e511aa0
review  [babakks 2026-08-14 14:33] CHANGES_REQUESTED, 13 threads (3 open) Thanks for this, @williammartin! :pray: First off, real appreciation f… [+3.4k chars]
thread  internal/config/config.go:361 resolved,outdated @9869df6
thread  internal/config/auth_config_test.go:1025 resolved @9869df6
…
thread  pkg/cmd/repo/delete/delete_test.go:199 OPEN @9869df6
…
review  [babakks 2026-08-28 12:49] APPROVED, 0 threads (0 open) LGTM
commit  c219743 Add acceptance coverage for gist
…
```

And `gh-comments 14104 -R cli/cli --toc --unresolved` is the answer to "what
is still open", including the thread a filtered bot review holds:

```
PR #14104 Honour api_host across the CLI, and give api.Client a flexible request surface [MERGED base:trunk]
reviews: 5 (+1 bot filtered) · inline threads: 17 (7 open) · top-level comments: 1

review  [williammartin 2026-08-07 18:26] COMMENTED, 2 threads (2 open)
thread  api/http_client.go:19 OPEN @ec71021
thread  docs/api-host-test-harness.md:71 OPEN,outdated @e511aa0
review  [babakks 2026-08-14 14:33] CHANGES_REQUESTED, 13 threads (3 open) Thanks for this, @williammartin! :pray: First off, real appreciation f… [+3.4k chars]
thread  pkg/cmd/repo/delete/delete_test.go:199 OPEN @9869df6
thread  api/client.go:229 OPEN @9869df6
thread  pkg/cmd/auth/shared/oauth_scopes.go:33 OPEN @9869df6
review  [2cs2vprhyf-creator 2026-08-28 11:59] COMMENTED, 1 thread (1 open)
thread  acceptance/scriptfilter_unit_test.go:1 OPEN @c8ed76f
threads in filtered bot reviews:
thread  pkg/cmd/api/http.go:163 OPEN @9869df6
```

Drop `--toc` for the bodies. Issues get the same treatment: `gh issue view
--comments` shows no timeline events, so it cannot say who closed an issue or
which PR did; `gh-comments <N>` renders `closed`, `reopened`, `xref` and
`renamed` lines in order, with label and assignee churn held back unless you
ask for it.

## How it compares

Measured in exact Claude tokens on the same PR, cli/cli#14104, with
`gh-comments` v1.0.0:

| Approach | Read the whole discussion | Which threads are still open |
|---|--:|--:|
| `gh pr view --comments` | 6,105, no inline threads | 6,105, cannot tell |
| REST API, raw JSON | 78,083, no open or resolved state | 59,629, cannot tell |
| hand-written GraphQL | | 930 |
| `gh-comments` | 8,502, all 17 threads | 475 with `--toc --unresolved`, 7 of 7 |

The Claude Code plugin costs 530 tokens in every session for its two skill
descriptions, and about 1,500 to 2,100 more when a skill runs. On a PR or
issue with little discussion, plain `gh` is cheaper once that is counted.
[BENCHMARKS.md](BENCHMARKS.md) has the method, nine targets and seven tasks,
and where the tool does and does not pay.

## Install

Requirements: `zsh`, `jq`, and an authenticated [GitHub CLI](https://cli.github.com)
(`gh auth login`). macOS has zsh; on Linux install it from your package
manager.

**As a GitHub CLI extension** — the command becomes `gh comments`:

```bash
gh extension install romansod/gh-comments
gh comments 123            # PR or issue 123 in the current repo
gh comments 123 --pr       # ...and error out if it is not a PR
```

**As a Claude Code plugin** — two skills (`pr-comments`, `issue-comments`)
that know when to reach for the tool, plus the `gh-comments` command on the
Bash tool's `PATH` while the plugin is enabled:

```bash
claude plugin marketplace add romansod/gh-comments
claude plugin install gh-comments@gh-comments
```

Then "what did reviewers say on PR 123" or "why was issue 45 closed" runs it.
The skills use only the portable [Agent Skills](https://agentskills.io)
frontmatter, so the same `skills/` directories work in other agents that
read that format; those need `gh-comments` on `PATH` (next route).

**Manually** — clone and put the executable on `PATH` under any name:

```bash
git clone https://github.com/romansod/gh-comments ~/.local/share/gh-comments
ln -s ~/.local/share/gh-comments/gh-comments ~/.local/bin/gh-comments
```

Diagnostics carry the name you link it as, so `ln -s … ~/.local/bin/r-gh-comments`
reports as `r-gh-comments`.

## Usage

```
gh-comments [<number>] [flags]
```

The resource type is resolved, never guessed: a repository numbers issues and
pull requests in one sequence, so `<number>` names exactly one of them and the
`issueOrPullRequest` GraphQL field says which. Pin it with `--pr` / `--issue`
when you want a wrong number to be an error rather than a different render.
With no number, the current branch's open PR is used.

```
  -R, --repo <owner/name>       Target repo (default: repo of the cwd); needs a number
  --pr, --issue                 Pin the resource type instead of resolving it
  --toc                         Skeleton only: one line per item, no bodies
  --since <iso-date>            Only items at/after this date (UTC): YYYY-MM-DD,
                                optionally with THH:MM[:SS][Z] (e.g. 2026-08-12)
  --bots                        Include bot comments and bot review bodies
                                (filtered by default). Threads are never
                                filtered: those of a filtered bot review render
                                under "threads in filtered bot reviews:".
                                Timeline events are never filtered by author —
                                a bot closing an issue is still why it closed.
  --hidden                      Show the bodies of hidden (minimized) comments.
                                By default a comment hidden as outdated, spam,
                                resolved, off-topic or duplicate renders as a
                                single marker line, e.g.
                                `comment [user date] (hidden: outdated)`, and
                                the counts line reports `(N hidden)`.

  Pull requests only:
  --unresolved                  Only reviews with open threads, and those threads
  --since-last-review[=<user>]  Only the last review (optionally by <user>)
                                and everything after it
  --latest[=<user>]             Only the most recent *substantive* review or
                                top-level comment (optionally by <user>) and
                                everything after it. Substantive: a review with
                                a body or inline threads, or a comment with a
                                body that is not hidden — so a bare approval
                                or a hidden comment is looked past as the
                                anchor, though it still shows when it comes
                                after the anchor; a bot is looked past and
                                not shown unless --bots. Exclusive with
                                --since-last-review, which anchors on the last
                                review object and ignores comments.
                                When either flag matches nothing, the TOC is
                                shown instead of the full timeline, under a
                                note saying so; with --unresolved or --since
                                that already-narrow view is shown as it is.
  --merges                      Include merge commits (filtered by default)

  Issues only:
  --events                      Include label / assignee / milestone events
                                (filtered by default; the counts line always
                                states how many were held back)

  --fixtures <tl.json> [<th.json>]
                                Render from saved GraphQL payloads instead of
                                fetching (testing/offline). Each file holds the
                                `gh api graphql --paginate ... | jq -s .` output
                                for the timeline / threads query. The threads
                                payload is required for a PR, meaningless for
                                an issue.
  -h, --help                    This help
  --version                     Print the version
```

A flag that only the other type can honour is an error, not a no-op:
`--unresolved` on an issue, `--events` on a PR. Ignoring it would report a
filtered view as a complete one.

### Reading the output

Every item starts at column 0 with a stable prefix, so the output greps:

```bash
gh-comments 989 > pr.txt
grep '^review \|^commit' pr.txt      # the timeline skeleton
grep 'thread.*OPEN' pr.txt           # unaddressed inline threads
grep -A 20 '\[B-M1\]' pr.txt         # one finding with its thread
grep '^xref\|^closed' issue.txt      # what happened to an issue
```

The counts line under the header is authoritative and says what the default
view held back: `(+2 bots filtered)`, `(1 hidden)`, `(+4 housekeeping
filtered)`. Thread headers carry `OPEN`/`resolved`, `outdated` when the code
under them has changed since, the anchoring commit as `@<sha>` (so
`git diff <sha>..HEAD -- <path>` shows what touched the code), and a loud
`[TRUNCATED: showing N of M replies]` when a thread outgrew one page.
`<!-- finding:ID -->` markers in thread comments are promoted onto the thread
header line. Rich-text HTML pastes are converted to markdown. The full key to
the markers is in the skills' reference files:
[pull requests](skills/pr-comments/references/output.md) and
[issues](skills/issue-comments/references/output.md).

### Known limits

- A slice (`--since-last-review`, `--latest`) shows its anchor and everything
  after it. A newer reply nested under an older review's thread is outside
  the slice; `--unresolved` is the flag for "what is still open regardless
  of age".
- Reviews GitHub has minimized are not yet marked the way comments are; their
  bodies render in full.
- Pin, lock, transfer, duplicate and sub-issue events are not fetched.
- Timestamps are UTC. A deleted account renders as `ghost`.

## Development

`make check` runs the offline suite twice — plain and under a pty — plus
lint. See [CONTRIBUTING.md](CONTRIBUTING.md) for the golden-file workflow and
the fixture rules.

## License

[MIT](LICENSE).
