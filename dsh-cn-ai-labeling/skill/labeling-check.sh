#!/usr/bin/env bash
#
# labeling-check.sh —— AI 生成内容标识的机械取证
#
# 依据：
#   《人工智能生成合成内容标识办法》(国信办通字〔2025〕2号)
#   《互联网信息服务深度合成管理规定》(第12号令) 第十六条、第十七条
#   GB 45438—2025《网络安全技术 人工智能生成合成内容标识方法》第5、6章 + 附录E
#
# 只做取证，不做合规定性：报告"找到了什么、缺什么"，是否违规由人判断。
#
# 用法：
#   bash labeling-check.sh --code [--dir 路径]
#   bash labeling-check.sh --meta <文件路径>
#   bash labeling-check.sh --all  [--dir 路径]
#
# 退出码：0 = 未发现问题；1 = 有发现；2 = 用法错误
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_JS="$SCRIPT_DIR/labeling-meta.mjs"

DIR="."
DO_CODE=0
DO_META=0
META_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --code) DO_CODE=1 ;;
    --meta) DO_META=1; META_FILE="${2:-}"; shift ;;
    --all)  DO_CODE=1; DO_META=1 ;;
    --dir)  DIR="${2:-.}"; shift ;;
    -h|--help)
      sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$DO_CODE" -eq 0 ] && [ "$DO_META" -eq 0 ]; then
  echo "用法：bash labeling-check.sh --code [--dir 路径] | --meta <文件> | --all" >&2
  exit 2
fi
if [ ! -d "$DIR" ]; then echo "目录不存在：$DIR" >&2; exit 2; fi

FOUND_ISSUE=0
hr() { printf '%s\n' "────────────────────────────────────────────────────────────"; }

# ── 定位 node ──────────────────────────────────────────────────────
# 元数据校验需要真正的 JSON 解析，用 node 实现。但 node 未必在 PATH 上
# （受限 PATH、nvm、自带 runtime 等），所以按候选清单探测。
# 关键：探测不到时绝不能静默通过 —— 那会把「没校验」伪装成「没问题」。
find_node() {
  if command -v node >/dev/null 2>&1; then command -v node; return 0; fi
  local c
  for c in /usr/local/bin/node /opt/homebrew/bin/node /usr/bin/node /snap/bin/node; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  for c in "$HOME"/.nvm/versions/node/*/bin/node \
           "$HOME"/.volta/bin/node \
           "$HOME"/.local/bin/node \
           "$HOME"/n/bin/node; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
NODE_BIN="$(find_node || true)"

# ── 通用检索：排除噪音目录与二进制 ──────────────────────────────────
scan() { # scan <扩展名过滤:空=全部> <正则>
  local pattern="$1"
  find "$DIR" \
    \( -name node_modules -o -name .git -o -name dist -o -name build -o -name out \
       -o -name .next -o -name coverage -o -name vendor -o -name target \
       -o -name .venv -o -name venv -o -name __pycache__ -o -name .cache \
       -o -name obs-upload -o -name .turbo \
       -o -name site-packages -o -name dependencies -o -name oh_modules \
       -o -name Pods -o -name .gradle -o -name .idea -o -name .dart_tool \
       -o -name .pnpm-store -o -name .yarn \) -prune -o \
    -type f -size -2M -print0 2>/dev/null \
  | xargs -0 grep -I -n -E "$pattern" 2>/dev/null
}

if [ "$DO_CODE" -eq 1 ]; then
  echo
  echo "AI 生成内容标识 · 代码取证"
  echo "目录：$(cd "$DIR" && pwd)"
  hr

  # ── 1. 隐式标识实现取证（GB 45438 6.1 / 附录E） ──────────────────
  echo
  echo "【1】隐式标识实现取证 —— 依据 GB 45438 6.1、附录E"
  echo

  MISSING=""
  for f in AIGC ContentProducer ProduceID ContentPropagator PropagateID ReservedCode1 ReservedCode2; do
    hit="$(scan "\"$f\"|'$f'|\\b$f\\b" | head -5)"
    if [ -n "$hit" ]; then
      echo "  ✅ $f"
      echo "$hit" | sed 's/^/       /' | head -3
    else
      echo "  ❌ $f  —— 未找到"
      MISSING="$MISSING $f"
    fi
  done
  if [ -n "$MISSING" ]; then
    echo
    echo "  ℹ️  未找到的字段：$MISSING"
    echo "     这不等于违规 —— 先确认你是否为义务主体（见 skill 第一节）。"
  fi

  # ── 2. 显式标识文案取证（GB 45438 5.1~5.6） ────────────────────
  echo
  hr
  echo
  echo "【2】显式标识候选文案 —— 依据 GB 45438 5.1~5.6（结果需人工筛选）"
  echo "  要求同时含「人工智能」或「AI」+「生成」和/或「合成」"
  echo
  # 排除两类已知误报：
  #   · 文档/配置类文件里对规则的描述（不是产品里的实际文案）
  #   · 报错与状态文案（「AI 生成失败，请重试」命中了同样的词，但不是标识）
  UI_HITS="$(scan '(人工智能|AI).{0,12}(生成|合成)|(生成|合成).{0,12}(人工智能|AI)' \
             | grep -viE '\.(md|txt|json|lock|log|yml|yaml):' \
             | grep -viE '(生成|合成)[^，。；、）)]{0,4}(失败|出错|错误|异常|中断|超时|完成)|请重试|loading|\.test\.|\.spec\.' \
             | head -12)"
  if [ -n "$UI_HITS" ]; then
    echo "$UI_HITS" | sed 's/^/  · /'
    echo
    echo "  ℹ️  以上是候选，不都是标识文案 —— 需人工确认哪一条是面向用户展示的标识。"
  else
    echo "  ❌ 未在代码中找到含两要素的提示文案"
    echo "     若产品有交互界面，对照 GB 45438 5.6 检查是否持续显示提示文字。"
  fi

  # ── 3. 导出链路取证（标识办法第四条第二款） ─────────────────────
  echo
  hr
  echo
  echo "【3】下载 / 复制 / 导出链路取证 —— 依据《标识办法》第四条第二款"
  echo
  EXPORT_HITS="$(scan 'docx|xlsx|pptx|openxml|ooxml|mammoth|docxtemplater|exceljs|pdf-lib|puppeteer|jspdf|saveAs|downloadFile' | head -10)"
  HAS_EXPORT=0
  if [ -n "$EXPORT_HITS" ]; then
    HAS_EXPORT=1
    echo "  发现导出链路："
    echo "$EXPORT_HITS" | sed 's/^/  · /'
    if [ -n "$MISSING" ] && echo "$MISSING" | grep -q AIGC; then
      echo
      echo "  ⚠️  有导出链路，但未找到 AIGC 元数据写入点。"
      echo "     导出物需含满足要求的标识 —— 这是用户唯一无法自行补齐的环节。"
      FOUND_ISSUE=1
    fi
  else
    echo "  · 未发现明显的导出链路（若确有导出功能，请人工确认探测关键词）"
  fi

  # ── 4. 反向风险取证（标识办法第十条第二款） ─────────────────────
  echo
  hr
  echo
  echo "【4】反向风险：是否存在删除 / 清洗标识的能力 —— 依据《标识办法》第十条第二款"
  echo "  任何组织和个人不得恶意删除、篡改、伪造、隐匿标识"
  echo
  STRIP_HITS="$(scan '(delete|remove|strip|clean|clear|scrub|erase)[A-Za-z_]*[Aa]igc|AIGC[A-Za-z_]*(delete|remove|strip|clean)|deleteMetadata|stripMetadata|removeMetadata' | head -10)"
  if [ -n "$STRIP_HITS" ]; then
    echo "  🔴 发现疑似移除元数据的代码，请人工确认是否涉及标识："
    echo "$STRIP_HITS" | sed 's/^/  · /'
    FOUND_ISSUE=1
  else
    echo "  ✅ 未发现针对 AIGC 标识的删除 / 清洗代码"
  fi

  # ── 5. 用户服务协议取证（标识办法第八条） ───────────────────────
  echo
  hr
  echo
  echo "【5】用户服务协议取证 —— 依据《标识办法》第八条"
  echo "  协议中应明确说明标识的方法、样式等规范内容"
  echo
  AGR_HITS="$(scan '(用户协议|服务协议|用户服务协议|terms).{0,20}(标识|label)|(标识).{0,20}(用户协议|服务协议)' | head -5)"
  if [ -n "$AGR_HITS" ]; then
    echo "$AGR_HITS" | sed 's/^/  · /'
  else
    echo "  ⚠️  未找到协议中关于标识方法 / 样式的说明（若你是义务主体，第八条要求写明）"
  fi
fi

# ── 元数据校验 ─────────────────────────────────────────────────────
if [ "$DO_META" -eq 1 ] && [ -n "$META_FILE" ]; then
  echo
  hr
  echo
  echo "【6】文件元数据隐式标识格式校验 —— 依据 GB 45438 附录E（规范性）"
  if [ -z "$NODE_BIN" ]; then
    # 不能静默通过：未校验 ≠ 通过
    echo "  ❌ 未校验：找不到 node，无法解析文件元数据。"
    echo "     请安装 node，或手动确认文件中的 AIGC 字段是否符合附录 E。"
    FOUND_ISSUE=1
  elif [ ! -f "$META_FILE" ]; then
    echo "  ❌ 未校验：文件不存在 $META_FILE"
    FOUND_ISSUE=1
  else
    "$NODE_BIN" "$META_JS" "$META_FILE" || FOUND_ISSUE=1
  fi
fi

echo
hr
if [ "$FOUND_ISSUE" -eq 0 ]; then
  echo "取证完成：未发现明确问题。"
  echo "注意：『未发现问题』≠ 合规 —— 主体判定、场景判定、视觉与交互类要求仍需人工确认。"
  exit 0
else
  echo "取证完成：有发现，请逐条人工判断。"
  exit 1
fi
