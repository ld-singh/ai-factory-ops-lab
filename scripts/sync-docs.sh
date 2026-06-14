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

count=$(find "$DEST" -name '*.md' | wc -l | tr -d ' ')
echo "Synced ${count} markdown pages into ${DEST}/ (root README published as course.md)."
