#!/usr/bin/env python3
"""Generate video clips on a RunPod pod running ComfyUI + LTX-2.3.

Loads workflow.json (ComfyUI API format), swaps in each treatment prompt and the
target resolution, submits to the local ComfyUI API, polls until done, and saves
the MP4. General-purpose: any project's prompts in prompts.json work.

  python3 generate_clips.py --album the-frozen-crypt
  python3 generate_clips.py --album the-frozen-crypt --only 0,1,2
  python3 generate_clips.py --album the-frozen-crypt --width 3840 --height 2160

Resumable: a scene whose output already exists and is > 100 KB is skipped.
The workflow is a separate JSON file so it can be tuned without rebuilding the image.
"""
from __future__ import annotations

import argparse
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

COMFY = os.environ.get("COMFY_URL", "http://127.0.0.1:8188")
_HERE = Path(__file__).resolve().parent
PROMPTS = Path(os.environ.get("PROMPTS_JSON", _HERE / "prompts.json"))
WORKFLOW = Path(os.environ.get("WORKFLOW_JSON", _HERE / "workflow.json"))
OUTROOT = Path(os.environ.get("OUTROOT", _HERE / "output"))

# node ids in workflow.json that we mutate per scene
PROMPT_NODE = "4"
LATENT_NODE = "6"
SEED_NODE = "10"


def build(prompt: str, width: int, height: int, frames: int, seed: int) -> dict:
    wf = json.loads(WORKFLOW.read_text())
    wf[PROMPT_NODE]["inputs"]["text"] = prompt
    wf[LATENT_NODE]["inputs"].update({"width": width, "height": height, "length": frames})
    wf[SEED_NODE]["inputs"]["noise_seed"] = seed
    return wf


def _post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"{COMFY}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def _get(path: str) -> dict:
    with urllib.request.urlopen(f"{COMFY}{path}", timeout=120) as r:
        return json.load(r)


def queue(wf: dict) -> str:
    return _post("/prompt", {"prompt": wf})["prompt_id"]


def wait(prompt_id: str, timeout: int = 3600) -> dict:
    start = time.time()
    while time.time() - start < timeout:
        try:
            hist = _get(f"/history/{prompt_id}")
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            hist = {}
        if prompt_id in hist:
            status = hist[prompt_id].get("status", {})
            if status.get("status_str") == "error":
                msgs = status.get("messages", [])
                raise RuntimeError(f"ComfyUI error: {msgs[-1] if msgs else status}")
            if status.get("completed") or status.get("status_str") == "success":
                return hist[prompt_id]
        time.sleep(5)
    raise TimeoutError(f"prompt {prompt_id} did not finish in {timeout}s")


def fetch_video(hist: dict, dest: Path) -> Path:
    """Find the produced video in the history and download it to dest."""
    for node in hist.get("outputs", {}).values():
        for key in ("videos", "gifs"):
            for f in node.get(key, []):
                qs = urllib.parse.urlencode({
                    "filename": f["filename"],
                    "subfolder": f.get("subfolder", ""),
                    "type": f.get("type", "output"),
                })
                with urllib.request.urlopen(f"{COMFY}/view?{qs}", timeout=300) as r:
                    dest.write_bytes(r.read())
                return dest
    raise RuntimeError("no video output found in history")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--album", required=True)
    ap.add_argument("--only", default="", help="comma-separated scene indexes")
    ap.add_argument("--width", type=int, default=1920)
    ap.add_argument("--height", type=int, default=1080)
    ap.add_argument("--frames", type=int, default=121, help="~5s at 24fps")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    data = json.loads(PROMPTS.read_text())
    if args.album not in data:
        print(f"no album {args.album!r}; known: {sorted(data)}")
        return 2
    album = data[args.album]
    look = album["look"]
    shots = album["shots"]

    outdir = OUTROOT / args.album
    outdir.mkdir(parents=True, exist_ok=True)

    wanted = [int(x) for x in args.only.split(",") if x.strip()] if args.only else sorted(map(int, shots))
    todo = []
    for i in wanted:
        out = outdir / f"scene{i:02d}.mp4"
        if out.exists() and out.stat().st_size > 100_000:
            print(f"scene {i:02d}: already have {out.name} - skip")
            continue
        todo.append((i, out))

    print(f"\n{len(todo)} clip(s) to generate -> {outdir}  ({args.width}x{args.height}, {args.frames}f)")
    for i, out in todo:
        print(f"  scene {i:02d} -> {out.name}")
    if args.dry_run:
        return 0

    failures = []
    for n, (i, out) in enumerate(todo, 1):
        prompt = f"{shots[str(i)]} {look}"
        print(f"\n=== [{n}/{len(todo)}] scene {i:02d} ===", flush=True)
        try:
            wf = build(prompt, args.width, args.height, args.frames, args.seed + i)
            pid = queue(wf)
            hist = wait(pid)
            fetch_video(hist, out)
            print(f"scene {i:02d}: OK -> {out} ({out.stat().st_size // 1024} KB)", flush=True)
        except Exception as e:
            print(f"scene {i:02d}: FAILED - {e}")
            failures.append(i)

    print(f"\ndone. ok={len(todo) - len(failures)} failed={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
