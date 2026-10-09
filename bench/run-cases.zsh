#!/usr/bin/env zsh
# Runs every (target, approach) pair once, capturing stdout exactly as an agent's
# Bash tool would receive it (non-TTY), plus wall-clock ms and the number of
# agent tool calls (always 1 here; composites add them up). Writes out/<id>.txt and cases.tsv.
#
# The script under test is this checkout's own gh-comments, so a run measures
# whatever is checked out (`git checkout v1.0.0` to measure a release); set
# GH_COMMENTS to an executable to measure another. The targets are in
# targets.json. Live GitHub targets drift between runs: a change in a raw `gh`
# row is GitHub moving, not the script.
set -uo pipefail
zmodload zsh/datetime zsh/mathfunc
# Resolved before the cd below, so a relative path means what the caller meant.
if [[ -n ${GH_COMMENTS:-} ]]; then
  S=${GH_COMMENTS:A}
else
  S=${0:A:h:h}/gh-comments
fi
[[ -x $S ]] || { print -ru2 -- "run-cases: $S is not an executable gh-comments"; exit 1 }
cd ${0:A:h}
mkdir -p out
print -r -- $'id\ttarget\tapproach\tcalls\tms\tbytes\texit' > cases.tsv

run() { # run <target> <approach> <calls> <cmd...>
  local tgt=$1 ap=$2 calls=$3; shift 3
  local id="$tgt.$ap" t0 t1 rc
  t0=$EPOCHREALTIME
  "$@" < /dev/null > out/$id.txt 2> out/$id.err; rc=$?
  t1=$EPOCHREALTIME
  print -r -- "$id"$'\t'"$tgt"$'\t'"$ap"$'\t'"$calls"$'\t'$(( int((t1 - t0) * 1000) ))$'\t'$(wc -c < out/$id.txt | tr -d ' ')$'\t'$rc >> cases.tsv
}

GQL_META='query($o:String!,$n:String!,$num:Int!,$endCursor:String){repository(owner:$o,name:$n){pullRequest(number:$num){reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{path line originalLine isResolved isOutdated}}}}}'
GQL_BODIES='query($o:String!,$n:String!,$num:Int!,$endCursor:String){repository(owner:$o,name:$n){pullRequest(number:$num){reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{path line originalLine isResolved isOutdated comments(first:50){nodes{author{login} createdAt body}}}}}}}'

pr_target() { # pr_target <label> <owner/name> <num> <since-date>
  local L=$1 R=$2 N=$3 SINCE=$4 O=${2%%/*} NM=${2##*/}
  run $L gh_view       1 gh pr view $N -R $R
  run $L gh_view_c     1 gh pr view $N -R $R --comments
  run $L rest_ic       1 gh api repos/$R/issues/$N/comments --paginate
  run $L rest_rv       1 gh api repos/$R/pulls/$N/reviews --paginate
  run $L rest_rc       1 gh api repos/$R/pulls/$N/comments --paginate
  run $L gql_meta      1 gh api graphql --paginate -F o=$O -F n=$NM -F num=$N -f query=$GQL_META
  run $L gql_open      1 gh api graphql --paginate -F o=$O -F n=$NM -F num=$N -f query=$GQL_BODIES \
        --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved|not)'
  run $L s_full        1 $S $N --pr -R $R
  run $L s_toc         1 $S $N --pr -R $R --toc
  run $L s_unres       1 $S $N --pr -R $R --unresolved
  run $L s_toc_unres   1 $S $N --pr -R $R --toc --unresolved
  run $L s_slr         1 $S $N --pr -R $R --since-last-review
  run $L s_latest      1 $S $N --pr -R $R --latest
  run $L s_since       1 $S $N --pr -R $R --since $SINCE
}

issue_target() { # issue_target <label> <owner/name> <num>
  local L=$1 R=$2 N=$3
  run $L gh_view       1 gh issue view $N -R $R
  run $L gh_view_c     1 gh issue view $N -R $R --comments
  run $L gh_json_close 1 gh issue view $N -R $R --json state,stateReason,closedAt,closedByPullRequestsReferences
  run $L rest_issue    1 gh api repos/$R/issues/$N
  run $L rest_ic       1 gh api repos/$R/issues/$N/comments --paginate
  run $L rest_tl       1 gh api repos/$R/issues/$N/timeline --paginate
  run $L s_full        1 $S $N -R $R --issue
  run $L s_toc         1 $S $N -R $R --issue --toc
  run $L s_events      1 $S $N -R $R --issue --events
}

print -r -- "run-cases: $S ($($S --version 2>/dev/null || print unknown version))" >&2
jq -r '.prs[] | [.label, .repo, .number, .since] | @tsv' targets.json |
  while IFS=$'\t' read -r L R N SINCE; do pr_target $L $R $N $SINCE; done
jq -r '.issues[] | [.label, .repo, .number] | @tsv' targets.json |
  while IFS=$'\t' read -r L R N; do issue_target $L $R $N; done
