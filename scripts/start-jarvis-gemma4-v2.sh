#!/bin/zsh
set -euo pipefail
exec </dev/null

JARVIS_ROOT="${JARVIS_ROOT:-/Users/jimmypark/Applications/Jarvis}"
MODEL="${AURA_GEMMA_MODEL_PATH:-$JARVIS_ROOT/models/gemma4-v2-Q4_K_M.gguf}"
RUNTIME_DIR="${AURA_LLAMA_RUNTIME_DIR:-$JARVIS_ROOT/runtime/llama.cpp/llama-b9553}"
SERVER="$RUNTIME_DIR/llama-server"
HOST="${AURA_LLAMA_HOST:-127.0.0.1}"
PORT="${AURA_LLAMA_PORT:-8080}"
ALIAS="${AURA_LLAMA_MODEL_ALIAS:-gemma4-v2}"

if [[ ! -x "$SERVER" ]]; then
  echo "Missing executable llama-server: $SERVER" >&2
  exit 1
fi

if [[ ! -f "$MODEL" ]]; then
  echo "Missing Gemma GGUF model: $MODEL" >&2
  exit 1
fi

echo "Aura local model server" >&2
echo "  runtime: $SERVER" >&2
echo "  model:   $MODEL" >&2
echo "  alias:   $ALIAS" >&2
echo "  url:     http://$HOST:$PORT/v1" >&2

exec "$SERVER" \
  --model "$MODEL" \
  --alias "$ALIAS" \
  --host "$HOST" \
  --port "$PORT" \
  --ctx-size "${AURA_LLAMA_CTX_SIZE:-8192}" \
  --ubatch-size "${AURA_LLAMA_UBATCH_SIZE:-1024}" \
  --threads "${AURA_LLAMA_THREADS:-6}" \
  --n-gpu-layers "${AURA_LLAMA_GPU_LAYERS:-99}" \
  --parallel "${AURA_LLAMA_PARALLEL:-1}" \
  --flash-attn on \
  --reasoning "${AURA_LLAMA_REASONING:-off}" \
  --repeat-penalty "${AURA_LLAMA_REPEAT_PENALTY:-1.1}" \
  --cache-ram "${AURA_LLAMA_CACHE_RAM_MB:-512}" \
  --cache-reuse "${AURA_LLAMA_CACHE_REUSE:-256}" \
  --ctx-checkpoints "${AURA_LLAMA_CONTEXT_CHECKPOINTS:-4}" \
  --jinja \
  --embeddings \
  --pooling cls \
  --cache-prompt \
  --no-mmproj
