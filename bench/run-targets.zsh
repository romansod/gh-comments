#!/usr/bin/env zsh
# Targeted retrieval: land ONE specific comment in context. Writes out/<id>.txt
# rows to targets.tsv. A "slice" is the exact item block from a dump that was
# redirected to a file (not in context): its header line through the line before
# the next column-0 item — the ideal grep/sed an agent following the skill does.
#
# Slices are cut from the dumps run-cases.zsh wrote, so run that first. The four
# items, and the PR or issue each comes from, are the `slices` in targets.json.
set -uo pipefail
zmodload zsh/datetime zsh/mathfunc
cd ${0:A:h}
print -r -- $'id\ttarget\tapproach\tcalls\tms\tbytes\texit' > targets.tsv

run() { # run <target> <approach> <cmd...>
  local tgt=$1 ap=$2; shift 2
  local id="$tgt.$ap" t0 t1 rc
  t0=$EPOCHREALTIME
  "$@" < /dev/null > out/$id.txt 2> out/$id.err; rc=$?
  t1=$EPOCHREALTIME
  print -r -- "$id"$'\t'"$tgt"$'\t'"$ap"$'\t'1$'\t'$(( int((t1 - t0) * 1000) ))$'\t'$(wc -c < out/$id.txt | tr -d ' ')$'\t'$rc >> targets.tsv
}

# slice_lit <dump> <literal prefix of the item's header line>
# A header that matches nothing exits 1 (pipefail carries it to the exit
# column), because an empty slice is otherwise indistinguishable from a 0-token
# answer and analyze.py would report it as a saving.
slice_lit() {
  awk -v lit="$2" '
    hit && /^[^ \t]/ { exit }
    !hit && index($0, lit) == 1 { hit = 1 }
    hit { print }
    END { exit !hit }
  ' "$1" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

# slice <dump> <ERE for the item's header line>
slice() {
  awk -v re="$2" '
    hit && /^[^ \t]/ { exit }
    !hit && $0 ~ re { hit = 1 }
    hit { print }
    END { exit !hit }
  ' "$1" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

LIST_IC='.[] | [.id, .user.login, .created_at, (.body | gsub("\\s+";" ") | .[0:70])] | @tsv'
GQL_LIST='query($o:String!,$n:String!,$num:Int!,$endCursor:String){repository(owner:$o,name:$n){pullRequest(number:$num){reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{path line originalLine isResolved comments(first:1){nodes{author{login} body}}}}}}}'
GQL_LIST_JQ='.data.repository.pullRequest.reviewThreads.nodes[] | [.path, (.line // .originalLine), .isResolved, .comments.nodes[0].author.login, (.comments.nodes[0].body | gsub("\\s+";" ") | .[0:70])] | @tsv'
GQL_BODIES='query($o:String!,$n:String!,$num:Int!,$endCursor:String){repository(owner:$o,name:$n){pullRequest(number:$num){reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{path line originalLine comments(first:50){nodes{author{login} createdAt body}}}}}}}'

t() { jq -r "$1" targets.json; }   # one value from targets.json
repo_of() { jq -r --arg l "$1" '(.prs + .issues)[] | select(.label == $l) | "\(.repo)\t\(.number)"' targets.json; }

# --- TA: a top-level comment on a PR, by when it was posted -------------------
# `created` is the comment's UTC time to the minute (YYYY-MM-DDTHH:MM), so no
# login has to be written down; the renderer prints it as `comment [<login>
# YYYY-MM-DD HH:MM]`.
L=$(t .slices.TA.from); IFS=$'\t' read -r R N <<< "$(repo_of $L)"
C=$(t .slices.TA.created)
run TA skill_slice slice out/$L.s_full.txt "^comment [[][^ ]+ ${C%T*} ${C#*T}[]]"
run TA expert_list gh api repos/$R/issues/$N/comments --paginate --jq $LIST_IC
ID=$(awk -F'\t' -v c="$C" 'index($3, c) == 1 {print $1; exit}' out/TA.expert_list.txt)
run TA expert_fetch gh api repos/$R/issues/comments/$ID --jq .body

# --- TB, TC: one inline review thread, by path:line ----------------------------
# The ERE matches the thread header the renderer prints: `thread  <path>:<line> `.
thread_target() { # thread_target <key>
  local K=$1 L R N P LN O NM re sel
  L=$(t .slices.$K.from); IFS=$'\t' read -r R N <<< "$(repo_of $L)"
  P=$(t .slices.$K.path); LN=$(t .slices.$K.line); O=${R%%/*}; NM=${R##*/}
  re="^thread  ${P//./[.]}:$LN "
  sel="select(.path == \"$P\" and ((.line // .originalLine) == $LN))"
  run $K skill_slice slice out/$L.s_full.txt "$re"
  [[ $(t ".slices.$K.open // false") == true ]] && run $K unres_slice slice out/$L.s_unres.txt "$re"
  run $K expert_list gh api graphql --paginate -F o=$O -F n=$NM -F num=$N -f query=$GQL_LIST --jq $GQL_LIST_JQ
  run $K expert_fetch gh api graphql --paginate -F o=$O -F n=$NM -F num=$N -f query=$GQL_BODIES \
    --jq ".data.repository.pullRequest.reviewThreads.nodes[] | $sel | .comments.nodes[] | \"[\\(.author.login) \\(.createdAt)]\\n\\(.body)\\n\""
}
thread_target TB
thread_target TC

# --- TD: the last comment on an issue ------------------------------------------
L=$(t .slices.TD.from); IFS=$'\t' read -r R N <<< "$(repo_of $L)"
run TD skill_slice slice_lit out/$L.s_full.txt "$(grep '^comment \[' out/$L.s_full.txt | tail -1)"
run TD expert_list gh api repos/$R/issues/$N/comments --paginate --jq $LIST_IC
ID=$(tail -1 out/TD.expert_list.txt | cut -f1)
run TD expert_fetch gh api repos/$R/issues/comments/$ID --jq .body
