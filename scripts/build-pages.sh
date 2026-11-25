#!/usr/bin/env bash
# 为 fork 部署构建 Cloudflare Pages 静态产物 dist/
#
#   bash scripts/build-pages.sh [--origin https://<your-project>.pages.dev] [--out dist]
#
# 也可通过环境变量 SITE_ORIGIN 指定站点地址。不指定时保留上游仓的原域名。
# 与上游 scripts/deploy-cf.sh 的区别：
#   - 产物落在仓库内固定的 dist/，可供 Cloudflare Pages 的 Git 集成直接用作输出目录；
#   - 把页面里硬编码的 math.pansgo.com 换成自己的域名（含 og:url、分享二维码、sitemap、kp 静态页）；
#   - 关闭上游的第三方访问统计上报与账号云同步后端，避免把数据发到别人的服务；
#   - 设置环境变量 API_BASE=<你自己的 Worker URL> 即可启用账号登录/云同步；
#   - 附带 LICENSE（CC BY-NC 4.0 署名要求）与 _headers 缓存规则。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
ORIGIN="${SITE_ORIGIN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --origin) ORIGIN="$2"; shift 2 ;;
    --origin=*) ORIGIN="${1#*=}"; shift ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$ORIGIN" ]] && ORIGIN="${ORIGIN%/}"
echo "构建产物: $OUT"
[[ -n "$ORIGIN" ]] && echo "站点域名: $ORIGIN" || echo "站点域名: 未指定（保留上游原域名）"

if [[ -e "$OUT" ]]; then
  echo "输出目录已存在: $OUT" >&2
  echo "为避免误删文件，请改用 --out <新目录> 或自行移除该目录后再构建。" >&2
  exit 1
fi
mkdir -p "$OUT/data"

cp "$ROOT/index.html" "$ROOT/sw.js" "$ROOT/manifest.webmanifest" "$OUT/"
[[ -f "$ROOT/.nojekyll" ]] && cp "$ROOT/.nojekyll" "$OUT/"
for d in assets explore diagnose children goods wrongbook finals english; do
  cp -a "$ROOT/$d" "$OUT/"
done
rm -f "$OUT/diagnose/README.md"

cp "$ROOT/data/topics.json" \
   "$ROOT/data/dependencies.json" \
   "$ROOT/data/cn-curriculum-standards.json" \
   "$ROOT/data/id-aliases.json" \
   "$OUT/data/"
cp -a "$ROOT/data/questions" "$OUT/data/"
cp -a "$ROOT/data/english" "$OUT/data/"
cp -a "$ROOT/data/mappings" "$OUT/data/"
# 过渡期兼容副本：旧页面/外部引用仍可能请求 data/questions.json
cp "$ROOT/data/questions.json" "$OUT/data/"

# 知识点静态页 + sitemap + robots（生成失败时脚本直接非零退出）
node "$ROOT/scripts/gen-kp-pages.mjs" --out "$OUT"
[[ -f "$ROOT/robots.txt" ]] && cp "$ROOT/robots.txt" "$OUT/"
[[ -f "$ROOT/sitemap.xml" ]] && cp "$ROOT/sitemap.xml" "$OUT/"

# ---- fork 适配：域名、统计、云同步 ----
ORIGIN="$ORIGIN" OUT="$OUT" API_BASE="${API_BASE:-}" node <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const OUT = process.env.OUT;
const ORIGIN = process.env.ORIGIN;

// 1) 关闭上游第三方统计上报（否则访问数据会发到别人的 Workers）
const stats = path.join(OUT, 'assets/stats-config.js');
let s = fs.readFileSync(stats, 'utf8');
s = s.replace(/endpoint:\s*'[^']*'/, "endpoint: ''");
fs.writeFileSync(stats, s);

// 2) 账号/云同步后端：设置 API_BASE 则接上你自己的 Worker，否则保持关闭
const API_BASE = process.env.API_BASE || '';
const account = path.join(OUT, 'assets/account.js');
let a = fs.readFileSync(account, 'utf8');
a = a.replace(/var DEFAULT_API = '[^']*';/, 'var DEFAULT_API = ' + JSON.stringify(API_BASE) + ';');
fs.writeFileSync(account, a);

if (!ORIGIN) { console.log('跳过域名替换'); process.exit(0); }
const HOST = ORIGIN.replace(/^https?:\/\//, '').replace(/\/+$/, '');
const EXTS = new Set(['.html', '.js', '.mjs', '.xml', '.txt', '.webmanifest', '.json']);
const SKIP_DIRS = new Set(['data', 'assets/vendor']);
let changed = 0;
function walk(dir) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) {
      if (SKIP_DIRS.has(name) && path.relative(OUT, p).split(path.sep).length === 1) continue;
      walk(p);
    } else if (EXTS.has(path.extname(name))) {
      let t = fs.readFileSync(p, 'utf8');
      const before = t;
      t = t.split('https://math.pansgo.com').join(ORIGIN)
           .split('http://math.pansgo.com').join(ORIGIN)
           .split('math.pansgo.com').join(HOST);
      if (t !== before) { fs.writeFileSync(p, t); changed++; }
    }
  }
}
walk(OUT);
console.log(`域名替换完成: ${changed} 个文件 -> ${ORIGIN}`);
NODE

# ---- Cloudflare Pages 配置 ----
cat > "$OUT/_headers" <<'EOF'
# 静态资源长缓存；数据文件短缓存，便于跟上游同步更新
/assets/*
  Cache-Control: public, max-age=31536000, immutable
/sw.js
  Cache-Control: public, max-age=0, must-revalidate
/data/*
  Cache-Control: public, max-age=3600
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
EOF

# CC BY-NC 4.0 要求署名并注明来源
cp "$ROOT/LICENSE" "$OUT/LICENSE.txt"
printf '\n# 数据来源: https://github.com/xiaoyang111222/cn-math-taxonomy (CC BY-NC 4.0)\n' >> "$OUT/robots.txt"

SIZE="$(du -sh "$OUT" | awk '{print $1}')"
COUNT="$(find "$OUT" -type f | wc -l)"
echo "完成: ${SIZE}, 共 ${COUNT} 个文件"
