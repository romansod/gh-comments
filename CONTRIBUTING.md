# Contributing

## Layout

```
gh-comments                       the implementation, one zsh script
bin/gh-comments                   → ../gh-comments, for the Claude Code plugin
skills/pr-comments/               Claude Code / Agent Skills: pull requests
skills/issue-comments/            same, for issues; each has references/output.md
.claude-plugin/plugin.json        the plugin manifest
.claude-plugin/marketplace.json   the one-entry marketplace that serves it
tests/                            run.zsh, lib.zsh, run-pty.py, test-*.zsh, fixtures/
bench/                            the token benchmark: scripts, targets.json, runs/<date>/
BENCHMARKS.md                     its results
```

The script is the repository root's `gh-comments` because a GitHub CLI
extension needs an executable of exactly that name there; `bin/gh-comments`
is a symlink to it because a Claude Code plugin puts `bin/` on the Bash
tool's `PATH`.

## Checks

```bash
make check      # lint, the suite, then the same suite under a pty
```

- `make lint`: `zsh -n` on the script and the benchmark scripts, a syntax
  check of `tests/run-pty.py` and the benchmark's Python,
  a check that `VERSION=` in the script matches `.claude-plugin/plugin.json`,
  and `claude plugin validate --strict .` when the `claude` CLI is on `PATH`
  (CI has none, so run it locally after touching the manifests or skills).
- `make test`: `zsh tests/run.zsh`.
- `make test-pty`: `python3 tests/run-pty.py`, the same suite under a real
  controlling terminal. See the docstring for why.

Needs `zsh`, `jq`, `gh`, `python3` and `make` on `PATH`. CI runs the same
three passes on Ubuntu and macOS, offline: no `GH_TOKEN` is provided, so an
accidental API call fails loudly.

Note that a `CLAUDE.md` at the repository root fails the strict plugin
validation (the plugin root is the repository root), which is why the
contributor notes live here and `.claude/CLAUDE.md` only imports this file.

## Tests

Everything is offline and deterministic. The suite gets there two ways:

- **Golden cases** render a saved API payload pair through `--fixtures` and
  diff the output against `tests/fixtures/<suite>/expected/<case>.txt`.
- **Non-golden cases** assert exit codes and substrings for what
  `--fixtures` cannot reach: the two GraphQL fetches and their error
  branches, run against a `gh` stub on `PATH` (and a `mktemp` stub, so
  temp-file cleanup is an exact assertion), plus generated inputs such as an
  oversized payload.

`tests/test-gh-comments-pr.zsh` pins the pull-request renderer with the type
pinned (`--pr`); `tests/test-gh-comments.zsh` pins the issue renderer, type
resolution from the payload, the refusals, and the invoked-name behaviour.
Each file's header comment lists what every fixture covers and how to add a
case.

### The golden workflow

Never hand-edit a golden file. After an *intentional* rendering change,
regenerate and review the diff like any other code change:

```bash
GOLDEN_UPDATE=1 zsh tests/test-gh-comments-pr.zsh
GOLDEN_UPDATE=1 zsh tests/test-gh-comments.zsh
git diff tests/fixtures/
```

A test that fails after a behaviour change is the workflow working; the fix
is a reviewed regeneration, not patching the expected file until it passes.
An expectation locks in whatever the code currently does, bugs included, so
read a new golden line by line before committing it.

Some cases pin a documented limitation rather than desired behaviour; they
are marked `LIMITATION` in the test file's header comment. Changing one is a
deliberate semantics change and should update the docs with it.

### The gh stub

The non-golden cases talk to a stub `gh` that answers the calls the script
makes and refuses what real `gh` refuses, as far as it has been taught:
`pr view -R <repo>` with no positional is one such refusal, learnt after a
stub that answered it let a broken branch lookup through a green suite.
A change to the shape of any `gh` call therefore needs one run against the
real `gh` as well, before the stub is taught the new shape.

### Fixtures

A fixture holds the exact shape the script fetches: the output of
`gh api graphql --paginate … | jq -s .` for the timeline query (`<name>.tl.json`)
and, for a PR, the threads query (`<name>.th.json`). Capture a real payload
for a regression test of a field-reported behaviour; author one synthetically
for coverage, since one small fixture can exercise paths real data happens
not to have. Keep each fixture single-purpose and named for the scenario it
pins, and list it in the suite's header comment.

The committed fixtures are synthetic and must stay free of real people's
content: placeholder logins (`alice`, `bob`, `reviewer-bart`, …), invented
repositories and bodies. Scrub a captured payload before committing it.

## Benchmark

`bench/` measures the token cost of the command and the skills against raw
`gh`, REST and GraphQL reads, on live public targets. It needs network,
`gh` auth and the `claude` CLI, and counting costs money, so neither
`make check` nor CI runs it. See [bench/README.md](bench/README.md) for how
to run it and file a run, and rerun it after a change to what the command
prints or to the skills, then update [BENCHMARKS.md](BENCHMARKS.md).

## Releasing

1. Bump `VERSION=` in `gh-comments` and `version` in
   `.claude-plugin/plugin.json` together; `make lint` refuses a mismatch.
2. `claude plugin tag --push` creates and pushes the `gh-comments--v<version>`
   tag the plugin marketplace reads. Also push a plain `v<version>` tag as
   the human-readable release marker. `gh extension upgrade` does not read
   tags: for a script extension it pulls the default branch, so merging to
   `main` is the release for extension users.
