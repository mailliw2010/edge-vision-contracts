#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DESCRIPTOR_OUT=${DESCRIPTOR_OUT:-$ROOT/gen/descriptors/edge-vision-contracts.pb}

if [[ ${1:-} == "--help" ]]; then
  cat <<USAGE
Usage: ./scripts/generate.sh

Validates all proto files under proto/ and writes a descriptor set.

Environment variables:
  DESCRIPTOR_OUT   Override descriptor output path
USAGE
  exit 0
fi

if ! command -v protoc >/dev/null 2>&1; then
  echo "protoc is required" >&2
  exit 1
fi

mapfile -t PROTOS < <(cd "$ROOT" && find proto -name '*.proto' | sort)

if [ ${#PROTOS[@]} -eq 0 ]; then
  echo "no proto files found" >&2
  exit 1
fi

mkdir -p "$(dirname "$DESCRIPTOR_OUT")"

echo "validating ${#PROTOS[@]} proto files"

protoc \
  --proto_path="$ROOT/proto" \
  --descriptor_set_out="$DESCRIPTOR_OUT" \
  --include_imports \
  "${PROTOS[@]/#/$ROOT/}"

echo "descriptor set written to $DESCRIPTOR_OUT"
