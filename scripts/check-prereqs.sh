#!/usr/bin/env bash
# check-prereqs.sh — verify local tooling for the AI Factory Operations Lab.
# Safe: read-only, makes no changes. Exit code 0 = all required tools present.

set -uo pipefail

REQUIRED=(docker kubectl kind helm jq)
OPTIONAL=(kwokctl kwok k3d)

missing=0

check_tool() {
  local tool="$1" level="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    # Print a short version string where the tool supports it, best-effort.
    local ver
    ver=$("$tool" version --short 2>/dev/null | head -1 || "$tool" --version 2>/dev/null | head -1 || echo "installed")
    printf "  [OK]      %-10s %s\n" "$tool" "$ver"
  else
    if [[ "$level" == "required" ]]; then
      printf "  [MISSING] %-10s REQUIRED\n" "$tool"
      missing=1
    else
      printf "  [absent]  %-10s optional\n" "$tool"
    fi
  fi
}

echo "AI Factory Operations Lab — prerequisite check"
echo
echo "Required tools:"
for t in "${REQUIRED[@]}"; do check_tool "$t" required; done
echo
echo "Optional tools (KWOK can also be installed in-cluster via manifests):"
for t in "${OPTIONAL[@]}"; do check_tool "$t" optional; done
echo

# Docker daemon reachable?
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    echo "  [OK]      docker daemon is reachable"
  else
    echo "  [WARN]    docker CLI present but daemon not reachable (is Docker running?)"
    missing=1
  fi
fi

echo
if [[ "$missing" -eq 0 ]]; then
  echo "All required prerequisites satisfied."
else
  echo "Missing prerequisites. Install docs:"
  echo "  kind:  https://kind.sigs.k8s.io/docs/user/quick-start/"
  echo "  KWOK:  https://kwok.sigs.k8s.io/docs/user/installation/"
  echo "  helm:  https://helm.sh/docs/intro/install/"
  exit 1
fi
