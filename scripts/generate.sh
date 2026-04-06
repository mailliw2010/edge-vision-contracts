#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/gen/descriptors"
mkdir -p "$OUT"

if ! command -v protoc >/dev/null 2>&1; then
  echo "protoc is required" >&2
  exit 1
fi

mapfile -t PROTOS < <(cd "$ROOT" && find proto -name '*.proto' | sort)

if [ ${#PROTOS[@]} -eq 0 ]; then
  echo "no proto files found" >&2
  exit 1
fi

protoc \
  --proto_path="$ROOT/proto" \
  --descriptor_set_out="$OUT/edge-vision-contracts.pb" \
  --include_imports \
  "${PROTOS[@]/#/$ROOT/}"

echo "descriptor set written to $OUT/edge-vision-contracts.pb"
