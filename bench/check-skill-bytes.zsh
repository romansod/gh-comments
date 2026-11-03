#!/usr/bin/env zsh
# The newest filed run's fixed-cost rows for SKILL.md and each reference file
# must carry the byte size of the file as committed, so a skill edit after the
# count shows up as a stale row rather than a published, wrong fixed cost.
#
# Not part of `make check` or CI: a stale row is fixed by recounting, which
# calls `claude -p` and costs money, and a skill edit should not need that to
# land. Run it before a release (`make bench-check`, CONTRIBUTING.md); when it
# fails, `zsh bench/refile-fixed.zsh` recounts the skill files into the newest
# run, keeps its other rows as filed, and rebuilds its tables (paid).
set -uo pipefail
root=${0:A:h:h}
typeset -a runs problems
runs=("$root"/bench/runs/*(/N:t))
(( ${#runs} )) || { print -ru2 -- "bench-check: no filed run under bench/runs"; exit 1; }
run=$root/bench/runs/${runs[-1]}
local id bytes k key file size c
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
  (( size == bytes )) || problems+=("$id: run counted $bytes bytes, $file is ${size// /}")
done < <(cut -f1,2 "$run/tokens.tsv")
# Every skill file that ships needs a row: run-fixed.zsh captures SKILL.md and
# a fixed set of references, so a new reference file would have none.
local -A rowfor=(SKILL.md skillmd output.md ref flags.md flags recipes.md recipes)
for file in "$root"/skills/*-comments/{SKILL.md,references/*.md}(N); do
  k=${${file:h:h:t}%-comments}; [[ ${file:h:t} == references ]] || k=${${file:h:t}%-comments}
  key=${rowfor[${file:t}]:-}
  if [[ -z $key ]]; then
    problems+=("${file#$root/}: no fixed-cost row (run-fixed.zsh does not capture it)")
  elif ! grep -q "^FIX.${k}_${key}	" "$run/tokens.tsv"; then
    problems+=("${file#$root/}: no FIX.${k}_${key} row in the run")
  fi
done
# Bytes miss an edit that keeps the length. In a git checkout, the skill files
# must be as they were at the commit that last wrote the run's counts, unless
# those counts are themselves uncommitted (a refile not yet committed).
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1 \
  && git -C "$root" diff --quiet HEAD -- "bench/runs/${runs[-1]}/tokens.tsv"; then
  c=$(git -C "$root" log -1 --format=%H -- "bench/runs/${runs[-1]}/tokens.tsv")
  [[ -n $c ]] && ! git -C "$root" diff --quiet "$c" -- skills/ \
    && problems+=("skills/ changed since ${c[1,7]} last counted the run: $(git -C "$root" diff --name-only "$c" -- skills/ | tr '\n' ' ')")
fi
if (( ${#problems} )); then
  print -ru2 -- "bench-check: bench/runs/${runs[-1]} is stale; zsh bench/refile-fixed.zsh recounts it (paid):"
  print -rlu2 -- "  "${^problems}
  exit 1
fi
print -r -- "bench-check: bench/runs/${runs[-1]} fixed costs match the skill files"
