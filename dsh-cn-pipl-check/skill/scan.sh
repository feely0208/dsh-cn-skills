#!/bin/bash
# ─────────────────────────────────────────────────────────────
# 个人信息保护合规 · 取证扫描（只报事实，不下结论）
#
# 用法：
#   scan.sh                          # 扫当前目录
#   scan.sh --dir <路径>             # 扫指定目录
#   scan.sh --policy <隐私政策文件>  # 额外做「政策 vs 代码」对照
#   scan.sh --quiet                  # 只输出取证结果，不输出说明
#
# 它回答的是一个问题：**代码里真实存在什么**。
# 至于「这算不算违规」，是人和审核方的事 —— 脚本不做定性。
#
# 退出码：0 = 扫描完成（哪怕有差异，这也是取证工具不是关卡）；2 = 用法错误
# ─────────────────────────────────────────────────────────────
set -uo pipefail

DIR="."; POLICY=""; QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2;;
    --policy) POLICY="$2"; shift 2;;
    --quiet) QUIET=1; shift;;
    -h|--help) sed -n '2,16p' "$0"; exit 0;;
    *) echo "未知参数: $1"; exit 2;;
  esac
done

if [ ! -d "$DIR" ]; then echo "❌ 目录不存在：$DIR"; exit 2; fi
if [ -n "$POLICY" ] && [ ! -f "$POLICY" ]; then echo "❌ 政策文件不存在：$POLICY"; exit 2; fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# BSD 与 GNU 的 grep 都支持的排除：跳过依赖与构建产物，否则结果全是噪声
SKIP_DIRS='node_modules|\.git|build|dist|\.gradle|Pods|\.next|__pycache__|vendor|oh_modules|\.hvigor'

say() { [ "$QUIET" = "1" ] && return 0; echo "$@"; }

# ── 1. 工程识别 ─────────────────────────────────────────────────────
say "══════════════════════════════════════════════"
say " 个人信息保护合规 · 取证扫描"
say " 目标目录：$DIR"
say "══════════════════════════════════════════════"

say ""
say "── 1. 平台与工程 ──"
FOUND_ANY=0
for pair in \
  "AndroidManifest.xml|Android" \
  "Info.plist|iOS" \
  "build.gradle|Android(Gradle)" \
  "build.gradle.kts|Android(Gradle KTS)" \
  "Podfile|iOS(CocoaPods)" \
  "package.json|JS/Node/Electron" \
  "pubspec.yaml|Flutter" \
  "oh-package.json5|HarmonyOS" \
  "requirements.txt|Python"
do
  name="${pair%%|*}"; label="${pair##*|}"
  hits=$(find "$DIR" -name "$name" -not -path "*/node_modules/*" -not -path "*/build/*" 2>/dev/null | head -5)
  if [ -n "$hits" ]; then
    echo "  ✅ $label"
    echo "$hits" | sed 's/^/       /'
    FOUND_ANY=1
  fi
done
[ "$FOUND_ANY" = "0" ] && echo "  ⚠️  没认出任何常见工程文件 —— 换个目录或用 --dir 指定"

# ── 2. 权限取证 ─────────────────────────────────────────────────────
say ""
say "── 2. 代码里真实声明的权限 ──"

: > "$TMP/perms"
# Android：uses-permission / uses-permission-sdk-*
find "$DIR" -name "AndroidManifest.xml" -not -path "*/build/*" 2>/dev/null | while read -r f; do
  # ⚠️ 值里有小写和点（android.permission.ACCESS_FINE_LOCATION），
  #    所以只能取引号内的全部字符，再按关键词筛 —— 一开始写成 [A-Z_]* ，
  #    结果一条都提取不到（实测踩过）。
  grep -o 'android:name="[^"]*"' "$f" 2>/dev/null | sed 's/android:name="//; s/"$//' \
    | grep -E 'PERMISSION|ACCESS_|CAMERA|RECORD_AUDIO|READ_|WRITE_|CALL_|GET_ACCOUNTS|BODY_SENSORS|ACTIVITY_RECOGNITION|POST_NOTIFICATIONS' \
    | while read -r p; do echo "$p|$(basename "$f")" >> "$TMP/perms"; done
done
# iOS：Info.plist 里所有 NS*UsageDescription
find "$DIR" -name "Info.plist" -not -path "*/node_modules/*" 2>/dev/null | while read -r f; do
  grep -o '<key>NS[A-Za-z]*UsageDescription</key>' "$f" 2>/dev/null | sed 's/<key>//; s/<\/key>//' | while read -r k; do
    echo "$k|$(basename "$f")" >> "$TMP/perms"
  done
done

if [ -s "$TMP/perms" ]; then
  sort -u "$TMP/perms" | while IFS='|' read -r p src; do echo "  · $p   （$src）"; done
else
  say "  （未从 AndroidManifest / Info.plist 中提取到权限声明）"
fi

# ── 3. 第三方 SDK 取证 ──────────────────────────────────────────────
say ""
say "── 3. 可能收集个人信息的第三方 SDK ──"
# 名单只覆盖「会收集个人信息」的高频 SDK；不追求穷尽，命中后由人确认。
SDK_RE='umeng|UMENG|友盟|jpush|jcore|极光|getui|个推|talkingdata|sensorsdata|SensorsAnalytics|openinstall|xinstall|bugly|Bugly|com\.tencent\.mm\.opensdk|wechat|weixin|alipay|com\.alipay|sina\.weibo|amap|AMap|高德|baidu\.location|com\.baidu|firebase|play-services|com\.google\.android\.gms|com\.facebook|bytedance|pangle|穿山甲|com\.qq\.e\b|kwad|sentry|bugsnag|mixpanel|amplitude|appsflyer|adjust|branch\.io|hms|com\.huawei\.hms|tracker|analytics'

: > "$TMP/sdks"
find "$DIR" \( -name "package.json" -o -name "build.gradle" -o -name "build.gradle.kts" -o -name "Podfile" -o -name "pubspec.yaml" -o -name "oh-package.json5" \) \
  -not -path "*/node_modules/*" -not -path "*/build/*" -not -path "*/Pods/*" 2>/dev/null | while read -r f; do
  grep -inE "$SDK_RE" "$f" 2>/dev/null | sed 's/^/ /' | while IFS= read -r line; do
    echo "$(basename "$f"):$line" >> "$TMP/sdks"
  done
done

if [ -s "$TMP/sdks" ]; then
  sort -u "$TMP/sdks" | head -60 | sed 's/^/  · /'
  n=$(sort -u "$TMP/sdks" | wc -l | tr -d ' ')
  [ "$n" -gt 60 ] && echo "  …（共 $n 条，已截断；建议按平台逐个核对）"
else
  say "  （依赖清单里没匹配到已知会收集个人信息的 SDK）"
fi

# ── 4. 用户权利入口取证 ─────────────────────────────────────────────
say ""
say "── 4. 用户权利入口（注销 / 删除账号 / 导出 / 撤回同意）──"
# 只搜「用户能看到的入口」通常长什么样；找不到 ≠ 没有，可能叫别的名字
RIGHT_RE='注销|销户|注销账号|删除账号|账号注销|帐号注销|删除账户|注销账户|账号注销|cancel.?account|delete.?account|close.?account|deactivate|注销按钮|退出登录.*注销'
: > "$TMP/rights"
grep -rniE "$RIGHT_RE" "$DIR" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=build --exclude-dir=dist \
  --exclude-dir=Pods --exclude-dir=oh_modules --exclude-dir=.hvigor \
  --include='*.java' --include='*.kt' --include='*.swift' --include='*.m' --include='*.mm' \
  --include='*.js' --include='*.ts' --include='*.tsx' --include='*.vue' --include='*.ets' \
  --include='*.dart' --include='*.xml' --include='*.json' --include='*.html' --include='*.strings' \
  2>/dev/null | head -40 | sed 's/^/  · /' > "$TMP/rights_out" || true

if [ -s "$TMP/rights_out" ]; then
  cat "$TMP/rights_out"
else
  say "  ⚠️  没找到明显的「注销 / 删除账号」字样。"
  say "      注意：这只是「没搜到」，不等于「没有」—— 可能叫别的名字，或只在服务端实现。"
  say "      但**政策里若承诺了「可随时注销」，代码里就必须有可被用户操作的入口**。"
fi

# ── 5. 出站域名取证 ─────────────────────────────────────────────────
say ""
say "── 5. 代码里出现的出站域名（跨境判断用）──"
: > "$TMP/domains"
grep -rhoE 'https?://[a-zA-Z0-9._-]+' "$DIR" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=build --exclude-dir=dist \
  --exclude-dir=Pods --exclude-dir=oh_modules --exclude-dir=.hvigor \
  2>/dev/null | sed 's|https\?://||' | sort -u | head -40 > "$TMP/domains" || true
if [ -s "$TMP/domains" ]; then
  # 粗标「看起来是境外」的：命中常见境外服务商后缀就提示，不自动定性
  while read -r d; do
    case "$d" in
      *google*|*googleapis*|*firebase*|*facebook*|*fbcdn*|*doubleclick*|*sentry.io*|*mixpanel*|*amplitude*|*appsflyer*|*adjust.com*|*bugsnag*|*github*|*cloudflare*|*amazonaws*|*azure*|*s3.*)
        echo "  · $d    ⚠️ 看起来是境外服务，需确认是否传输个人信息";;
      *) echo "  · $d";;
    esac
  done < "$TMP/domains"
else
  say "  （没扫到 http(s) 域名）"
fi

# ── 6. 隐私政策定位与「政策 ↔ 代码」对照 ─────────────────────────────
say ""
say "── 6. 隐私政策 ──"
POLICY_FILES=$(find "$DIR" -iname "*privacy*" -o -iname "*隐私*" 2>/dev/null | grep -v node_modules | head -10)
if [ -n "$POLICY_FILES" ]; then
  echo "$POLICY_FILES" | sed 's/^/  · /'
else
  say "  ⚠️  没找到隐私政策文件。若产品会收集任何个人信息，这是必须有的。"
fi

# 权限名 → 隐私政策里常用的中文说法。
# 为什么需要：政策里写的是「相机」「位置信息」，代码里是 CAMERA / ACCESS_FINE_LOCATION，
# 直接拿权限名去 grep 中文政策**必然一条都匹配不上**。
policy_keywords() {
  case "$1" in
    *ACCESS_FINE_LOCATION*|*ACCESS_COARSE_LOCATION*|*ACCESS_BACKGROUND_LOCATION*|*NSLocation*) echo "位置|定位|行踪";;
    *CAMERA*|*NSCameraUsageDescription*) echo "相机|拍照|摄像头";;
    *RECORD_AUDIO*|*NSMicrophoneUsageDescription*) echo "麦克风|录音|语音";;
    *CONTACTS*|*NSContactsUsageDescription*) echo "通讯录|联系人";;
    *CALENDAR*|*NSCalendars*) echo "日历|日程";;
    *READ_SMS*|*SEND_SMS*) echo "短信";;
    *CALL_PHONE*|*READ_CALL_LOG*|*CALL_LOG*) echo "电话|通话记录";;
    *READ_PHONE_STATE*|*PHONE_STATE*) echo "设备信息|设备标识|电话状态";;
    *EXTERNAL_STORAGE*|*READ_MEDIA*|*NSPhotoLibrary*) echo "存储|相册|照片|文件";;
    *BODY_SENSORS*|*ACTIVITY_RECOGNITION*|*NSHealth*) echo "运动|健康|步数";;
    *GET_ACCOUNTS*) echo "账号";;
    *POST_NOTIFICATIONS*) echo "通知";;
    *BLUETOOTH*) echo "蓝牙";;
    *NSUserTracking*) echo "跟踪|广告标识";;
    *) echo "";;
  esac
}

if [ -n "$POLICY" ]; then
  say ""
  say "── 7. 对照：代码里的事实 × 政策里有没有写 ──"
  say "  （✅ = 政策里有对应表述（原文一并摘出，由你判断）；❌ = 没匹配到 → 确认是漏写还是不收集）"
  say ""

  if [ -s "$TMP/perms" ]; then
    say "  【权限】"
    say "  （摘出政策原文供你判断 —— 脚本只做匹配，不做定性）"
    say ""
    sort -u "$TMP/perms" | cut -d'|' -f1 | sort -u | while read -r p; do
      kws=$(policy_keywords "$p")
      pat="$p"
      [ -n "$kws" ] && pat="$kws|$p"
      snippet=$(grep -nE "$pat" "$POLICY" 2>/dev/null | head -1 | cut -c1-100)
      if [ -z "$snippet" ]; then
        echo "  ❌ $p"
        echo "       政策里没找到对应表述 → 确认是漏写，还是它其实不收集这类信息"
      else
        echo "  ✅ $p"
        echo "       政策原文：「$snippet」"
        # 政策里出现否定词时单独提示：很可能出现「政策说不收集、代码里却要权限」这种最危险的不一致
        case "$snippet" in
          *不收集*|*不会*|*从不*|*无需*|*不获取*|*不读取*|*不申请*)
            echo "       ⚠️ 上面这段含**否定表述** —— 而代码里存在该权限。这正是最危险的一类不一致，务必人工确认";;
        esac
      fi
    done
    say ""
    say "  ⚠️  ✅/❌ 只代表「关键词有没有匹配上」，**不是合规结论**："
    say "      · 政策可能用别的说法描述同一件事（→ 假 ❌）"
    say "      · 政策提了不等于做对了（→ 假 ✅）"
    say "      所以每一条都要回到政策原文和实现里人工确认。"
  fi

  if [ -s "$TMP/sdks" ]; then
    say ""
    say "  【第三方 SDK】"
    sort -u "$TMP/sdks" | head -30 | while IFS= read -r line; do
      echo "  · $line"
    done
    say "      → 请把上列 SDK 逐个在政策里核对；政策通常会以「我们接入的第三方 SDK」清单形式列出"
  fi
fi

# ── 收尾 ────────────────────────────────────────────────────────────
say ""
say "──────────────────────────────────────────────"
say " 取证完成。**以下必须人工判断**（脚本不下结论）："
say "   1. 权限是否「最小必要」：每个权限是否有非它不可的功能？申请时机是否「用到才要」？"
say "   2. 敏感个人信息（人脸/指纹/行踪/医疗/金融）是否做了**单独同意**，而不是混在总协议里？"
say "   3. 政策承诺的每一项（收集范围、第三方共享、存储期限、注销方式）是否都能在实现里找到对应？"
say "   4. 数据是否出境（上面的域名清单 + 云服务所在地）？政策里有没有写？"
say "   5. 是否有「导出/复制个人信息」的入口？"
say "──────────────────────────────────────────────"
exit 0
