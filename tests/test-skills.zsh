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
#                          line exits 2, the reads find the dump, and a
#                          second number's dump leaves the first's alone
#   skill-invocation       a repo appears in an "Invoked as" line only with
#                          a number, since -R needs one
#   skill-one-item-flow    step 1 of each SKILL.md names --toc --only, the
#                          one-item TOC that analyze.py prices, and the
#                          question table names --item
#   bench-tables-match-run analyze.py over the newest filed run, with the
#                          run before it as baseline, reproduces its
#                          committed tables.md byte for byte
#   readme-figures-match-run README's diagram and How it compares table
#                          quote the newest run's cli/cli#14104 figures and
#                          name that run, and its per-invocation skill cost
#                          brackets both SKILL.md counts
#
# Whether the newest run's fixed costs still match the skill files is not
# checked here: fixing a stale row needs a paid recount, so that check is
# bench/check-skill-bytes.zsh, run before a release (`make bench-check`).
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
  local name=recipes-read-the-dump tmp kind golden golden2 user line rc out
  local -i reads hits k
  local -a lines first
  tmp=$(mktemp -d)
  mkdir -p "$tmp/bin" "$tmp/cwd" "$tmp/tmpdir"
  # Each line runs in its own shell, as an agent's Bash calls do; the stub
  # prints one golden for number 1 and another for number 2.
  run_line() {  # run_line <line> <n> — sets rc and out
    line=${1//<N>/$2}
    line=${line//<user>/$user}
    out=$(cd "$tmp/cwd" && PATH="$tmp/bin:$PATH" TMPDIR="$tmp/tmpdir" zsh -fc "$line" 2>&1)
    rc=$?
  }
  for kind golden golden2 user in \
    pr "$here/fixtures/pr-comments/expected/basic-full.txt" \
       "$here/fixtures/pr-comments/expected/multi-full.txt" reviewer-bart \
    issue "$here/fixtures/gh-comments/expected/issue-basic-full.txt" \
       "$here/fixtures/gh-comments/expected/issue-closed-full.txt" alice; do
    print -r -- "#!/bin/sh
case \$1 in 1) cat '$golden' ;; *) cat '$golden2' ;; esac" > "$tmp/bin/gh-comments"
    chmod +x "$tmp/bin/gh-comments"
    rm -f "$tmp/tmpdir"/*(N)
    lines=("${(@f)$(block "$root/skills/$kind-comments/references/recipes.md")}")
    lines=(${lines:#})
    reads=0 hits=0 first=()
    for line in $lines; do
      run_line "$line" 1
      (( rc == 2 )) || [[ $out == *"No such file"* ]] \
        && problems+=("$kind: exit $rc: $line: ${out%%$'\n'*}")
      if [[ $line != *'gh-comments '* ]]; then
        (( reads += 1 ))
        [[ -n $out ]] && (( hits += 1 ))
        first+=("$out")
      fi
    done
    (( reads > 0 )) || problems+=("$kind: the recipe block has no reads")
    (( hits > 0 )) || problems+=("$kind: no read printed anything from the dump")
    [[ -z $(print -l "$tmp/cwd"/*(N)) ]] || problems+=("$kind: the recipe wrote into the cwd")
    # A second number's dump must not change what the first number's reads see.
    for line in ${(M)lines:#*gh-comments *}; do run_line "$line" 2; done
    k=0
    for line in ${lines:#*gh-comments *}; do
      (( k += 1 ))
      run_line "$line" 1
      [[ $out == "${first[k]}" ]] \
        || problems+=("$kind: after dumping number 2, number 1's read reads another dump: $line")
    done
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

readme_figures_match_run() {
  local name=readme-figures-match-run run readme section id lo hi n
  local -a runs
  local -A tok
  runs=("$root"/bench/runs/*(/N:t))
  run=${runs[-1]}
  while IFS=$'\t' read -r id _ n; do tok[$id]=$n; done < "$root/bench/runs/$run/tokens.tsv"
  readme=$(<"$root/README.md")
  section=${${readme#*$'\n'## How it compares$'\n'}%%$'\n'## *}
  # fmt <n> — thousands with commas, as the docs write them.
  fmt() {
    local n=$1 out=
    while (( ${#n} > 3 )); do out=,${n[-3,-1]}$out; n=${n[1,-4]}; done
    print -r -- $n$out
  }
  local -a want=(
    "O1.gh_view_c|$(fmt ${tok[O1.gh_view_c]})"
    "O1.rest_rc|$(fmt ${tok[O1.rest_rc]})"
    "O1.rest trio|$(fmt $(( tok[O1.rest_ic] + tok[O1.rest_rv] + tok[O1.rest_rc] )))"
    "O1.gql_meta|$(fmt ${tok[O1.gql_meta]})"
    "O1.s_full|$(fmt ${tok[O1.s_full]})"
    "O1.s_toc_unres|$(fmt ${tok[O1.s_toc_unres]})"
  )
  local w
  for w in $want; do
    [[ $section == *" ${w#*|}"* ]] || problems+=("How it compares: no ${w#*|} (${w%%|*} in $run)")
  done
  [[ $section == *$run* ]] || problems+=("How it compares does not name the run it quotes ($run)")
  [[ $readme == *"──▶ ${want[6]#*|} tokens"* ]] \
    || problems+=("diagram: no '──▶ ${want[6]#*|} tokens' (O1.s_toc_unres in $run)")
  [[ $readme == *"──▶ ${want[2]#*|} tokens"* ]] \
    || problems+=("diagram: no '──▶ ${want[2]#*|} tokens' (O1.rest_rc in $run)")
  if [[ $section =~ 'about ([0-9,]+) to ([0-9,]+) more when a skill runs' ]]; then
    lo=${match[1]//,/} hi=${match[2]//,/}
    for id in FIX.pr_skillmd FIX.issue_skillmd; do
      (( lo <= tok[$id] && tok[$id] <= hi )) \
        || problems+=("cost sentence $lo to $hi does not bracket $id ${tok[$id]} in $run")
    done
  else
    problems+=("How it compares has no 'about X to Y more when a skill runs'")
  fi
  report "$name" "README quotes another run"
}
readme_figures_match_run

(( fails == 0 ))
