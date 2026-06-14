#!/usr/bin/env bash
# sync-docs.sh - copy the lesson markdown into docs/ for the MkDocs site build.
#
# portfolio-lab/ (and runbooks/, diagrams/, control-plane/) stay the single source of
# truth and keep the runnable labs intact. This mirrors their .md (and image assets)
# into docs/ so MkDocs can render them, preserving the relative paths so the existing
# cross-links between lessons keep working. The synced copies under docs/ are gitignored.
#
# docs/index.md, docs/about.md, and docs/stylesheets/ are authored directly and are
# NOT touched by this script.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."   # repo root

DEST="docs"
SRC_DIRS=(portfolio-lab runbooks diagrams control-plane)

for d in "${SRC_DIRS[@]}"; do
  rm -rf "${DEST:?}/$d"
  while IFS= read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"
    cp "$f" "$DEST/$f"
  done < <(find "$d" -type f \( -name '*.md' -o -name '*.png' -o -name '*.svg' -o -name '*.jpg' \) \
             -not -path '*/evidence/*' -not -path '*/private/*')
done

# The root README is the course overview (and holds Lesson 0). Publish it as a page so
# the lessons' "Course home" / "Lesson 0" up-links resolve in the site. The lessons
# link to it as some chain of ../ ending in README.md; rewrite those to course.md.
# (A single ../README.md is a PARENT-lesson link, not the root, so it is left alone.)
cp README.md "$DEST/course.md"
find "$DEST/portfolio-lab" "$DEST/runbooks" "$DEST/diagrams" "$DEST/control-plane" -name '*.md' \
  -exec sed -i 's|\.\./\.\./README\.md|../../course.md|g' {} +

# Inject a "get the code" note into each lesson page (site only). On the website the
# lessons render but the .sh/.yaml/Makefile links do not, so readers need the repo to
# run a lab. The note is added after the page's H1 and links to that lesson's folder
# on GitHub. This is NOT added to the source READMEs (on GitHub you are already in the repo).
REPO_URL="https://github.com/ld-singh/ai-factory-ops-lab"
while IFS= read -r f; do
  reldir=$(dirname "${f#"$DEST"/}")          # e.g. portfolio-lab/01-k8s-gpu-platform
  note=$(printf '%s\n' \
    '!!! tip "Get the code to run this lab"' \
    "    The commands on this page come from the repository, not the website. Clone it and enter this lesson's folder: \`git clone ${REPO_URL} && cd ai-factory-ops-lab/${reldir}\`. [:material-github: Browse this lesson on GitHub](${REPO_URL}/tree/main/${reldir})" \
    '')
  awk -v note="$note" '!ins && /^# /{print; print ""; print note; ins=1; next} {print}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done < <(find "$DEST/portfolio-lab" -name 'README.md')

count=$(find "$DEST" -name '*.md' | wc -l | tr -d ' ')
echo "Synced ${count} markdown pages into ${DEST}/ (root README published as course.md; repo note added to lessons)."
