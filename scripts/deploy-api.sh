#!/usr/bin/env bash
# 在【你自己的】Cloudflare 账户里创建账号/云同步后端：D1 库 + Worker。
# 不改动上游任何文件；配置来自 api/wrangler.fork.toml（fork 新增文件）。
#
#   export CLOUDFLARE_API_TOKEN=...    # 权限: Account / D1:Edit + Workers Scripts:Edit + Account Settings:Read
#   export CLOUDFLARE_ACCOUNT_ID=...
#   bash scripts/deploy-api.sh
#
# 完成后还必须手动设置发信密钥（交互式，脚本不能替你输入）：
#   cd api && npx --yes wrangler@4.86.0 secret put RESEND_API_KEY --config wrangler.fork.toml
# 或阿里云：ALIYUN_AK_ID / ALIYUN_AK_SECRET（至少一组，否则验证码邮件发不出去）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_DIR="$ROOT/api"
CONFIG="$API_DIR/wrangler.fork.toml"
export npm_config_registry="${npm_config_registry:-https://registry.npmmirror.com}"

: "${CLOUDFLARE_API_TOKEN:?请先 export CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?请先 export CLOUDFLARE_ACCOUNT_ID}"
[[ -f "$CONFIG" ]] || { echo "找不到 $CONFIG" >&2; exit 1; }

W=(npx --yes wrangler@4.86.0)
DB_NAME="$(grep -E '^database_name[[:space:]]*=' "$CONFIG" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
DB_ID="$(grep -E '^database_id[[:space:]]*=' "$CONFIG" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
[[ -n "$DB_NAME" && -n "$DB_ID" ]] || { echo "无法从配置读取 D1 名称/id" >&2; exit 1; }

if [[ "$DB_ID" == REPLACE_WITH_D1_DATABASE_ID ]]; then
  echo "=== 创建 D1 数据库: $DB_NAME ==="
  OUT="$(cd "$API_DIR" && "${W[@]}" d1 create "$DB_NAME" 2>&1)"
  printf '%s\n' "$OUT"
  DB_ID="$(printf '%s\n' "$OUT" | grep -Eo 'database_id[[:space:]]*=[[:space:]]*"[0-9a-fA-F-]{36}"' | head -1 | grep -Eo '[0-9a-fA-F-]{36}' || true)"
  [[ -n "$DB_ID" ]] || { echo "没能从输出里解析 database_id，请手动把 id 填进 $CONFIG 后重跑。" >&2; exit 1; }
  DB_ID="$DB_ID" CONFIG="$CONFIG" node -e '
    const fs=require("node:fs");
    const p=process.env.CONFIG, id=process.env.DB_ID;
    let t=fs.readFileSync(p,"utf8");
    t=t.replace(/database_id\s*=\s*"[^"]*"/, `database_id = "${id}"`);
    fs.writeFileSync(p,t);
  '
  echo "已把 database_id 写入 $CONFIG"
fi

echo "=== 初始化 D1 表结构（可重复跑，CREATE TABLE IF NOT EXISTS）==="
(cd "$API_DIR" && "${W[@]}" d1 execute "$DB_NAME" --remote --file=schema.sql)

echo "=== 部署 Worker ==="
(cd "$API_DIR" && "${W[@]}" deploy --config wrangler.fork.toml)

echo ""
echo "=== 下一步（必做）==="
echo "1) 设置发信密钥，二选一："
echo "   cd api && npx --yes wrangler@4.86.0 secret put RESEND_API_KEY --config wrangler.fork.toml"
echo "   或：ALIYUN_AK_ID / ALIYUN_AK_SECRET（阿里云邮件推送）"
echo "2) 在 Cloudflare Pages 项目 gracenas-cn-math-taxonomy 里加环境变量："
echo "   API_BASE = <上面部署输出的 https://gracenas-math-api.<你的子域>.workers.dev>"
echo "3) 重新部署 Pages（Git 集成下 push 一次即可）"
