#!/usr/bin/env bash
# serve-cpu.sh - start a tiny OpenAI-compatible model server on CPU, purely to
# validate that the load harness works end to end. $0, no GPU.
#
# HONESTY MARKER: numbers from this server are NOT a benchmark - CPU inference of
# a tiny model tells you nothing about GPU serving. This tier exists so you can
# build and debug the harness for free, then point it at a real GPU server
# (Lesson 2) where the numbers actually mean something.
#
# Uses Ollama in Docker (exposes an OpenAI-compatible /v1 endpoint). If you prefer
# llama.cpp's server or vLLM-CPU, any OpenAI-compatible /v1/chat/completions works.
set -euo pipefail

MODEL="${OLLAMA_MODEL:-qwen2:0.5b}"      # ~0.5B params, smallest useful chat model
PORT="${PORT:-8000}"
NAME="ai-factory-ollama"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found. This $0 tier uses Ollama-in-Docker."
  exit 1
fi

echo "==> Starting Ollama (CPU) on :${PORT} ..."
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "${PORT}:11434" ollama/ollama >/dev/null

echo "==> Waiting for Ollama to answer..."
for _ in $(seq 1 30); do
  if curl -s "http://localhost:${PORT}/api/tags" >/dev/null 2>&1; then break; fi
  sleep 2
done

echo "==> Pulling a tiny model (${MODEL}) - first run downloads it..."
docker exec "$NAME" ollama pull "$MODEL"

cat <<EOF

Ollama is serving an OpenAI-compatible API at:
  http://localhost:${PORT}/v1/chat/completions   (model name: ${MODEL})

Run the harness against it:
  MODEL=${MODEL} ENDPOINT=http://localhost:${PORT} make phase5-bench

Stop it when done:
  make phase5-down

Remember: these are HARNESS-VALIDATION numbers, not a GPU benchmark.
EOF
