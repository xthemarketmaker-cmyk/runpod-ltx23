#!/usr/bin/env bash
# One-time: build the RunPod image and push it to GitHub Container Registry.
set -euo pipefail

GH_USER="xthemarketmaker-cmyk"
IMAGE="ghcr.io/${GH_USER}/runpod-ltx23:v1"

cd "E:/EMPIRE/01-PROJECTS/infrastructure/runpod-video-pipeline/runpod"

echo ">> logging in to ghcr.io..."
gh auth token | docker login ghcr.io -u "$GH_USER" --password-stdin

echo ">> building ${IMAGE} (this takes 20-40 min)..."
docker build --platform linux/amd64 -t "$IMAGE" .

echo ">> pushing ${IMAGE}..."
docker push "$IMAGE"

echo ">> DONE: ${IMAGE}"
docker images "$IMAGE"
