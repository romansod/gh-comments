#!/usr/bin/env zsh
# Recounts the skill files into the newest filed run, when `make bench-check`
# says a skill file changed after the run counted it. Calls `claude -p` for
# each changed file, so it costs money (a few cents); see bench/README.md for
# who pays.
#
# Only the fixed-cost rows (FIX.*) are recounted and replaced. Every other row
# of the run's tokens.tsv is a capture of live data that this checkout may not
# have (out/ is not tracked), so it is kept as filed. The run's tables.md is
# then rebuilt, against the run before it when there is one, and the byte
# check is run again. Rebuild BENCHMARKS.md's results from the new tables.md
# by hand, as for any filed run.
set -euo pipefail
cd ${0:A:h}
typeset -a runs
runs=(runs/*(/N:t))
(( ${#runs} )) || { print -ru2 -- "refile-fixed: no filed run under bench/runs"; exit 1; }
run=runs/${runs[-1]}
zsh run-fixed.zsh >/dev/null
COUNT_ONLY=FIX. python3 count_tokens.py
# The run's rows other than FIX.*, then the fresh FIX.* rows, in the order
# count_tokens.py writes a whole run in (by output file name).
python3 -I - "$run/tokens.tsv" tokens.tsv <<'EOF'
import sys
run, fresh = sys.argv[1], sys.argv[2]
head, *rows = open(run).read().splitlines()
keep = [r for r in rows if not r.startswith("FIX.")]
new = [r for r in open(fresh).read().splitlines()[1:] if r.startswith("FIX.")]
rows = sorted(keep + new, key=lambda r: r.split("\t", 1)[0] + ".txt")
open(run + ".new", "w").write("\n".join([head] + rows) + "\n")
EOF
mv "$run/tokens.tsv.new" "$run/tokens.tsv"
# A tokens.tsv here holds only the FIX.* rows; analyze.py reads one from this
# directory by default, so it must not stay behind.
rm -f tokens.tsv
typeset -a args=("$run")
(( ${#runs} >= 2 )) && args+=(--baseline "runs/${runs[-2]}")
python3 analyze.py $args >/dev/null
print -r -- "refile-fixed: $run/tokens.tsv and tables.md updated"
zsh check-skill-bytes.zsh
