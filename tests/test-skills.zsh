#!/usr/bin/env zsh

# Tests for what the skills tell an agent to run, and for the benchmark
# tables built from a filed run. Neither is the script's output, so the
# golden suites never read them; each case here pins one claim the docs or
# BENCHMARKS.md make.
#
#   recipes-read-the-dump  each references/recipes.md bash block, run one
#                          line per fresh shell (an agent's Bash tool keeps
#                          no shell state between calls) from an empty cwd,
#                          with gh-comments stubbed to print a golden: no
#                          line exits 2, and the reads find the dump
#   skill-invocation       a repo appears in an "Invoked as" line only with
#                          a number, since -R needs one
#   skill-one-item-flow    step 1 of each SKILL.md names --toc --only, the
#                          one-item TOC that analyze.py prices, and the
#                          question table names --item
#   bench-tables-match-run analyze.py over the newest filed run, with the
#                          run before it as baseline, reproduces its
#                          committed tables.md byte for byte
#   bench-skill-bytes      the newest run's fixed-cost rows for SKILL.md
#                          and each reference file carry the byte size of
#                          the file as committed, so a skill edit after the
#                          count shows up as a stale row
set -uo pipefail

here=${0:A:h}
root=$here/..
source "$here/lib.zsh"
typeset -i fails=0
typeset -a problems=()

# report <case> <detail> — one t_ok, or one t_fail carrying the problem
# list. Always clears `problems`.
report() {
  local name=$1 dtmp
  if (( ${#problems} == 0 )); then
    t_ok "$name"
  else
    dtmp=$(mktemp)
    print -rl -- $problems > "$dtmp"
    t_fail "$name" "$dtmp" "tests/test-skills.zsh" "${2:-check failed}"
    rm -f "$dtmp"
    (( fails += 1 ))
  fi
  problems=()
  return 0
}

# block <file> — the first ```bash fenced block of a markdown file.
block() {
  awk '/^```bash$/ { if (!d) { p = 1; next } } /^```$/ { if (p) { p = 0; d = 1 } } p' "$1"
}

recipes_read_the_dump() {
  local name=recipes-read-the-dump tmp kind golden user line rc out
  local -i reads hits
  tmp=$(mktemp -d)
  mkdir -p "$tmp/bin" "$tmp/cwd" "$tmp/tmpdir"
  for kind golden user in \
    pr "$here/fixtures/pr-comments/expected/basic-full.txt" reviewer-bart \
    issue "$here/fixtures/gh-comments/expected/issue-basic-full.txt" alice; do
    print -r -- "#!/bin/sh
cat '$golden'" > "$tmp/bin/gh-comments"
    chmod +x "$tmp/bin/gh-comments"
    rm -f "$tmp/tmpdir"/*(N)
    reads=0 hits=0
    while IFS= read -r line; do
      [[ -n $line ]] || continue
      line=${line//<N>/1}
      line=${line//<user>/$user}
      out=$(cd "$tmp/cwd" && PATH="$tmp/bin:$PATH" TMPDIR="$tmp/tmpdir" zsh -fc "$line" 2>&1)
      rc=$?
      (( rc == 2 )) || [[ $out == *"No such file"* ]] \
        && problems+=("$kind: exit $rc: $line: ${out%%$'\n'*}")
      if [[ $line != *'gh-comments '* ]]; then
        (( reads += 1 ))
        [[ -n $out ]] && (( hits += 1 ))
      fi
    done < <(block "$root/skills/$kind-comments/references/recipes.md")
    (( reads > 0 )) || problems+=("$kind: the recipe block has no reads")
    (( hits > 0 )) || problems+=("$kind: no read printed anything from the dump")
    [[ -z $(print -l "$tmp/cwd"/*(N)) ]] || problems+=("$kind: the recipe wrote into the cwd")
  done
  rm -rf "$tmp"
  report "$name" "a recipe line misses the dump"
}
recipes_read_the_dump

skill_invocation() {
  local name=skill-invocation f line
  for f in "$root"/skills/*/SKILL.md; do
    line=$(grep -m1 'Invoked as' "$f")
    [[ -n $line ]] || { problems+=("${f#$root/}: no 'Invoked as' line"); continue; }
    # A repo is allowed nested inside an optional number, or after a
    # required one; never as a bracket of its own beside the number's.
    [[ $line == *'[<N>] [<owner>/<repo>]'* ]] \
      && problems+=("${f#$root/}: a repo without a number: $line")
    [[ $line == *'[<N> [<owner>/<repo>]]'* || $line == *'`'*'-comments <N> [<owner>/<repo>]`'* ]] \
      || problems+=("${f#$root/}: unexpected invocation grammar: $line")
  done
  report "$name" "invocation grammar"
}
skill_invocation

skill_one_item_flow() {
  local name=skill-one-item-flow f step1
  for f in "$root"/skills/*/SKILL.md; do
    step1=$(awk '/^1\. \*\*Orient/ { p = 1 } /^2\. / { p = 0 } p' "$f")
    [[ $step1 == *'--toc --only'* ]] \
      || problems+=("${f#$root/}: step 1 does not name --toc --only for one item")
    grep -q -- '`--item`' "$f" || problems+=("${f#$root/}: the question table does not name --item")
  done
  report "$name" "one-item flow"
}
skill_one_item_flow

bench_tables_match_run() {
  local name=bench-tables-match-run tmp out
  local -a runs
  runs=("$root"/bench/runs/*(/N:t))
  if (( ${#runs} < 2 )); then
    problems+=("need two filed runs, found ${#runs}")
    report "$name"; return 0
  fi
  tmp=$(mktemp -d)
  cp -R "$root/bench/runs/${runs[-2]}" "$root/bench/runs/${runs[-1]}" "$tmp/"
  out=$(python3 -I "$root/bench/analyze.py" "$tmp/${runs[-1]}" --baseline "$tmp/${runs[-2]}" 2>&1) \
    || problems+=("analyze.py exited $?: ${out##*$'\n'}")
  diff -u "$root/bench/runs/${runs[-1]}/tables.md" "$tmp/${runs[-1]}/tables.md" > "$tmp/diff" \
    || problems+=("bench/runs/${runs[-1]}/tables.md differs from what analyze.py builds:" "$(head -20 "$tmp/diff")")
  rm -rf "$tmp"
  report "$name" "stale tables"
}
bench_tables_match_run

bench_skill_bytes() {
  local name=bench-skill-bytes run id k key file bytes size
  local -a runs
  runs=("$root"/bench/runs/*(/N:t))
  run=$root/bench/runs/${runs[-1]}
  while IFS=$'\t' read -r id bytes; do
    [[ $id == FIX.(pr|issue)_* ]] || continue
    k=${${id#FIX.}%%_*} key=${id#FIX.${k}_}
    case $key in
      (skillmd) file=skills/$k-comments/SKILL.md ;;
      (ref)     file=skills/$k-comments/references/output.md ;;
      (flags|recipes) file=skills/$k-comments/references/$key.md ;;
      (*) continue ;;
    esac
    size=$(wc -c < "$root/$file")
    (( size == bytes )) || problems+=("$id: run counted $bytes bytes, $file is ${size// /} — recount the skill files")
  done < <(cut -f1,2 "$run/tokens.tsv")
  report "$name" "stale fixed costs"
}
bench_skill_bytes

(( fails == 0 ))
