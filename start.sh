#!/usr/bin/env bash
# RunPod entrypoint: sync ComfyUI to the volume, download models, boot ComfyUI,
# then (optionally) run the batch and package the output.
#
# Env: ALBUM, ALBUM_ONLY, WIDTH, HEIGHT, FRAMES, RUN_BATCH (default true)
set -Eeuo pipefail

: "${COMFYUI_DIR:=/workspace/ComfyUI}"
: "${COMFYUI_PORT:=8188}"
: "${RUN_BATCH:=true}"
: "${ALBUM:=the-frozen-crypt}"
: "${WIDTH:=1920}"
: "${HEIGHT:=1080}"
: "${FRAMES:=121}"

# RunPod base services (SSH/Jupyter) if present
if [ -x /start.sh ]; then /start.sh & fi

echo ">> [1/4] syncing ComfyUI to ${COMFYUI_DIR}..."
mkdir -p "$COMFYUI_DIR"
for p in api_server assets comfy comfy_api comfy_extras custom_nodes web; do
  rm -rf "${COMFYUI_DIR:?}/${p}"
done
rsync -a --delete \
  --exclude=/models/*** --exclude=/input/*** --exclude=/output/*** \
  --exclude=/temp/*** --exclude=/user/*** \
  /opt/ComfyUI/ "${COMFYUI_DIR}/"

echo ">> [2/4] downloading models (skipped if present)..."
/download_models.sh

echo ">> [3/4] booting ComfyUI on :${COMFYUI_PORT}..."
cd "$COMFYUI_DIR"
python main.py --listen 0.0.0.0 --port "$COMFYUI_PORT" --reserve-vram 2 \
  > /workspace/comfyui.log 2>&1 &

for i in $(seq 1 90); do
  if curl -sf "http://127.0.0.1:${COMFYUI_PORT}/system_stats" >/dev/null 2>&1; then
    echo "   ComfyUI ready after $((i*2))s"; break
  fi
  sleep 2
done

if [ "$RUN_BATCH" = "true" ]; then
  echo ">> [4/4] generating clips for '$ALBUM' (${WIDTH}x${HEIGHT}, ${FRAMES}f)..."
  cd /workspace
  ARGS=(--album "$ALBUM" --width "$WIDTH" --height "$HEIGHT" --frames "$FRAMES")
  [ -n "${ALBUM_ONLY:-}" ] && ARGS+=(--only "$ALBUM_ONLY")
  python3 /workspace/generate_clips.py "${ARGS[@]}" || echo "!! batch reported failures"

  echo ">> packaging output..."
  tar -czf "clips-${ALBUM}.tar.gz" -C /workspace/output "$ALBUM" 2>/dev/null || true
  ls -lh "/workspace/clips-${ALBUM}.tar.gz" 2>/dev/null || true
  echo ">> DONE. Output: /workspace/clips-${ALBUM}.tar.gz"
else
  echo ">> RUN_BATCH=false - ComfyUI is up on :${COMFYUI_PORT}. Run the batch manually:"
  echo "   python3 /workspace/generate_clips.py --album ${ALBUM} --width ${WIDTH} --height ${HEIGHT}"
fi

echo ">> pod staying alive for inspection. ComfyUI log: /workspace/comfyui.log"
sleep infinity
