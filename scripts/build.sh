#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Generate signing keys if they don't exist
if [ ! -f melange.rsa ]; then
  echo "=== Generating melange signing keys ==="
  melange keygen
fi

echo "=== Building melange package ==="
melange build melange.yaml --signing-key melange.rsa --arch x86_64 --out-dir packages

echo ""
echo "=== Building wolfi-base WITH DoD certs ==="
apko build wolfi-base.yaml wolfi-base:latest wolfi-base.tar --arch x86_64
docker load < wolfi-base.tar

echo ""
echo "=== Building wolfi-base WITHOUT DoD certs (baseline) ==="
apko build wolfi-base-nodod.yaml wolfi-base-nodod:latest wolfi-base-nodod.tar --arch x86_64
docker load < wolfi-base-nodod.tar

echo ""
echo "All images built and loaded."
