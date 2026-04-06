#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-all}
DESCRIPTOR_OUT=${DESCRIPTOR_OUT:-$ROOT/gen/descriptors/edge-vision-contracts.pb}
GO_MODULE=${GO_MODULE:-edgevision/contracts}

usage() {
  cat <<USAGE
Usage: ./scripts/generate.sh [all|descriptor|go]

Modes:
  all         Generate descriptor set and Go bindings (default)
  descriptor  Generate descriptor set only
  go          Generate Go bindings only

Environment variables:
  DESCRIPTOR_OUT   Override descriptor output path
  GO_MODULE        Go module prefix used by protoc-gen-go (default: edgevision/contracts)
USAGE
}

require_cmd() {
  local cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd is required" >&2
    exit 1
  fi
}

if [[ "$MODE" == "--help" || "$MODE" == "-h" ]]; then
  usage
  exit 0
fi

case "$MODE" in
  all|descriptor|go) ;;
  *)
    usage >&2
    exit 1
    ;;
esac

require_cmd protoc

mapfile -t PROTOS < <(cd "$ROOT" && find proto -name '*.proto' | sort)

if [[ ${#PROTOS[@]} -eq 0 ]]; then
  echo "no proto files found" >&2
  exit 1
fi

run_protoc() {
  protoc \
    --proto_path="$ROOT/proto" \
    "$@" \
    "${PROTOS[@]/#/$ROOT/}"
}

generate_descriptor() {
  mkdir -p "$(dirname "$DESCRIPTOR_OUT")"
  echo "generating descriptor set -> $DESCRIPTOR_OUT"
  run_protoc \
    --descriptor_set_out="$DESCRIPTOR_OUT" \
    --include_imports
}

generate_go() {
  require_cmd protoc-gen-go
  require_cmd protoc-gen-go-grpc

  echo "generating Go bindings under $ROOT/gen (module prefix: $GO_MODULE)"
  run_protoc \
    --go_out="$ROOT" \
    --go_opt=module="$GO_MODULE" \
    --go-grpc_out="$ROOT" \
    --go-grpc_opt=module="$GO_MODULE"
}

echo "processing ${#PROTOS[@]} proto files"

case "$MODE" in
  all)
    generate_descriptor
    generate_go
    ;;
  descriptor)
    generate_descriptor
    ;;
  go)
    generate_go
    ;;
esac

echo "done"
