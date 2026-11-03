#!/usr/bin/env zsh
# The newest filed run's fixed-cost rows for SKILL.md and each reference file
# must carry the byte size of the file as committed, so a skill edit after the
# count shows up as a stale row rather than a published, wrong fixed cost.
#
# Not part of `make check` or CI: a stale row is fixed by recounting, which
# calls `claude -p` and costs money, and a skill edit should not need that to
# land. Run it before a release (`make bench-check`, CONTRIBUTING.md); when it
# fails, recount into the newest run and rebuild its tables:
#
#   cd bench && zsh run-fixed.zsh && python3 count_tokens.py
#   cp tokens.tsv runs/<newest>/ && python3 analyze.py runs/<newest> --baseline runs/<previous>
set -uo pipefail
root=${0:A:h:h}
typeset -a runs problems
runs=("$root"/bench/runs/*(/N:t))
(( ${#runs} )) || { print -ru2 -- "bench-check: no filed run under bench/runs"; exit 1; }
run=$root/bench/runs/${runs[-1]}
local id bytes k key file size
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
if (( ${#problems} )); then
  print -ru2 -- "bench-check: bench/runs/${runs[-1]} is stale; recount the skill files:"
  print -rlu2 -- "  "${^problems}
  exit 1
fi
print -r -- "bench-check: bench/runs/${runs[-1]} fixed costs match the skill files"
