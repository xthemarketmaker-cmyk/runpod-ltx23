# RunPod image: ComfyUI + LTX-2.3 for video-clip generation.
# Structure follows the proven dasiwa-ltx23 RunPod pattern.
# Target: H100 80GB (4K-capable), A100 80GB, L40S 48GB.
ARG BASE_IMAGE=pytorch/pytorch:2.8.0-cuda12.8-cudnn9-runtime
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_ROOT_USER_ACTION=ignore \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    HF_HUB_ENABLE_HF_TRANSFER=1 \
    COMFYUI_DIR=/opt/ComfyUI \
    COMFYUI_PORT=8188

RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 build-essential ca-certificates curl ffmpeg git git-lfs \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 ninja-build rsync wget \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --upgrade pip setuptools wheel

# --- ComfyUI ---
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI
WORKDIR /opt/ComfyUI
RUN python -m pip install --no-cache-dir -r requirements.txt \
    && python -m pip install --no-cache-dir \
      accelerate av diffusers hf_transfer imageio-ffmpeg librosa \
      opencv-python-headless protobuf sentencepiece soundfile \
      "transformers[timm]==4.56.2"

# --- custom nodes (only what our T2V workflow needs) ---
WORKDIR /opt/ComfyUI/custom_nodes
RUN git clone --depth=1 https://github.com/Comfy-Org/ComfyUI-Manager.git ComfyUI-Manager \
    && git clone --depth=1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ComfyUI-VideoHelperSuite \
    && git clone --depth=1 https://github.com/kijai/ComfyUI-KJNodes.git ComfyUI-KJNodes \
    && git clone --depth=1 https://github.com/Lightricks/ComfyUI-LTXVideo.git ComfyUI-LTXVideo \
    && git clone --depth=1 https://github.com/city96/ComfyUI-GGUF.git ComfyUI-GGUF

WORKDIR /opt/ComfyUI
RUN set -eux; \
    for req in custom_nodes/*/requirements.txt; do \
      if [ -f "$req" ]; then python -m pip install --no-cache-dir -r "$req" || true; fi; \
    done; \
    python -m pip install --no-cache-dir --upgrade "transformers[timm]==4.56.2"

# --- our pipeline ---
COPY generate_clips.py /workspace/generate_clips.py
COPY prompts.json /workspace/prompts.json
COPY workflow.json /workspace/workflow.json
COPY download_models.sh /download_models.sh
COPY start.sh /start-comfy.sh
RUN chmod +x /download_models.sh /start-comfy.sh

EXPOSE 8188
CMD ["/start-comfy.sh"]
