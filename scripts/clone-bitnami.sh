#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
SRC_NS="bitnamilegacy" # !: In
TARGET_NS="sxfloudsrl" # !: Out
IMAGES=(
  "redis:8.2.1-debian-12-r0"
  "redis-sentinel:8.2.1-debian-12-r0"
  "redis-exporter:1.76.0-debian-12-r0"
  "os-shell:12-debian-12-r51"
  "kubectl:1.33.4-debian-12-r0"
)
ARCHES=("amd64" "arm64")
# ====================

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1"; exit 1; }; }
need_cmd docker

echo "Logging into Docker (if required)..."
# docker login   # ?: Login

for image in "${IMAGES[@]}"; do
  name="${image%%:*}"
  tag="${image#*:}"

  echo
  echo "=== Processing ${name}:${tag} ==="

  # 1) Pull both architectures from source namespace
  for arch in "${ARCHES[@]}"; do
    echo "--- Pulling ${SRC_NS}/${name}:${tag} for linux/${arch}"
    docker pull --platform "linux/${arch}" "${SRC_NS}/${name}:${tag}"

    # 2) Re-tag into target namespace with arch suffix
    target_tag="${TARGET_NS}/${name}:${tag}-${arch}"
    echo "--- Tagging -> ${target_tag}"
    docker tag "${SRC_NS}/${name}:${tag}" "${target_tag}"

    # 3) Push arch-specific tag
    echo "--- Pushing ${target_tag}"
    docker push "${target_tag}"
  done

  # 4) Create multi-arch manifest pointing to the two arch-specific tags
  multi="${TARGET_NS}/${name}:${tag}"
  echo "--- Creating manifest ${multi}"
  docker manifest create "${multi}" \
    --amend "${TARGET_NS}/${name}:${tag}-amd64" \
    --amend "${TARGET_NS}/${name}:${tag}-arm64"

  # 5) Annotate (explicitly set OS/arch) and push the manifest
  docker manifest annotate "${multi}" "${TARGET_NS}/${name}:${tag}-amd64" --os linux --arch amd64
  docker manifest annotate "${multi}" "${TARGET_NS}/${name}:${tag}-arm64" --os linux --arch arm64

  echo "--- Pushing manifest ${multi}"
  docker manifest push "${multi}"

  echo "=== Done ${multi} ==="
done

echo
echo "All images published as multi-arch to namespace: ${TARGET_NS}"
