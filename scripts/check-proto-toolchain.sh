#!/usr/bin/env bash
set -euo pipefail
for cmd in protoc grpc_cpp_plugin; do
  printf '%-18s' "$cmd"
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" --version 2>/dev/null | head -n 1 || echo FOUND
  else
    echo MISSING
  fi
done
for cmd in protoc-gen-go protoc-gen-go-grpc; do
  printf '%-18s' "$cmd"
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" --version 2>/dev/null | head -n 1 || echo FOUND
  else
    echo MISSING
  fi
done
