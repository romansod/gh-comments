#!/usr/bin/env zsh
# lib.zsh — shared reporting for tests/. Sourced, never executed.
#
# Kanji-rain styling: a truecolor palette with 合 pass / 落 fail / 書
# golden-written case lines. Colors turn
# on when stdout is a TTY or FORCE_COLOR / CLICOLOR_FORCE is set (the CI
# workflow sets FORCE_COLOR=1 — the Actions log renders ANSI).
#
# Under GitHub Actions (GITHUB_ACTIONS=true) failures additionally emit
# ::error annotations anchored on the golden file, and every case appends to
# the job's Markdown step summary ($GITHUB_STEP_SUMMARY) — pass/fail bullets
# plus a collapsed diff per failure.
#
# API (test files):
#   t_ok    <case>
#   t_fail  <case> <detail-file> [<repo-rel-path>] [<title>]
#   t_wrote <path>                              # GOLDEN_UPDATE mode
# There is deliberately no skip helper: every suite here runs on every platform,
# and a file that bows out wholesale still counts as a passing file in run.zsh's
# footer — which is exactly how a broken suite reads as green.
# run.zsh additionally uses t_summary and tallies $T_STATS (one ok/fail line
# per case; unset when a test file runs standalone).

[[ -n ${_T_LIB:-} ]] && return 0
_T_LIB=1

if [[ -t 1 || -n ${FORCE_COLOR:-} || -n ${CLICOLOR_FORCE:-} ]]; then
  T_MAG=$'\033[38;2;255;79;208m'   # kanji icons, header rule, diff hunks
  T_CYN=$'\033[38;2;77;240;224m'   # pass, added diff lines
  T_AMB=$'\033[38;2;255;180;84m'   # golden-update writes
  T_RED=$'\033[38;2;255;75;87m'    # fail, removed diff lines
  T_WHT=$'\033[38;2;232;238;250m'  # file headers
  T_DIM=$'\033[38;2;74;88;113m'    # chrome, diff context
  T_RST=$'\033[0m'
else
  T_MAG='' T_CYN='' T_AMB='' T_RED='' T_WHT='' T_DIM='' T_RST=''
fi

typeset -gi T_CI=0
[[ ${GITHUB_ACTIONS:-} == true ]] && T_CI=1

# Append a line to the CI step summary; no-op outside Actions.
t_summary() {
  [[ -n ${GITHUB_STEP_SUMMARY:-} ]] || return 0
  print -r -- "$1" >> "$GITHUB_STEP_SUMMARY"
}

_t_count() {  # ok|fail — run.zsh tallies these for the footer meter
  [[ -n ${T_STATS:-} ]] && print -r -- "$1" >> "$T_STATS"
  return 0
}

t_ok() {
  print -r -- "  ${T_CYN}合${T_RST} $1"
  _t_count ok
  t_summary "- 合 \`$1\`"
}

t_wrote() {
  print -r -- "  ${T_AMB}書${T_RST} wrote $1"
}

# t_fail <case> <detail-file> [<repo-rel-path>] [<title>]
# detail-file holds a unified diff (golden mismatch) or raw output (script
# error); repo-rel-path anchors the ::error annotation — for a golden
# mismatch, the golden file itself, so the annotation lands on the file whose
# regeneration fixes it.
t_fail() {
  local name=$1 detail=${2:-} anno=${3:-} title=${4:-golden mismatch} line
  print -r -- "  ${T_RED}落 ${name}${T_RST} ${T_DIM}(${title})${T_RST}"
  if [[ -n $detail && -s $detail ]]; then
    while IFS= read -r line; do
      case $line in
        (---*|+++*) print -r -- "    ${T_WHT}${line}${T_RST}" ;;
        (@@*)       print -r -- "    ${T_MAG}${line}${T_RST}" ;;
        (-*)        print -r -- "    ${T_RED}${line}${T_RST}" ;;
        (+*)        print -r -- "    ${T_CYN}${line}${T_RST}" ;;
        (*)         print -r -- "    ${T_DIM}${line}${T_RST}" ;;
      esac
    done < "$detail"
  fi
  _t_count fail
  if (( T_CI )); then
    if [[ -n $anno ]]; then
      print -r -- "::error file=${anno},title=${title}::${name} failed — full diff in the step summary and log"
    else
      print -r -- "::error title=${title}::${name} failed"
    fi
  fi
  t_summary "- 落 \`$name\` — ${title}"
  if [[ -n ${GITHUB_STEP_SUMMARY:-} && -n $detail && -s $detail ]]; then
    # Four-backtick fence: goldens themselves contain ``` fences (html-heavy).
    {
      print -r -- "<details><summary>落 <code>${name}</code> — ${title}</summary>"
      print -r -- ""
      print -r -- '````diff'
      cat -- "$detail"
      print -r -- '````'
      print -r -- ""
      print -r -- "</details>"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  return 0
}
