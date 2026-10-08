#!/usr/bin/env zsh

# Runs every test-*.zsh in this directory; exits 0 iff all pass.
#
# Output is kanji-rain styled (palette and case lines in lib.zsh). Under
# GitHub Actions each test file's output folds into a ::group::, failures
# surface as ::error annotations, and a Markdown report lands in the job's
# step summary.
set -uo pipefail

cd -- "${0:A:h}"
source ./lib.zsh

export T_STATS
T_STATS=$(mktemp)
trap 'rm -f "$T_STATS"' EXIT

typeset -i ran=0 failed=0
typeset t rule="${T_MAG}▓▒░${T_DIM}────────────────────────────────${T_RST}"

print
print -- "  ${T_MAG}試${T_RST} ${T_CYN}gh-comments${T_RST} ${T_DIM}·${T_RST} script tests"
print -- "  $rule"

t_summary "## 試 gh-comments script tests"

typeset -i prefails
for t in test-*.zsh(N); do
  (( ran++ ))
  (( T_CI )) && print -r -- "::group::${t}"
  print
  print -- "  ${T_WHT}${t}${T_RST}"
  t_summary ""
  t_summary "### \`${t}\`"
  t_summary ""
  prefails=$(grep -c '^fail$' "$T_STATS")
  if ! zsh "$t"; then
    (( failed++ ))
    # Belt for files that die before reporting any case (syntax error etc.);
    # cases that failed normally already carried their own annotation.
    if (( T_CI )) && (( $(grep -c '^fail$' "$T_STATS") == prefails )); then
      print -r -- "::error file=tests/${t}::test file failed without reporting a case: ${t}"
    fi
  fi
  (( T_CI )) && print -r -- "::endgroup::"
done

if (( ran == 0 )); then
  print -- "no tests found" >&2
  exit 1
fi

typeset -i okc failc cases filled=0
okc=$(grep -c '^ok$' "$T_STATS")
failc=$(grep -c '^fail$' "$T_STATS")
cases=$(( okc + failc ))

typeset color=$T_CYN failcolor=$T_DIM bar
if (( cases > 0 )); then
  filled=$(( okc * 8 / cases ))
  # A failure always costs at least one visible empty cell.
  (( failc > 0 && filled == 8 )) && filled=7
fi
(( failc > 0 )) && color=$T_RED failcolor=$T_RED
bar="${(l:$filled::▓:):-}${(l:$(( 8 - filled ))::░:):-}"

print
print -- "  $rule"
print -- "  ${T_MAG}計${T_RST} ${color}${bar}${T_RST} ${okc}/${cases} ${T_DIM}·${T_RST} ${T_CYN}合 ${okc}${T_RST} ${T_DIM}·${T_RST} ${failcolor}落 ${failc}${T_RST} ${T_DIM}·${T_RST} $(( ran - failed ))/${ran} files"

t_summary ""
if (( failc == 0 && failed == 0 )); then
  t_summary "**合 ${okc}/${cases} cases passed** across ${ran} test file(s)."
else
  t_summary "**落 ${failc} of ${cases} cases failed** across ${ran} test file(s) — diffs in the details blocks above."
fi

(( failed == 0 ))
