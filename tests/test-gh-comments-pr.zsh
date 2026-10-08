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
# still render, bare). The rest deliberately do not: they were captured before
# those fields were added to the query, and legacy-pr-payload below pins that
# such a payload renders no `body` line rather than a hollow "body [ghost ]".
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
#
# Not every case is golden. Below the goldens, six sections assert exit
# codes and substrings instead, because their input is built at runtime:
#
#   oversized payload  generates a >1 MB timeline rather than committing one
#   fixture shapes     the --slurpfile unwrap: array form, bare stream, garbage
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
#     last review line for --since-last-review, the last substantive line
#     for --latest (a review with threads or a body, or a comment with a
#     body that is not hidden), the named author's when one is named — and
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
# A --latest candidate, read off its TOC line: a review with threads or a
# body preview, or a comment with a preview and no (hidden: …) marker. The
# `[login date time]` header is cut at its closing `HH:MM]`, not the first
# `]` — `vercel[bot]` has one of its own.
_slice_substantive() {
  local rest
  case $1 in
    'review  ['*) rest=${1#*[0-9][0-9]:[0-9][0-9]\] }; [[ ${${rest#*, }%% *} != 0 || -n ${rest#*open\)} ]] ;;
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
        # The anchor: the last review line (slr) or substantive line (latest)
        # in the full render, by the named author when one is named. None
        # means the fallback is expected.
        ai=0
        for (( i = ${#fitems}; i >= 1; i-- )); do
          l=${fitems[i]}
          if [[ $mode == slr ]]; then [[ $l == 'review  ['* ]] || continue
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
# the hidden count either way, with the bot gate applied first.
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
  report "$name" "hidden comments" $rc "$def"
  return 0
}
hidden_bodies_gated

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

# latest-skips-hidden — a hidden comment is not substantive. dave's only
# comment on the hidden fixture is minimized, so --latest=dave has nothing to
# slice from and falls back.
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
  report "$name" "latest" $rc "$out"
  return 0
}
latest_skips_hidden

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
emit_log() { print -r -- "$1" >> "${GH_STUB_LOG:-/dev/null}" }

case "$1 $2" in
  "repo view")
    emit_log "repo view"; print -r -- acme/widget; exit 0 ;;
  "pr view")
    # The branch's-PR hint in the not-found diagnosis and the no-number
    # lookup. Absent answer file means "no PR for this branch", which is a
    # nonzero exit from real gh. The argv is logged so a case can see which
    # repo the lookup was pointed at.
    emit_log "pr view ${*[3,-1]}"
    [[ -r $GH_STUB_FX/branch-pr ]] || exit 1
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
    notfound-*) print -ru2 -- "gh: Could not resolve to a PullRequest with the number of 999."; exit 1 ;;
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
  # errors[] array on stdout.
  notfound-both)
    print -rn -- '{"data":{"repository":{"pullRequest":null}},"errors":[{"type":"NOT_FOUND","path":["repository","pullRequest"],"message":"Could not resolve to a PullRequest with the number of 999."}]}'
    print -ru2 -- "gh: Could not resolve to a PullRequest with the number of 999."
    exit 1 ;;
  # One stream each: the subject greps both, and these pin each half. If it
  # ever greps only one, exactly one of the two cases goes red.
  notfound-stderr)
    print -ru2 -- "gh: Could not resolve to a PullRequest with the number of 999."
    exit 1 ;;
  notfound-stdout)
    print -rn -- '{"errors":[{"message":"Could not resolve to a PullRequest with the number of 999."}]}'
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
  local -i has_commits=0 has_body=0 has_desc=0 has_hidden=0
  gh_reset
  gh_case ok 7 "$@"
  (( gh_rc == 0 )) || problems+=("exit $gh_rc (want 0)")
  grep -q 'PULL_REQUEST_COMMIT' "$qlog" && has_commits=1
  # The IssueComment body follows its minimizedReason; the PR description's
  # body follows its createdAt, so the two markers cannot match each other.
  grep -q 'minimizedReason body' "$qlog" && has_body=1
  # The PR's own description hangs off baseRefName, which nothing else in the
  # query is followed by.
  grep -q 'baseRefName author' "$qlog" && has_desc=1
  # isMinimized rides on the comment node, outside the body slot: the counts
  # line reports hidden comments in every mode, lean included.
  grep -q 'createdAt isMinimized minimizedReason' "$qlog" && has_hidden=1
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

# gh-no-number-uses-repo-flag — with no number the branch's PR is looked up,
# and that lookup must be made in the -R repo: resolved in the cwd's repo and
# fetched from another, the number names a different PR or nothing.
gh_reset
print -r -- '7' > "$stubfx/branch-pr"
gh_rc=0
gh_out=$(env "${gh_env[@]}" GH_STUB_MODE=ok zsh "$script" --pr -R acme/widget --toc 2>&1) || gh_rc=$?
(( gh_rc == 0 )) || problems+=("exit $gh_rc (want 0)")
[[ "$gh_out" == *"note: no number given — using the current branch's PR #7"* ]] \
  || problems+=("did not use the branch's PR")
[[ "$gh_out" == *"PR #7 docs: clarify retry semantics"* ]] || problems+=("did not render PR #7")
grep -q -- '^pr view -R acme/widget ' "$stublog" \
  || problems+=("the branch lookup was not pointed at -R: $(grep '^pr view' "$stublog")")
gh_leaks
report gh-no-number-uses-repo-flag "stubbed gh" $gh_rc "$gh_out"

# gh-no-number-events-refused-before-fetch — the branch lookup settles the
# type as PR, so an issue-only flag is refused there and no timeline is paid for.
gh_reset
print -r -- '7' > "$stubfx/branch-pr"
gh_rc=0
gh_out=$(env "${gh_env[@]}" GH_STUB_MODE=ok zsh "$script" --events 2>&1) || gh_rc=$?
(( gh_rc == 1 )) || problems+=("exit $gh_rc (want 1)")
[[ "$gh_out" == "gh-comments: --events only applies to issues; #7, the current branch's PR, is a pull request" ]] \
  || problems+=("output was: $gh_out")
(( $(grep -c '^graphql:' "$stublog") == 0 )) || problems+=("fetched before refusing")
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
argcase arg-unknown-flag      1 "unknown flag: --nope" 7 --nope
argcase arg-second-pr-number  1 "unexpected argument: 8" 7 8
# --fixtures validates the timeline operand up front, because every path after
# it assumes that file is readable. The threads operand is optional at parse
# time — an issue has none — and refused later, once the payload has said the
# target is a PR after all.
argcase arg-fixtures-missing  1 "needs a readable timeline JSON file" 7 --fixtures /nonexistent/a /nonexistent/b
argcase arg-fixtures-pr-needs-threads 1 "needs a threads payload for a PR" 7 --fixtures "$fx/zero-threads.tl.json"
argcase arg-fixtures-no-number 1 "a number is required with --fixtures" \
  --fixtures "$fx/zero-threads.tl.json" "$fx/zero-threads.th.json"

rm -rf "$stubdir"

(( fails == 0 ))
