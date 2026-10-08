#!/usr/bin/env zsh

# Tests for gh-comments — the issue renderer, type resolution, and the
# refusals that keep a flag from silently doing nothing.
#
# The PR renderer is pinned by test-gh-comments-pr.zsh, which runs every case
# with the type pinned (--pr). This file covers the rest: the issue renderer,
# resolving the type from the payload when nothing pins it, and the refusals.
#
# Goldens diff against fixtures/gh-comments/expected/<case>.txt. After an
# *intentional* rendering change, regenerate and review the diff:
#
#   GOLDEN_UPDATE=1 zsh tests/test-gh-comments.zsh
#
# Fixtures (issue timelines; the PR fixtures live in fixtures/pr-comments/ and
# are reused here for the auto-detection cases):
#   issue-basic   reopened issue: opening body with an HTML comment, human and
#                 bot comments, a rename, a cross-reference that closes, a
#                 close/reopen pair, and label/assignee/milestone housekeeping
#                 on both sides of --events
#   issue-closed  CLOSED as not_planned; a *cross-repo* cross-reference to an
#                 issue rather than a PR, an unassignment, and a comment with
#                 an empty body
#   issue-empty   no timeline items, no body, no labels, no assignees, and a
#                 deleted author (author:null → ghost)
#   issue-paged   two pages of `gh --paginate` output — the counts header and
#                 the render must span both, and the type probe must read only
#                 the first
#   issue-bot-closed  a stale bot closed it and a Dependabot PR references it,
#                 so the two lines that explain the issue are both bot-authored
#                 — plus a bot label, which is bot *and* housekeeping and so
#                 must count once under each gate without rendering
#   issue-html    a rich-text HTML paste (converted to markdown), a plain
#                 comment whose fenced HTML must survive, and a body long
#                 enough to carry a --toc "… [+N chars]" cue
#   issue-hidden  issue-basic plus a comment minimized as SPAM (uppercase, as
#                 the live API returned it on cli/cli#11809): a marker line
#                 and no body by default, the body under --hidden, and
#                 `(1 hidden)` in the counts line. The other comments carry
#                 isMinimized:null, which must read as not hidden
#
# Below the goldens, non-golden cases assert exit codes and substrings:
#
#   bot filtering    bot-authored closed/xref events survive the default view
#                    while the bot comment and the bot label stay gated
#   header           a short labels(first:20) page grows a (+N more) marker;
#                    a complete one does not
#   auto-detection   the same PR fixture rendered with no --pr must equal the
#                    --pr suite's golden, byte for byte
#   type refusals    a pinned type that does not match is an error, never a
#                    silent switch to the other renderer
#   flag refusals    --unresolved/--since-last-review/--merges on an issue and
#                    --events on a PR are errors, because ignoring them would
#                    report a filtered view as a complete one
#   stubbed gh       call counts and query shape per resolved type — an issue
#                    must not pay for the reviewThreads fetch
#   argument validation  the flag parser's refusals
#   missing tools    jq or gh absent from PATH is one sentence naming every
#                    missing tool, refused before the branch lookup runs gh;
#                    a --fixtures render needs only jq
#   invoked name     a symlink's name, and `gh comments` under GH_EXTENSION=1,
#                    prefix every diagnostic and the rerun hint; --version
#                    keeps the product name
#
# issue-basic's body carries an HTML comment on its own line: `clean` strips it
# and then closes the gap it left, so the golden shows one paragraph break
# there rather than three. That collapse is shared with every other body in
# both renderers.
set -uo pipefail

here=${0:A:h}
script=$here/../gh-comments
fx=$here/fixtures/gh-comments
prfx=$here/fixtures/pr-comments
source "$here/lib.zsh"
typeset -i fails=0
typeset -a problems=()

# report <case> <title> <rc> <output> — one t_ok, or one t_fail carrying the
# problem list and the head of the output. Always clears `problems`.
report() {
  local name=$1 title=$2 out=$4 dtmp
  local -i rc=$3
  if (( ${#problems} == 0 )); then
    t_ok "$name"
  else
    dtmp=$(mktemp)
    { print -r -- "exit $rc"
      print -rl -- $problems
      print -r -- "--- first 10 lines of output ---"
      print -r -- "$out" | head -10
    } > "$dtmp"
    t_fail "$name" "$dtmp" "tests/test-gh-comments.zsh" "$title"
    rm -f "$dtmp"
    (( fails += 1 ))
  fi
  problems=()
  return 0
}

# check <case-name> <fixture-base> <number> [flags...] — an issue golden. Only
# a timeline payload is passed: an issue has no review threads, and that the
# second --fixtures operand is genuinely optional is part of what this pins.
check() {
  local name=$1 fixture=$2 num=$3; shift 3
  local expected=$fx/expected/$name.txt
  local actual dtmp rc=0
  actual=$(zsh "$script" "$num" "$@" --fixtures "$fx/$fixture.tl.json" 2>&1) || rc=$?
  if (( rc != 0 )); then
    dtmp=$(mktemp)
    print -r -- "$actual" > "$dtmp"
    t_fail "$name" "$dtmp" "tests/test-gh-comments.zsh" "exit $rc"
    rm -f "$dtmp"
    (( fails += 1 ))
    return 0
  fi
  if [[ "${GOLDEN_UPDATE:-0}" == 1 ]]; then
    mkdir -p "$fx/expected"
    print -r -- "$actual" > "$expected"
    t_wrote "$expected"
    return 0
  fi
  dtmp=$(mktemp)
  if diff -u -L "expected/$name.txt" -L "actual" "$expected" <(print -r -- "$actual") > "$dtmp" 2>&1; then
    t_ok "$name"
  else
    t_fail "$name" "$dtmp" "tests/fixtures/gh-comments/expected/$name.txt" "golden mismatch"
    (( fails += 1 ))
  fi
  rm -f "$dtmp"
  return 0
}

check issue-basic-full    issue-basic 21
check issue-basic-toc     issue-basic 21 --toc
# Both ends of the housekeeping gate. The counts line must stay honest either
# way — "(+4 housekeeping filtered)" vs "(incl. 4 housekeeping)" — which is why
# those events are fetched unconditionally and dropped in the renderer.
check issue-basic-events  issue-basic 21 --toc --events
check issue-basic-bots    issue-basic 21 --toc --bots
# The opening post is deliberately outside the --since window and must still
# render: --since narrows the discussion, not what is being discussed.
check issue-basic-since   issue-basic 21 --since 2026-08-20

check issue-closed-full   issue-closed 5

# issue-bot-closed-* — a regression pin. --bots used to filter *every* node by
# author, so a bot-closed issue rendered a header saying [CLOSED not_planned],
# a counts line saying `events: 0`, and no reason anywhere; the bot-authored
# `closed` and `xref` lines are precisely the ones that answer "why was this
# closed" and "what PR references it". Events are no longer filtered by author
# at all, matching the PR branch, and the default view must carry both lines.
check issue-bot-closed-toc    issue-bot-closed 33 --toc
check issue-bot-closed-full   issue-bot-closed 33
# The bot comment and the bot label are still gated — by --bots and --events
# respectively — and the counts must add up the same way from either side.
check issue-bot-closed-open   issue-bot-closed 33 --toc --bots --events

check issue-empty-full    issue-empty 7
check issue-empty-toc     issue-empty 7 --toc

check issue-paged-full    issue-paged 12
check issue-paged-toc     issue-paged 12 --toc

check issue-html-full     issue-html 9
check issue-html-toc      issue-html 9 --toc

check issue-hidden-full   issue-hidden 21
check issue-hidden-toc    issue-hidden 21 --toc
check issue-hidden-shown  issue-hidden 21 --hidden

# bot-events-survive-default — the goldens above would happily record the bug
# again if someone regenerated them after reintroducing it. This says out loud
# what must be true, independent of any expected file.
bot_events_survive() {
  local name=bot-events-survive-default out
  local -i rc=0
  out=$(zsh "$script" 33 --toc --fixtures "$fx/issue-bot-closed.tl.json" 2>&1) || rc=$?
  (( rc == 0 )) || problems+=("exit $rc (want 0)")
  [[ "$out" == *"closed [github-actions[bot]"* ]] \
    || problems+=("the bot-authored close event was filtered out of the default view")
  [[ "$out" == *"xref [dependabot[bot]"* ]] \
    || problems+=("the bot-authored cross-reference was filtered out of the default view")
  [[ "$out" != *"marked as stale"* ]] \
    || problems+=("the bot *comment* leaked into the default view")
  [[ "$out" != *"label ["* ]] || problems+=("a housekeeping event leaked into the default view")
  # The counts must describe the same render: one event shown (the close),
  # one cross-ref, and the bot label counted as housekeeping rather than
  # vanishing before it could be counted.
  [[ "$out" == *"comments: 1 (+1 bot filtered) · cross-refs: 1 · events: 1 (+1 housekeeping filtered)"* ]] \
    || problems+=("counts line disagrees with what was rendered")
  report "$name" "bot filtering" $rc "$out"
  return 0
}
bot_events_survive

# labels-truncated — `labels(first:20)` is a page, and the header joins
# whatever came back. Twenty labels on one issue is beyond unlikely, which is
# exactly why a silent cut there would never be noticed; the renderer compares
# totalCount against what it got, so a small synthetic short-page exercises the
# same comparison as a real 21-label issue without committing one.
labels_truncated() {
  local name=labels-truncated tmp cut out_cut out_plain
  local -i rc=0
  tmp=$(mktemp -d) || {
    t_fail "$name" "" "tests/test-gh-comments.zsh" "mktemp -d failed"
    (( fails += 1 )); return 0
  }
  cut=$tmp/labels-cut.tl.json
  jq -c '(.[].data.repository.issueOrPullRequest.labels.totalCount) = 7' \
    "$fx/issue-basic.tl.json" > "$cut"
  out_cut=$(zsh "$script" 21 --toc --fixtures "$cut" 2>&1) || { rc=$?; problems+=("exited $rc"); }
  out_plain=$(zsh "$script" 21 --toc --fixtures "$fx/issue-basic.tl.json" 2>&1) \
    || problems+=("the untruncated run failed")

  [[ "$out_cut" == *"labels:design,enhancement (+5 more)"* ]] \
    || problems+=("a short label page rendered as if it were the whole set")
  # The complete page must stay clean — a marker that fires when nothing was
  # cut is the same lie in the other direction.
  [[ "$out_plain" == *"labels:design,enhancement assignees:"* ]] \
    || problems+=("a complete label page grew a truncation marker")

  report "$name" "header" $rc "$out_cut"
  rm -rf "$tmp"
  return 0
}
labels_truncated

# ---------------------------------------------------------------------------
# Auto-detection. The type comes from the payload, so the same PR fixture must
# render the same through either entry point.
# ---------------------------------------------------------------------------

# auto-pr-matches-golden — compared against the *committed --pr golden*, not
# a second copy of it. A fork between the pinned and the resolved path then
# fails here rather than being papered over by a golden regenerated from the
# forked behavior.
auto_pr_identical() {
  local name=auto-pr-matches-golden out
  local -i rc=0
  out=$(zsh "$script" 1001 --fixtures "$prfx/basic.tl.json" "$prfx/basic.th.json" 2>&1) || rc=$?
  (( rc == 0 )) || problems+=("exit $rc (want 0)")
  [[ "$out" == "PR #1001 "* ]] || problems+=("auto mode did not resolve the payload as a PR")
  if ! diff -q <(print -r -- "$out") "$prfx/expected/basic-full.txt" > /dev/null 2>&1; then
    problems+=("auto-mode PR render differs from the --pr golden")
  fi
  report "$name" "auto-detection" $rc "$out"
  return 0
}
auto_pr_identical

# auto-legacy-payload-shape — every committed PR fixture predates the union
# query and holds `data.repository.pullRequest`, not `issueOrPullRequest`. The
# renderer accepts both, which is the whole reason those fixtures survived the
# rewrite; this pins that the *type probe* accepts both too.
auto_legacy_shape() {
  local name=auto-legacy-payload-shape tmp unioned out_legacy out_union
  local -i rc=0
  tmp=$(mktemp -d) || {
    t_fail "$name" "" "tests/test-gh-comments.zsh" "mktemp -d failed"
    (( fails += 1 )); return 0
  }
  unioned=$tmp/basic-union.tl.json
  # Exactly what the union query returns for the same PR.
  jq -c 'map(.data.repository |= {issueOrPullRequest: (.pullRequest + {__typename: "PullRequest"})})' \
    "$prfx/basic.tl.json" > "$unioned"
  jq -e '.[0].data.repository.issueOrPullRequest.__typename == "PullRequest"' "$unioned" > /dev/null \
    || problems+=("the rewritten payload is not in union shape — the case proves nothing")

  out_legacy=$(zsh "$script" 1001 --toc --fixtures "$prfx/basic.tl.json" "$prfx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("legacy-shape run exited $rc"); }
  out_union=$(zsh "$script" 1001 --toc --fixtures "$unioned" "$prfx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("union-shape run exited $rc"); }
  [[ "$out_union" == "$out_legacy" ]] \
    || problems+=("the two payload shapes render differently")

  report "$name" "auto-detection" $rc "$out_union"
  rm -rf "$tmp"
  return 0
}
auto_legacy_shape

# ---------------------------------------------------------------------------
# Refusals. Each of these could plausibly have been implemented as "do
# something reasonable instead", and each of those would report a partial
# answer as a complete one.
# ---------------------------------------------------------------------------

# refuse <name> <want-substring> [args...] — run the subject, expect exit 1 and
# the substring, and expect nothing rendered.
refuse() {
  local name=$1 want=$2 out; shift 2
  local -i rc=0
  out=$(zsh "$script" "$@" 2>&1) || rc=$?
  (( rc == 1 )) || problems+=("exit $rc (want 1)")
  [[ "$out" == *"$want"* ]] || problems+=("output lacks: $want")
  [[ "$out" != "issue #"* && "$out" != "PR #"* ]] \
    || problems+=("rendered a target instead of refusing")
  report "$name" "refusals" $rc "$out"
  return 0
}

refuse type-pr-on-issue \
  'is an issue, not a pull request: "design: support GitHub issue discussion alongside PR comments"' \
  21 --pr --fixtures "$fx/issue-basic.tl.json"
refuse type-issue-on-pr \
  'is a pull request, not an issue' \
  1001 --issue --fixtures "$prfx/basic.tl.json" "$prfx/basic.th.json"
# The hint under a wrong-type refusal is the same command without the pin:
# the invoked name (see prog-from-invoked-name below for the symlink side of
# that) and every other argument, so -R and the view flags survive and the
# suggestion targets the repo the user named.
refuse type-hint-names-command "rerun as: gh-comments 21 --fixtures $fx/issue-basic.tl.json" \
  21 --pr --fixtures "$fx/issue-basic.tl.json"
refuse type-hint-keeps-flags "rerun as: gh-comments 21 -R acme/widget --toc --fixtures $fx/issue-basic.tl.json" \
  21 -R acme/widget --pr --toc --fixtures "$fx/issue-basic.tl.json"
# ...but not a flag the resolved type would refuse on the rerun.
refuse type-hint-drops-wrong-type-flags "rerun as: gh-comments 21 --toc --fixtures $fx/issue-basic.tl.json" \
  21 --pr --unresolved --latest=alice --toc --fixtures "$fx/issue-basic.tl.json"
refuse type-hint-drops-events "rerun as: gh-comments 1001 --fixtures $prfx/basic.tl.json $prfx/basic.th.json" \
  1001 --issue --events --fixtures "$prfx/basic.tl.json" "$prfx/basic.th.json"

refuse flag-unresolved-on-issue "--unresolved only applies to pull requests; #21 is an issue" \
  21 --unresolved --fixtures "$fx/issue-basic.tl.json"
refuse flag-slr-on-issue "--since-last-review only applies to pull requests; #21 is an issue" \
  21 --since-last-review --fixtures "$fx/issue-basic.tl.json"
refuse flag-merges-on-issue "--merges only applies to pull requests; #21 is an issue" \
  21 --merges --fixtures "$fx/issue-basic.tl.json"
refuse flag-latest-on-issue "--latest only applies to pull requests; #21 is an issue" \
  21 --latest --fixtures "$fx/issue-basic.tl.json"
# All three at once: the message lists every offender rather than stopping at
# the first, so one rerun is enough.
refuse flag-many-on-issue "--unresolved, --since-last-review, --merges only apply to pull requests" \
  21 --unresolved --since-last-review --merges --fixtures "$fx/issue-basic.tl.json"
refuse flag-events-on-pr "--events only applies to issues; #1001 is a pull request" \
  1001 --events --fixtures "$prfx/basic.tl.json" "$prfx/basic.th.json"

# ---------------------------------------------------------------------------
# Stubbed gh — the fetch half, which --fixtures can never reach. Offline by
# construction: the stub never touches the network, and CI has no GH_TOKEN.
# The question here is not what renders but what is *asked for*: how many
# round trips each resolved type costs, and which fragments the query carries.
# ---------------------------------------------------------------------------
stubdir=$(mktemp -d) || { print -ru2 -- "mktemp -d failed"; exit 1 }
stublog=$stubdir/argv.log
qlog=$stubdir/tl-query.txt

cat > "$stubdir/gh" <<'STUB'
#!/usr/bin/env zsh
# gh stub — offline. $GH_STUB_MODE picks the scenario; every call appends a tag
# to $GH_STUB_LOG so a change in the subject's call pattern fails here instead
# of landing silently. The two graphql calls are told apart by their query
# text: only the threads query mentions reviewThreads.
emit_log() { print -r -- "$1" >> "${GH_STUB_LOG:-/dev/null}" }

case "$1 $2" in
  "repo view") emit_log "repo view"; print -r -- acme/widget; exit 0 ;;
  "pr view")   emit_log "pr view"; exit 1 ;;
esac
if [[ "$1 $2" != "api graphql" ]]; then
  print -ru2 -- "gh stub: unexpected argv: $*"; exit 64
fi

which=tl
[[ "$*" == *reviewThreads* ]] && which=th
emit_log "graphql:$which"
if [[ $which == tl && -n ${GH_STUB_QUERY_LOG:-} ]]; then
  print -r -- "$*" > "$GH_STUB_QUERY_LOG"
fi

if [[ $which == th ]]; then jq -c '.[]' "$GH_STUB_TH"; exit 0; fi

case "${GH_STUB_MODE:-}" in
  pr)    jq -c '.[]' "$GH_STUB_TL"; exit 0 ;;
  issue) jq -c '.[]' "$GH_STUB_ISSUE"; exit 0 ;;
  notfound)
    print -rn -- '{"data":{"repository":{"issueOrPullRequest":null}},"errors":[{"type":"NOT_FOUND","message":"Could not resolve to an issue or pull request with the number of 999."}]}'
    print -ru2 -- "gh: Could not resolve to an issue or pull request with the number of 999."
    exit 1 ;;
esac
print -ru2 -- "gh stub: unhandled mode ${GH_STUB_MODE:-<unset>}"
exit 65
STUB
chmod +x "$stubdir/gh" || { print -ru2 -- "chmod gh stub failed"; exit 1 }

typeset -ga gh_env=(
  PATH="$stubdir:$PATH"
  GH_STUB_LOG="$stublog"
  GH_STUB_TL="$prfx/zero-threads.tl.json"
  GH_STUB_TH="$prfx/zero-threads.th.json"
  GH_STUB_ISSUE="$fx/issue-basic.tl.json"
  GH_STUB_QUERY_LOG="$qlog"
)
gh_reset() { : > "$stublog"; : > "$qlog" }

typeset -g gh_out=""; typeset -gi gh_rc=0
gh_case() {
  local mode=$1; shift
  gh_rc=0
  gh_out=$(env "${gh_env[@]}" GH_STUB_MODE="$mode" zsh "$script" "$@" 2>&1) || gh_rc=$?
  return 0
}

# gh-auto-issue-one-fetch — an issue costs exactly one round trip. The
# reviewThreads query is the expensive half of a PR dump and an issue has no
# threads to fetch; issuing it anyway would be a silent tax on every issue.
gh_reset
gh_case issue 21 --toc
(( gh_rc == 0 )) || problems+=("exit $gh_rc (want 0)")
[[ "$gh_out" == "issue #21 "* ]] || problems+=("did not render as an issue")
[[ "$(grep -c '^graphql:' "$stublog")" == 1 ]] \
  || problems+=("expected exactly 1 graphql call, log has: $(tr '\n' ' ' < "$stublog")")
grep -qx 'graphql:th' "$stublog" && problems+=("fetched review threads for an issue")
report gh-auto-issue-one-fetch "stubbed gh" $gh_rc "$gh_out"

# gh-auto-pr-two-fetches — a PR still costs two, resolved rather than assumed.
gh_reset
gh_case pr 7 --toc
(( gh_rc == 0 )) || problems+=("exit $gh_rc (want 0)")
[[ "$gh_out" == "PR #7 "* ]] || problems+=("did not render as a PR")
[[ "$(grep -c '^graphql:' "$stublog")" == 2 ]] \
  || problems+=("expected exactly 2 graphql calls, log has: $(tr '\n' ' ' < "$stublog")")
report gh-auto-pr-two-fetches "stubbed gh" $gh_rc "$gh_out"

# gh-query-fragments-* — which fragments the timeline query carries. In auto
# mode both are full, because either type may come back. With the type pinned,
# the other side shrinks to `number title` — enough to name the mistake, not
# enough to pay for a timeline that will never render. Getting this wrong in
# the permissive direction is only wasted bytes; getting it wrong in the other
# is a wrong-type diagnosis with no title in it.
fragment_case() {
  local name=$1 want_pr=$2 want_issue=$3; shift 3
  local -i has_pr_tl=0 has_issue_tl=0
  gh_reset
  gh_case "$@"
  grep -q 'PULL_REQUEST_REVIEW' "$qlog" && has_pr_tl=1
  grep -q 'CROSS_REFERENCED_EVENT' "$qlog" && has_issue_tl=1
  (( has_pr_tl == want_pr )) \
    || problems+=("PR fragment full=$has_pr_tl, want $want_pr")
  (( has_issue_tl == want_issue )) \
    || problems+=("Issue fragment full=$has_issue_tl, want $want_issue")
  grep -q '@PR_FRAGMENT@\|@ISSUE_FRAGMENT@\|@ITEM_TYPES@\|@COMMIT_FRAGMENT@\|@COMMENT_BODY@' "$qlog" \
    && problems+=("an unsubstituted template slot reached the query")
  report "$name" "stubbed gh" $gh_rc "$gh_out"
  return 0
}

fragment_case gh-query-fragments-auto     1 1 pr    7 --toc
fragment_case gh-query-fragments-pinned-pr    1 0 pr    7 --pr --toc
fragment_case gh-query-fragments-pinned-issue 0 1 issue 21 --issue --toc

# gh-pinned-flag-refused-before-fetch — with the type pinned, a flag the
# pinned type cannot honour is decidable from argv alone, so it is refused
# before the timeline is paid for.
for spec in "issue --issue --unresolved|--unresolved only applies to pull requests; the type is pinned to an issue by --issue" \
            "pr --pr --events|--events only applies to issues; the type is pinned to a pull request by --pr"; do
  gh_reset
  gh_case ${=${spec%%|*}}
  (( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
  [[ "$gh_out" == "gh-comments: ${spec#*|}" ]] || problems+=("output was: $gh_out")
  (( $(grep -c '^graphql:' "$stublog") == 0 )) \
    || problems+=("fetched before refusing: $(tr '\n' ' ' < "$stublog")")
  report "gh-pinned-flag-refused-before-fetch-${${spec%% *}}" "stubbed gh" $gh_rc "$gh_out"
done

# gh-notfound — the union resolves both sequences, so a number it cannot
# resolve is neither a PR nor an issue. The wording has to stop saying "PR".
gh_reset
gh_case notfound 999 --toc
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == *"gh-comments: #999 not found in acme/widget"* ]] \
  || problems+=("the not-found diagnosis did not replace the raw gh error")
[[ "$gh_out" != *"PR #999 not found"* ]] \
  || problems+=("still calls an unresolvable number a PR")
report gh-notfound "stubbed gh" $gh_rc "$gh_out"

rm -rf "$stubdir"

# ---------------------------------------------------------------------------
# Argument validation.
# ---------------------------------------------------------------------------
argcase() {
  local name=$1 want=$3 out
  local -i want_rc=$2 rc=0
  shift 3
  out=$(zsh "$script" "$@" 2>&1) || rc=$?
  (( rc == want_rc )) || problems+=("exit $rc (want $want_rc)")
  [[ "$out" == *"$want"* ]] || problems+=("output lacks: $want")
  report "$name" "argument validation" $rc "$out"
}

argcase arg-help          0 "Usage: gh-comments" --help
# --version prints the product name, whatever the script was invoked as, and
# a dotted version — the exact string is pinned against plugin.json by
# `make lint`, not here, so a release bump is one edit and not two.
version_flag() {
  local name=arg-version out
  local -i rc=0
  out=$(zsh "$script" --version 2>&1) || rc=$?
  (( rc == 0 )) || problems+=("exit $rc (want 0)")
  [[ "$out" =~ '^gh-comments [0-9]+\.[0-9]+\.[0-9]+$' ]] \
    || problems+=("--version printed: $out")
  report "$name" "argument validation" $rc "$out"
  return 0
}
version_flag
argcase arg-bad-number    1 "not a PR or issue number: 21a" 21a
# The optional second --fixtures operand must not swallow the number. Here the
# number follows the flag, and taking it as a threads payload would leave the
# run with no target at all.
argcase arg-fixtures-number-after 0 "issue #21" --fixtures "$fx/issue-basic.tl.json" 21
argcase arg-issue-needs-number 1 "an issue number is required" --issue

# --since compares lexically against ISO timestamps, so a value in any other
# shape used to give a wrong answer with no error: a word matched nothing, a
# US-style date matched everything. The accepted forms
# are a date and a date with a time. Each accepts-* case names the minute of
# alice's comment (createdAt 2026-08-16T18:00:00Z) and wants that comment in
# the output: every accepted spelling of that instant has to *keep* the item
# at it — `T18:00Z` used to sort after `T18:00:00Z` and drop it — so the
# assertion is on the selection, not just on the run surviving.
alice="comment [alice 2026-08-16 18:00]"
argcase arg-since-rejects-word    1 "--since needs an ISO date, UTC (YYYY-MM-DD, optionally THH:MM[:SS][Z]); got: yesterday" \
  21 --since yesterday --fixtures "$fx/issue-basic.tl.json"
argcase arg-since-rejects-us-date 1 "got: 08/20/2026" 21 --since 08/20/2026 --fixtures "$fx/issue-basic.tl.json"
argcase arg-since-rejects-partial 1 "got: 2026-08" 21 --since 2026-08 --fixtures "$fx/issue-basic.tl.json"
# Right shape, impossible value: a typo'd month or hour must not pass as an
# empty window, and an offset cannot be compared lexically with a Z timestamp.
argcase arg-since-rejects-month-13 1 "got: 2026-13-01" 21 --since 2026-13-01 --fixtures "$fx/issue-basic.tl.json"
argcase arg-since-rejects-hour-24  1 "got: 2026-08-16T24:00" 21 --since 2026-08-16T24:00 --fixtures "$fx/issue-basic.tl.json"
argcase arg-since-rejects-offset   1 "got: 2026-08-16T18:00+02:00" 21 --since 2026-08-16T18:00+02:00 --fixtures "$fx/issue-basic.tl.json"
argcase arg-since-accepts-date    0 "$alice" 21 --toc --since 2026-08-16 --fixtures "$fx/issue-basic.tl.json"
argcase arg-since-accepts-time    0 "$alice" 21 --toc --since 2026-08-16T18:00 --fixtures "$fx/issue-basic.tl.json"
argcase arg-since-accepts-minute-z 0 "$alice" 21 --toc --since 2026-08-16T18:00Z --fixtures "$fx/issue-basic.tl.json"
argcase arg-since-accepts-seconds-z 0 "$alice" 21 --toc --since=2026-08-16T18:00:00Z --fixtures "$fx/issue-basic.tl.json"

# arg-since-boundary-excludes — the other edge of the same window: one second
# past alice's comment must drop it while the run still renders.
since_boundary() {
  local name=arg-since-boundary-excludes out
  local -i rc=0
  out=$(zsh "$script" 21 --toc --since 2026-08-16T18:00:01 --fixtures "$fx/issue-basic.tl.json" 2>&1) || rc=$?
  (( rc == 0 )) || problems+=("exit $rc (want 0)")
  [[ "$out" == *"issue #21"* ]] || problems+=("output lacks the header")
  [[ "$out" != *"$alice"* ]] || problems+=("--since 18:00:01 still shows the 18:00:00 comment")
  report "$name" "argument validation" $rc "$out"
}
since_boundary

# A flag that takes a value, given none. These used to die inside the parser
# with zsh's "2: parameter not set" under set -u; now
# they are usage errors that name the form. No --fixtures on purpose: the
# refusal has to come before anything is fetched.
argcase arg-repo-missing-value   1 "-R needs <owner/name>" 21 -R
argcase arg-repo-flag-as-value   1 "--repo needs <owner/name>" 21 --repo --toc
argcase arg-repo-empty           1 "--repo needs <owner/name>" 21 --repo=
argcase arg-since-missing-value  1 "--since needs <iso-date>" 21 --since
argcase arg-since-empty          1 "--since needs <iso-date>" 21 --since=

# Two answers to "which item do I slice from" cannot both be honoured.
argcase arg-latest-with-slr      1 "--latest and --since-last-review are exclusive" 21 --latest --since-last-review

# missing-* — a tool the script needs but PATH lacks is one sentence naming
# every missing tool, not zsh's "command not found" with a line number. PATH
# is rebuilt from scratch with only what the script needs besides the tool
# under test, so the absence is real rather than a shadowing stub, and the
# probes run `zsh -f`, so a ~/.zshenv that exports PATH cannot put the tool
# back. gh is needed only to fetch: a --fixtures render must not demand it,
# and the no-number branch lookup must be refused before it runs gh.
typeset -g miss_dir=""
miss_path() {  # miss_path <tool>... — a PATH holding the script's needs plus <tool>s
  local t
  miss_dir=$(mktemp -d) || return 1
  for t in zsh mktemp grep cat tail rm "$@"; do
    ln -s "$(command -v $t)" "$miss_dir/$t" || return 1
  done
  return 0
}
# miss_case <name> <want-rc> <want-output> <tools-present>... -- <args>...
miss_case() {
  local name=$1 want=$3 out; local -i want_rc=$2 rc=0; shift 3
  local -a tools=()
  while (( $# )) && [[ $1 != -- ]]; do tools+=("$1"); shift; done
  shift
  if ! miss_path "${tools[@]}"; then
    t_fail "$name" "" "tests/test-gh-comments.zsh" "could not build the PATH"
    (( fails += 1 )); rm -rf "$miss_dir"; return 0
  fi
  out=$(cd "$miss_dir" && PATH=$miss_dir zsh -f "$script" "$@" 2>&1) || rc=$?
  (( rc == want_rc )) || problems+=("exit $rc (want $want_rc)")
  if (( want_rc == 0 )); then
    [[ "$out" == "$want"* ]] || problems+=("output does not start with: $want")
  else
    # The first line: a usage error goes on to print the usage text.
    [[ "${out%%$'\n'*}" == "$want" ]] || problems+=("output was: ${out%%$'\n'*}")
  fi
  report "$name" "missing tools" $rc "$out"
  rm -rf "$miss_dir"
  return 0
}
miss_case missing-jq      1 "gh-comments: needs jq on PATH" -- 21 --fixtures "$fx/issue-basic.tl.json"
# A usage error the parser can make on its own comes before the tool check:
# the user is told what is wrong with the command, not sent to install gh.
miss_case parser-before-preflight 1 "gh-comments: not a PR or issue number: abc" -- abc
miss_case issue-needs-number-before-preflight 1 "gh-comments: an issue number is required — there is no \"current branch's issue\"" -- --issue
miss_case missing-both    1 "gh-comments: needs jq and gh (the GitHub CLI) on PATH" -- 21 -R acme/widget
miss_case missing-gh      1 "gh-comments: needs gh (the GitHub CLI) on PATH" jq -- 21 -R acme/widget
# With no number the script would look the branch's PR up through gh; the
# refusal has to come first, or a missing gh reads as "no PR found".
miss_case missing-gh-no-number 1 "gh-comments: needs gh (the GitHub CLI) on PATH" jq --
# A --fixtures render needs jq and nothing else.
miss_case missing-gh-fixtures-render 0 "issue #21 " jq -- 21 --fixtures "$fx/issue-basic.tl.json"

# arg-no-zsh-internals — the positive substrings above would also pass if the
# usage error were printed *and* the shell still died on its own; this pins
# that the parser never reaches set -u's message at all.
no_internals() {
  local name=arg-no-zsh-internals out args bad_out=""
  local -i rc=0 bad_rc=0 nbad=0
  for args in "21 -R" "21 --since" "-R" "--since"; do
    rc=0
    out=$(zsh "$script" ${=args} 2>&1) || rc=$?
    [[ "$out" != *"parameter not set"* ]] || problems+=("'$args' leaked a zsh internal: $out")
    (( rc == 1 )) || problems+=("'$args' exited $rc (want 1)")
    # report() shows one exit code and one output; make them the first failing
    # case's, not whichever ran last.
    if (( ${#problems} > nbad )); then
      (( nbad )) || { bad_rc=$rc; bad_out=$out }
      nbad=${#problems}
    fi
  done
  (( nbad )) && { rc=$bad_rc; out=$bad_out }
  report "$name" "argument validation" $rc "$out"
  return 0
}
no_internals

# ---------------------------------------------------------------------------
# The invoked name. Every diagnostic is prefixed with the name the script was
# run as, so a symlink named r-gh-comments reports as r-gh-comments, with or
# without an extension on the link, and a run under `gh comments` reports as
# that — and the wrong-type hint names that same command, never a hard-coded
# one. --version is the exception: it names the product, since that is what
# the version is of.
# ---------------------------------------------------------------------------
invoked_name() {
  local name=prog-from-invoked-name tmp link out
  local -i rc=0
  tmp=$(mktemp -d) || {
    t_fail "$name" "" "tests/test-gh-comments.zsh" "mktemp -d failed"
    (( fails += 1 )); return 0
  }
  for link in r-gh-comments r-gh-comments.zsh; do
    ln -s "${script:A}" "$tmp/$link"
    out=$(zsh "$tmp/$link" --help 2>&1) || { rc=$?; problems+=("$link --help exited $rc"); }
    [[ "$out" == "Usage: r-gh-comments "* ]] \
      || problems+=("$link: usage does not carry the invoked name: ${out%%$'\n'*}")
    out=$(zsh "$tmp/$link" 21 --pr --fixtures "$fx/issue-basic.tl.json" 2>&1) && problems+=("$link: did not refuse")
    [[ "$out" == "r-gh-comments: #21 is an issue, not a pull request"* ]] \
      || problems+=("$link: diagnostic lacks the invoked name: ${out%%$'\n'*}")
    [[ "$out" == *"rerun as: r-gh-comments 21"* ]] \
      || problems+=("$link: the hint does not name the invoked command")
    out=$(zsh "$tmp/$link" --version 2>&1) || { rc=$?; problems+=("$link --version exited $rc"); }
    [[ "$out" == "gh-comments "* ]] || problems+=("$link: --version renamed the product: $out")
  done
  # Under `gh comments` the binary is still gh-comments, but gh sets
  # GH_EXTENSION=1, and the user typed `gh comments` — so that is the name
  # the usage line, the prefix and the hint carry.
  out=$(GH_EXTENSION=1 zsh "$script" --help 2>&1) || { rc=$?; problems+=("GH_EXTENSION --help exited $rc"); }
  [[ "$out" == "Usage: gh comments "* ]] \
    || problems+=("under gh: usage does not read gh comments: ${out%%$'\n'*}")
  out=$(GH_EXTENSION=1 zsh "$script" 21 --pr --fixtures "$fx/issue-basic.tl.json" 2>&1) && problems+=("under gh: did not refuse")
  [[ "$out" == "gh comments: #21 is an issue, not a pull request"* ]] \
    || problems+=("under gh: diagnostic prefix: ${out%%$'\n'*}")
  [[ "$out" == *"rerun as: gh comments 21 --fixtures"* ]] \
    || problems+=("under gh: the hint does not say gh comments")
  out=$(GH_EXTENSION=1 zsh "$script" --version 2>&1) || { rc=$?; problems+=("GH_EXTENSION --version exited $rc"); }
  [[ "$out" == "gh-comments "* ]] || problems+=("under gh: --version renamed the product: $out")
  report "$name" "invoked name" $rc "$out"
  rm -rf "$tmp"
  return 0
}
invoked_name

(( fails == 0 ))
