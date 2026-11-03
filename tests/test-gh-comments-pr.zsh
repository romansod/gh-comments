#!/usr/bin/env zsh

# Golden tests for gh-comments on pull requests — offline, via --fixtures.
#
# Every case here pins the type with --pr, so a number that is not a PR is an
# error rather than a different render. The issue renderer and the resolution
# of the type from the payload live in test-gh-comments.zsh.
#
# Each case renders a saved GraphQL payload pair from fixtures/pr-comments/
# and diffs the output against expected/<case>.txt. After an *intentional*
# rendering change, regenerate the golden files and review the diff:
#
#   GOLDEN_UPDATE=1 zsh tests/test-gh-comments-pr.zsh
#
# Fixtures:
#   basic         one review; open + resolved,outdated threads; thread reply;
#                 finding markers; orphan thread; bot comment; merge commit;
#                 pending review; force-push; a markdown PR description
#
# Four fixtures carry the opening-post fields (author/createdAt/body) the
# `body` item renders: basic (markdown), multi (one-liner, so --since and
# --since-last-review can pin that it survives narrowing), html-heavy (a
# rich-text paste), and zero-threads (empty string — the header line must
# still render, bare) — and so do the four derived from basic and multi
# (bot-review, bot-review-late, empty-review, hidden). all-resolved,
# late-reply, outdated-open, reply-51 and slr-late-reply deliberately do not:
# they were captured before those fields were added to the query, and
# legacy-pr-payload below pins (on all-resolved) that such a payload renders
# no `body` line rather than a hollow "body [ghost ]".
#   multi         two reviews (CHANGES_REQUESTED + APPROVED with no threads);
#                 issue comments between reviews — exercises --since and
#                 --since-last-review[=<user>]
#   zero-threads  review + comments but no inline threads at all
#   all-resolved  threads exist but every one is resolved
#   html-heavy    one rich-text HTML paste (converted to markdown) + one plain
#                 comment whose fenced HTML snippet must survive untouched
#   reply-51      thread with more replies than one page (hasNextPage) — the
#                 header must carry a loud TRUNCATED marker
#   late-reply    old review whose thread got a recent reply, plus an orphan
#                 thread with a recent comment — --since must keep both
#   slr-late-reply  two reviews; a reply on the FIRST review's thread dated
#                 after the second — pins a DOCUMENTED LIMITATION (see below)
#   empty-review  multi plus an empty COMMENTED review last — the shape of a
#                 bare approval (no body, no threads). --since-last-review
#                 anchors on it and shows a lone review line; --latest anchors
#                 on the last item that said something and still shows the
#                 empty review after it. (The empty review a thread *reply*
#                 creates is a different thing: the timeline API never
#                 returns it, as the reply-wrapper note in the skill says.)
#   outdated-open an OPEN thread that is also outdated, so GitHub sends
#                 line:null and the position survives only in originalLine.
#                 The other fixtures carry that shape on *resolved* threads
#                 only, which --unresolved filters out — so this is the one
#                 that reaches the fallback on the paths the skill documents
#                 as cheapest (--toc --unresolved).
#   bot-review    the basic pair with the review (and the two thread openers
#                 it authored) re-typed as a Bot. --bots filters the review,
#                 and its threads used to vanish with it while the counts
#                 line went on counting them; they now
#                 render under "threads in filtered bot reviews:".
#   bot-review-only-open  the same timeline with a threads payload that drops
#                 the human orphan thread, so the bot holds the *only* open
#                 one — the shape that printed "(no unresolved threads)"
#                 under a header saying "(1 open)".
#   bot-review-late  multi with alice's review re-typed as a Bot and a third,
#                 bot review (one open thread) after bob's — one bot review
#                 on each side of the review --since-last-review anchors on,
#                 so a slice must show the later one's thread and not the
#                 earlier one's. Likewise one orphan on each side: an open
#                 thread with no review before the anchor, and one after it
#                 keyed to a review the timeline never carried (PRR_pending),
#                 which renders as an orphan rather than vanishing.
#   hidden        basic with minimized comments: a hidden (OUTDATED) human
#                 top-level comment, the bot comment hidden as RESOLVED, and a
#                 hidden (RESOLVED) reply inside the retry.ts thread. Pins the
#                 marker line, the body gate behind --hidden, and the counts
#                 line in all four combinations of --bots and --hidden — the
#                 bot gate is applied first, so the hidden bot comment counts
#                 once, as a bot, until --bots puts it back.
#   hidden-review multi with two minimized reviews: alice's CHANGES_REQUESTED
#                 review hidden as OUTDATED, which keeps its two threads, and
#                 a third review, carol's, hidden as SPAM, with a body and no
#                 threads, last. Pins the marker on the review line, the body
#                 gate behind --hidden, the hidden tally on `reviews:`, and
#                 --latest and --since-last-review looking past a review
#                 whose only substance is a hidden body while still
#                 anchoring on one with threads.
#
# Not every case is golden. Directly below the goldens come the invariant
# cases, which take no golden and build no input: threads-match-header and
# slice-matches-full run a rule over every *.th.json in the directory (a new
# fixture is covered the day it lands), and hidden-bodies-gated,
# fallback-is-toc, fallback-keeps-narrowing and latest-skips-hidden say out
# loud what their goldens would otherwise re-record. The --item cases come
# next: item-is-its-block feeds every TOC line of five renders back to --item
# and checks the result against the full render; item-refusals and
# item-past-filters pin the refusals and what the default view holds back.
# The only-* goldens pin --only. Then six sections
# assert exit codes and substrings, because their input is built at runtime:
#
#   oversized payload  generates a >1 MB timeline rather than committing one
#   fixture shapes     the --slurpfile unwrap: array form, bare stream, garbage,
#                      and a threads capture carrying errors[], refused
#   html entities      numeric entities decode (decimal and hex), dangerous
#                      code points are replaced, and `&#38;amp;` is not
#                      decoded twice
#   lean timeline      --unresolved fetches a reduced timeline (no commits, no
#                      issue-comment bodies). One case proves the render cannot
#                      see the difference, another that the reduced query is
#                      sent exactly when it is safe to send.
#   stubbed gh         the fetch-and-diagnose half of the script, which
#                      --fixtures can never reach — errors on either stream,
#                      the not-found diagnosis, a failed threads fetch, an
#                      interrupt mid-fetch, and temp-file cleanup
#   argument validation  the flag parser's refusals
#
# zero-threads-unresolved and all-resolved-unresolved share the body
# "(no unresolved threads)" but must diverge in the header counts line:
# 0 threads vs N threads (0 open).
#
# LIMITATION golden — slr-late-reply-slr pins current, documented behavior,
# not desired behavior: --since-last-review shows the last review onward, so
# carol's reply (the newest item on the PR) is invisible because it nests
# under the older review. The skill documents this and points at
# --unresolved. If this golden ever gains the reply, that's a deliberate
# semantics change to --since-last-review, not a regression. --latest slices
# the same way and inherits the limitation.
set -uo pipefail

here=${0:A:h}
script=$here/../gh-comments
fx=$here/fixtures/pr-comments
source "$here/lib.zsh"
typeset -i fails=0

# check <case-name> <fixture-base> <pr-number> [flags...] — a golden over the
# fixture pair <base>.tl.json + <base>.th.json. check_pair is the same with
# the two halves named separately, for a threads payload that pairs with
# another fixture's timeline.
check() {
  local name=$1 fixture=$2; shift 2
  check_pair "$name" "$fixture" "$fixture" "$@"
}
check_pair() {
  local name=$1 tl=$2 th=$3 pr=$4; shift 4
  local expected=$fx/expected/$name.txt
  local actual dtmp rc=0
  actual=$(zsh "$script" --pr "$pr" "$@" --fixtures "$fx/$tl.tl.json" "$fx/$th.th.json" 2>&1) || rc=$?
  if (( rc != 0 )); then
    dtmp=$(mktemp)
    print -r -- "$actual" > "$dtmp"
    t_fail "$name" "$dtmp" "tests/test-gh-comments-pr.zsh" "exit $rc"
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
    t_fail "$name" "$dtmp" "tests/fixtures/pr-comments/expected/$name.txt" "golden mismatch"
    (( fails += 1 ))
  fi
  rm -f "$dtmp"
  return 0
}

check basic-full         basic 1001
check basic-toc          basic 1001 --toc
check basic-unresolved   basic 1001 --unresolved
check basic-bots-merges  basic 1001 --bots --merges
# --toc --unresolved is the cheapest correct answer to "what is still open"
# and is now documented as such in the skill, so both
# ends of it are pinned: threads to show, and none to show.
check basic-toc-unresolved  basic 1001 --toc --unresolved

check multi-full         multi 42
check multi-toc          multi 42 --toc
check multi-unresolved   multi 42 --unresolved
check multi-slr          multi 42 --since-last-review
check multi-slr-alice    multi 42 --since-last-review=alice
check multi-since        multi 42 --since 2026-08-12
# --latest picks the last *substantive* item of any kind: here alice's
# closing comment, not bob's earlier APPROVED review; =bob picks that review.
check multi-latest       multi 42 --latest
check multi-latest-toc   multi 42 --toc --latest
check multi-latest-bob   multi 42 --latest=bob
# A slicing flag that matches nothing shows the TOC under a note, not the
# full timeline — fallback-is-toc below pins that it is exactly the TOC.
check multi-slr-nomatch     multi 42 --since-last-review=nobody
check multi-latest-nomatch  multi 42 --latest=nobody
# ...unless another flag already narrows the view: then that view is shown as
# it is — fallback-keeps-narrowing pins it against the same run unsliced.
check multi-unresolved-latest-nomatch  multi 42 --unresolved --latest=nobody
# A slice that matched under --unresolved can leave nothing to render while
# the header still counts open threads — they sit on a review before the
# anchor. The line then says what the slice withheld, not "nothing is open".
check multi-unresolved-latest  multi 42 --unresolved --latest
check multi-unresolved-slr     multi 42 --unresolved --since-last-review

# empty-review-* — the two anchoring rules side by side.
check empty-review-slr     empty-review 43 --since-last-review
check empty-review-latest  empty-review 43 --latest

check zero-threads-toc         zero-threads 7 --toc
check zero-threads-unresolved  zero-threads 7 --unresolved

check all-resolved-full        all-resolved 8
check all-resolved-unresolved  all-resolved 8 --unresolved
check all-resolved-toc-unresolved  all-resolved 8 --toc --unresolved

check html-heavy-full  html-heavy 9
check html-heavy-toc   html-heavy 9 --toc

check reply-51-full  reply-51 10
# On a TOC line the opener follows the TRUNCATED marker, the two in that order.
check reply-51-toc   reply-51 10 --toc

check late-reply-since  late-reply 11 --since 2026-08-10

check slr-late-reply-slr  slr-late-reply 12 --since-last-review

# `.line // .originalLine` is what a hand-rolled `nodes{ path line }` query
# gets wrong — it silently reports no location on every outdated thread. The
# skill claims that as a reason to prefer the script, so both narrowed paths
# pin it, not just the full render.
check outdated-open-full            outdated-open 20
check outdated-open-unresolved      outdated-open 20 --unresolved
check outdated-open-toc-unresolved  outdated-open 20 --toc --unresolved

# bot-review-* — threads are an unfiltered axis. The default view holds the
# bot review back and must still show its threads, under their own heading;
# --bots puts the review back and nests them under it as before.
check bot-review-full            bot-review 1001
check bot-review-toc             bot-review 1001 --toc
check bot-review-unresolved      bot-review 1001 --unresolved
check bot-review-toc-unresolved  bot-review 1001 --toc --unresolved
check bot-review-bots            bot-review 1001 --bots
# Same timeline, a threads payload where the bot holds the only open thread.
check_pair bot-review-only-open-toc-unresolved bot-review bot-review-only-open 1001 --toc --unresolved
# --since-last-review is a window from the anchoring review on, and a held
# bot review is inside it exactly when it was submitted after the anchor.
# No human review to anchor on is the full-timeline fallback, which shows
# both blocks like any full render.
check bot-review-slr-toc              bot-review 1001 --toc --since-last-review
check bot-review-late-toc             bot-review-late 42 --toc
check bot-review-late-slr             bot-review-late 42 --since-last-review
check bot-review-late-slr-toc         bot-review-late 42 --toc --since-last-review
check bot-review-late-slr-bots-toc    bot-review-late 42 --toc --since-last-review --bots
check bot-review-late-slr-unresolved-toc bot-review-late 42 --toc --unresolved --since-last-review
# An empty slice under --unresolved says so, because the header still counts
# the open thread that lies before the anchor.
check multi-slr-unresolved-toc        multi 42 --toc --unresolved --since-last-review

# hidden-* — a minimized comment keeps its header line, gains a
# `(hidden: <reason>)` marker, and loses its body unless --hidden is passed.
check hidden-full            hidden 1001
check hidden-toc             hidden 1001 --toc
check hidden-shown           hidden 1001 --hidden
check hidden-toc-unresolved  hidden 1001 --toc --unresolved
check hidden-bots-shown      hidden 1001 --bots --hidden
# hidden-review-* — the same treatment on a review: the marker on its line,
# the body withheld unless --hidden, its threads rendered either way.
check hidden-review-full           hidden-review 44
check hidden-review-toc            hidden-review 44 --toc
check hidden-review-shown          hidden-review 44 --hidden
check hidden-review-latest         hidden-review 44 --latest
check hidden-review-toc-unresolved hidden-review 44 --toc --unresolved
check hidden-review-slr            hidden-review 44 --since-last-review

# only-* — --only keeps the kinds of item asked for and leaves the counts
# line as it was. A review left out keeps its threads when thread is asked
# for; review alone drops them; a filter that keeps nothing says so.
check basic-only-comment-toc      basic 1001 --toc --only comment
check basic-only-comment          basic 1001 --only comment
check basic-only-thread-toc       basic 1001 --toc --only thread
check basic-only-review           basic 1001 --only review
check basic-only-review-thread-toc basic 1001 --toc --only review,thread
check bot-review-only-thread-toc  bot-review 1001 --toc --only thread
check multi-only-none-toc         multi 42 --toc --only force-push

# ---------------------------------------------------------------------------
# Non-golden cases. Everything above diffs a committed golden; everything
# below asserts exit codes and substrings instead, because its input is built
# at runtime (an oversized payload, a stub gh, an interrupt) and the
# interesting part is a handful of lines rather than a whole render.
#
# They share one reporter. A case appends to `problems`, then calls report;
# an empty list is a pass. Adding a case means adding assertions, not another
# copy of the t_fail plumbing.
# ---------------------------------------------------------------------------
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
    t_fail "$name" "$dtmp" "tests/test-gh-comments-pr.zsh" "$title"
    rm -f "$dtmp"
    (( fails += 1 ))
  fi
  problems=()
  return 0
}

# threads-match-header — the counts line is the promise the skill tells
# readers to trust, and the goldens above would happily re-record a thread
# that went missing. So this says it independently of any expected file, for
# every PR fixture pair in the directory (a new fixture is covered the day it
# lands): the number of thread lines in --toc equals `inline threads: N`, and
# the number of OPEN thread lines in --toc --unresolved equals `(N open)` —
# with and without --bots, since the bug was in the filtered view.
threads_match_header() {
  local name=threads-match-header th tl base out hdr flags
  local -i rc=0 want_all want_open got
  # A threads payload that pairs with another fixture's timeline is named
  # here. Any other *.th.json without a sibling .tl.json is a mistake, and
  # the case says so rather than checking it against a timeline it was not
  # written for.
  local -A shared_tl=(bot-review-only-open bot-review)
  for th in "$fx"/*.th.json; do
    base=${th:t:r:r}
    tl=$fx/$base.tl.json
    if [[ ! -r $tl ]]; then
      if [[ -n ${shared_tl[$base]:-} ]]; then tl=$fx/${shared_tl[$base]}.tl.json
      else problems+=("$base: no $base.tl.json and no shared_tl entry"); continue; fi
    fi
    for flags in "" "--bots"; do
      out=$(zsh "$script" --pr 1 --toc ${=flags} --fixtures "$tl" "$th" 2>&1) || { rc=$?; problems+=("$base $flags: exit $rc"); continue; }
      # `inline threads: 3 (2 open)` — parse from that label, not from the
      # first `(` on the line, which on a bot fixture is `(+1 bot filtered)`.
      hdr=${"$(print -r -- "$out" | sed -n '2p')"#*inline threads: }
      want_all=${hdr%% *}
      want_open=${${hdr#*\(}%% open*}
      got=$(print -r -- "$out" | grep -c '^thread ')
      (( got == want_all )) || problems+=("$base $flags: --toc shows $got thread lines, header says $want_all")
      out=$(zsh "$script" --pr 1 --toc --unresolved ${=flags} --fixtures "$tl" "$th" 2>&1) || { rc=$?; problems+=("$base $flags: --unresolved exit $rc"); continue; }
      got=$(print -r -- "$out" | grep -c '^thread .* OPEN')
      (( got == want_open )) || problems+=("$base $flags: --toc --unresolved shows $got OPEN threads, header says $want_open")
      if (( want_open > 0 )) && [[ "$out" == *"(no unresolved threads)"* ]]; then
        problems+=("$base $flags: says (no unresolved threads) under a header counting $want_open open")
      fi
    done
  done
  report "$name" "threads vs header" $rc "$out"
  return 0
}
threads_match_header

# slice-matches-full — a slice (--since-last-review, --latest) is the one
# view that shows fewer threads than the header counts, so
# threads-match-header cannot run over it, and the slice goldens above pin it
# on a few fixtures only. This says what a slice *is*, for both flags, every
# fixture pair, every author on it, and an author nobody is, with and without
# --bots: the full --toc render from the anchor on, with the two titled
# blocks cut to the same window. Everything but the orphan rule is read off
# rendered output, so the case restates no rendering logic beyond which line
# is the anchor:
#   - the items are a suffix of the full render, from its anchor line — the
#     last review line for --since-last-review (passing over a hidden one
#     with no threads), the last substantive line for --latest (a review
#     with threads or a body that is not hidden, or a comment with a body
#     that is not hidden), the named author's when one is named — and
#     nested threads travel with their review, so none can go missing
#     inside the window;
#   - a held bot thread is in exactly when its review sits after the anchor,
#     read from the --bots render, where bot reviews stand in timeline order;
#   - an orphan is in exactly when one of its comments is dated at or after
#     the anchor — the one rule the TOC cannot show, so those dates come from
#     the threads payload and the anchor's from the timeline;
#   - no slice line is absent from the full render;
#   - --toc --unresolved over the same slice shows exactly the OPEN threads
#     the slice shows, and says "(no unresolved threads" exactly when there
#     are none;
#   - an author nobody matches, and a fixture with nothing to anchor on, fall
#     back to the full render plus the note.
typeset -ga _sec_head _sec_items _sec_orph _sec_held
_slice_sections() {
  local l sec=head
  _sec_head=() _sec_items=() _sec_orph=() _sec_held=()
  for l in "${(@f)1}"; do
    if [[ $sec == head ]]; then
      if [[ -z $l ]]; then sec=items; else _sec_head+=("$l"); fi
      continue
    fi
    case $l in
      'threads with no parent review:') sec=orph; continue ;;
      'threads in filtered bot reviews:') sec=held; continue ;;
    esac
    case $sec in
      items) [[ $l == 'body '* ]] || _sec_items+=("$l") ;;
      orph)  _sec_orph+=("$l") ;;
      held)  _sec_held+=("$l") ;;
    esac
  done
}
# A review line --since-last-review passes over: hidden, with no threads.
_slice_hidden_bare() {
  local rest=${1#*[0-9][0-9]:[0-9][0-9]\] }
  [[ ${${rest#*, }%% *} == 0 && $rest == *'open) (hidden: '* ]]
}
# A --latest candidate, read off its TOC line: a review with threads, or one
# with a body preview that is not hidden (a hidden review with no threads
# never counts, even when --hidden shows its preview), or a comment with a
# preview and no (hidden: …) marker. A TOC line does not show whether a
# thread's comments are hidden, so this counts every thread; no committed
# fixture has one whose comments are all hidden, and anchor-needs-live-thread
# covers that case on derived copies. The `[login date time]` header is cut
# at its closing `HH:MM]`, not the first `]` — `vercel[bot]` has one of its
# own.
_slice_substantive() {
  local rest
  case $1 in
    'review  ['*) _slice_hidden_bare "$1" && return 1
                  rest=${1#*[0-9][0-9]:[0-9][0-9]\] }; [[ ${${rest#*, }%% *} != 0 || -n ${rest#*open\)} ]] ;;
    'comment ['*) rest=${1#*[0-9][0-9]:[0-9][0-9]\]}; [[ -n $rest && $rest != ' (hidden:'* ]] ;;
    *) false ;;
  esac
}
slice_matches_full() {
  local name=slice-matches-full th tl base flags mode mflag v login atype full slice uns botsfull anchor note key l ts ats
  local -i rc=0 i ai after isbot want
  local -a flines slines ulines rlogins clogins variants fitems sitems forph sorph fheld sheld bitems sopen uopen
  local -A shared_tl=(bot-review-only-open bot-review) maxts
  for th in "$fx"/*.th.json; do
    base=${th:t:r:r}
    tl=$fx/$base.tl.json
    if [[ ! -r $tl ]]; then
      if [[ -n ${shared_tl[$base]:-} ]]; then tl=$fx/${shared_tl[$base]}.tl.json
      else continue; fi   # threads-match-header already reports an unpaired payload
    fi
    # path:line → the newest comment date on that thread, for the orphan rule.
    maxts=()
    while IFS=$'\t' read -r key ts; do
      [[ -z ${maxts[$key]:-} || $ts > ${maxts[$key]} ]] && maxts[$key]=$ts
    done < <(jq -r '[.. | objects | select(has("isResolved"))][]
      | "\(.path):\(.line // .originalLine // "?")\t\([.comments.nodes[]?.createdAt // empty] | max // "")"' "$th")
    for flags in "" "--bots"; do
      full=$(zsh "$script" --pr 1 --toc ${=flags} --fixtures "$tl" "$th" 2>&1) || { rc=$?; problems+=("$base $flags: exit $rc"); continue; }
      flines=("${(@f)full}")
      _slice_sections "$full"
      fitems=("${_sec_items[@]}") forph=("${_sec_orph[@]}") fheld=("${_sec_held[@]}")
      rlogins=() clogins=()
      for l in "${fitems[@]}"; do
        case $l in
          'review  ['*) rlogins+=("${${l#*\[}%% *}") ;;
          'comment ['*) clogins+=("${${l#*\[}%% *}") ;;
        esac
      done
      bitems=()
      if [[ -z $flags ]]; then
        botsfull=$(zsh "$script" --pr 1 --toc --bots --fixtures "$tl" "$th" 2>&1) || { rc=$?; problems+=("$base --bots: exit $rc"); continue; }
        _slice_sections "$botsfull"; bitems=("${_sec_items[@]}")
      fi
      for mode in slr latest; do
      if [[ $mode == slr ]]; then mflag=--since-last-review; variants=(${(u)rlogins})
      else mflag=--latest; variants=(${(u)rlogins} ${(u)clogins}); fi
      variants=("" "=nobody-wrote-this" ${${(u)variants}/#/=})
      for v in "${variants[@]}"; do
        slice=$(zsh "$script" --pr 1 --toc $mflag$v ${=flags} --fixtures "$tl" "$th" 2>&1) || { rc=$?; problems+=("$base $flags $mode$v: exit $rc"); continue; }
        uns=$(zsh "$script" --pr 1 --toc --unresolved $mflag$v ${=flags} --fixtures "$tl" "$th" 2>&1) || { rc=$?; problems+=("$base $flags $mode$v: --unresolved exit $rc"); continue; }
        # Quoted array expansions throughout: an unquoted one drops the empty
        # element that is the blank line after the header.
        slines=("${(@f)slice}")
        note=${(M)slines:#note: no matching *}
        slines=("${(@)slines:#note: *}")
        # The anchor: the last review line (slr, past a hidden one with no
        # threads) or substantive line (latest)
        # in the full render, by the named author when one is named. None
        # means the fallback is expected.
        ai=0
        for (( i = ${#fitems}; i >= 1; i-- )); do
          l=${fitems[i]}
          if [[ $mode == slr ]]; then [[ $l == 'review  ['* ]] && ! _slice_hidden_bare "$l" || continue
          else _slice_substantive "$l" || continue; fi
          [[ -z $v || ${${l#*\[}%% *} == ${v#=} ]] && { ai=i; break; }
        done
        if (( ai == 0 )); then
          if [[ -z $note ]]; then
            problems+=("$base $flags $mode$v: nothing to anchor on, but no fallback note"); continue
          fi
          if [[ ${(F)slines} != "$full" ]]; then
            problems+=("$base $flags $mode$v: fallback is not the full render")
          fi
        else
          if [[ -n $note ]]; then
            problems+=("$base $flags $mode$v: a review matched, yet a fallback note"); continue
          fi
          [[ ${slines[1]} == "${flines[1]}" && ${slines[2]} == "${flines[2]}" ]] ||
            problems+=("$base $flags $mode$v: header differs from the full render")
          _slice_sections "$slice"
          sitems=("${_sec_items[@]}") sorph=("${_sec_orph[@]}") sheld=("${_sec_held[@]}")
          [[ ${(F)sitems} == "${(F)fitems[ai,-1]}" ]] ||
            problems+=("$base $flags $mode$v: items are not the full render from the anchor on")
          # Orphans: by date, against the anchor's timestamp in the payload —
          # a review's submittedAt, a comment's createdAt.
          atype=PullRequestReview; [[ ${fitems[ai]} == 'comment ['* ]] && atype=IssueComment
          anchor=${fitems[ai]#*\[}
          login=${anchor%% *}; ts=${anchor#* }; ts=${${ts%%\]*}/ /T}
          ats=$(jq -r --arg t "$atype" --arg l "$login" --arg m "$ts" '[.. | objects
            | select((.__typename? // "") == $t and (.author.login? // "") == $l
                     and (((.submittedAt? // .createdAt?) // "") | startswith($m)))]
            | last | (.submittedAt // .createdAt) // empty' "$tl")
          [[ -n $ats ]] || problems+=("$base $flags $mode$v: anchor $login $ts not found in the timeline payload")
          for l in "${forph[@]}"; do
            key=${${l#thread  }%% *}
            want=0; [[ -n $ats && ( ${maxts[$key]:-} > $ats || ${maxts[$key]:-} == $ats ) ]] && want=1
            (( (${sorph[(Ie)$l]} > 0) == want )) ||
              problems+=("$base $flags $mode$v: orphan $key $( (( want )) && echo missing || echo present ) (newest comment ${maxts[$key]:-?}, anchor $ats)")
          done
          for l in "${sorph[@]}"; do
            (( ${forph[(Ie)$l]} )) || problems+=("$base $flags $mode$v: orphan line not in the full render: $l")
          done
          # Held bot threads: by position, read from the --bots render.
          after=0 isbot=0
          for l in "${bitems[@]}"; do
            [[ $l == "${fitems[ai]}" ]] && after=1
            if [[ $l == 'review  ['* ]]; then
              isbot=1; (( ${fitems[(Ie)$l]} )) && isbot=0
            elif [[ $l != 'thread  '* ]]; then
              isbot=0
            elif (( isbot )); then
              (( (${sheld[(Ie)$l]} > 0) == after )) ||
                problems+=("$base $flags $mode$v: held thread $( (( after )) && echo missing || echo present ): $l")
            fi
          done
          for l in "${sheld[@]}"; do
            (( ${fheld[(Ie)$l]} )) || problems+=("$base $flags $mode$v: held line not in the full render: $l")
          done
        fi
        # --unresolved over the same slice: exactly the OPEN threads it shows.
        ulines=("${(@)${(@f)uns}:#note: *}")
        sopen=(${(o)${(M)slines:#thread  * OPEN*}})
        uopen=(${(o)${(M)ulines:#thread  * OPEN*}})
        [[ ${(F)uopen} == "${(F)sopen}" ]] ||
          problems+=("$base $flags $mode$v: --unresolved shows ${#uopen} OPEN threads, the slice shows ${#sopen}")
        if (( ${#sopen} == 0 )); then
          [[ $uns == *'(no unresolved threads'* ]] || problems+=("$base $flags $mode$v: no OPEN thread in the slice, but --unresolved does not say so")
        else
          [[ $uns != *'(no unresolved threads'* ]] || problems+=("$base $flags $mode$v: --unresolved says no unresolved threads over ${#sopen} OPEN in the slice")
        fi
      done
      done
    done
  done
  report "$name" "slice vs full render" $rc "$slice"
  return 0
}
slice_matches_full

# hidden-bodies-gated — said independently of the goldens: a hidden body never
# renders by default, always renders under --hidden, and the counts line names
# the hidden count either way, with the bot gate applied first, on the
# comments and on the reviews alike.
hidden_bodies_gated() {
  local name=hidden-bodies-gated out def shown
  local -i rc=0
  local tl=$fx/hidden.tl.json th=$fx/hidden.th.json
  def=$(zsh "$script" --pr 1001 --fixtures "$tl" "$th" 2>&1) || { rc=$?; problems+=("default run exited $rc"); }
  shown=$(zsh "$script" --pr 1001 --hidden --fixtures "$tl" "$th" 2>&1) || { rc=$?; problems+=("--hidden run exited $rc"); }
  # dave's hidden top-level comment and romansod's hidden thread reply.
  [[ "$def" != *"guard is inverted"* ]] || problems+=("a hidden top-level body rendered by default")
  [[ "$def" != *"the probe now rethrows"* ]] || problems+=("a hidden thread reply rendered by default")
  [[ "$def" == *"comment [dave 2026-08-14 22:00] (hidden: outdated)"* ]] \
    || problems+=("the hidden top-level comment lost its marker line")
  [[ "$def" == *"[romansod 2026-08-14 23:41] (hidden: resolved)"* ]] \
    || problems+=("the hidden thread reply lost its marker line")
  [[ "$shown" == *"guard is inverted"* && "$shown" == *"the probe now rethrows"* ]] \
    || problems+=("--hidden did not render the hidden bodies")
  # The number counts rendered lines, marker included, so it reads the same
  # with and without --hidden and matches a count of `comment` lines.
  [[ "$def" == *"top-level comments: 2 (+1 bot filtered) (1 hidden)"* ]] \
    || problems+=("default counts: $(print -r -- "$def" | sed -n 2p)")
  [[ "$shown" == *"top-level comments: 2 (+1 bot filtered) (1 hidden)"* ]] \
    || problems+=("--hidden counts: $(print -r -- "$shown" | sed -n 2p)")
  (( $(print -r -- "$def" | grep -c '^comment ') == 2 )) \
    || problems+=("default render: $(print -r -- "$def" | grep -c '^comment ') comment lines under a header counting 2")
  # With --bots the hidden bot comment moves from the bot tally to the hidden one.
  out=$(zsh "$script" --pr 1001 --toc --bots --fixtures "$tl" "$th" 2>&1) || { rc=$?; problems+=("--bots run exited $rc"); }
  [[ "$out" == *"top-level comments: 3 (incl. 1 bot) (2 hidden)"* ]] \
    || problems+=("--bots counts: $(print -r -- "$out" | sed -n 2p)")
  (( $(print -r -- "$out" | grep -c '^comment ') == 3 )) \
    || problems+=("--bots render: $(print -r -- "$out" | grep -c '^comment ') comment lines under a header counting 3")
  out=$(zsh "$script" --pr 1001 --toc --bots --hidden --fixtures "$tl" "$th" 2>&1) || { rc=$?; problems+=("--bots --hidden run exited $rc"); }
  [[ "$out" == *"top-level comments: 3 (incl. 1 bot) (2 hidden)"* ]] \
    || problems+=("--bots --hidden counts: $(print -r -- "$out" | sed -n 2p)")
  # The same gate on reviews: carol's hidden review, re-typed as a bot's in a
  # copy of the hidden-review timeline, counts as a bot until --bots puts it
  # back among the hidden.
  local btl rth=$fx/hidden-review.th.json
  btl=$(mktemp) || { problems+=("mktemp failed"); report "$name" "hidden comments" 1 "$def"; return 0; }
  jq '(.[].data.repository.pullRequest.timelineItems.nodes[]
       | select(.__typename == "PullRequestReview" and .author.login == "carol")
       | .author) |= {login: "carol[bot]", __typename: "Bot"}' \
    "$fx/hidden-review.tl.json" > "$btl" || problems+=("could not derive the bot-review timeline")
  out=$(zsh "$script" --pr 44 --toc --fixtures "$btl" "$rth" 2>&1) || { rc=$?; problems+=("bot-review run exited $rc"); }
  [[ "$out" == *"reviews: 2 (+1 bot filtered) (1 hidden)"* ]] \
    || problems+=("review counts: $(print -r -- "$out" | sed -n 2p)")
  out=$(zsh "$script" --pr 44 --toc --bots --fixtures "$btl" "$rth" 2>&1) || { rc=$?; problems+=("bot-review --bots run exited $rc"); }
  [[ "$out" == *"reviews: 3 (incl. 1 bot) (2 hidden)"* ]] \
    || problems+=("--bots review counts: $(print -r -- "$out" | sed -n 2p)")
  rm -f "$btl"
  report "$name" "hidden comments" $rc "$def"
  return 0
}
hidden_bodies_gated

# threads-errors-refused — a saved threads payload gh failed on. The capture
# command keeps the page gh printed before exiting non-zero, so a th.json can
# carry errors[]; the live threads fetch rides set -e and never renders one.
# --fixtures must refuse it the same way, in the default and --toc views,
# rather than render the PR with its threads missing.
threads_errors_refused() {
  local name=threads-errors-refused tmp out view
  local -i rc=0
  tmp=$(mktemp -d) || {
    t_fail "$name" "" "tests/test-gh-comments-pr.zsh" "mktemp -d failed"
    (( fails += 1 )); return 0
  }
  jq '(.[0].errors) = [{"type":"FORBIDDEN","path":["repository","pullRequest","reviewThreads"],"message":"Resource not accessible by personal access token"}]' \
    "$fx/all-resolved.th.json" > "$tmp/errors.th.json"
  # And two captures gh stopped with no errors[]: the last page saying more
  # follow (the connection dropped), and a page that is a REST-shaped error
  # body rather than a GraphQL response (a rate limit).
  jq '(.[-1].data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage) = true' \
    "$fx/all-resolved.th.json" > "$tmp/truncated.th.json"
  jq '.[0] = {"message":"You have exceeded a secondary rate limit.","documentation_url":"https://docs.github.com/"}' \
    "$fx/all-resolved.th.json" > "$tmp/restbody.th.json"
  # And that body as a second page after a good first one, the shape gh
  # leaves when the limit bites mid-pagination; only this variant tells a
  # gate on every page from one on the first.
  jq '. + [{"message":"You have exceeded a secondary rate limit.","documentation_url":"https://docs.github.com/"}]' \
    "$fx/all-resolved.th.json" > "$tmp/restlast.th.json"
  # And no page at all: what `jq -s .` saves when gh fails before printing
  # one. A PR must not render as having no threads.
  print -r -- '[]' > "$tmp/empty.th.json"
  local spec
  for spec in errors truncated restbody restlast empty; do
    for view in "" "--toc"; do
      rc=0
      out=$(zsh "$script" --pr 1 ${=view} --fixtures "$fx/all-resolved.tl.json" "$tmp/$spec.th.json" 2>&1) || rc=$?
      (( rc == 1 )) || problems+=("$spec: exit $rc (want 1) with ${view:-the default view}")
      [[ "$out" != "PR #"* ]] || problems+=("$spec: rendered with ${view:-the default view}")
    done
    case $spec in
      errors)    [[ "$out" == *"errors"* ]] || problems+=("errors: output lacks the error diagnosis") ;;
      truncated) [[ "$out" == *"stopped before its last page"* ]] || problems+=("truncated: output lacks the incomplete-capture refusal") ;;
      restbody|restlast) [[ "$out" == *"not a GraphQL response"* ]] || problems+=("$spec: output lacks the not-a-response refusal") ;;
      empty)     [[ "$out" == *"holds no page"* ]] || problems+=("empty: output lacks the no-page refusal") ;;
    esac
  done
  report "$name" "fixture shapes" $rc "$out"
  rm -rf "$tmp"
  return 0
}
threads_errors_refused

# fallback-is-toc — a slicing flag that matches nothing must print the TOC
# and nothing more: the output minus its note line is byte-identical to a
# plain --toc run, and so strictly smaller than the full render it used to
# fall back to. Three fixtures, because the
# TOC's orphan block (basic) and held-bot-thread block (bot-review) render
# under a gate the fallback shares with a matching slice, and multi has
# neither — on it alone, hiding both blocks under every slicing flag would
# still pass.
fallback_is_toc() {
  local name=fallback-is-toc toc full fb flag fixture num
  local -i rc=0
  for fixture num in multi 42 basic 1001 bot-review 1001; do
    toc=$(zsh "$script" --pr $num --toc --fixtures "$fx/$fixture.tl.json" "$fx/$fixture.th.json" 2>&1) || { rc=$?; problems+=("$fixture: --toc run exited $rc"); }
    full=$(zsh "$script" --pr $num --fixtures "$fx/$fixture.tl.json" "$fx/$fixture.th.json" 2>&1) || { rc=$?; problems+=("$fixture: full run exited $rc"); }
    for flag in --since-last-review=nobody --latest=nobody; do
      fb=$(zsh "$script" --pr $num $flag --fixtures "$fx/$fixture.tl.json" "$fx/$fixture.th.json" 2>&1) || { rc=$?; problems+=("$fixture $flag run exited $rc"); continue; }
      [[ "$fb" == *$'\nnote: no matching'*" — showing the TOC instead"$'\n'* ]] \
        || problems+=("$fixture $flag: no fallback note in the output")
      [[ "$(print -r -- "$fb" | grep -v '^note: ')" == "$toc" ]] \
        || problems+=("$fixture $flag: the fallback is not the TOC")
      (( ${#fb} < ${#full} )) || problems+=("$fixture $flag: the fallback is not smaller than the full render")
    done
  done
  report "$name" "fallback" $rc "$fb"
  return 0
}
fallback_is_toc

# fallback-keeps-narrowing — the TOC fallback is for the case where the
# alternative is the unfiltered full timeline. Under --unresolved or --since
# the view is already narrow, so a no-match slice shows that view exactly as
# the same run without the slicing flag would, bodies included, and the note
# names the view. Forcing the TOC there stripped the thread bodies from the
# one flag the docs point at for them.
fallback_keeps_narrowing() {
  local name=fallback-keeps-narrowing want fb c flags view slice what
  local -i rc=0
  local -a cases=(
    "--unresolved|the unresolved view"
    "--since 2026-08-12|the --since window"
    "--unresolved --since 2026-08-12|the unresolved view"
  )
  for c in $cases; do
    flags=${c%%|*} view=${c#*|}
    want=$(zsh "$script" --pr 42 ${=flags} --fixtures "$fx/multi.tl.json" "$fx/multi.th.json" 2>&1) || { rc=$?; problems+=("$flags run exited $rc"); }
    # Both slicing flags, each with its own note prefix: the rule lives in
    # one binding, but each note branch interpolates it separately.
    for slice what in --since-last-review=nobody "earlier review" --latest=nobody "review or comment"; do
      fb=$(zsh "$script" --pr 42 ${=flags} $slice --fixtures "$fx/multi.tl.json" "$fx/multi.th.json" 2>&1) || { rc=$?; problems+=("$flags $slice run exited $rc"); continue; }
      [[ "$fb" == *$'\n'"note: no matching $what — showing $view instead"$'\n'* ]] \
        || problems+=("$flags $slice: the note does not name $view")
      [[ "$(print -r -- "$fb" | grep -v '^note: ')" == "$want" ]] \
        || problems+=("$flags $slice: the fallback changed the narrowed view")
    done
  done
  report "$name" "fallback" $rc "$fb"
  return 0
}
fallback_keeps_narrowing

# latest-skips-hidden — a hidden comment, or a hidden review's body, is not
# substantive. dave's only comment on the hidden fixture is minimized, so
# --latest=dave has nothing to slice from and falls back.
latest_skips_hidden() {
  local name=latest-skips-hidden out
  local -i rc=0
  out=$(zsh "$script" --pr 1001 --latest=dave --fixtures "$fx/hidden.tl.json" "$fx/hidden.th.json" 2>&1) || { rc=$?; problems+=("exit $rc"); }
  [[ "$out" == *"note: no matching review or comment"* ]] \
    || problems+=("--latest sliced from a hidden comment")
  out=$(zsh "$script" --pr 1001 --latest=dave --hidden --fixtures "$fx/hidden.tl.json" "$fx/hidden.th.json" 2>&1) || { rc=$?; problems+=("--hidden exit $rc"); }
  # --hidden shows hidden bodies; it does not make a hidden comment the
  # latest thing said.
  [[ "$out" == *"note: no matching review or comment"* ]] \
    || problems+=("--hidden made a hidden comment substantive")
  # A review is no different: carol's only review is hidden and has no
  # threads, so its body is all it had to say. alice's hidden review keeps
  # its threads, which are substance of their own, so it can still anchor.
  local rtl=$fx/hidden-review.tl.json rth=$fx/hidden-review.th.json
  out=$(zsh "$script" --pr 44 --latest=carol --hidden --fixtures "$rtl" "$rth" 2>&1) || { rc=$?; problems+=("hidden-review exit $rc"); }
  [[ "$out" == *"note: no matching review or comment"* ]] \
    || problems+=("--latest sliced from a hidden review with no threads")
  # On the fixture alice also has a later visible comment, which --latest=alice
  # would anchor on whatever the rule says about her review, so the check runs
  # on a copy without that comment: the hidden review is all she said.
  local atl
  atl=$(mktemp) || { problems+=("mktemp failed"); report "$name" "latest" 1 ""; return 0; }
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        map(select((.__typename == "IssueComment" and .author.login == "alice") | not))' \
    "$rtl" > "$atl" || problems+=("could not derive the alice-only timeline")
  out=$(zsh "$script" --pr 44 --toc --latest=alice --fixtures "$atl" "$rth" 2>&1) || { rc=$?; problems+=("hidden-review alice exit $rc"); }
  rm -f "$atl"
  [[ "$out" != *"note: no matching"* ]] \
    || problems+=("a hidden review with threads did not count as substantive")
  [[ "$(print -r -- "$out" | grep -v '^body ' | sed -n 4p)" == 'review  [alice 2026-08-10 12:00] '*'(hidden: outdated)' ]] \
    || problems+=("--latest=alice did not anchor on her hidden review: $(print -r -- "$out" | grep -v '^body ' | sed -n 4p)")
  report "$name" "latest" $rc "$out"
  return 0
}
latest_skips_hidden
# slr-skips-hidden — --since-last-review passes over a review GitHub hid
# that has no threads, as --latest does: on the hidden-review fixture
# carol's spam review is last, so the slice starts at bob's approval. alice's
# hidden review keeps its threads and can still anchor, so naming her slices
# from it; naming carol, whose only review is hidden, falls back.
slr_skips_hidden() {
  local name=slr-skips-hidden out first
  local -i rc=0
  local rtl=$fx/hidden-review.tl.json rth=$fx/hidden-review.th.json
  out=$(zsh "$script" --pr 44 --toc --since-last-review --fixtures "$rtl" "$rth" 2>&1) || { rc=$?; problems+=("exit $rc"); }
  first=$(print -r -- "$out" | grep -v '^body ' | sed -n 4p)
  [[ $first == 'review  [bob 2026-08-11 14:00] APPROVED'* ]] \
    || problems+=("--since-last-review did not pass over carol's hidden review: $first")
  # --hidden shows hidden bodies; it does not make carol's hidden review the
  # last review said, any more than it does for --latest.
  out=$(zsh "$script" --pr 44 --toc --since-last-review --hidden --fixtures "$rtl" "$rth" 2>&1) || { rc=$?; problems+=("--hidden exit $rc"); }
  first=$(print -r -- "$out" | grep -v '^body ' | sed -n 4p)
  [[ $first == 'review  [bob 2026-08-11 14:00] APPROVED'* ]] \
    || problems+=("--since-last-review --hidden anchored elsewhere: $first")
  out=$(zsh "$script" --pr 44 --toc --since-last-review=alice --fixtures "$rtl" "$rth" 2>&1) || { rc=$?; problems+=("alice exit $rc"); }
  first=$(print -r -- "$out" | grep -v '^body ' | sed -n 4p)
  [[ $first == 'review  [alice 2026-08-10 12:00] '*'(hidden: outdated)' ]] \
    || problems+=("--since-last-review=alice did not anchor on her hidden review with threads: $first")
  out=$(zsh "$script" --pr 44 --toc --since-last-review=carol --fixtures "$rtl" "$rth" 2>&1) || { rc=$?; problems+=("carol exit $rc"); }
  [[ "$out" == *"note: no matching earlier review"* ]] \
    || problems+=("--since-last-review=carol sliced from a hidden review with no threads")
  report "$name" "since-last-review" $rc "$out"
  return 0
}
slr_skips_hidden
# anchor-needs-live-thread — a thread makes a hidden review an anchor only
# while it has a comment that is not hidden. Derived from the hidden-review
# payloads, since the slice invariant reads TOC lines, which do not show a
# thread comment's hidden state: with every comment on alice's two threads
# hidden, her hidden review falls back under both flags; with all hidden but
# bob's reply on one thread, that reply still anchors it, and so does alice's
# opening comment when the reply under it is the hidden one; and a thread with
# replies past the fetched page anchors it, since those may be visible. The
# --latest rule holds for a visible review too: made visible with an empty
# body, alice's review with every thread comment hidden falls back, though
# --since-last-review, which anchors on any visible review, still takes it.
anchor_needs_live_thread() {
  local name=anchor-needs-live-thread out first f atl vtl
  local -i rc=0
  local rtl=$fx/hidden-review.tl.json rth=$fx/hidden-review.th.json
  local -A th
  # As in latest-skips-hidden: without her later comment, --latest=alice can
  # only anchor on her review.
  atl=$(mktemp) && vtl=$(mktemp) && th[all]=$(mktemp) && th[one]=$(mktemp) && th[first]=$(mktemp) && th[more]=$(mktemp) ||
    { problems+=("mktemp failed"); report "$name" "anchors" 1 ""; return 0; }
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        map(select((.__typename == "IssueComment" and .author.login == "alice") | not))' \
    "$rtl" > "$atl" || problems+=("could not derive the alice-only timeline")
  jq '(.[].data.repository.pullRequest.timelineItems.nodes[] | select(.id == "PRR_r1"))
        |= (.isMinimized = false | .minimizedReason = null | .body = "")' \
    "$atl" > "$vtl" || problems+=("could not derive the visible-review timeline")
  # hide(a; p): minimize every comment by a on alice's threads whose path
  # matches p.
  local hide='def hide(a; p): (.[].data.repository.pullRequest.reviewThreads.nodes[]
      | select(.comments.nodes[0].pullRequestReview.id == "PRR_r1" and (.path | test(p)))
      | .comments.nodes[] | select(.author.login | test(a)))
      |= (.isMinimized = true | .minimizedReason = "OUTDATED");'
  jq "$hide hide(\".\"; \".\")" "$rth" > "${th[all]}" || problems+=("could not derive the all-hidden threads")
  jq "$hide hide(\"alice\"; \".\")" "$rth" > "${th[one]}" || problems+=("could not derive the one-reply threads")
  jq "$hide hide(\"bob\"; \".\") | hide(\".\"; \"cursor\")" "$rth" > "${th[first]}" ||
    problems+=("could not derive the hidden-reply threads")
  jq "$hide hide(\".\"; \".\") | (.[].data.repository.pullRequest.reviewThreads.nodes[]
      | select(.path == \"src/api/cursor.ts\") | .comments.pageInfo) = {hasNextPage: true}" \
    "$rth" > "${th[more]}" || problems+=("could not derive the truncated thread")
  out=$(zsh "$script" --pr 44 --toc --since-last-review=alice --fixtures "$rtl" "${th[all]}" 2>&1) || { rc=$?; problems+=("all slr exit $rc"); }
  [[ "$out" == *"note: no matching earlier review"* ]] \
    || problems+=("--since-last-review=alice anchored on a hidden review whose thread comments are all hidden")
  out=$(zsh "$script" --pr 44 --toc --latest=alice --fixtures "$atl" "${th[all]}" 2>&1) || { rc=$?; problems+=("all latest exit $rc"); }
  [[ "$out" == *"note: no matching review or comment"* ]] \
    || problems+=("--latest=alice anchored on a hidden review whose thread comments are all hidden")
  for f in one first more; do
    out=$(zsh "$script" --pr 44 --toc --since-last-review=alice --fixtures "$rtl" "${th[$f]}" 2>&1) || { rc=$?; problems+=("$f slr exit $rc"); }
    first=$(print -r -- "$out" | grep -v '^body ' | sed -n 4p)
    [[ $first == 'review  [alice 2026-08-10 12:00] '*'(hidden: outdated)' ]] \
      || problems+=("$f: --since-last-review=alice did not anchor on her hidden review: $first")
    out=$(zsh "$script" --pr 44 --toc --latest=alice --fixtures "$atl" "${th[$f]}" 2>&1) || { rc=$?; problems+=("$f latest exit $rc"); }
    first=$(print -r -- "$out" | grep -v '^body ' | sed -n 4p)
    [[ $first == 'review  [alice 2026-08-10 12:00] '*'(hidden: outdated)' ]] \
      || problems+=("$f: --latest=alice did not anchor on her hidden review: $first")
  done
  out=$(zsh "$script" --pr 44 --toc --latest=alice --fixtures "$vtl" "${th[all]}" 2>&1) || { rc=$?; problems+=("visible latest exit $rc"); }
  [[ "$out" == *"note: no matching review or comment"* ]] \
    || problems+=("--latest=alice anchored on a visible bodyless review whose thread comments are all hidden")
  out=$(zsh "$script" --pr 44 --toc --since-last-review=alice --fixtures "$vtl" "${th[all]}" 2>&1) || { rc=$?; problems+=("visible slr exit $rc"); }
  first=$(print -r -- "$out" | grep -v '^body ' | sed -n 4p)
  [[ $first == 'review  [alice 2026-08-10 12:00] CHANGES_REQUESTED, 2 threads (1 open)' ]] \
    || problems+=("--since-last-review=alice did not anchor on her visible review: $first")
  out=$(zsh "$script" --pr 44 --toc --latest=alice --fixtures "$vtl" "${th[one]}" 2>&1) || { rc=$?; problems+=("visible one latest exit $rc"); }
  first=$(print -r -- "$out" | grep -v '^body ' | sed -n 4p)
  [[ $first == 'review  [alice 2026-08-10 12:00] CHANGES_REQUESTED, 2 threads (1 open)' ]] \
    || problems+=("--latest=alice did not anchor on her visible review through bob's reply: $first")
  rm -f "$atl" "$vtl" "${th[@]}"
  report "$name" "anchors" $rc "$out"
  return 0
}
anchor_needs_live_thread

# item-is-its-block — --item prints the block the full render prints for that
# item, chosen by its TOC line. Every TOC line of each fixture that names one
# item (block titles do not) is fed back whole, under the flags that list
# every item, and the output must be the header that line starts with and
# appear verbatim in the full render under the same flags. A line two items
# share would be refused, and none of these fixtures has one.
item_is_its_block() {
  local name=item-is-its-block base pr line out full head
  local -i rc=0 n=0
  local -a flags
  for base pr flags in basic 1001 '--bots --merges' hidden 1001 '--bots' \
      hidden 1001 '--bots --hidden' bot-review 1001 '--bots' hidden-review 44 ''; do
    full=$(zsh "$script" --pr $pr ${=flags} --fixtures "$fx/$base.tl.json" "$fx/$base.th.json" 2>&1) \
      || { rc=$?; problems+=("$base full exit $rc"); continue; }
    while IFS= read -r line; do
      [[ $line == (body|comment|review|thread|commit|force-push)' '* ]] || continue
      (( n += 1 ))
      out=$(zsh "$script" --pr $pr ${=flags} --item "$line" --fixtures "$fx/$base.tl.json" "$fx/$base.th.json" 2>&1) \
        || { rc=$?; problems+=("$base ${flags:-(no flags)}: exit $rc on: $line"); continue; }
      head=${out%%$'\n'*}
      [[ $line == "$head"* ]] || problems+=("$base: header '$head' does not start the TOC line: $line")
      [[ $full == *"$out"* ]] || problems+=("$base ${flags:-(no flags)}: not a block of the full render: $line")
    done < <(zsh "$script" --pr $pr ${=flags} --toc --fixtures "$fx/$base.tl.json" "$fx/$base.th.json" 2>/dev/null)
  done
  (( n >= 30 )) || problems+=("only $n TOC lines were tried")
  report "$name" "item" $rc "$out"
  return 0
}
item_is_its_block
# item-refusals — a prefix that matches nothing, or more than one item, is an
# error on stderr with nothing on stdout, and several matches are listed, not
# the first taken. Two comments by one author in one minute share a header,
# so a copy of basic with a second such comment is refused on the header
# and resolved by the preview text the TOC line carries after it.
item_refusals() {
  local name=item-refusals out err tl dtl
  local -i rc=0
  tl=$fx/basic.tl.json
  local -a pair=(--fixtures "$tl" "$fx/basic.th.json")
  err=$(zsh "$script" --pr 1001 --item 'comment [nobody' "${pair[@]}" 2>&1 >/dev/null) && problems+=("no match exited 0")
  [[ $err == *"no item starts with: comment [nobody"* ]] || problems+=("no match: $err")
  out=$(zsh "$script" --pr 1001 --item 'comment [nobody' "${pair[@]}" 2>/dev/null) || true
  [[ -z $out ]] || problems+=("no match printed to stdout: $out")
  err=$(zsh "$script" --pr 1001 --item 'commit' "${pair[@]}" 2>&1 >/dev/null) && problems+=("several matches exited 0")
  [[ $err == *"3 items start with: commit"* ]] || problems+=("several: no count: $err")
  [[ $err == *$'\n  commit  1a2b3c4 '*$'\n  commit  e5f6a7b '*$'\n  commit  9d8c7b6 '* ]] \
    || problems+=("several: the matching lines are not listed: $err")
  dtl=$(mktemp) || { problems+=("mktemp failed"); report "$name" "item" 1 ""; return 0; }
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        (. + [(.[] | select(.__typename == "IssueComment" and .author.login == "romansod")
               | .body = "A second note in the same minute.")])' "$tl" > "$dtl" \
    || problems+=("could not derive the same-minute timeline")
  err=$(zsh "$script" --pr 1001 --item 'comment [romansod 2026-08-14 23:40]' --fixtures "$dtl" "$fx/basic.th.json" 2>&1 >/dev/null) \
    && problems+=("a header two comments share exited 0")
  [[ $err == *"2 items start with"*"Thanks @reviewer-bart"*"A second note"* ]] \
    || problems+=("same minute: both lines not listed: $err")
  out=$(zsh "$script" --pr 1001 --item 'comment [romansod 2026-08-14 23:40] A second' --fixtures "$dtl" "$fx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("the preview did not select one: exit $rc"); }
  [[ $out == $'comment [romansod 2026-08-14 23:40]\n  A second note in the same minute.' ]] \
    || problems+=("the preview selected the wrong item: $out")
  # A whole TOC line that begins another one (`LGTM` and `LGTM, thanks`) is
  # still a name: an exact line wins over the lines it is a prefix of.
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        (map(if .__typename == "IssueComment" and .author.login == "romansod" then .body = "LGTM" else . end)
         + [(.[] | select(.__typename == "IssueComment" and .author.login == "romansod") | .body = "LGTM, thanks")])' \
    "$tl" > "$dtl" || problems+=("could not derive the nested timeline")
  out=$(zsh "$script" --pr 1001 --item 'comment [romansod 2026-08-14 23:40] LGTM' --fixtures "$dtl" "$fx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("a whole line that begins another was not selected: exit $rc"); }
  [[ $out == $'comment [romansod 2026-08-14 23:40]\n  LGTM' ]] || problems+=("the exact line selected the wrong item: $out")
  # ...but a bare header is not a name: a comment whose body cleans to
  # nothing has a TOC line that is only its header, the same text as the
  # header prefix the docs teach, so it never wins over the comment beside it.
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        (. + [(.[] | select(.__typename == "IssueComment" and .author.login == "romansod")
               | .body = "<!-- tracking marker -->")])' "$tl" > "$dtl" \
    || problems+=("could not derive the empty-sibling timeline")
  err=$(zsh "$script" --pr 1001 --item 'comment [romansod 2026-08-14 23:40]' --fixtures "$dtl" "$fx/basic.th.json" 2>&1 >/dev/null) \
    && problems+=("a bare header chose the empty comment beside another: exit 0")
  [[ $err == *"2 items start with: comment [romansod 2026-08-14 23:40]"*"Thanks @reviewer-bart"* ]] \
    || problems+=("bare header: both lines not listed: $err")
  # A review line with nothing past its counts is more than the bare header
  # (`review  [carol 2026-08-14 22:30]`), so its whole line names it beside a
  # same-minute review whose line goes on to a preview; the bare header is
  # still only a prefix of both.
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        (. + [(.[] | select(.id == "PRR_review1")
               | .id = "PRR_carol_empty" | .author.login = "carol" | .submittedAt = "2026-08-14T22:30:00Z"
               | .state = "COMMENTED" | .body = ""),
              (.[] | select(.id == "PRR_review1")
               | .id = "PRR_carol_ok" | .author.login = "carol" | .submittedAt = "2026-08-14T22:30:00Z"
               | .state = "COMMENTED" | .body = "ok")])' "$tl" > "$dtl" \
    || problems+=("could not derive the two reviews")
  out=$(zsh "$script" --pr 1001 --item 'review  [carol 2026-08-14 22:30] COMMENTED, 0 threads (0 open)' --fixtures "$dtl" "$fx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("the whole empty-review line was not selected: exit $rc"); }
  [[ $out == 'review  [carol 2026-08-14 22:30] COMMENTED, 0 threads (0 open)' ]] \
    || problems+=("the whole empty-review line selected: $out")
  err=$(zsh "$script" --pr 1001 --item 'review  [carol 2026-08-14 22:30]' --fixtures "$dtl" "$fx/basic.th.json" 2>&1 >/dev/null) \
    && problems+=("the bare review header chose one review: exit 0")
  [[ $err == *"2 items start with: review  [carol 2026-08-14 22:30]"* ]] \
    || problems+=("bare review header: not refused as a prefix: $err")
  # A login may itself hold brackets (`vercel[bot]`); the bare header is known
  # by its shape, not by where the first `]` falls, so a bot's empty comment
  # is refused on its header like anyone's.
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        (. + [(.[] | select(.__typename == "IssueComment" and .author.login == "vercel[bot]")
               | .body = "<!-- marker only -->")])' "$tl" > "$dtl" \
    || problems+=("could not derive the empty bot comment")
  err=$(zsh "$script" --pr 1001 --item 'comment [vercel[bot] 2026-08-14 20:02]' --fixtures "$dtl" "$fx/basic.th.json" 2>&1 >/dev/null) \
    && problems+=("a bot's bare header chose its empty comment: exit 0")
  [[ $err == *"2 items start with: comment [vercel[bot] 2026-08-14 20:02]"* ]] \
    || problems+=("bot bare header: not refused as a prefix: $err")
  # A preview may itself end in something header-shaped (`see [a 2026-08-16
  # 18:00]`); only the whole line from its start is a bare header, so this
  # one still names its comment beside the longer one.
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        (map(if .__typename == "IssueComment" and .author.login == "romansod" then .body = "see [a 2026-08-16 18:00]" else . end)
         + [(.[] | select(.__typename == "IssueComment" and .author.login == "romansod") | .body = "see [a 2026-08-16 18:00] more")])' \
    "$tl" > "$dtl" || problems+=("could not derive the header-shaped previews")
  out=$(zsh "$script" --pr 1001 --item 'comment [romansod 2026-08-14 23:40] see [a 2026-08-16 18:00]' --fixtures "$dtl" "$fx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("a preview ending in a header shape was not selected: exit $rc"); }
  [[ $out == $'comment [romansod 2026-08-14 23:40]\n  see [a 2026-08-16 18:00]' ]] \
    || problems+=("the header-shaped preview selected: $out")
  rm -f "$dtl"
  report "$name" "item" $rc "$out"
  return 0
}
item_refusals
# item-same-line-threads — two threads on one path:line from one commit differ
# only in who opened them and when, so a thread TOC line ends with its opener
# and either can be named. Two the same person opened in the same minute
# still share every character of the line; the refusal says so, and points
# at the dump, rather than asking for more of a line there is no more of.
item_same_line_threads() {
  local name=item-same-line-threads out err dth sth toc
  local -i rc=0
  local tl=$fx/basic.tl.json
  dth=$(mktemp) && sth=$(mktemp) || { problems+=("mktemp failed"); report "$name" "item" 1 ""; return 0; }
  jq '(.[].data.repository.pullRequest.reviewThreads.nodes) |=
        (. + [(.[] | select(.path == "README.md") | .id = "dup"
               | .comments.nodes = [.comments.nodes[0]
                   | .author.login = "carol" | .createdAt = "2026-08-15T08:02:00Z"
                   | .body = "A second thread on the same line."])])' "$fx/basic.th.json" > "$dth" \
    || problems+=("could not derive the second thread")
  jq '(.[].data.repository.pullRequest.reviewThreads.nodes) |=
        (. + [(.[] | select(.path == "README.md") | .id = "dup")])' "$fx/basic.th.json" > "$sth" \
    || problems+=("could not derive the twin thread")
  toc=$(zsh "$script" --pr 1001 --toc --only thread --fixtures "$tl" "$dth" 2>&1) || { rc=$?; problems+=("toc exit $rc"); }
  [[ $toc == *$'\nthread  README.md:3 OPEN @bbb2222 ['*$'\nthread  README.md:3 OPEN @bbb2222 [carol 2026-08-15 08:02]'* ]] \
    || problems+=("the two thread lines do not name their openers: $toc")
  out=$(zsh "$script" --pr 1001 --item 'thread  README.md:3 OPEN @bbb2222 [carol' --fixtures "$tl" "$dth" 2>&1) \
    || { rc=$?; problems+=("the opener did not select one: exit $rc"); }
  [[ $out == 'thread  README.md:3 OPEN @bbb2222'$'\n''    [carol 2026-08-15 08:02]'$'\n''      A second thread'* ]] \
    || problems+=("the opener selected the wrong thread: $out")
  err=$(zsh "$script" --pr 1001 --item 'thread  README.md:3' --fixtures "$tl" "$sth" 2>&1 >/dev/null) \
    && problems+=("two identical lines exited 0")
  [[ $err == *"2 items share this exact TOC line"*"dump"* ]] \
    || problems+=("identical lines: the refusal does not say so: $err")
  # The whole twin line, not just a prefix of it: an exact match of two items
  # is refused like any two matches, never the first of them printed.
  err=$(zsh "$script" --pr 1001 --item 'thread  README.md:3 OPEN @bbb2222 [reviewer-bart 2026-08-15 10:00]' --fixtures "$tl" "$sth" 2>&1 >/dev/null) \
    && problems+=("the whole twin line exited 0")
  [[ $err == *"2 items share this exact TOC line"* ]] \
    || problems+=("whole twin line: the refusal does not say so: $err")
  rm -f "$dth" "$sth"
  report "$name" "item" $rc "$out"
  return 0
}
item_same_line_threads
# item-past-filters — what the default view holds back can still be fetched
# by name: a bot comment, a merge commit, a thread of a filtered bot review.
# A hidden comment prints its marker alone unless --hidden, as it renders.
item_past_filters() {
  local name=item-past-filters out
  local -i rc=0
  out=$(zsh "$script" --pr 1001 --item 'comment [vercel[bot]' --fixtures "$fx/basic.tl.json" "$fx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("bot comment exit $rc"); }
  [[ $out == 'comment [vercel[bot] 2026-08-14 20:02]'$'\n''  Deployment preview ready'* ]] || problems+=("bot comment: $out")
  out=$(zsh "$script" --pr 1001 --item 'commit  9d8c7b6' --fixtures "$fx/basic.tl.json" "$fx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("merge commit exit $rc"); }
  [[ $out == 'commit  9d8c7b6 '* ]] || problems+=("merge commit: $out")
  out=$(zsh "$script" --pr 1001 --item 'thread  src/widget/retry.ts' --fixtures "$fx/bot-review.tl.json" "$fx/bot-review.th.json" 2>&1) \
    || { rc=$?; problems+=("bot-review thread exit $rc"); }
  [[ $out == 'thread  src/widget/retry.ts:42 [B-M1] OPEN @1a2b3c4'$'\n''    ['* ]] || problems+=("bot-review thread: $out")
  out=$(zsh "$script" --pr 1001 --item 'comment [dave' --fixtures "$fx/hidden.tl.json" "$fx/hidden.th.json" 2>&1) \
    || { rc=$?; problems+=("hidden exit $rc"); }
  [[ $out == 'comment [dave 2026-08-14 22:00] (hidden: outdated)' ]] || problems+=("hidden comment printed more than its marker: $out")
  out=$(zsh "$script" --pr 1001 --hidden --item 'comment [dave' --fixtures "$fx/hidden.tl.json" "$fx/hidden.th.json" 2>&1) \
    || { rc=$?; problems+=("hidden --hidden exit $rc"); }
  [[ $out == 'comment [dave 2026-08-14 22:00] (hidden: outdated)'$'\n''  '?* ]] || problems+=("--hidden did not print the body: $out")
  # Two hidden comments by one author in one minute share their marker-only
  # line, and a dump without --hidden shows them the same way; --hidden is
  # what tells them apart, so that is what the refusal points at.
  local htl
  htl=$(mktemp) || { problems+=("mktemp failed"); report "$name" "item" 1 ""; return 0; }
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        (. + [(.[] | select(.__typename == "IssueComment" and .author.login == "dave") | .body = "A second hidden note.")])' \
    "$fx/hidden.tl.json" > "$htl" || problems+=("could not derive the twin hidden comments")
  err=$(zsh "$script" --pr 1001 --item 'comment [dave' --fixtures "$htl" "$fx/hidden.th.json" 2>&1 >/dev/null) \
    && problems+=("two hidden twins exited 0")
  [[ $err == *"share this exact TOC line"*"--hidden"* && $err != *"dump"* ]] \
    || problems+=("hidden twins: the refusal does not point at --hidden: $err")
  # With --hidden already given and the bodies the same, the lines stay twins
  # and --hidden has nothing more to give: the dump is the advice again.
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        (. + [(.[] | select(.__typename == "IssueComment" and .author.login == "dave"))])' \
    "$fx/hidden.tl.json" > "$htl" || problems+=("could not derive the same-body hidden twins")
  err=$(zsh "$script" --pr 1001 --hidden --item 'comment [dave' --fixtures "$htl" "$fx/hidden.th.json" 2>&1 >/dev/null) \
    && problems+=("same-body hidden twins under --hidden exited 0")
  [[ $err == *"share this exact TOC line"*"dump"* && $err != *"rerun"* ]] \
    || problems+=("same-body twins under --hidden: not pointed at the dump: $err")
  # A hidden comment beside a visible one of the same minute: their lines
  # differ, so this is the ordinary several-matches refusal, not twins.
  jq '(.[].data.repository.pullRequest.timelineItems.nodes) |=
        (. + [(.[] | select(.__typename == "IssueComment" and .author.login == "dave")
               | .isMinimized = false | .minimizedReason = null | .body = "A visible note.")])' \
    "$fx/hidden.tl.json" > "$htl" || problems+=("could not derive the hidden and visible pair")
  err=$(zsh "$script" --pr 1001 --item 'comment [dave' --fixtures "$htl" "$fx/hidden.th.json" 2>&1 >/dev/null) \
    && problems+=("a hidden and a visible comment exited 0")
  [[ $err == *"2 items start with: comment [dave — give more of the line"* && $err != *"share this exact"* ]] \
    || problems+=("hidden and visible: not the several-matches refusal: $err")
  rm -f "$htl"
  report "$name" "item" $rc "$out"
  return 0
}
item_past_filters
# item-miss-hints — a miss says why when the reason is knowable. Each of the
# four kinds whose header takes two spaces, given with one, is told the TOC
# writes two, naming the kind and its form; a miss that is not that (two
# spaces already, no space, another kind) gets no such hint, and on an issue,
# which has none of those kinds, neither does that form. A line copied from
# --toc --hidden and given without --hidden is told to add --hidden.
item_miss_hints() {
  local name=item-miss-hints err k p
  local -i rc=0
  local -a pair=(--fixtures "$fx/basic.tl.json" "$fx/basic.th.json")
  for k p in review '[reviewer-bart' thread 'src/' commit '1a2b3c4' force-push 'aaa'; do
    err=$(zsh "$script" --pr 1001 --item "$k $p" "${pair[@]}" 2>&1 >/dev/null) && problems+=("$k: one-space miss exited 0")
    [[ $err == *"no item starts with: $k $p (the TOC writes two spaces after $k: '$k  ')" ]] \
      || problems+=("$k: no two-space hint: $err")
  done
  for p in 'review  [nobody' 'reviewer' 'comment [nobody' 'comment review [x' 'commit'$'\t''x'; do
    err=$(zsh "$script" --pr 1001 --item "$p" "${pair[@]}" 2>&1 >/dev/null)
    [[ $err == *"no item starts with: $p" && $err != *"two spaces"* ]] || problems+=("'$p': hinted wrongly: $err")
  done
  err=$(zsh "$script" 21 --item 'review [x' --fixtures "$here/fixtures/gh-comments/issue-basic.tl.json" 2>&1 >/dev/null)
  [[ $err == *"no item starts with: review [x"* && $err != *"two spaces"* ]] || problems+=("issue: two-space hint for a kind issues lack: $err")
  local line
  line=$(zsh "$script" --pr 1001 --toc --hidden --only comment --fixtures "$fx/hidden.tl.json" "$fx/hidden.th.json" 2>/dev/null | grep '^comment \[dave')
  err=$(zsh "$script" --pr 1001 --item "$line" --fixtures "$fx/hidden.tl.json" "$fx/hidden.th.json" 2>&1 >/dev/null)
  [[ $err == *"no item starts with"*"--hidden"* ]] || problems+=("a --toc --hidden line without --hidden: no hint: $err")
  report "$name" "item" $rc "$err"
  return 0
}
item_miss_hints

# check_oversized — a payload too large to fit in argv. Passing the two
# payloads as `jq --argjson` died with "argument list too long: jq" (exit 127,
# zero output) once they passed macOS's 1,048,576-byte ARG_MAX — and died
# *after* both network fetches had been paid for.  The fixture is
# generated here rather than committed: a >1 MB JSON has no business in git,
# and nothing about the rendering is worth diffing, so this asserts exit 0 and
# the header instead.
check_oversized() {
  local name=oversized-payload
  local tmp big actual
  local -i rc=0 bytes=0
  tmp=$(mktemp -d) || {
    t_fail "$name" "" "tests/test-gh-comments-pr.zsh" "mktemp -d failed"
    (( fails += 1 )); return 0
  }
  big=$tmp/oversized.tl.json
  # The padding is built inside jq, not handed to it — a 1 MB `--arg` would
  # hit the very limit this case exists to cover. jq's stderr is deliberately
  # not silenced: if generation ever breaks, the case would otherwise fail
  # with "payload is 0 bytes" and no reason.
  jq -c '.[0].data.repository.pullRequest.timelineItems.nodes +=
           [{__typename: "IssueComment",
             author: {login: "bulk", __typename: "User"},
             createdAt: "2026-08-16T10:00:00Z",
             body: ("x" * 1200000)}]' \
    "$fx/zero-threads.tl.json" > "$big"
  bytes=$(wc -c < "$big")
  actual=$(zsh "$script" --pr 7 --toc --fixtures "$big" "$fx/zero-threads.th.json" 2>&1) || rc=$?

  (( bytes > 1048576 )) || problems+=("payload is $bytes bytes — under ARG_MAX, so the case proves nothing")
  (( rc == 0 )) || problems+=("exit $rc (want 0)")
  [[ "$actual" == *"PR #7 docs: clarify retry semantics [OPEN base:main]"* ]] \
    || problems+=("header line missing from the render")
  [[ "$actual" == *"comment [bulk 2026-08-16 10:00] xxx"*"chars]"* ]] \
    || problems+=("the oversized comment did not reach the render")

  report "$name" "oversized payload ($bytes bytes)" $rc "$actual"
  rm -rf "$tmp"
  return 0
}

check_oversized

# --- fixture shapes --------------------------------------------------------
# The two payloads reach jq as --slurpfile, which wants a stream of values
# where the committed fixtures hold the `jq -s .` array form. The script
# unwraps one level to bridge that, and documents that a bare stream works
# too; these pin both halves, plus what a fixture jq cannot parse does.

# fixtures-bare-stream — an unwrapped fixture must render identically to the
# array form. The array form's render is itself golden-checked above
# (zero-threads-toc), so this compares against it rather than a second copy.
check_bare_stream() {
  local name=fixtures-bare-stream tmp bare arr_out bare_out
  local -i rc=0 rc_bare=0
  tmp=$(mktemp -d) || {
    t_fail "$name" "" "tests/test-gh-comments-pr.zsh" "mktemp -d failed"
    (( fails += 1 )); return 0
  }
  bare=$tmp/bare.tl.json
  jq -c '.[]' "$fx/zero-threads.tl.json" > "$bare"
  arr_out=$(zsh "$script" --pr 7 --toc --fixtures "$fx/zero-threads.tl.json" "$fx/zero-threads.th.json" 2>&1) || rc=$?
  bare_out=$(zsh "$script" --pr 7 --toc --fixtures "$bare" "$fx/zero-threads.th.json" 2>&1) || rc_bare=$?

  (( rc == 0 )) || problems+=("array-form run exited $rc (want 0)")
  (( rc_bare == 0 )) || problems+=("bare-stream run exited $rc_bare (want 0)")
  [[ "$bare_out" == "$arr_out" ]] \
    || problems+=("bare-stream render differs from the array form")

  report "$name" "fixture shapes" $rc_bare "$bare_out"
  rm -rf "$tmp"
  return 0
}

check_bare_stream

# fixtures-malformed — jq fails on the unwrap and set -e stops there, so the
# case pins that nothing is rendered before the error. The exit code is jq's
# own 5, not the script's 1: the unwrap is not wrapped in a diagnosis.
# LIMITATION — the message is a bare `jq: parse error`, naming neither
# gh-comments nor which of the two fixtures was unreadable.
check_malformed_fixture() {
  local name=fixtures-malformed tmp bad out
  local -i rc=0
  tmp=$(mktemp -d) || {
    t_fail "$name" "" "tests/test-gh-comments-pr.zsh" "mktemp -d failed"
    (( fails += 1 )); return 0
  }
  bad=$tmp/bad.tl.json
  print -r -- '{not json' > "$bad"
  out=$(zsh "$script" --pr 7 --toc --fixtures "$bad" "$fx/zero-threads.th.json" 2>&1) || rc=$?

  (( rc != 0 )) || problems+=("exit 0 — a fixture jq cannot parse must not be a success")
  [[ "$out" == *"parse error"* ]] || problems+=("no parse error reported")
  [[ "$out" != *"PR #7"* ]] || problems+=("rendered a header despite the unreadable fixture")

  report "$name" "fixture shapes" $rc "$out"
  rm -rf "$tmp"
  return 0
}

check_malformed_fixture

# legacy-pr-payload — a timeline payload saved before the opening-post fields
# were added to the query. Real: every fixture here was one until this commit,
# and the advice to dump once and slice later means saved payloads outlive
# query changes. The `has_body` guard keys on createdAt rather than on body,
# because a PR with an empty description is a different thing from a PR whose
# description was never fetched, and only the second may vanish silently.
check_legacy_payload() {
  local name=legacy-pr-payload out
  local -i rc=0 fields=0
  fields=$(jq '[.[].data.repository.pullRequest
                | select(has("body") or has("createdAt") or has("author"))] | length' \
             "$fx/all-resolved.tl.json")
  (( fields == 0 )) \
    || problems+=("all-resolved.tl.json now carries opening-post fields — the case proves nothing")
  out=$(zsh "$script" --pr 8 --fixtures "$fx/all-resolved.tl.json" "$fx/all-resolved.th.json" 2>&1) || rc=$?
  (( rc == 0 )) || problems+=("exit $rc (want 0)")
  [[ "$out" == "PR #8 "* ]] || problems+=("the render did not survive the missing fields")
  [[ "$out" != *"body ["* ]] || problems+=("emitted a body item with nothing to put in it")
  [[ "$out" != *"ghost"* ]] || problems+=("rendered a ghost author for an unfetched field")
  report "$name" "fixture shapes" $rc "$out"
  return 0
}

check_legacy_payload

# html-entities — numeric entities in an HTML-heavy paste: decimal and hex
# both decode, and a code point no text should carry (NUL, a C0 control, a
# surrogate) is replaced rather than written out — a NUL in the dump makes
# grep call the whole file binary, which breaks the dump-once-and-grep flow.
check_html_entities() {
  local name=html-entities tmp fixture out
  local -i rc=0 nuls=0
  tmp=$(mktemp -d) || {
    t_fail "$name" "" "tests/test-gh-comments-pr.zsh" "mktemp -d failed"
    (( fails += 1 )); return 0
  }
  fixture=$tmp/entities.tl.json
  # The html-heavy fixture carries one rich-text body; append the entities
  # to it so the htmlheavy gate still fires.
  jq -c '(.[0].data.repository.pullRequest.timelineItems.nodes[]
          | select(.__typename == "IssueComment" and (.body | test("<div")) and (.body | test("```") | not))
          | .body) += "<p>dash&#8212;hex&#x2014;nul&#0;ctl&#x1;sur&#xD800;big&#1114112;tab&#9;end lit&#38;amp;eral&#x26;amp;lt; cr&#13;lf win&#146;s&#150;x nb&#160;sp&#xA0;x</p>"' \
    "$fx/html-heavy.tl.json" > "$fixture"
  out=$(zsh "$script" --pr 9 --fixtures "$fixture" "$fx/html-heavy.th.json" 2>&1) || rc=$?
  (( rc == 0 )) || problems+=("exit $rc (want 0)")
  [[ "$out" == *"dash—hex—nul"* ]] || problems+=("decimal or hex entity not decoded")
  # One pass: the `&` that &#38; / &#x26; decode to must not then eat `amp;`.
  [[ "$out" == *"lit&amp;eral&amp;lt;"* ]] \
    || problems+=("a decoded & was rescanned: $(print -r -- "$out" | grep -o 'lit.*lt;' | head -1)")
  # U+FFFD as its UTF-8 bytes: $'\uFFFD' is a "character not in range"
  # error under a C locale (zsh 5.8), and the suite must not depend on LANG.
  local r=$'\xEF\xBF\xBD'
  [[ "$out" == *"nul${r}ctl${r}sur${r}big${r}tab"$'\t'"end"* ]] \
    || problems+=("a dangerous code point was not replaced: $(print -r -- "$out" | grep -o 'nul.*end')")
  # A CR entity is dropped like a literal CR; 128-159 read as windows-1252
  # (curly apostrophe, en dash), not as C1 controls; &#160; is a space.
  [[ "$out" == *"crlf win’s–x nb sp x"* ]] \
    || problems+=("CR, C1 or nbsp entity mishandled: $(print -r -- "$out" | grep -o 'crlf.*sp.x' | head -1)")
  nuls=$(print -r -- "$out" | tr -cd '\000' | wc -c)
  (( nuls == 0 )) || problems+=("$nuls NUL byte(s) in the output")
  report "$name" "html entities" $rc "$out"
  rm -rf "$tmp"
  return 0
}
check_html_entities

# --- lean timeline ---------------------------------------------------------
# --unresolved fetches a reduced timeline: PULL_REQUEST_COMMIT dropped from
# itemTypes, `body` dropped from the IssueComment fragment. That has two
# halves, and they need different harnesses — the render must not be able to
# tell the difference (here), and the reduced query must be sent
# exactly when it is safe to send (gh-lean-query-* below).
#
# unresolved-lean-identical is the render half, checked the only way that
# actually proves it: render the same PR from the full payload and from one
# reduced exactly as the lean query reduces it, then compare. --fixtures
# bypasses the network, so the reduction is applied here rather than fetched.
check_lean_identical() {
  local name=unresolved-lean-identical tmp lean
  local full_out lean_out full_toc lean_toc
  local -i rc=0
  local -i full_commits=0 lean_commits=0 full_bodies=0 lean_bodies=0 full_desc=0 lean_desc=0
  tmp=$(mktemp -d) || {
    t_fail "$name" "" "tests/test-gh-comments-pr.zsh" "mktemp -d failed"
    (( fails += 1 )); return 0
  }
  lean=$tmp/basic-lean.tl.json
  # Exactly the shape the lean query returns: no PullRequestCommit nodes at
  # all, IssueComment nodes carrying no body key, and no opening-post fields on
  # the pullRequest object itself.
  jq -c 'map(.data.repository.pullRequest
             |= (del(.author, .createdAt, .body)
                 | .timelineItems.nodes |=
                     (map(select(.__typename != "PullRequestCommit"))
                      | map(if .__typename == "IssueComment" then del(.body) else . end))))' \
    "$fx/basic.tl.json" > "$lean"

  # If the reduction ever stops reducing, the comparison below passes while
  # proving nothing — the same trap check_oversized guards with its byte count.
  full_commits=$(jq '[.[].data.repository.pullRequest.timelineItems.nodes[]
                      | select(.__typename == "PullRequestCommit")] | length' "$fx/basic.tl.json")
  lean_commits=$(jq '[.[].data.repository.pullRequest.timelineItems.nodes[]
                      | select(.__typename == "PullRequestCommit")] | length' "$lean")
  full_bodies=$(jq '[.[].data.repository.pullRequest.timelineItems.nodes[]
                     | select(.__typename == "IssueComment") | select(has("body"))] | length' "$fx/basic.tl.json")
  lean_bodies=$(jq '[.[].data.repository.pullRequest.timelineItems.nodes[]
                     | select(.__typename == "IssueComment") | select(has("body"))] | length' "$lean")
  full_desc=$(jq '[.[].data.repository.pullRequest | select(has("body"))] | length' "$fx/basic.tl.json")
  lean_desc=$(jq '[.[].data.repository.pullRequest | select(has("body"))] | length' "$lean")
  # Both halves of the reduction need a before *and* an after. Asserting only
  # that the lean payload lacks something is vacuous if the full one lacked it
  # too — an edit to basic.tl.json that dropped its comment bodies would leave
  # this case green while it proved nothing about the dropped body.
  (( full_commits > 0 )) \
    || problems+=("basic.tl.json has no commit nodes — the reduction proves nothing")
  (( full_bodies > 0 )) \
    || problems+=("basic.tl.json has no issue-comment bodies — the reduction proves nothing")
  (( lean_commits == 0 )) || problems+=("$lean_commits commit node(s) survived the reduction")
  (( lean_bodies == 0 )) || problems+=("$lean_bodies issue-comment body(s) survived the reduction")
  (( full_desc > 0 )) \
    || problems+=("basic.tl.json has no PR description — the reduction proves nothing")
  (( lean_desc == 0 )) || problems+=("the PR description survived the reduction")

  full_out=$(zsh "$script" --pr 1001 --unresolved --fixtures "$fx/basic.tl.json" "$fx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("full --unresolved run exited $rc"); }
  lean_out=$(zsh "$script" --pr 1001 --unresolved --fixtures "$lean" "$fx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("lean --unresolved run exited $rc"); }
  full_toc=$(zsh "$script" --pr 1001 --toc --unresolved --fixtures "$fx/basic.tl.json" "$fx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("full --toc --unresolved run exited $rc"); }
  lean_toc=$(zsh "$script" --pr 1001 --toc --unresolved --fixtures "$lean" "$fx/basic.th.json" 2>&1) \
    || { rc=$?; problems+=("lean --toc --unresolved run exited $rc"); }

  [[ "$lean_out" == "$full_out" ]] \
    || problems+=("--unresolved render differs between the full and lean payloads")
  [[ "$lean_toc" == "$full_toc" ]] \
    || problems+=("--toc --unresolved render differs between the full and lean payloads")
  # --unresolved renders no `body` item, so dropping the description cannot
  # move a byte of its output — which is exactly what the identity comparison
  # above proves, and the reason the field is safe to leave out of the query.
  [[ "$full_out" != *"body ["* ]] \
    || problems+=("--unresolved rendered the PR description")
  # The counts header is the whole reason the IssueComment node survives the
  # reduction while its body does not, so pin that it still counts both.
  [[ "$lean_out" == *"top-level comments: 1 (+1 bot filtered)"* ]] \
    || problems+=("counts header lost its top-level comment tally on the lean payload")

  report "$name" "lean timeline" $rc "$lean_out"
  rm -rf "$tmp"
  return 0
}

check_lean_identical

# --- stubbed gh ------------------------------------------------------------
# Every golden case reaches the script through --fixtures, so nothing above
# exercises the half that fetches and diagnoses: the two graphql calls, the
# error branches that read them, and the trap that cleans up after. These
# cases prepend stubs on PATH and pin that behavior. Offline by construction — the stub never reaches the network, and
# CI has no GH_TOKEN, so an escape would fail loudly rather than quietly pass.
#
# `mktemp` is stubbed alongside `gh`, for one reason: asserting the payload
# files are gone needs to know where they were. Pointing TMPDIR at a private
# directory does not work — macOS's mktemp ignores TMPDIR entirely (it uses
# confstr(_CS_DARWIN_USER_TEMP_DIR)) — and counting entries in the shared temp
# dir races anything else on the machine.
stubdir=$(mktemp -d) || { print -ru2 -- "mktemp -d failed"; exit 1 }
stublog=$stubdir/argv.log
mklog=$stubdir/mktemp.log
qlog=$stubdir/tl-query.txt
stubfx=$stubdir/fx        # per-case answer files, rm'd between cases
mkdir -p "$stubfx" || { print -ru2 -- "mkdir $stubfx failed"; exit 1 }

cat > "$stubdir/gh" <<'STUB'
#!/usr/bin/env zsh
# gh stub — offline. The scenario comes from $GH_STUB_MODE; every call appends
# a compact tag to $GH_STUB_LOG so a refactor of the subject's argv shape
# fails here instead of silently landing in a fallthrough. The two graphql
# calls are told apart by their query text: only the threads query mentions
# reviewThreads.
emit_log() {
  print -r -- "$1" >> "${GH_STUB_LOG:-/dev/null}"
  # GH_STUB_NOISY: gh's debug log on stderr, which real gh writes on every
  # call — successful ones included — under GH_DEBUG or DEBUG=1. The answer
  # must come from stdout alone.
  # The lines carry what real ones do — a URL, with its / and : — so a
  # merged stream cannot slip past the owner/name check by looking plain.
  [[ -n ${GH_STUB_NOISY:-} ]] && print -ru2 -- "[git remote -v]"$'\n'"* Request to https://api.github.com/graphql ($1)"
  return 0
}

case "$1 $2" in
  "repo view")
    # GH_STUB_NO_REPO: the cwd is not a GitHub repo, in gh's wording.
    # GH_STUB_REPO_ERROR: gh itself failed (no network, a bad token).
    emit_log "repo view"
    [[ -n ${GH_STUB_NO_REPO:-} ]] && { print -ru2 -- "no git remotes found"; exit 1; }
    [[ -n ${GH_STUB_REPO_ERROR:-} ]] && { print -ru2 -- "error connecting to api.github.com"; exit 1; }
    print -r -- acme/widget; exit 0 ;;
  "pr view")
    # The branch's-PR hint in the not-found diagnosis and the no-number
    # lookup. Absent answer file means "no PR for this branch", which is a
    # nonzero exit from real gh. The argv is logged so a case can see what
    # the lookup was given. Real gh refuses `pr view -R <repo>` with no
    # positional, and the script never passes a positional here, so -R is
    # refused the way gh does — a stub that answered it hid exactly that
    # regression once.
    emit_log "pr view ${*[3,-1]}"
    if [[ " ${*[3,-1]} " == *" -R "* || " ${*[3,-1]} " == *" --repo "* || " ${*[3,-1]} " == *" --repo="* ]]; then
      print -ru2 -- "argument required when using the --repo flag"; exit 1
    fi
    # GH_STUB_PR_VIEW_ERROR: gh itself failed, which is not "no PR".
    [[ -n ${GH_STUB_PR_VIEW_ERROR:-} ]] && { print -ru2 -- "error connecting to api.github.com"; exit 1; }
    [[ -r $GH_STUB_FX/branch-pr ]] || { print -ru2 -- 'no pull requests found for branch "feature"'; exit 1; }
    cat "$GH_STUB_FX/branch-pr"; exit 0 ;;
esac

if [[ "$1" == api && "$2" != graphql ]]; then
  # A tripwire, not a feature. The is-this-an-issue REST probe was retired
  # when the union query started answering the question for free; if any REST
  # call comes back, the case that triggered it should say so loudly rather
  # than quietly costing a round trip.
  print -ru2 -- "gh stub: unexpected REST call: $*"; exit 64
fi
if [[ "$1 $2" != "api graphql" ]]; then
  print -ru2 -- "gh stub: unexpected argv: $*"; exit 64
fi

which=tl
[[ "$*" == *reviewThreads* ]] && which=th
emit_log "graphql:$which"

# The timeline query's own text, for the lean-vs-full gating cases. Written
# rather than appended: there is one timeline call per run. Kept separate from
# the argv log so the existing `grep -qx graphql:tl` assertions still hold.
if [[ $which == tl && -n ${GH_STUB_QUERY_LOG:-} ]]; then
  print -r -- "$*" > "$GH_STUB_QUERY_LOG"
fi

if [[ $which == th ]]; then
  case "${GH_STUB_MODE:-}" in
    th-fail) print -ru2 -- "gh: HTTP 502 Bad Gateway (fetching review threads)"; exit 1 ;;
    # A bad PR number fails *both* queries against the real API, so the stub
    # models that. With the fetches sequential this branch is unreachable —
    # the threads call is skipped when the timeline call fails — which is
    # exactly why it stays: it is what went red when the two briefly ran
    # concurrently and gh's raw error printed ahead of the curated diagnosis.
    notfound-*) print -ru2 -- "gh: Could not resolve to an issue or pull request with the number of 999."; exit 1 ;;
    *)       jq -c '.[]' "$GH_STUB_TH"; exit 0 ;;
  esac
fi

case "${GH_STUB_MODE:-}" in
  ok|th-fail) jq -c '.[]' "$GH_STUB_TL"; exit 0 ;;

  # The number resolves — to an Issue. Only the union query can see this;
  # `pullRequest(number:)` reported it as NOT_FOUND.
  issue-target)
    print -rn -- '{"data":{"repository":{"issueOrPullRequest":{"__typename":"Issue","number":43,"title":"ARG_MAX crash on large PRs"}}}}'
    exit 0 ;;
  issue-backslash)
    print -rn -- '{"data":{"repository":{"issueOrPullRequest":{"__typename":"Issue","number":43,"title":"fix \\t and \\c in the parser"}}}}'
    exit 0 ;;

  # Both streams carry the not-found wording — the shape real gh produces,
  # verified against github.com: a one-line summary on stderr and the full
  # errors[] array on stdout, in the union field's wording.
  notfound-both)
    print -rn -- '{"data":{"repository":{"issueOrPullRequest":null}},"errors":[{"type":"NOT_FOUND","path":["repository","issueOrPullRequest"],"message":"Could not resolve to an issue or pull request with the number of 999."}]}'
    print -ru2 -- "gh: Could not resolve to an issue or pull request with the number of 999."
    exit 1 ;;
  # One stream each: the subject greps both, and these pin each half. If it
  # ever greps only one, exactly one of the two cases goes red.
  notfound-stderr)
    print -ru2 -- "gh: Could not resolve to an issue or pull request with the number of 999."
    exit 1 ;;
  notfound-stdout)
    print -rn -- '{"data":{"repository":{"issueOrPullRequest":null}},"errors":[{"type":"NOT_FOUND","path":["repository","issueOrPullRequest"],"message":"Could not resolve to an issue or pull request with the number of 999."}]}'
    exit 1 ;;
  # A page gh fetched before a later one failed: the target's body quotes
  # the not-found sentence, and the failure itself is something else. The
  # diagnosis must come from the error structure, not from the text.
  notfound-in-body)
    print -r -- '{"data":{"repository":{"issueOrPullRequest":{"__typename":"PullRequest","body":"gh said: Could not resolve to an issue or pull request with the number of 999."}}}}'
    print -ru2 -- "gh: HTTP 502 Bad Gateway (fetching page 2)"
    exit 1 ;;
  # A repository that does not resolve, in gh's wording (verified live). It
  # also says "Could not resolve", and must not be read as a bad number.
  badrepo)
    print -rn -- '{"data":{"repository":null},"errors":[{"type":"NOT_FOUND","path":["repository"],"message":"Could not resolve to a Repository with the name '"'"'acme/no-such-repo'"'"'."}]}'
    print -ru2 -- "gh: Could not resolve to a Repository with the name 'acme/no-such-repo'."
    exit 1 ;;

  # A summary on stderr AND the structured body on stdout: gh's shape for a
  # 401. Both halves must reach the user — the body names the status and the
  # docs URL, the summary is the readable line.
  badcreds)
    print -rn -- '{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest","status":"401"}'
    print -ru2 -- "gh: Bad credentials (HTTP 401)"
    exit 1 ;;
  # stderr empty, body on stdout only.
  body-only)
    print -rn -- '{"message":"upstream connect timeout","status":"504"}'
    exit 1 ;;

  # A partial page, then hold, so the signal lands mid-fetch. The wait is
  # bounded: if the signal never arrives the stub gives up and the case fails
  # on its assertions instead of hanging the suite.
  hang)
    print -r -- '{"data":{"partial":true}}'
    for i in {1..200}; do
      [[ -e $GH_STUB_FX/hold ]] || break
      sleep 0.05
    done
    exit 130 ;;
esac
print -ru2 -- "gh stub: unhandled mode ${GH_STUB_MODE:-<unset>}"
exit 65
STUB
chmod +x "$stubdir/gh" || { print -ru2 -- "chmod gh stub failed"; exit 1 }

cat > "$stubdir/mktemp" <<'STUB'
#!/usr/bin/env zsh
# mktemp stub — same contract as the real one for the subject's bare `mktemp`,
# but inside a known directory and with every path recorded, so a case can
# assert the cleanup trap removed all of them.
[[ -n ${MKTEMP_STUB_DIR:-} ]] || { print -ru2 -- "mktemp stub: MKTEMP_STUB_DIR unset"; exit 64 }
n=$MKTEMP_STUB_DIR/m$$.$RANDOM
if [[ ${1:-} == -d ]]; then mkdir -p "$n"; else : > "$n"; fi || exit 1
print -r -- "$n" >> "${MKTEMP_STUB_LOG:-/dev/null}"
print -r -- "$n"
STUB
chmod +x "$stubdir/mktemp" || { print -ru2 -- "chmod mktemp stub failed"; exit 1 }

# The directory the stubbed mktemp creates into; emptied per case so a leak
# is attributable.
mkdir -p "$stubdir/tmp" || { print -ru2 -- "mkdir $stubdir/tmp failed"; exit 1 }

# gh_env — the stub environment, as an array to prefix a command with.
typeset -ga gh_env=()
_gh_env() {
  gh_env=(
    PATH="$stubdir:$PATH"
    GH_STUB_LOG="$stublog"
    GH_STUB_FX="$stubfx"
    GH_STUB_TL="$fx/zero-threads.tl.json"
    GH_STUB_TH="$fx/zero-threads.th.json"
    MKTEMP_STUB_DIR="$stubdir/tmp"
    MKTEMP_STUB_LOG="$mklog"
    GH_STUB_QUERY_LOG="$qlog"
  )
}

# gh_reset — clear the per-case logs and answer files.
gh_reset() {
  : > "$stublog"; : > "$mklog"; : > "$qlog"
  rm -rf "$stubfx" "$stubdir/tmp"
  mkdir -p "$stubfx" "$stubdir/tmp"
  _gh_env
}

# gh_leaks — names any recorded temp path the subject failed to clean up.
gh_leaks() {
  local f
  while IFS= read -r f; do
    [[ -e $f ]] && problems+=("temp file survived the run: ${f:t}")
  done < "$mklog"
  # Belt and braces: catch a file the stub created but did not log.
  local -a stray=("$stubdir"/tmp/*(N))
  (( ${#stray} )) && problems+=("${#stray} file(s) left in the stub temp dir")
  return 0
}

# gh_case <name> <mode> <pr> [extra-args...] — run the subject under the stub.
# Sets gh_out / gh_rc; the caller adds assertions and calls report.
gh_case() {
  local mode=$1 pr=$2; shift 2
  gh_rc=0
  gh_out=$(env "${gh_env[@]}" GH_STUB_MODE="$mode" zsh "$script" --pr "$pr" "$@" 2>&1) || gh_rc=$?
  return 0
}
typeset -g gh_out=""; typeset -gi gh_rc=0

# gh-live-render — the fetch path end to end: two graphql calls, a render
# matching what the same payload renders through --fixtures, no leftovers.
gh_reset
gh_case ok 7 --toc
[[ "$gh_out" == *"PR #7 docs: clarify retry semantics [OPEN base:main]"* ]] \
  || problems+=("header line missing from the render")
(( gh_rc == 0 )) || problems+=("exit $gh_rc (want 0)")
[[ "$(grep -c '^graphql:' "$stublog")" == 2 ]] \
  || problems+=("expected exactly 2 graphql calls, log has: $(tr '\n' ' ' < "$stublog")")
grep -qx 'graphql:tl' "$stublog" || problems+=("no timeline query was issued")
grep -qx 'graphql:th' "$stublog" || problems+=("no threads query was issued")
# owner and name travel as raw strings (-f): -F would read a digit-only
# name as a number and a leading @ as a file. Only the number is typed.
grep -q -- '-f owner=acme -f name=widget -F num=7 ' "$qlog" \
  || problems+=("owner/name not passed as raw strings: $(grep -o -- '-[fF] owner=[^ ]* -[fF] name=[^ ]* -[fF] num=[^ ]*' "$qlog")")
gh_leaks
report gh-live-render "stubbed gh" $gh_rc "$gh_out"

# gh-lean-query-* — the fetch half of the lean query, read off the query
# text the stub recorded.
#
# Gated *in* by --unresolved alone and by --toc --unresolved: both render the
# same reviews-and-threads subset, so neither can observe the dropped fields.
# Gated *out* of a bare run and a bare --toc, which need every body for the
# previews and the findings scan, and out of --since / --since-last-review,
# which read the commit timestamps and full timeline ordering the lean query
# drops. Getting that gate wrong in the permissive direction is silent data
# loss, not a slow query, which is why each flag combination gets a case.
#
# Both markers are asserted, not just one: itemTypes and the IssueComment body
# are substituted through separate slots, so a half-applied gate would leave
# one right and one wrong.
gating_case() {
  local name=$1 want=$2; shift 2
  local -i has_commits=0 has_body=0 has_desc=0 has_hidden=0 has_rev_hidden=0
  gh_reset
  gh_case ok 7 "$@"
  (( gh_rc == 0 )) || problems+=("exit $gh_rc (want 0)")
  grep -q 'PULL_REQUEST_COMMIT' "$qlog" && has_commits=1
  # The IssueComment body follows its createdAt and minimizedReason; a
  # review's isMinimized follows its state, and the PR description's body
  # follows its createdAt alone, so none of the markers match each other.
  grep -q 'createdAt isMinimized minimizedReason body' "$qlog" && has_body=1
  # The PR's own description hangs off baseRefName, which nothing else in the
  # query is followed by.
  grep -q 'baseRefName author' "$qlog" && has_desc=1
  # isMinimized rides on the comment node, outside the body slot: the counts
  # line reports hidden comments in every mode, lean included.
  grep -q 'createdAt isMinimized minimizedReason' "$qlog" && has_hidden=1
  # And on the review node, in every mode too: the fixtures carry the field
  # whatever the query asks for, so only the query text shows it is fetched.
  grep -q 'state isMinimized minimizedReason body' "$qlog" && has_rev_hidden=1
  if [[ $want == lean ]]; then
    (( has_commits == 0 )) || problems+=("lean query still asks for PULL_REQUEST_COMMIT")
    (( has_body == 0 )) || problems+=("lean query still asks for the IssueComment body")
    (( has_desc == 0 )) || problems+=("lean query still asks for the PR description")
  else
    (( has_commits == 1 )) || problems+=("full query dropped PULL_REQUEST_COMMIT")
    (( has_body == 1 )) || problems+=("full query dropped the IssueComment body")
    (( has_desc == 1 )) || problems+=("full query dropped the PR description")
  fi
  (( has_hidden == 1 )) || problems+=("$want query dropped isMinimized from the IssueComment node")
  (( has_rev_hidden == 1 )) || problems+=("$want query dropped isMinimized from the PullRequestReview node")
  # An unsubstituted slot is neither shape, and GraphQL would reject it — but
  # only against the real API, which no test reaches.
  if grep -q '@ITEM_TYPES@\|@COMMIT_FRAGMENT@\|@COMMENT_BODY@' "$qlog"; then
    problems+=("an unsubstituted template slot reached the query")
  fi
  gh_leaks
  report "$name" "stubbed gh" $gh_rc "$gh_out"
  return 0
}

gating_case gh-lean-query-unresolved      lean --unresolved
gating_case gh-lean-query-toc-unresolved  lean --toc --unresolved
gating_case gh-lean-query-bare            full
gating_case gh-lean-query-toc             full --toc
gating_case gh-lean-query-since           full --unresolved --since 2026-08-12
gating_case gh-lean-query-slr             full --unresolved --since-last-review
gating_case gh-lean-query-latest          full --unresolved --latest

# gh-notfound-* — "Could not resolve" is the signal that the number is not a
# PR, and gh may put it on either stream, so the subject greps both. One case
# per stream: greping only one leaves exactly one of these red.
for mode in both stderr stdout; do
  gh_reset
  gh_case "notfound-$mode" 999 --toc
  (( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
  # "#999", not "PR #999": the query resolves both sequences through
  # `issueOrPullRequest`, so a number that fails to resolve is neither.
  [[ "$gh_out" == *"gh-comments: #999 not found in acme/widget"* ]] \
    || problems+=("the not-found diagnosis did not replace the raw gh error")
  [[ "$gh_out" != *"gh error:"* ]] \
    || problems+=("fell through to the generic gh-error branch")
  # A tripwire, not a live assertion: sequential fetches never reach the
  # threads call on a bad number. It went red while the two ran concurrently,
  # and guards the curated diagnosis if that is ever revisited.
  [[ "$gh_out" != *"gh: Could not resolve"* ]] \
    || problems+=("gh's raw resolve error leaked ahead of the curated diagnosis")
  [[ "$gh_out" != *"No such file"* ]] || problems+=("a temp file was read after deletion")
  gh_leaks
  report "gh-notfound-$mode" "stubbed gh" $gh_rc "$gh_out"
done

# gh-notfound-phrase-in-body — a body on an already-fetched page quotes the
# not-found sentence and a later page fails for another reason: that is a
# gh error, not a missing number.
gh_reset
gh_case notfound-in-body 999 --toc
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == *"gh-comments: gh error:"* ]] || problems+=("did not fall through to the gh-error branch")
[[ "$gh_out" == *"HTTP 502 Bad Gateway"* ]] || problems+=("gh's own error was not shown")
[[ "$gh_out" != *"not found in acme/widget"* ]] || problems+=("a body quoting the sentence was read as not-found")
gh_leaks
report gh-notfound-phrase-in-body "stubbed gh" $gh_rc "$gh_out"

# gh-repo-view-error — gh failing to resolve the cwd's repo for its own
# reasons (no network, a bad token) is gh's error to show, not "not in a
# GitHub repo" with advice to pass -R.
gh_reset
gh_rc=0
gh_out=$(env "${gh_env[@]}" GH_STUB_MODE=ok GH_STUB_REPO_ERROR=1 zsh "$script" --pr 7 --toc 2>&1) || gh_rc=$?
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == "gh-comments: gh error:"$'\n'"error connecting to api.github.com" ]] || problems+=("output was: $gh_out")
(( $(grep -c '^graphql' "$stublog") == 0 )) || problems+=("fetched after the repo lookup failed")
gh_leaks
report gh-repo-view-error "stubbed gh" $gh_rc "$gh_out"

# gh-debug-stderr-ignored-on-success — under GH_DEBUG / DEBUG=1 real gh
# writes its debug log to stderr on every call, successful ones included.
# The repo lookup, the branch lookup and the fetches must take their answer
# from stdout alone: with no number, the run renders. (A merged stream once
# read the branch lookup's debug lines as a failed lookup.)
gh_reset
print -r -- '7' > "$stubfx/branch-pr"
gh_rc=0
gh_out=$(env "${gh_env[@]}" GH_STUB_MODE=ok GH_STUB_NOISY=1 zsh "$script" --pr --toc 2>/dev/null) || gh_rc=$?
(( gh_rc == 0 )) || problems+=("exit $gh_rc (want 0)")
[[ "$gh_out" == *"PR #7 docs: clarify retry semantics"* ]] || problems+=("did not render with gh's debug log on stderr")
# The repo lookup too: the render never prints the repo, so the fetch's
# argv is where a merged answer would show.
grep -q -- '-f owner=acme -f name=widget -F num=7 ' "$qlog" \
  || problems+=("owner/name carried gh's stderr: $(grep -o -- '-f owner=[^ ]* -f name=[^ ]*' "$qlog" | head -1)")
gh_leaks
report gh-debug-stderr-ignored-on-success "stubbed gh" $gh_rc "$gh_out"

# gh-branch-lookup-error — with no number, gh failing to look the branch
# up is gh's error, not "no PR found": that message is kept for gh's own
# no-PR wording (gh-no-number-no-pr below).
gh_reset
gh_rc=0
gh_out=$(env "${gh_env[@]}" GH_STUB_MODE=ok GH_STUB_PR_VIEW_ERROR=1 zsh "$script" --pr --toc 2>&1) || gh_rc=$?
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == "gh-comments: gh error:"$'\n'"error connecting to api.github.com" ]] || problems+=("output was: $gh_out")
(( $(grep -c '^graphql' "$stublog") == 0 )) || problems+=("fetched after the lookup failed")
gh_leaks
report gh-branch-lookup-error "stubbed gh" $gh_rc "$gh_out"

# gh-no-number-no-pr — and the real "no PR for this branch" answer.
gh_reset
gh_rc=0
gh_out=$(env "${gh_env[@]}" GH_STUB_MODE=ok zsh "$script" --pr --toc 2>&1) || gh_rc=$?
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == "gh-comments: no number given and no PR found for the current branch in acme/widget" ]] \
  || problems+=("output was: $gh_out")
gh_leaks
report gh-no-number-no-pr "stubbed gh" $gh_rc "$gh_out"

# gh-badrepo-not-a-bad-number — a repository that does not resolve is gh's
# own error to show, not "#1 not found": the user typed the repo wrong, and
# the branch-PR hint would send them to check the number instead.
gh_reset
print -r -- '#44: reach jq through files' > "$stubfx/branch-pr"
gh_case badrepo 1 -R acme/no-such-repo --toc
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == *"gh-comments: gh error:"* ]] || problems+=("did not fall through to the gh-error branch")
[[ "$gh_out" == *"Could not resolve to a Repository with the name 'acme/no-such-repo'"* ]] \
  || problems+=("gh's own message was not shown")
[[ "$gh_out" != *"not found in acme/no-such-repo"* ]] || problems+=("reported the number as missing")
[[ "$gh_out" != *"rerun with that number"* ]] || problems+=("hinted at the branch PR for a bad repo")
gh_leaks
report gh-badrepo-not-a-bad-number "stubbed gh" $gh_rc "$gh_out"

# gh-notfound-branch-hint — the number exists nowhere in the repo, so the only
# hint left is the branch's actual PR. That is the common mistake made
# self-correcting: N was the issue number embedded in the branch name.
gh_reset
print -r -- '#44: reach jq through files' > "$stubfx/branch-pr"
gh_case notfound-both 43 --toc
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == *"the current branch's PR is #44: reach jq through files — rerun with that number"* ]] \
  || problems+=("branch PR hint not reported")
gh_leaks
report gh-notfound-branch-hint "stubbed gh" $gh_rc "$gh_out"

# gh-notfound-hint-not-circular — when the branch's PR *is* the number that
# failed, the hint would send the user back to the same command, so it is
# left out.
gh_reset
print -r -- '#43: reach jq through files' > "$stubfx/branch-pr"
gh_case notfound-both 43 --toc
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == *"#43 not found in acme/widget"* ]] || problems+=("no not-found diagnosis")
[[ "$gh_out" != *"rerun with that number"* ]] \
  || problems+=("hinted at the number that just failed")
gh_leaks
report gh-notfound-hint-not-circular "stubbed gh" $gh_rc "$gh_out"

# gh-no-number-plain-lookup — with no number the branch's PR is looked up
# with a bare `gh pr view`: no -R, which gh refuses without a positional
# (the stub refuses it too), and the fetch then goes to the same repo gh
# resolved the branch in.
gh_reset
print -r -- '7' > "$stubfx/branch-pr"
gh_rc=0
gh_out=$(env "${gh_env[@]}" GH_STUB_MODE=ok zsh "$script" --pr --toc 2>&1) || gh_rc=$?
(( gh_rc == 0 )) || problems+=("exit $gh_rc (want 0)")
[[ "$gh_out" == *"note: no number given — using the current branch's PR #7"* ]] \
  || problems+=("did not use the branch's PR")
[[ "$gh_out" == *"PR #7 docs: clarify retry semantics"* ]] || problems+=("did not render PR #7")
grep -q -- '^pr view --json number ' "$stublog" \
  || problems+=("the branch lookup was not a bare pr view: $(grep '^pr view' "$stublog")")
gh_leaks
report gh-no-number-plain-lookup "stubbed gh" $gh_rc "$gh_out"

# gh-no-number-with-repo-flag-refused — "no number" means the cwd's branch
# PR and -R means another repo; the pair is refused before any gh call
# rather than resolved in one repo and fetched from the other.
gh_reset
print -r -- '7' > "$stubfx/branch-pr"
gh_rc=0
gh_out=$(env "${gh_env[@]}" GH_STUB_MODE=ok zsh "$script" --pr -R acme/widget --toc 2>&1) || gh_rc=$?
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == "gh-comments: -R needs a number: the current branch's PR is in the cwd's repo, not in acme/widget" ]] \
  || problems+=("output was: $gh_out")
[[ ! -s "$stublog" ]] || problems+=("called gh before refusing: $(tr '\n' ' ' < "$stublog")")
gh_leaks
report gh-no-number-with-repo-flag-refused "stubbed gh" $gh_rc "$gh_out"

# gh-no-repo-* — outside a GitHub repo the hint asks for what is missing:
# -R when a number was given, a number and -R when none was, since -R on
# its own is refused and would send the user from one refusal to the next.
for spec in "number|gh-comments: not in a GitHub repo — pass -R <owner/name>|7" \
            "no-number|gh-comments: no number given and not in a GitHub repo — pass <number> -R <owner/name>|"; do
  gh_reset
  gh_rc=0
  gh_out=$(env "${gh_env[@]}" GH_STUB_MODE=ok GH_STUB_NO_REPO=1 zsh "$script" --pr ${=${spec##*|}} --toc 2>&1) || gh_rc=$?
  (( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
  [[ "$gh_out" == "${${spec#*|}%|*}" ]] || problems+=("output was: $gh_out")
  (( $(grep -c '^pr view\|^graphql' "$stublog") == 0 )) || problems+=("went on after the repo failed")
  gh_leaks
  report "gh-no-repo-${spec%%|*}" "stubbed gh" $gh_rc "$gh_out"
done

# gh-notfound-no-hint-under-repo-flag — the branch's PR is in the cwd's
# repo, so under -R it is no answer to "#N is not in <repo>": no hint, and
# no lookup to pay for.
gh_reset
print -r -- '#44: reach jq through files' > "$stubfx/branch-pr"
gh_case notfound-both 43 -R acme/widget --toc
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == *"#43 not found in acme/widget"* ]] || problems+=("no not-found diagnosis")
[[ "$gh_out" != *"rerun with that number"* ]] || problems+=("hinted at the cwd branch's PR under -R")
(( $(grep -c '^pr view' "$stublog") == 0 )) || problems+=("looked the branch up under -R")
gh_leaks
report gh-notfound-no-hint-under-repo-flag "stubbed gh" $gh_rc "$gh_out"

# gh-no-number-events-refused-before-fetch — no number means the current
# branch's PR, so an issue-only flag is refused from argv alone: not only
# before the timeline, but before the branch lookup itself is paid for.
gh_reset
print -r -- '7' > "$stubfx/branch-pr"
gh_rc=0
gh_out=$(env "${gh_env[@]}" GH_STUB_MODE=ok zsh "$script" --events 2>&1) || gh_rc=$?
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == "gh-comments: --events only applies to issues; no number means the current branch's pull request" ]] \
  || problems+=("output was: $gh_out")
(( $(grep -c '' "$stublog") == 0 )) || problems+=("called gh before refusing: $(tr '\n' ' ' < "$stublog")")
gh_leaks
report gh-no-number-events-refused-before-fetch "stubbed gh" $gh_rc "$gh_out"

# gh-wrong-type-title-backslash — a title is third-party text; the
# diagnostic must print it as is, not read `\t` or `\c` as an escape.
gh_reset
gh_case issue-backslash 43 --toc
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == *'not a pull request: "fix \t and \c in the parser"'* ]] \
  || problems+=("the title was mangled: $(print -r -- "$gh_out" | head -1)")
[[ "$gh_out" == *$'\n'"  the type was pinned by --pr — rerun as: gh-comments 43 --toc"* ]] \
  || problems+=("the hint line was lost or glued on")
gh_leaks
report gh-wrong-type-title-backslash "stubbed gh" $gh_rc "$gh_out"

# gh-issue-number-rejected — the *other* half of that mistake, and the one
# that changed shape when the union query landed. A number that names an
# issue used to fail the PR-only query and get diagnosed by a second REST
# probe; now the union
# query returns the Issue outright, so the diagnosis is free and carries the
# title. What must not change: --pr refuses, rather than quietly
# rendering the issue. It also must not pay for the threads fetch.
gh_reset
print -r -- '#44: reach jq through files' > "$stubfx/branch-pr"
gh_case issue-target 43 --toc
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == *'gh-comments: #43 is an issue, not a pull request: "ARG_MAX crash on large PRs"'* ]] \
  || problems+=("the wrong-type diagnosis is missing or does not name the issue")
[[ "$gh_out" == *"rerun as: gh-comments 43"* ]] \
  || problems+=("no pointer at the command that would render it")
[[ "$gh_out" != *"issue #43"* ]] || problems+=("rendered the issue instead of refusing")
[[ "$(grep -c '^graphql:' "$stublog")" == 1 ]] \
  || problems+=("expected exactly 1 graphql call, log has: $(tr '\n' ' ' < "$stublog")")
gh_leaks
report gh-issue-number-rejected "stubbed gh" $gh_rc "$gh_out"

# gh-error-both-streams — the generic branch. gh writes a readable summary to
# stderr *and* the structured body to stdout; printing only one of the two
# throws away half the diagnosis, so both must appear.
gh_reset
gh_case badcreds 44 --toc
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == *"gh-comments: gh error:"* ]] || problems+=("no gh-error header")
[[ "$gh_out" == *"gh: Bad credentials (HTTP 401)"* ]] || problems+=("stderr summary missing")
[[ "$gh_out" == *'"documentation_url":"https://docs.github.com/rest"'* ]] \
  || problems+=("stdout error body missing — only one stream was printed")
gh_leaks
report gh-error-both-streams "stubbed gh" $gh_rc "$gh_out"

# gh-error-body-only — nothing on stderr, so the body is the whole diagnosis.
gh_reset
gh_case body-only 44 --toc
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == *'"upstream connect timeout"'* ]] \
  || problems+=("stdout error body missing when stderr was empty")
gh_leaks
report gh-error-body-only "stubbed gh" $gh_rc "$gh_out"

# gh-threads-fetch-fails — the second fetch has no diagnosis of its own; it
# rides set -e. Pin that it still fails loudly and renders nothing, so a
# half-fetched PR can never look like a complete one.
gh_reset
gh_case th-fail 7 --toc
(( gh_rc != 0 )) || problems+=("exit 0 — a failed threads fetch must not be a success")
[[ "$gh_out" == *"HTTP 502"* ]] || problems+=("gh's own error was swallowed")
[[ "$gh_out" != *"PR #7 docs:"* ]] || problems+=("rendered a header despite the failed threads fetch")
gh_leaks
report gh-threads-fetch-fails "stubbed gh" $gh_rc "$gh_out"

# terminate-mid-fetch — a signal arriving while a fetch is in flight.
#
# The cleanup trap was `EXIT INT TERM`. zsh resumes execution after a
# non-exiting signal handler, so the payload files were deleted and the script
# then walked into the error branch reading files that no longer existed:
#
#   grep: /var/.../tmp.QSF3nyXaBB: No such file or directory
#   grep: /var/.../tmp.PMDW2Um9Un: No such file or directory
#   gh-comments: gh error:
#   cat: /var/.../tmp.PMDW2Um9Un: No such file or directory
#
# EXIT alone fires on signal death too, so the files are still cleaned — they
# just stay alive for the branch that reads them. Asserted here: no read of a
# deleted file, no render, nothing left behind.
#
# SIGTERM rather than the SIGINT a user would actually type: a shell without
# job control starts background jobs with SIGINT *and* SIGQUIT set to ignore,
# so a test script cannot deliver one to its own child. TERM was in the same
# trap list and reaches the same handler, so it pins the same behavior.
#
# Deliberately not asserted: the exit status. How a host zsh reports death
# after a trapped signal is exactly the sort of thing that differs between
# versions, and the regression this case guards shows up in the output.
check_signal_mid_fetch() {
  local name=terminate-mid-fetch outfile out
  local -i rc=0 pid=0 waited=0
  gh_reset
  outfile=$stubdir/signal.out
  : > "$stubfx/hold"

  env "${gh_env[@]}" GH_STUB_MODE=hang zsh "$script" --pr 7 --toc > "$outfile" 2>&1 &
  pid=$!
  # Wait for the stub to log the timeline query — that is the fetch being in
  # flight. Bounded, so a broken stub fails the case instead of hanging CI.
  while (( waited < 200 )) && ! grep -qx 'graphql:tl' "$stublog" 2>/dev/null; do
    sleep 0.05; (( waited += 1 ))
  done
  grep -qx 'graphql:tl' "$stublog" 2>/dev/null \
    || problems+=("the stub never reached the timeline fetch — nothing was signalled")
  kill -TERM $pid 2>/dev/null
  wait $pid; rc=$?
  rm -f "$stubfx/hold"   # release the stub if it outlived its parent

  out=$(<"$outfile")
  [[ "$out" != *"No such file"* ]] \
    || problems+=("read a temp file the trap had already deleted")
  [[ "$out" != *"PR #7 docs:"* ]] \
    || problems+=("rendered a header despite being killed mid-fetch")
  gh_leaks
  report "$name" "signal mid-fetch" $rc "$out"
  return 0
}

check_signal_mid_fetch

# --- argument validation ---------------------------------------------------
# argcase <name> <want-rc> <want-substring> [args...]
argcase() {
  local name=$1 want=$3 out
  local -i want_rc=$2 rc=0
  shift 3
  out=$(zsh "$script" --pr "$@" 2>&1) || rc=$?
  (( rc == want_rc )) || problems+=("exit $rc (want $want_rc)")
  [[ "$out" == *"$want"* ]] || problems+=("output lacks: $want")
  report "$name" "argument validation" $rc "$out"
}

argcase arg-help              0 "Usage: gh-comments" --help
argcase arg-bad-pr-number     1 "not a PR or issue number: abc" abc
# A bad number is reported before a flag the pinned type refuses, so one
# rerun fixes the command line.
argcase arg-bad-number-before-pinned-flag 1 "not a PR or issue number: abc" abc --events
# An argument is printed as is: `\c` would otherwise end the line early and
# glue the usage text onto the diagnostic.
argcase arg-bad-number-backslash 1 'not a PR or issue number: a\cb'$'\n'"Usage: gh-comments" 'a\cb'
argcase arg-unknown-flag      1 "unknown flag: --nope" 7 --nope
argcase arg-second-pr-number  1 "unexpected argument: 8" 7 8
# The same for the two diagnostics that quote an argument verbatim.
argcase arg-unknown-flag-backslash 1 'unknown flag: --x\cy' 7 '--x\cy'
argcase arg-second-number-backslash 1 'unexpected argument: x\cy' 7 'x\cy'
# --fixtures validates the timeline operand up front, because every path after
# it assumes that file is readable. The threads operand is optional at parse
# time — an issue has none — and refused later, once the payload has said the
# target is a PR after all.
argcase arg-fixtures-missing  1 "needs a readable timeline JSON file" 7 --fixtures /nonexistent/a /nonexistent/b
# The query takes owner and name apart, so the host- and URL-qualified forms
# gh's own -R accepts are refused up front rather than split wrong.
argcase arg-repo-url-form     1 "-R needs <owner/name>; got: https://github.com/acme/widget" 7 -R https://github.com/acme/widget
argcase arg-repo-host-form    1 "-R needs <owner/name>; got: github.com/acme/widget" 7 --repo=github.com/acme/widget
argcase arg-repo-bare-name    1 "-R needs <owner/name>; got: widget" 7 -R widget
argcase arg-repo-needs-number 1 "-R needs a number: the current branch's PR is in the cwd's repo, not in acme/widget" -R acme/widget
argcase arg-fixtures-pr-needs-threads 1 "needs a threads payload for a PR" 7 --fixtures "$fx/zero-threads.tl.json"
argcase arg-fixtures-no-number 1 "a number is required with --fixtures" \
  --fixtures "$fx/zero-threads.tl.json" "$fx/zero-threads.th.json"
# A kind only an issue has is refused on a PR by name, like --events.
argcase arg-only-issue-kind   1 "--only xref, --only closed only apply to issues; the type is pinned to a pull request by --pr" \
  7 --only comment,xref,closed
# --unresolved renders reviews and threads only, so asking it for another kind
# could only print an empty line under a counts line that says otherwise.
argcase arg-only-unresolved-kinds 1 "--only comment, --only commit with --unresolved, which renders only reviews and threads" \
  7 --unresolved --only comment,thread,commit
# Each kind on its own, with a payload that would render: the refusal, not a
# fetch that cannot run offline, is what must end the run.
for k in comment body commit force-push; do
  argcase arg-only-unresolved-$k 1 "--only $k with --unresolved, which renders only reviews and threads" \
    1001 --unresolved --only $k --fixtures "$fx/basic.tl.json" "$fx/basic.th.json"
done
# Under a window, a filter that keeps nothing says the window is empty, not
# the PR: multi has two reviews, both before the --latest anchor.
argcase arg-only-nothing-after-anchor 0 "(no items of kind: review after the anchor)" \
  42 --toc --latest --only review --fixtures "$fx/multi.tl.json" "$fx/multi.th.json"
argcase arg-only-nothing-since    0 "(no items of kind: commit since 2026-08-14T23:30)" \
  1001 --toc --since 2026-08-14T23:30 --only commit --fixtures "$fx/basic.tl.json" "$fx/basic.th.json"
# --unresolved is a view of its own: bot-review-late has a human review, but
# none with an open thread, so the line names the view rather than say the PR
# has no review.
argcase arg-only-nothing-unresolved 0 "(no items of kind: review in the unresolved view)" \
  42 --toc --unresolved --only review --fixtures "$fx/bot-review-late.tl.json" "$fx/bot-review-late.th.json"
# Both at once: the window is after the anchor *and* since the date.
argcase arg-only-nothing-anchor-since 0 "(no items of kind: review after the anchor and since 2026-08-12)" \
  42 --toc --latest --since 2026-08-12 --only review --fixtures "$fx/multi.tl.json" "$fx/multi.th.json"
# --item is a selector: every flag that narrows the view is refused, all at once.
argcase arg-item-with-views   1 "--item selects one item and takes no view flag; drop --toc, --only, --unresolved, --latest, --since" \
  7 --item x --toc --only comment --unresolved --latest --since 2026-01-01
argcase arg-item-with-slr     1 "drop --since-last-review" 7 --item x --since-last-review
argcase arg-item-missing-value 1 "--item needs <header-prefix>" 7 --item
argcase arg-item-empty        1 "--item needs <header-prefix>" 7 --item=
# Review, thread, commit and force-push headers take two spaces after the
# kind; a prefix typed with one, as a comment's is, finds nothing, and the
# refusal says why.
argcase arg-item-one-space    1 "no item starts with: review [reviewer-bart (the TOC writes two spaces after review" \
  1001 --item 'review [reviewer-bart' --fixtures "$fx/basic.tl.json" "$fx/basic.th.json"

rm -rf "$stubdir"

(( fails == 0 ))
