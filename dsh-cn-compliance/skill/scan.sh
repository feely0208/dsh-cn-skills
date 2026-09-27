#!/bin/bash
# ─────────────────────────────────────────────────────────────
# 中国大陆对外内容 · 合规红线扫描
#
# 用法：
#   scan.sh                        # 扫当前目录
#   scan.sh --dir <路径>           # 扫指定目录
#   scan.sh --docs-only            # 只扫 .md（公开仓库用，避免源码术语误报）
#   SITE_HOST=https://a.example scan.sh --online     # 扫线上页面
#   SITE_HOST=https://a.example scan.sh --all        # 本地 + 线上 + 暴露探测
#   scan.sh --all --quiet          # 只输出命中项
#
# 环境变量：
#   SITE_HOST      线上站点根地址（--online/--all 必需）
#   DOCS_DIRS      额外要扫的文档目录，冒号分隔（--all 时使用）
#   EXTRA_PATHS    额外要探测的内部路径，空格分隔，追加到内置清单
#
# 退出码：0 = 无命中；1 = 有命中（可用于 CI / 发布前卡口）
# ─────────────────────────────────────────────────────────────
set -uo pipefail

SITE_HOST="${SITE_HOST:-}"
DOCS_DIRS="${DOCS_DIRS:-}"
EXTRA_PATHS="${EXTRA_PATHS:-}"

MODE="local"; DIR="."; QUIET=0; DOC_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --online) MODE="online"; shift;;
    --dir) MODE="local"; DIR="$2"; shift 2;;
    --all) MODE="all"; shift;;
    --quiet) QUIET=1; shift;;
    --docs-only) DOC_ONLY=1; shift;;
    -h|--help) sed -n '2,18p' "$0"; exit 0;;
    *) echo "未知参数: $1"; exit 2;;
  esac
done

if [ "$MODE" != "local" ] && [ -z "$SITE_HOST" ]; then
  echo "❌ --online / --all 需要设置 SITE_HOST 环境变量，例如："
  echo "   SITE_HOST=https://your-domain.example $0 --all"
  exit 2
fi

# ══ 词表 ══
# 🔴 A 类：网络工具（绝对禁用）
WORDS_A='VPN|vpn|Vpn|虚拟局域网|虚拟专用网络|虚拟专用网|翻墙|科学上网|梯子|机场|加速器|shadowsocks|v2ray|clash|trojan|突破封锁|绕过封锁'
# 🔴 A- 类：擦边（建议一并避免）
# 「穿透/隧道」单独出现多属技术术语（UI 的「点击穿透」、HTTP tunnel），
# 只有与网络语境同现才判为风险 —— 这条语境判断是避免误报的关键。
WORDS_A2='内网穿透|代理工具'
WORDS_A2NET='(内网|网络|端口|代理|路由|NAT|服务器|公网)[^，。；\n]{0,12}(穿透|隧道)|(穿透|隧道)[^，。；\n]{0,12}(内网|网络|端口|代理|路由|NAT|公网)'
WORDS_A2EN='\\b(tunnel|Tunnel)\\b'
# 🔴 B 类：广告法极限用语
WORDS_B='国家级|世界级|国际级|国家认定|官方指定|央视上榜|全网最低|全球第一|百分之百|唯一|独家|顶级|极致|王牌|冠军|万能|绝对|第一品牌|国内第一|行业第一|最好|最强|最快|最优|最佳|最便宜|最先进|最高级|最低价|最专业|最权威|最领先|首个|首家|首创|首款|遥遥领先|领导者'
# 🟠 C 类：绝对化承诺（需人工判断）
WORDS_C='永久免费|终身|零风险|绝不|永远|绝对安全|绝不泄露'
# 100% 只在营销语境命中，避开 CSS 的 0%,100% 与 width:100%
WORDS_PCT='100%[[:space:]]*(自研|安全|有效|保证|满意|纯净|原生|免费|准确|可靠|成功|通过|无|自主)'

HITS_TOTAL=0
CLEAN_MARK="✅"
# 去重表：同一「级别 + 位置 + 命中词」只报一次。
# 必要性：同一段文本可能同时命中多条规则（例如「内网穿透」既命中字面词表，
# 也命中语境规则），不去重会出现完全相同的两行，干扰逐条判断。
SEEN_KEYS=""

report_line() { # $1=级别 $2=位置 $3=命中词 $4=上下文
  local key="$1|$2|$3"
  case "$SEEN_KEYS" in
    *"$key"*) return 0;;
  esac
  SEEN_KEYS="${SEEN_KEYS}${key}
"
  HITS_TOTAL=$((HITS_TOTAL+1))
  printf "  %s %-42s %s\n" "$1" "$2" "$3"
  [ -n "${4:-}" ] && printf "        ↳ %s\n" "$4"
}
# 取命中词周围的上下文（截断）
ctx() {
  printf '%s' "$1" | grep -oiE ".{0,28}$2.{0,28}" 2>/dev/null | head -1 | tr -d '\n' | sed 's/  */ /g'
}

scan_text() { # $1=来源标识  $2=文件  (内容从 stdin 读)
  local label="$1" file="$2"
  local body
  if [ -n "$file" ]; then body=$(cat "$file" 2>/dev/null); else body=$(cat); fi
  [ -z "$body" ] && return 0

  local m c
  hit() {
    m=$(printf '%s' "$body" | grep -oiE "$2" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
    [ -z "$m" ] && return 0
    c=$(ctx "$body" "$(printf '%s' "$m" | cut -d, -f1)")
    report_line "$1" "$label" "$m" "$c"
  }
  hit "🔴A类"       "$WORDS_A"
  hit "🔴A类-擦边"  "$WORDS_A2"
  hit "🔴A类-擦边"  "$WORDS_A2NET"
  hit "🔴A类-擦边"  "$WORDS_A2EN"
  hit "🔴B类广告法" "$WORDS_B"
  hit "🔴B类广告法" "$WORDS_PCT"
  hit "🟠C类待判断" "$WORDS_C"
  return 0
}

scan_local() { # $1=目录或文件
  local target="$1"
  [ ! -e "$target" ] && return 0
  [ "$QUIET" = "0" ] && echo "── 本地扫描：$target"
  if [ -f "$target" ]; then
    scan_text "$(basename "$target")" "$target"
  else
    while IFS= read -r f; do
      if [ "$DOC_ONLY" = "1" ]; then
        # 只扫对外文档：源码里的技术术语（如 CSS 的 click-through「穿透点击」）会造成大量误报
        case "$f" in *.md|*.markdown) ;; *) continue;; esac
      else
        case "$f" in *.html|*.js|*.md|*.json|*.txt|*.yml|*.yaml) ;; *) continue;; esac
      fi
      # 排除依赖 / 版本库 / 构建产物 / 归档（否则会扫进几百 MB 二进制，极慢且无意义）
      case "$f" in
        */node_modules/*|*/.git/*) continue;;
        */release/*|*/dist/*|*/build/*|*/out/*|*/.venv/*|*/venv/*) continue;;
        */vendor/*|*/third_party/*) continue;;
        *-runtime/*|*/runtime/*) continue;;   # 随包运行时：内含大量第三方 README，纯噪音
        *.asar|*.dmg|*.exe|*.AppImage|*.deb|*.zip|*.apk|*.png|*.jpg|*.jpeg|*.ico) continue;;
        */news.json) continue;;              # 第三方抓取内容，其用词不代表本站表述
      esac
      local rel="${f#"$target"/}"
      scan_text "$rel" "$f"
    done < <(find "$target" -type f 2>/dev/null)
  fi
}

# 内部路径：这些一旦公网可读就是「信息暴露」，也常夹带合规敏感内容。
# 只放通用项；项目特有的目录请用 EXTRA_PATHS 追加。
INTERNAL_PATHS=(
  ".git/config" ".git/HEAD" ".env" ".env.local" ".env.production"
  "package.json" "package-lock.json" "docker-compose.yml" "Dockerfile"
  "backup.zip" "backup.tar.gz" ".DS_Store"
  "tools/" "scripts/" "deploy/" "nginx.conf"
)
# 追加用户自定义路径
if [ -n "$EXTRA_PATHS" ]; then
  # shellcheck disable=SC2206
  INTERNAL_PATHS+=($EXTRA_PATHS)
fi

scan_exposure() {
  [ "$QUIET" = "0" ] && echo "── 内部文件暴露探测：$SITE_HOST"
  local f c
  for f in "${INTERNAL_PATHS[@]}"; do
    c=$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 12 "$SITE_HOST/$f" 2>/dev/null)
    case "$c" in
      200|301|302) report_line "🔴暴露" "/$f" "可公网访问（http=$c）" "应加 nginx 屏蔽规则";;
    esac
  done
}

# 从首页提取同源链接，自动发现要扫的页面（避免硬编码页面清单）
discover_pages() {
  local home
  home=$(curl -s -L --max-time 25 "$SITE_HOST/" 2>/dev/null)
  printf '/\n'
  printf '%s' "$home" \
    | grep -oiE 'href="[^"#?]+"' \
    | sed 's/^href="//; s/"$//' \
    | grep -viE '^(https?:|mailto:|javascript:|tel:|//)' \
    | grep -iE '\.(html?|php|jsp|aspx)$|/$' \
    | sed 's|^\./||; s|^/||' \
    | sort -u
}

scan_online() {
  [ "$QUIET" = "0" ] && echo "── 线上内容扫描：$SITE_HOST"
  local pages p body
  pages=$(discover_pages)
  [ -z "$pages" ] && pages="/"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    body=$(curl -s -L --max-time 25 "$SITE_HOST/$p" 2>/dev/null)
    if [ -z "$body" ]; then
      report_line "⚠️" "/$p" "抓取失败（检查网络或页面是否存在）"
      continue
    fi
    scan_text "/$p" "" <<< "$body"
  done <<< "$pages"
}

echo "════════ 对外内容 · 合规红线扫描 ════════"
echo "  时间: $(date '+%F %T')   模式: $MODE"
[ -n "$SITE_HOST" ] && echo "  站点: $SITE_HOST"
echo

case "$MODE" in
  local)  scan_local "$DIR";;
  online) scan_online; echo; scan_exposure;;
  all)
    scan_local "$DIR"; echo
    # 额外文档目录（冒号分隔）：只扫 .md，不扫源码
    if [ -n "$DOCS_DIRS" ]; then
      DOC_ONLY=1
      IFS=':' read -ra _dirs <<< "$DOCS_DIRS"
      for d in "${_dirs[@]}"; do [ -e "$d" ] && scan_local "$d"; done
      DOC_ONLY=0
      echo
    fi
    scan_online; echo; scan_exposure;;
esac

echo
echo "─────────────────────────────────────────────"
if [ "$HITS_TOTAL" -eq 0 ]; then
  echo "  $CLEAN_MARK 未发现命中项"
  echo
  echo "  ⚠️ 仍需人工审（脚本查不出）："
  echo "     · 政治敏感 / 时政表述（C 类）"
  echo "     · 地图类图片（台湾、藏南、南海诸岛是否完整）"
  echo "     · AI 生成内容是否宣称可替代专业判断"
  echo "     · 资质宣称是否有依据（官方合作、协会指定等）"
  exit 0
else
  echo "  ❌ 共 $HITS_TOTAL 条命中，需逐条判断："
  echo "     🔴A类     = 必须改（网络工具类，绝对红线）"
  echo "     🔴A类-擦边 = 建议改（内网穿透 / 隧道等，需看语境）"
  echo "     🔴B类     = 必须改（广告法极限用语）"
  echo "     🟠C类     = 人工判断（绝对化承诺，看是否有依据）"
  echo "     🔴暴露    = 内部文件公网可读（信息安全 + 可能夹带合规敏感内容）"
  exit 1
fi
