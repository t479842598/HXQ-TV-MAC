#!/usr/bin/env bash
# CI 补丁：PiliPlus 依赖对 Flutter SDK / material_ui / cupertino_ui 打的源码补丁。
# 用法：bash tool/ci_patch.sh <android|macos|ios|linux|windows>
set -uo pipefail

PLATFORM="${1:-}"
WS="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="$WS/lib/scripts"

log() { echo "[patch] $*"; }

apply_patch() {
  local dir="$1" file="$2"
  local out
  # 1) 正常应用
  if out=$(cd "$dir" && git apply -p1 "$file" 2>&1); then
    log "OK   $file"
    return 0
  fi
  # 2) 已经打过（CI 缓存了打过补丁的 SDK / 重复执行）→ 视为成功
  if (cd "$dir" && git apply -p1 --reverse --check "$file" >/dev/null 2>&1); then
    log "OK=  $file (已应用，跳过)"
    return 0
  fi
  # 3) 回退 patch 命令
  out=$(cd "$dir" && patch -p1 --forward --silent < "$file" 2>&1)
  local rc=$?
  if [ $rc -eq 0 ]; then
    log "OK*  $file (patch -p1)"
    return 0
  fi
  if echo "$out" | grep -qi 'previously applied\|Reversed (or previously applied)'; then
    log "OK=  $file (已应用，跳过)"
    return 0
  fi
  log "FAIL $file :: $out"
  return 1
}

# ---------- 1. Flutter SDK 补丁 ----------
if [ -z "${FLUTTER_ROOT:-}" ]; then
  FLBIN="$(command -v flutter)"
  # 解析软链（macOS 没有 readlink -f）
  while [ -L "$FLBIN" ]; do
    target="$(readlink "$FLBIN")"
    case "$target" in
      /*) FLBIN="$target" ;;
      *)  FLBIN="$(dirname "$FLBIN")/$target" ;;
    esac
  done
  FLUTTER_ROOT="$(cd "$(dirname "$FLBIN")/.." && pwd)"
fi
log "FLUTTER_ROOT=$FLUTTER_ROOT"

SDK_PATCHES=(
  modal_barrier.patch text_selection.patch mouse_cursor.patch image_anim.patch
  layout_builder.patch navigation_drawer.patch popup_menu.patch fab.patch
  null_safety_for_selectable_region.patch selectable_region.patch editable_text.patch
  text_field.patch scroll_position.patch scrollable.patch scrollable_gesture.patch
  draggable_scrollable_sheet.patch scaffold.patch text.patch text_painter.patch
  sliver.patch refresh_indicator.patch double_tap_gesture.patch
)
case "$PLATFORM" in
  android) SDK_PATCHES+=(bottom_sheet_android.patch scroll_view.patch navigator.patch) ;;
  ios)     SDK_PATCHES+=(scroll_view.patch bottom_sheet_ios_flutter.patch navigator.patch) ;;
esac

sdk_fail=0
for p in "${SDK_PATCHES[@]}"; do
  apply_patch "$FLUTTER_ROOT" "$PATCH_DIR/$p" || sdk_fail=$((sdk_fail+1))
done
log "SDK 补丁失败数: $sdk_fail / ${#SDK_PATCHES[@]}"

# ios 还要改本项目自己的文件
if [ "$PLATFORM" = "ios" ]; then
  apply_patch "$WS" "$PATCH_DIR/bottom_sheet_ios_piliplus.patch" || true
  apply_patch "$WS" "$PATCH_DIR/geetest_ios.patch" || true
fi

# ---------- 2. material_ui 补丁 ----------
PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
MAT_DIR=""
if [ -d "$PUB_CACHE/hosted/pub.dev" ]; then
  MAT_DIR="$(ls -d "$PUB_CACHE"/hosted/pub.dev/material_ui-* 2>/dev/null | tail -1)"
fi
if [ -n "$MAT_DIR" ]; then
  log "material_ui: $MAT_DIR"
  MAT_PATCHES=(modal_barrier_material.patch navigation_drawer.patch popup_menu.patch
               fab.patch text_field.patch scaffold.patch refresh_indicator.patch tabs.patch)
  case "$PLATFORM" in
    android) MAT_PATCHES+=(bottom_sheet_android.patch) ;;
    ios)     MAT_PATCHES+=(bottom_sheet_ios_flutter_material.patch) ;;
  esac
  for p in "${MAT_PATCHES[@]}"; do
    apply_patch "$MAT_DIR" "$PATCH_DIR/material/$p" || true
  done
else
  log "跳过 material_ui（未在 pub cache 找到）"
fi

# ---------- 3. cupertino_ui 补丁（仅 ios） ----------
if [ "$PLATFORM" = "ios" ] && [ -d "$PUB_CACHE/hosted/pub.dev" ]; then
  CUP_DIR="$(ls -d "$PUB_CACHE"/hosted/pub.dev/cupertino_ui-* 2>/dev/null | tail -1)"
  if [ -n "$CUP_DIR" ]; then
    log "cupertino_ui: $CUP_DIR"
    apply_patch "$CUP_DIR" "$PATCH_DIR/cupertino/bottom_sheet_ios_flutter.patch" || true
  fi
fi

if [ "$sdk_fail" -gt 0 ]; then
  log "有 $sdk_fail 个 SDK 补丁未应用 —— 后面的编译大概率失败"
  exit 1
fi
log "全部补丁处理完成"
