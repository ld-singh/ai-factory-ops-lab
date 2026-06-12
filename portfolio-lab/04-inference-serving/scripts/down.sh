#!/usr/bin/env bash
# down.sh — stop the local CPU model server.
set -euo pipefail
NAME="ai-factory-ollama"
docker rm -f "$NAME" >/dev/null 2>&1 && echo "Stopped ${NAME}." || echo "No ${NAME} container running."
