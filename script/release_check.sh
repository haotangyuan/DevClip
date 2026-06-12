#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DevClip"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

"$ROOT_DIR/script/build_and_run.sh" --verify

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "缺少 app bundle: $APP_BUNDLE" >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "缺少 Info.plist: $INFO_PLIST" >&2
  exit 1
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "缺少可执行文件: $APP_BINARY" >&2
  exit 1
fi

/usr/bin/plutil -lint "$INFO_PLIST"

if /usr/bin/codesign -dvvv "$APP_BUNDLE" >/tmp/devclip-codesign.txt 2>&1; then
  echo "签名状态：已签名"
  cat /tmp/devclip-codesign.txt
else
  echo "签名状态：未签名或临时开发构建"
fi

if /usr/sbin/spctl -a -vv "$APP_BUNDLE" >/tmp/devclip-spctl.txt 2>&1; then
  echo "Gatekeeper：通过"
  cat /tmp/devclip-spctl.txt
else
  echo "Gatekeeper：未通过，本地未签名构建属于预期状态"
  cat /tmp/devclip-spctl.txt || true
fi

echo "发布检查完成：bundle 结构有效。正式发布仍需要 Developer ID 签名、Hardened Runtime 和 Notarization。"
