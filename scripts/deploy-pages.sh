#!/usr/bin/env bash
# 把 dist/ 上传到自己账户下的 Cloudflare Pages 项目（不依赖上游的项目名/账号）。
#
#   export CLOUDFLARE_API_TOKEN=...
#   export CLOUDFLARE_ACCOUNT_ID=...
#   PAGES_PROJECT=my-math-taxonomy bash scripts/deploy-pages.sh [dist目录]
#
# 常量：
#   PAGES_PROJECT  项目名，决定 https://<项目名>.pages.dev（默认 cn-math-taxonomy）
#   PAGES_BRANCH   生产分支，默认 main
#   WRANGLER_VER   wrangler 版本，默认 4.86.0（与上游 deploy-cf.sh 一致）
#   npm_config_registry 默认走国内镜像，绕开 npmjs 不可达的环境
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
PROJECT="${PAGES_PROJECT:-cn-math-taxonomy}"
BRANCH="${PAGES_BRANCH:-main}"
WVER="${WRANGLER_VER:-4.86.0}"
export npm_config_registry="${npm_config_registry:-https://registry.npmmirror.com}"

[[ -d "$OUT" ]] || { echo "找不到产物目录: $OUT" >&2; exit 1; }
: "${CLOUDFLARE_API_TOKEN:?请先 export CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?请先 export CLOUDFLARE_ACCOUNT_ID}"

W=(npx --yes "wrangler@${WVER}")

echo "项目: ${PROJECT}  分支: ${BRANCH}  产物: ${OUT}"
# 首次部署需要先建项目；已存在时忽略报错继续上传。
"${W[@]}" pages project create "$PROJECT" --production-branch "$BRANCH" 2>&1 | tail -5 || true
echo "--- 开始上传 ---"
"${W[@]}" pages deploy "$OUT" \
  --project-name "$PROJECT" \
  --branch "$BRANCH" \
  --commit-dirty=true
echo "--- 完成 ---"
echo "访问: https://${PROJECT}.pages.dev/"
