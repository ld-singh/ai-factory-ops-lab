#!/usr/bin/env python3
"""Rewrite relative links to non-rendered repo files into absolute GitHub URLs.

The docs site renders the Markdown pages but not the code (scripts, manifests,
Makefiles, Dockerfiles, configs, dashboards). Links to those would 404 on the site,
so here we point them at GitHub instead. Left untouched: external/anchor links,
Markdown pages (.md), images, and directories that have their own README (rendered
sections like runbooks/ and 06-validation-reports/).

Operates in place on the synced docs/ tree (scripts/sync-docs.sh calls it). Paths
resolve correctly because docs/ mirrors the repo layout, and the script runs from the
repo root so it can stat the real files to decide file (blob) vs directory (tree).
"""
import os
import re
import sys

REPO = "https://github.com/ld-singh/ai-factory-ops-lab"
BRANCH = "main"
IMAGE_EXT = (".png", ".svg", ".jpg", ".jpeg", ".gif", ".webp")
LINK_RE = re.compile(r'(!?)\[([^\]]*)\]\(([^)\s]+)(\s+"[^"]*")?\)')

docs = sys.argv[1] if len(sys.argv) > 1 else "docs"


def rewrite(text, repo_dir):
    def repl(m):
        bang, label, target, title = m.group(1), m.group(2), m.group(3), m.group(4) or ""
        if bang:                                    # image: rendered inline, leave it
            return m.group(0)
        if target.startswith(("http://", "https://", "mailto:", "#", "/")):
            return m.group(0)
        url = target.split("#", 1)[0]
        frag = "#" + target.split("#", 1)[1] if "#" in target else ""
        if url == "":
            return m.group(0)
        base = "" if repo_dir == "." else repo_dir
        resolved = os.path.normpath(os.path.join(base, url))
        if resolved.startswith(".."):               # outside the repo: leave
            return m.group(0)
        low = resolved.lower()
        if low.endswith(".md") or low.endswith(IMAGE_EXT):   # rendered page / image
            return m.group(0)
        if os.path.isdir(resolved):
            if os.path.isfile(os.path.join(resolved, "README.md")):
                return m.group(0)                   # rendered section: keep relative
            return f"{bang}[{label}]({REPO}/tree/{BRANCH}/{resolved}{frag}{title})"
        if os.path.isfile(resolved):
            return f"{bang}[{label}]({REPO}/blob/{BRANCH}/{resolved}{frag}{title})"
        return m.group(0)                           # unknown target: leave

    return LINK_RE.sub(repl, text)


count = 0
for root, _, files in os.walk(docs):
    for fn in files:
        if not fn.endswith(".md"):
            continue
        path = os.path.join(root, fn)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        new = rewrite(text, os.path.relpath(root, docs))
        if new != text:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(new)
            count += 1

print(f"Rewrote code-file links to GitHub URLs in {count} page(s).")
