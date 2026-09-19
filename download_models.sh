#!/usr/bin/env bash
# Download LTX-2.3 model files into the persistent ComfyUI models dir.
# ALL ungated - no HuggingFace token required.
set -Eeuo pipefail

: "${COMFYUI_DIR:=/workspace/ComfyUI}"
MODELS="${COMFYUI_DIR}/models"
mkdir -p "$MODELS/unet" "$MODELS/text_encoders" "$MODELS/vae"

dl() {  # dl <url> <dest>
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then echo "   have $(basename "$dest")"; return 0; fi
  echo ">> downloading $(basename "$dest")..."
  aria2c -x8 -s8 -k1M --file-allocation=none -o "$(basename "$dest")" -d "$(dirname "$dest")" "$url"
}

# --- transformer (LTX-2.3 distilled, fp8) ---
dl "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled_transformer_only_fp8_scaled.safetensors?download=true" \
   "$MODELS/unet/ltx-2.3-22b-distilled_transformer_only_fp8_scaled.safetensors"

# --- text encoder (Gemma3 12B, fp8, ungated) + projection ---
dl "https://huggingface.co/DreamFast/gemma-3-12b-it-heretic-v2/resolve/main/comfyui/gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors" \
   "$MODELS/text_encoders/gemma-3-12b-it-heretic-v2_fp8_e4m3fn.safetensors"
dl "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors?download=true" \
   "$MODELS/text_encoders/ltx-2.3_text_projection_bf16.safetensors"

# --- video VAE ---
dl "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors?download=true" \
   "$MODELS/vae/LTX23_video_vae_bf16.safetensors"

echo ">> models ready:"
ls -lh "$MODELS/unet" "$MODELS/text_encoders" "$MODELS/vae"
