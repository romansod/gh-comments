#!/usr/bin/env zsh
# Fixed costs: what a session pays for the two skills before any command runs.
# Writes out/FIX.<key>.txt so count_tokens.py counts them alongside everything
# else and analyze.py can fill the "Fixed costs" table:
#
#   FIX.pr_desc, FIX.issue_desc   each description as it appears in the skill
#                                 listing a session is given: `- <name>: <text>`
#                                 on one line — paid every session, used or not.
#                                 A plugin's skills are listed under its
#                                 namespace (`gh-comments:pr-comments`), so the
#                                 name carries SKILL_PREFIX, `gh-comments:` by
#                                 default; set it empty for a copy installed
#                                 without one, such as Codex's
#   FIX.pr_skillmd, FIX.issue_skillmd
#                                 SKILL.md, which is what an invocation loads
#   FIX.<k>_ref, FIX.<k>_flags, FIX.<k>_recipes
#                                 references/output.md, flags.md and
#                                 recipes.md, each loaded only when the
#                                 SKILL.md's pointer to it applies; a copy
#                                 without one of them has no row for it
#   FIX.banner                    an install banner on its own, so its share
#                                 is visible — only when the copy carries one
#
# Reads this checkout's skills/, which is what the plugin installs: a plugin
# copy is the repository as-is, with no banner. SKILLS_DIR measures another
# copy instead, for example one an installer stamped with a banner.
set -euo pipefail
# Resolved before the cd below, so a relative path means what the caller meant.
if [[ -n ${SKILLS_DIR:-} ]]; then
  SK=${SKILLS_DIR:A}
else
  SK=${0:A:h:h}/skills
fi
cd ${0:A:h}
mkdir -p out
# New outputs need a new count, as in run-cases.zsh.
rm -f tokens.tsv
PFX=${SKILL_PREFIX-gh-comments:}

# desc <SKILL.md> — the folded `description: >` scalar from the frontmatter,
# joined with single spaces the way a folded YAML scalar reads.
desc() {
  awk '
    /^description: >/ { p = 1; next }
    p && (/^[a-z-]+:/ || /^---$/) { exit }
    p { sub(/^  /, ""); printf "%s%s", (n++ ? " " : ""), $0 }
  ' "$1"
}

for k in pr issue; do
  f=$SK/$k-comments/SKILL.md
  if [[ ! -r $f ]]; then
    print -ru2 -- "run-fixed: $f not found — point SKILLS_DIR at a directory holding pr-comments/ and issue-comments/"
    exit 1
  fi
  cp "$f" out/FIX.${k}_skillmd.txt
  # No trailing newline: that is how the baseline captured them, and a byte of
  # difference is a cache miss and a spurious delta.
  print -rn -- "- $PFX$k-comments: $(desc "$f")" > out/FIX.${k}_desc.txt
  # output.md keeps the key `ref` it had before the other two existed, so
  # runs on either side of the split compare row for row.
  for name key in output ref flags flags recipes recipes; do
    r=$SK/$k-comments/references/$name.md
    if [[ -r $r ]]; then
      cp "$r" out/FIX.${k}_$key.txt
    else
      rm -f out/FIX.${k}_$key.txt
      print -ru2 -- "run-fixed: no $r — no FIX.${k}_$key row"
    fi
  done
done
# A copy an installer stamped carries its banner as the first `<!-- Deployed
# copy` line; take it from one. A plugin copy has none, and then there is no
# banner row: an empty
# file would count as a banner that costs nothing, so the file is taken away
# (the redirect has already truncated it by then) and the absence is said.
grep -m1 '^<!-- Deployed copy' "$SK/pr-comments/SKILL.md" > out/FIX.banner.txt || {
  rm -f out/FIX.banner.txt
  print -ru2 -- "run-fixed: no install banner in $SK/pr-comments/SKILL.md — no FIX.banner row"
}
wc -c out/FIX.*.txt
