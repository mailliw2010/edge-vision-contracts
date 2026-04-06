#!/usr/bin/env bash
set -euo pipefail

printf '%-18s' "protoc"
if command -v protoc >/dev/null 2>&1; then
  protoc --version 2>/dev/null | head -n 1 || echo FOUND
else
  echo MISSING
fi

for cmd in protoc-gen-go protoc-gen-go-grpc grpc_cpp_plugin; do
  printf '%-18s' "$cmd"
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" --version 2>/dev/null | head -n 1 || echo FOUND
  else
    echo OPTIONAL
  fi
done
