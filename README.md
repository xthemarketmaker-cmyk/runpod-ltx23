# RunPod → LTX-2.3 video clip pipeline

Generate video clips (1080p or **4K**) on a RunPod GPU from treatment prompts.
Commercial-safe (Apache 2.0 weights, ungated), unwatermarked, **no HuggingFace token needed**.

This is the **general video-generation pipeline** — any project feeds prompts via `prompts.json`.

## Files
- `Dockerfile` — ComfyUI + LTX-2.3 (PyTorch 2.8 / CUDA 12.8 base), proven RunPod structure
- `download_models.sh` — pulls ungated LTX-2.3 + Gemma3 weights (Kijai / DreamFast)
- `workflow.json` — the ComfyUI **API-format** text-to-video graph (edit to tune without rebuilding)
- `generate_clips.py` — loads `workflow.json`, swaps prompt + resolution per scene, drives the ComfyUI API
- `prompts.json` — treatment prompts per project (24 shots each)
- `start.sh` — sync ComfyUI → volume, download models, boot ComfyUI, run the batch, tar output

## Build & push (one time)

```bash
cd E:/EMPIRE/01-PROJECTS/infrastructure/runpod-video-pipeline/runpod
docker build --platform linux/amd64 -t runpod-ltx23:v1 .
docker tag runpod-ltx23:v1 ghcr.io/<your-gh-username>/runpod-ltx23:v1
docker push ghcr.io/<your-gh-username>/runpod-ltx23:v1
```

## RunPod template config

Create a template in the RunPod console (or via API) with:

| Setting | Value |
|---|---|
| Container Image | `ghcr.io/<your-gh-username>/runpod-ltx23:v1` |
| Container Disk | 60 GB |
| Volume Disk | 120 GB (**mount at `/workspace`**) |
| HTTP Ports | `8188` (ComfyUI UI) |
| Env | `ALBUM=the-frozen-crypt`, `WIDTH=1920`, `HEIGHT=1080`, `FRAMES=121` |
| | 4K: `WIDTH=3840`, `HEIGHT=2160` |

Deploy on an **H100 80GB** (4K-capable) or **A100 80GB**. First boot downloads ~35 GB of
models (~20–30 min); a Network Volume caches them so later boots skip it.

The pod syncs ComfyUI to the volume, downloads models, boots ComfyUI on :8188, runs the
batch, and writes **`/workspace/clips-<album>.tar.gz`**. Download it and extract to the
project's `flow-clips/` folder, then run the project's retime + compose.

## Tuning
- **Workflow**: edit `workflow.json` (ComfyUI API format) — node `4` is the prompt,
  node `6` is width/height/length, node `10` is the seed. No image rebuild needed if you
  edit it on the pod.
- **Resolution**: `WIDTH`/`HEIGHT` env, or `--width/--height` flags.
- **Clip length**: `FRAMES` (121 = ~5 s at 24 fps).
- **Resumable**: re-running skips finished clips.
- **Few scenes only**: `ALBUM_ONLY=0,1,2`.

## Cost
- H100 80GB ~$2.89/hr · A100 80GB ~$1.59/hr
- One album (24 clips) ≈ **~$3–6** depending on GPU + resolution
