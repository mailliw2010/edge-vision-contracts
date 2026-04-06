#!/usr/bin/env bash
set -euo pipefail

status=0

printf '%-20s' "protoc"
if command -v protoc >/dev/null 2>&1; then
  protoc --version 2>/dev/null | head -n 1 || echo FOUND
else
  echo "MISSING (required)"
  status=1
fi

for cmd in protoc-gen-go protoc-gen-go-grpc grpc_cpp_plugin; do
  printf '%-20s' "$cmd"
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" --version 2>/dev/null | head -n 1 || echo FOUND
  else
    echo "OPTIONAL (missing)"
  fi
done

exit "$status"
