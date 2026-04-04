#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/gen"
mkdir -p "$OUT"

echo 'This is the v1 skeleton generator placeholder.'
echo 'Next step: wire protoc-gen-go / protoc-gen-go-grpc / grpc_cpp_plugin outputs here.'
