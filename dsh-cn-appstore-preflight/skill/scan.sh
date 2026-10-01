#!/bin/bash
# ─────────────────────────────────────────────────────────────
# 国内应用市场上架预检 · 取证 + 材料清单骨架
#
# 用法：
#   scan.sh                        # 扫当前目录
#   scan.sh --dir <路径>           # 扫指定目录
#   scan.sh --quiet                # 只输出取证结果
#
# 它做两件事：
#   1. 从工程里**取证**：包名/版本、App 备案号是否在 App 内可见、隐私政策入口、
#      权限清单与用途说明、账号注销入口、未成年人保护；
#   2. 按取证结果生成**上架材料清单骨架** —— 可以直接照着往市场后台填。
#
# ⚠️ 各应用市场的具体要求会变，且各家不同。本脚本给的是**通用骨架**，
#    正式提交前请以目标市场的官方最新公告为准。
#
# 退出码：0 = 扫描完成；2 = 用法错误
# ─────────────────────────────────────────────────────────────
set -uo pipefail

DIR="."; QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2;;
    --quiet) QUIET=1; shift;;
    -h|--help) sed -n '2,19p' "$0"; exit 0;;
    *) echo "未知参数: $1"; exit 2;;
  esac
done
[ -d "$DIR" ] || { echo "❌ 目录不存在：$DIR"; exit 2; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
say() { [ "$QUIET" = "1" ] && return 0; echo "$@"; }

# 统一排除依赖与构建产物
GREP_EXCLUDES="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=build --exclude-dir=dist --exclude-dir=Pods --exclude-dir=oh_modules --exclude-dir=.hvigor --exclude-dir=.idea"

say "══════════════════════════════════════════════"
say " 应用市场上架预检 · 取证"
say " 目标目录：$DIR"
say "══════════════════════════════════════════════"

# ── 1. 包名与版本 ───────────────────────────────────────────────────
say ""
say "── 1. 包名 / 版本（材料里要填的第一项）──"
: > "$TMP/ids"
# Android: applicationId / namespace；iOS: CFBundleIdentifier；鸿蒙: bundleName
find "$DIR" -name "build.gradle" -o -name "build.gradle.kts" 2>/dev/null | while read -r f; do
  grep -nE 'applicationId|namespace' "$f" 2>/dev/null | grep -v '^\s*//' | head -3 | sed "s|^|  · $(basename "$f"): |" >> "$TMP/ids"
done
find "$DIR" -name "Info.plist" -not -path "*/node_modules/*" 2>/dev/null | while read -r f; do
  grep -A1 'CFBundleIdentifier' "$f" 2>/dev/null | grep '<string>' | head -1 | sed 's/^[[:space:]]*/  · Info.plist: /' >> "$TMP/ids"
done
find "$DIR" -name "app.json5" -o -name "module.json5" 2>/dev/null | while read -r f; do
  grep -nE 'bundleName|"versionName"' "$f" 2>/dev/null | head -2 | sed "s|^|  · $(basename "$f"): |" >> "$TMP/ids"
done
if [ -s "$TMP/ids" ]; then cat "$TMP/ids"; else say "  ⚠️  没取到包名 —— 材料里这一项需要手工填"; fi

# targetSdkVersion：市场对最低/目标版本有要求
say ""
say "  目标 API 版本（targetSdkVersion，各市场对它有下限要求）"
grep -rnE 'targetSdkVersion|targetSdk' "$DIR" $GREP_EXCLUDES 2>/dev/null | grep -v '//' | head -5 | sed 's/^/  · /' || say "  ⚠️  没找到 targetSdkVersion"

# ── 2. App 备案号 ───────────────────────────────────────────────────
say ""
say "── 2. App 备案号（**未备案不得上架**）──"
# App 备案是工信部要求（2023 年起），备案号通常要在 App 内可查/可展示。
: > "$TMP/beian"
grep -rnE 'ICP备[0-9]+号|ICP证[0-9]+号|公网安备[0-9]+号|网安备[0-9]+号|备案号' "$DIR" $GREP_EXCLUDES 2>/dev/null | head -10 | sed 's/^/  · /' > "$TMP/beian" || true
if [ -s "$TMP/beian" ]; then
  cat "$TMP/beian"
  say "  → 上面是「App 内出现备案号」的证据。确认：① 号码是**本 App 的**（不是网站的 ICP）；② 在「关于/设置」里用户能找到"
else
  say "  ❌ 工程里没找到任何备案号字样。"
  say "     两种可能：① 真的没做 App 备案（**不得上架**）；② 备案号放在服务端下发或市场后台单独提交。"
  say "     注意：**网站 ICP 备案 ≠ App 备案**，是两个不同的备案。"
fi

# ── 3. 隐私政策入口 ─────────────────────────────────────────────────
say ""
say "── 3. 隐私政策入口（必须能从 App 内打开）──"
POLICY_FILES=$(find "$DIR" \( -iname "*privacy*" -o -iname "*隐私*" \) -not -path "*/node_modules/*" 2>/dev/null | head -5)
if [ -n "$POLICY_FILES" ]; then echo "$POLICY_FILES" | sed 's/^/  · 文件: /'; else say "  ⚠️  工程里没有隐私政策文件（也可能是服务端页面）"; fi
grep -rnE 'privacy|隐私政策' "$DIR" $GREP_EXCLUDES --include='*.xml' --include='*.json' --include='*.js' --include='*.ts' --include='*.ets' --include='*.java' --include='*.kt' --include='*.swift' 2>/dev/null | grep -iE 'http|href|url|链接' | head -8 | sed 's/^/  · 引用: /' || true

# ── 4. 权限与用途说明 ───────────────────────────────────────────────
say ""
say "── 4. 权限清单 + 使用场景说明 ──"
: > "$TMP/perms"
find "$DIR" -name "AndroidManifest.xml" -not -path "*/build/*" 2>/dev/null | while read -r f; do
  grep -o 'android:name="[^"]*"' "$f" 2>/dev/null | sed 's/android:name="//; s/"$//' \
    | grep -E 'PERMISSION|ACCESS_|CAMERA|RECORD_AUDIO|READ_|WRITE_|CALL_|GET_ACCOUNTS|BODY_SENSORS|ACTIVITY_RECOGNITION|POST_NOTIFICATIONS' \
    | while read -r p; do echo "$p" >> "$TMP/perms"; done
done
if [ -s "$TMP/perms" ]; then
  sort -u "$TMP/perms" | sed 's/^/  · /'
  say ""
  say "  → 市场通常要求为每个权限填「使用场景说明」。检查工程里有没有写："
  SCENE=$(grep -rnE '使用场景|用途说明|权限说明|用于.*功能' "$DIR" $GREP_EXCLUDES 2>/dev/null | head -5)
  if [ -n "$SCENE" ]; then echo "$SCENE" | sed 's/^/     /'; else say "     ⚠️  没找到「使用场景/用途说明」字样 —— 这类说明可以放在材料里而不是代码里，但必须准备"; fi
else
  say "  （未从 AndroidManifest 提取到权限）"
fi

# ── 5. 账号注销入口 ─────────────────────────────────────────────────
say ""
say "── 5. 账号注销入口（有账号体系就必须有）──"
RIGHTS=$(grep -rniE '注销账号|账号注销|删除账号|delete.?account|cancel.?account|close.?account' "$DIR" $GREP_EXCLUDES \
  --include='*.java' --include='*.kt' --include='*.swift' --include='*.ets' --include='*.js' --include='*.ts' --include='*.xml' --include='*.json' 2>/dev/null | head -6)
if [ -n "$RIGHTS" ]; then echo "$RIGHTS" | sed 's/^/  · /'; else say "  ⚠️  没搜到注销入口。若产品有账号体系，这通常是**必驳项**（找不到 ≠ 没有，请人工确认）"; fi

# ── 6. 未成年人保护 ─────────────────────────────────────────────────
say ""
say "── 6. 未成年人保护 ──"
MINOR=$(grep -rniE '未成年|青少年模式|儿童模式|监护人|防沉迷|实名认证' "$DIR" $GREP_EXCLUDES 2>/dev/null | head -6)
if [ -n "$MINOR" ]; then echo "$MINOR" | sed 's/^/  · /'; else say "  · 没搜到未成年人相关实现 —— 若面向未成年人或含社交/游戏/直播元素，需准备对应机制"; fi

# ── 7. 上架材料清单骨架 ─────────────────────────────────────────────
say ""
say "══════════════════════════════════════════════"
say " 上架材料清单骨架（照这个往市场后台填）"
say "══════════════════════════════════════════════"
say ""
say "  【基本信息】"
say "   · 应用名称 / 包名 / 版本号 / versionCode（每次提交必须递增）"
say "   · 应用图标、截图（各市场尺寸不同，按后台要求）"
say "   · 应用分类、一句话简介、详细描述"
say ""
say "  【资质与备案】"
say "   · App 备案号（工信部）；**网站 ICP 备案不能替代**"
say "   · 软著证书（多数市场要求，名称要与 App 名称一致）"
say "   · 若涉及特殊行业：相应许可证（如医疗、教育、金融）"
say ""
say "  【隐私与权限】"
say "   · 隐私政策链接（必须公网可达、必须与实现一致 —— 先跑 pipl-check 对照）"
say "   · 权限使用场景说明（逐个权限写「为什么需要」）"
say "   · 第三方 SDK 清单（名称 / 收集的信息 / 用途 / 官网）"
say "   · 个人信息收集清单与共享清单"
say "   · 账号注销路径说明"
say ""
say "  【内容与合规】"
say "   · 截图与描述文案不要踩红线（先跑 dsh-cn-compliance 扫一遍）"
say "   · 若含 AI 生成内容：标识与相关材料（先跑 dsh-cn-ai-labeling 核对）"
say "   · 未成年人保护说明（如适用）"
say ""
say "──────────────────────────────────────────────"
say " ⚠️ 各市场要求不同且会变，正式提交前请以**目标市场的官方最新公告**为准。"
say "    本清单是通用骨架，不是任一市场的官方清单。"
say "──────────────────────────────────────────────"
exit 0
