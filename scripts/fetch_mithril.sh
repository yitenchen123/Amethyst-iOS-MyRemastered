#!/bin/sh
# 下载 Mithril 渲染器预编译产物（libmithril.dylib）并放进启动器的 Frameworks 目录。
#
# Mithril（Uniaball/Mithril-Wrapper）是 OpenGL 3.3 Core -> Vulkan -> MoltenVK -> Metal
# 的转译层。与 MobileGlues / MobileGL 不同，它的 iOS 产物由上游 CI 构建，本仓库不
# 从源码编译，只需要把 dylib 放进 Natives/resources/Frameworks/ 即可被打包
# （payload 的 `cp -R Natives/resources/*` 会带上它）。
#
# 用法：
#   scripts/fetch_mithril.sh                       # 用下面默认的 RUN_ID / ARTIFACT_ID
#   scripts/fetch_mithril.sh <artifact-id>         # 指定 artifact id
#   RUN_ID=<run-id> scripts/fetch_mithril.sh       # 指定 workflow run，自动查 artifact
#   MITHRIL_ZIP_URL=<直链> scripts/fetch_mithril.sh
#
# 认证：GitHub Actions 的 artifact 下载需要 token。
#   export GITHUB_TOKEN=ghp_xxx   （或 GH_TOKEN）
# 公共仓库用任意有 public_repo/actions:read 的 token 即可；未设置时脚本会明确报错退出，
# 不会留下半成品文件。
#
# 为什么不用默认 GITHUB_TOKEN：它只对当前仓库有效，跨仓库下载需要 PAT。
set -eu

REPO_OWNER="${MITHRIL_REPO_OWNER:-21Z121Z1}"
REPO_NAME="${MITHRIL_REPO_NAME:-Mithril-Wrapper}"
# 默认取最近一次成功的 iOS DirectVulkan 构建（可在调用时用环境变量覆盖）
RUN_ID="${RUN_ID:-33342656349}"
ARTIFACT_ID="${ARTIFACT_ID:-9741035381}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DEST_DIR="$SOURCE_DIR/Natives/resources/Frameworks"
DEST="$DEST_DIR/libmithril.dylib"

TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

TMPDIR_MG=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_MG"; }
trap cleanup EXIT

if [ -n "${MITHRIL_ZIP_URL:-}" ]; then
    echo "[fetch_mithril] 使用给定的直链"
    curl -fsSL -H "Authorization: token $TOKEN" -o "$TMPDIR_MG/a.zip" "$MITHRIL_ZIP_URL"
elif [ -n "$ARTIFACT_ID" ]; then
    [ -n "$TOKEN" ] || { echo "[fetch_mithril] 错误：需要 GITHUB_TOKEN（跨仓库下载 artifact）" >&2; exit 1; }
    echo "[fetch_mithril] 下载 artifact $ARTIFACT_ID (repo=$REPO_OWNER/$REPO_NAME)"
    curl -fsSL -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
        -o "$TMPDIR_MG/a.zip" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/artifacts/$ARTIFACT_ID/zip"
else
    [ -n "$TOKEN" ] || { echo "[fetch_mithril] 错误：需要 GITHUB_TOKEN" >&2; exit 1; }
    echo "[fetch_mithril] 查询 run $RUN_ID 的 artifacts"
    curl -fsSL -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
        -o "$TMPDIR_MG/list.json" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runs/$RUN_ID/artifacts"
    ID=$(python3 -c "import json,sys;d=json.load(open('$TMPDIR_MG/list.json'));a=d.get('artifacts') or [];print(a[0]['id'] if a else '')")
    [ -n "$ID" ] || { echo "[fetch_mithril] 错误：run $RUN_ID 没有可用 artifact（可能已过期）" >&2; exit 1; }
    echo "[fetch_mithril] 下载 artifact $ID"
    curl -fsSL -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
        -o "$TMPDIR_MG/a.zip" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/artifacts/$ID/zip"
fi

echo "[fetch_mithril] 解压"
(cd "$TMPDIR_MG" && unzip -qo a.zip)

DYLIB=$(find "$TMPDIR_MG" -name 'libmithril.dylib' -type f | head -1)
[ -n "$DYLIB" ] || { echo "[fetch_mithril] 错误：压缩包里没有 libmithril.dylib" >&2; exit 1; }

mkdir -p "$DEST_DIR"
cp "$DYLIB" "$DEST"
echo "[fetch_mithril] 已安装 -> $DEST ($(wc -c < "$DEST") 字节)"
echo "[fetch_mithril] 架构：$(lipo -archs "$DEST" 2>/dev/null || file -b "$DEST")"
echo "[fetch_mithril] 完成。构建时该 dylib 会随 Natives/resources/* 一起打进 app。"
