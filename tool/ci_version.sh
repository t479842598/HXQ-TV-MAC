#!/usr/bin/env bash
# CI 版本号：把 pubspec.yaml 的 version 换成 vX.Y.Z+<commit count>，
# 并生成 ci_build.json 供 --dart-define-from-file 使用。
set -euo pipefail

PLATFORM="${1:-}"

BASE_NAME="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml | head -1)"
if [ -z "$BASE_NAME" ]; then
  echo "pubspec.yaml 里找不到 version" >&2
  exit 1
fi

if [ "$#" -gt 0 ] && git rev-parse --git-dir >/dev/null 2>&1; then
  BUILD_CODE="$(git rev-list --count HEAD)"
  COMMIT_HASH="$(git rev-parse HEAD)"
else
  BUILD_CODE="$(date +%s)"
  COMMIT_HASH="local"
fi

VERSION="${BASE_NAME}+${BUILD_CODE}"

# 重写 pubspec 的 version 行
python3 - "$VERSION" <<'PY'
import re, sys
version = sys.argv[1]
with open('pubspec.yaml') as f:
    src = f.read()
src = re.sub(r'^version:.*$', 'version: ' + version, src, count=1, flags=re.M)
with open('pubspec.yaml', 'w') as f:
    f.write(src)
PY

cat > ci_build.json <<EOF
{"pili.name":"$BASE_NAME","pili.code":$BUILD_CODE,"pili.hash":"$COMMIT_HASH","pili.time":$(date +%s)}
EOF

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "VERSION=$BASE_NAME" >> "$GITHUB_ENV"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=$BASE_NAME" >> "$GITHUB_OUTPUT"
fi

echo "VERSION=$BASE_NAME  BUILD=$VERSION  PLATFORM=$PLATFORM"
