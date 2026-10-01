#!/bin/bash
# ─────────────────────────────────────────────────────────────
# 密钥与敏感信息扫描
#
# 用法：
#   scan.sh                      # 扫当前目录
#   scan.sh --dir <路径>         # 扫指定目录
#   scan.sh --quiet              # 只输出命中项
#   scan.sh --reveal             # ⚠️ 打印完整密钥（默认打码，仅排障时用）
#
# ⚠️ 默认**打码输出**（只留前后各 4 位）。扫描工具把完整密钥打进终端/日志，
#    等于换个地方又泄露一次 —— 所以默认不给看全，必须显式加 --reveal。
#
# 退出码：1 = 有高置信命中（可用作 pre-commit / CI 卡口）；0 = 未命中；2 = 用法错误
# ─────────────────────────────────────────────────────────────
set -uo pipefail

DIR="."; QUIET=0; REVEAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2;;
    --quiet) QUIET=1; shift;;
    --reveal) REVEAL=1; shift;;
    -h|--help) sed -n '2,14p' "$0"; exit 0;;
    *) echo "未知参数: $1"; exit 2;;
  esac
done
[ -d "$DIR" ] || { echo "❌ 目录不存在：$DIR"; exit 2; }

say() { [ "$QUIET" = "1" ] && return 0; echo "$@"; }

# 排除依赖与构建产物，否则 node_modules 里能刷出成百上千条噪声
EX="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=build --exclude-dir=dist --exclude-dir=Pods --exclude-dir=oh_modules --exclude-dir=.hvigor --exclude-dir=vendor --exclude-dir=__pycache__ --exclude-dir=.venv"

HITS=0
SUSPECT=0

# 打码：只留前后各 4 位。短于 12 位的只留前 2 位。
mask() {
  # ⚠️ 必须分两行：`local s="$1" n=${#s}` 会在赋值**之前**就展开 ${#s}，
  #    set -u 下直接报 "s: unbound variable"，结果是所有密钥都打不出码。
  local s="$1"
  local n=${#s}
  if [ "$REVEAL" = "1" ]; then printf '%s' "$s"; return; fi
  if [ "$n" -le 12 ]; then printf '%s****' "$(printf '%s' "$s" | cut -c1-2)"
  else printf '%s****%s' "$(printf '%s' "$s" | cut -c1-4)" "$(printf '%s' "$s" | cut -c$((n-3))-"$n")"
  fi
}

# 占位符/示例值过滤：这些是文档里的假值，报了只会让人不再看报告
is_placeholder() {
  printf '%s' "$1" | grep -qiE 'example|your[-_]?|xxx|placeholder|changeme|change[-_]?me|dummy|fake|sample|redacted|todo|test[-_]?key|<[^>]*>|\$\{|hidden|masked|xxxx'
}

# 输出一条命中：file:line:secret → 打码后打印
report() {
  local kind="$1" line="$2" label="$3" nomask="${4:-0}"
  local file rest ln secret shown
  file="${line%%:*}"; rest="${line#*:}"; ln="${rest%%:*}"; secret="${rest#*:}"
  if is_placeholder "$secret"; then return 0; fi
  if [ "$nomask" = "1" ]; then
    # 内网 IP / 内部域名不是秘密，蒙掉反而看不懂 —— 去掉脏前缀后原样显示
    shown=$(printf '%s' "$secret" | sed 's/^[^0-9A-Za-z]*//')
  else
    shown=$(mask "$secret")
  fi
  printf '  %s %s:%s  %s\n' "$kind" "$file" "$ln" "$shown"
  return 0
}

# 扫描一个高置信模式
scan_pattern() {
  local label="$1" regex="$2" kind="$3" flags="${4:-}" nomask="${5:-0}"
  local out
  # shellcheck disable=SC2086
  out=$(grep -rnEo $flags "$regex" "$DIR" $EX 2>/dev/null | head -25)
  [ -z "$out" ] && return 0
  local printed=0
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    local before
    before=$(printf '%s' "$l" | awk -F: '{print $NF}')
    if is_placeholder "$before"; then continue; fi
    [ "$printed" = "0" ] && { say ""; say "  【$label】"; printed=1; }
    report "$kind" "$l" "$label" "$nomask"
  done <<< "$out"
  if [ "$printed" = "1" ]; then
    if [ "$kind" = "🔴" ]; then HITS=$((HITS+1)); else SUSPECT=$((SUSPECT+1)); fi
  fi
}

say "══════════════════════════════════════════════"
say " 密钥与敏感信息扫描"
say " 目标目录：$DIR"
[ "$REVEAL" = "1" ] && say " ⚠️ --reveal 已开启：下面会打印完整密钥（别把输出存进文件或贴到聊天里）"
say "══════════════════════════════════════════════"

# ── 1. 高置信令牌 ───────────────────────────────────────────────────
say ""
say "── 1. 高置信令牌（格式几乎不会误报）──"
scan_pattern '云厂商 Access Key'   'AKIA[0-9A-Z]{16}'                     '🔴'
scan_pattern '阿里云 AccessKey'     'LTAI[A-Za-z0-9]{12,}'                 '🔴'
scan_pattern '腾讯云 SecretId'      'AKID[A-Za-z0-9]{13,}'                 '🔴'
scan_pattern 'GitHub 令牌'          'gh[pousr]_[A-Za-z0-9]{30,}'           '🔴'
scan_pattern 'npm 令牌'            'npm_[A-Za-z0-9]{30,}'                 '🔴'
scan_pattern 'Slack 令牌'          'xox[baprs]-[A-Za-z0-9-]{10,}'         '🔴'
scan_pattern 'Google API Key'      'AIza[0-9A-Za-z_-]{35}'                '🔴'
scan_pattern 'sk- 风格密钥'         'sk-[A-Za-z0-9]{20,}'                   '🟠'

# ── 2. 私钥 ─────────────────────────────────────────────────────────
say ""
say "── 2. 私钥与证书文件 ──"
KEYS=$(find "$DIR" \( -name "id_rsa" -o -name "id_dsa" -o -name "id_ecdsa" -o -name "id_ed25519" \
  -o -name "*.pem" -o -name "*.p12" -o -name "*.pfx" -o -name "*.jks" -o -name "*.keystore" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -15)
if [ -n "$KEYS" ]; then
  echo "$KEYS" | sed 's|^|  🔴 私钥/证书文件: |'
  HITS=$((HITS+1))
else
  say "  ✅ 没找到私钥/证书文件"
fi
# 内容里的 PEM 头（可能嵌在代码或配置里）
scan_pattern 'PEM 私钥内容' '-----BEGIN [A-Z ]*PRIVATE KEY-----' '🔴'

# ── 3. 凭据文件是否进了 git ─────────────────────────────────────────
say ""
say "── 3. 凭据文件有没有被 git 跟踪（进了历史就很难彻底删掉）──"
if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  TRACKED=$(git -C "$DIR" ls-files 2>/dev/null | grep -iE '(^|/)(\.env($|\.)|\.env\.[a-z]+|.*\.(pem|p12|key|jks)$|credentials?(\.json)?$|\.npmrc$|id_rsa)' | head -20)
  if [ -n "$TRACKED" ]; then
    echo "$TRACKED" | sed 's/^/  🔴 已被跟踪: /'
    say "     → 用 git rm --cached 移出跟踪，并确认 .gitignore 已覆盖；**已经推到远端的还要轮换密钥**"
    HITS=$((HITS+1))
  else
    say "  ✅ 没有凭据文件被 git 跟踪"
  fi
  # .gitignore 是否覆盖了 .env
  if [ -f "$DIR/.gitignore" ]; then
    grep -qE '^\.env|^\.env$|\*\.pem|^\.npmrc' "$DIR/.gitignore" 2>/dev/null \
      && say "  ✅ .gitignore 覆盖了 .env / *.pem / .npmrc 中的至少一项" \
      || say "  ⚠️  .gitignore 里没看到 .env / *.pem / .npmrc —— 确认是否需要加"
  else
    say "  ⚠️  没有 .gitignore"
  fi
else
  say "  （不是 git 仓库，跳过）"
fi

# ── 4. 配置里的敏感赋值 ─────────────────────────────────────────────
say ""
say "── 4. 配置里的敏感赋值（误报较多，逐条看）──"
# 引号可有可无（.env 里通常没有），但值要够长（>=12）以压住噪声
# 引号可有可无（.env 里通常没有），且**关键字大小写都要认**（.env 里是 DB_PASSWORD 这种大写）；值 >=12 位以压噪声
scan_pattern '疑似硬编码凭据' '(password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_./+=-]{12,}' '🟠' '-i'

# ── 5. 内部信息 ─────────────────────────────────────────────────────
say ""
say "── 5. 内部信息（内部域名 / 内网 IP）──"
scan_pattern '内网 IP' '((^|[^0-9])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})|(192\.168\.[0-9]{1,3}\.[0-9]{1,3})|(172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}))' '🟠' '' '1'
scan_pattern '内部域名' '[A-Za-z0-9._-]+\.(internal|corp|intranet|lan|local)\b' '🟠' '' '1'

# ── 收尾 ────────────────────────────────────────────────────────────
say ""
say "──────────────────────────────────────────────"
if [ "$HITS" -eq 0 ] && [ "$SUSPECT" -eq 0 ]; then
  say " ✅ 未发现命中项"
  say "    （注意：扫描只覆盖已知模式，"没扫到"不等于"没有"。）"
  exit 0
fi
say " 结果：🔴 高置信 $HITS 项 / 🟠 需人工判断 $SUSPECT 项"
say ""
say " 处置顺序建议："
say "   1. 🔴 先处理：**凡是真的密钥，第一件事是去服务商后台轮换（作废旧的）**，"
say "      再清理代码 —— 只删代码不轮换，等于没处理（git 历史/日志/备份里还在）。"
say "   2. 用 git rm --cached 把凭据移出跟踪，补 .gitignore。"
say "   3. 已经推到远端的：改写历史（git filter-repo）或**当作已泄露**直接轮换。"
say "   4. 🟠 逐条确认：示例值、占位符可以直接忽略（扫描已过滤大部分）。"
say "──────────────────────────────────────────────"
[ "$HITS" -gt 0 ] && exit 1
exit 0
