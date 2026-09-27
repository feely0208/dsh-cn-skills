#!/bin/bash
# 发布自检 · 自动化部分
#
# 配套本包的 skill/SKILL.md 使用。只做能机械核对的部分；
# 需要判断的（架构、清单合理性）在 SKILL.md 里。
#
# ── 配置（全部可选，不设就自动推断）────────────────────────────────
#   SELFCHECK_REPO_SLUG   仓库 slug，如 owner/repo（默认从 git remote 推断）
#   SELFCHECK_REPO_DIR    仓库根目录（默认从当前目录向上找 package.json）
#   SELFCHECK_MAIN_SITE   主站目录，用于版本一致性比对（不设则跳过该项）
#   SELFCHECK_PAGES_INDEX Pages 站的 index.html 路径（默认 <repo>/docs/index.html）
#   SELFCHECK_CDN         CDN 域名（默认从 SKILL.md 场景推断，可用 --cdn 覆盖）
#
# 用法：
#   selfcheck.sh manifest <expected.txt> <dir>
#   selfcheck.sh versions
#   selfcheck.sh links <页面URL>
#   selfcheck.sh release <壳tag> [套装tag]
set -uo pipefail

PASS=0
FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  $1"; }
head2() { echo; echo "── $1 ──"; }

# ── 配置解析 ────────────────────────────────────────────────────
resolve_repo_dir() {
  if [ -n "${SELFCHECK_REPO_DIR:-}" ]; then echo "$SELFCHECK_REPO_DIR"; return; fi
  local d="$PWD"
  while [ "$d" != "/" ]; do
    [ -f "$d/package.json" ] && { echo "$d"; return; }
    d=$(dirname "$d")
  done
  echo "$PWD"
}

resolve_repo_slug() {
  if [ -n "${SELFCHECK_REPO_SLUG:-}" ]; then echo "$SELFCHECK_REPO_SLUG"; return; fi
  local url
  url=$(git -C "$(resolve_repo_dir)" remote get-url origin 2>/dev/null)
  [ -z "$url" ] && { echo ""; return; }
  # 支持 git@host:owner/repo.git 与 https://host/owner/repo.git
  echo "$url" | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##'
}

REPO_DIR=$(resolve_repo_dir)
REPO_SLUG=$(resolve_repo_slug)

# ── 产物清单比对 ────────────────────────────────────────────────
# 核心用途：防止「目录里多出什么就传什么」。
# 事故背景：迁移脚本 `mkdir -p assets` 撞上仓库已有的 assets/，
# 结果把 11 个无关文件一起传上了对象存储，而工作流报"成功"。
cmd_manifest() {
  local expected="$1" dir="$2"
  [ -f "$expected" ] || { echo "找不到清单文件: $expected"; exit 2; }
  [ -d "$dir" ] || { echo "找不到目录: $dir"; exit 2; }

  head2 "产物清单比对"
  echo "  清单: $expected"
  echo "  目录: $dir"

  local tmp_exp tmp_act
  tmp_exp=$(mktemp); tmp_act=$(mktemp)
  sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' "$expected" | grep -v '^$' | grep -v '^#' | sort -u > "$tmp_exp"
  (cd "$dir" && find . -type f | sed 's|^\./||' | sort) > "$tmp_act"

  local n_exp n_act
  n_exp=$(wc -l < "$tmp_exp" | tr -d ' ')
  n_act=$(wc -l < "$tmp_act" | tr -d ' ')
  echo
  echo "  预期 $n_exp 个，实际 $n_act 个"

  local extra missing
  extra=$(comm -13 "$tmp_exp" "$tmp_act")
  missing=$(comm -23 "$tmp_exp" "$tmp_act")

  if [ -z "$extra" ] && [ -z "$missing" ]; then
    ok "完全一致"
  else
    if [ -n "$extra" ]; then
      echo
      echo "  🔴 多出来的（**不该传的东西**，逐个确认来源）:"
      echo "$extra" | sed 's/^/      + /'
      FAIL=$((FAIL+1))
    fi
    if [ -n "$missing" ]; then
      echo
      echo "  🔴 缺少的（**该传没传**）:"
      echo "$missing" | sed 's/^/      - /'
      FAIL=$((FAIL+1))
    fi
  fi

  # 提醒：临时目录名撞上仓库已有目录，正是那类事故的根因
  local clash
  for name in assets dist build public static; do
    if [ -d "$REPO_DIR/$name" ] && [ "$(cd "$dir" && pwd)" != "$REPO_DIR/$name" ]; then
      clash="${clash:-} $name"
    fi
  done
  if [ -n "${clash:-}" ]; then
    warn "仓库根目录已有：${clash# } —— 上传/下载用的临时目录**绝不要**用这些名字"
  fi

  rm -f "$tmp_exp" "$tmp_act"
}

# ── 版本一致性 ──────────────────────────────────────────────────
cmd_versions() {
  head2 "版本一致性"
  echo "  仓库: ${REPO_SLUG:-（未识别）}"
  echo "  目录: $REPO_DIR"

  local pkg_ver
  pkg_ver=$(python3 -c "import json;print(json.load(open('$REPO_DIR/package.json'))['version'])" 2>/dev/null)
  if [ -n "$pkg_ver" ]; then
    echo "  package.json:      $pkg_ver"
  else
    bad "读不到 $REPO_DIR/package.json"
    echo "        如果当前不在仓库里，请设 SELFCHECK_REPO_DIR=/path/to/repo"
    echo "        （或在仓库目录下运行）"
  fi

  local latest_tag
  latest_tag=$(git -C "$REPO_DIR" tag --sort=-creatordate 2>/dev/null | grep -E '^v[0-9]' | head -1)
  [ -n "$latest_tag" ] && echo "  最新 tag:          $latest_tag"
  if [ -n "$pkg_ver" ] && [ "$latest_tag" = "v$pkg_ver" ]; then
    ok "package.json 与最新 tag 一致"
  elif [ -n "$latest_tag" ]; then
    warn "package.json ($pkg_ver) 与最新 tag ($latest_tag) 不一致 —— 若在准备下一版属正常"
  fi

  # 站点版本（主站目录可选）
  local main_site="${SELFCHECK_MAIN_SITE:-}"
  local pages_index="${SELFCHECK_PAGES_INDEX:-$REPO_DIR/docs/index.html}"
  local main_ver="" pages_ver=""
  # 注意：不同项目的写法可能带空格也可能不带，正则要允许任意空白，
  # 否则会静默读不到并误报"不一致"。
  if [ -n "$main_site" ] && [ -f "$main_site/assets/site.js" ]; then
    main_ver=$(grep -oE "DESKTOP_VERSION[[:space:]]*=[[:space:]]*'[^']*'" "$main_site/assets/site.js" 2>/dev/null | head -1 | sed "s/.*'\\(.*\\)'/\\1/")
    echo "  主站 site.js:      ${main_ver:-读不到}"
  else
    warn "未配置 SELFCHECK_MAIN_SITE，跳过主站版本检查"
  fi
  if [ -f "$pages_index" ]; then
    pages_ver=$(grep -oE "DESKTOP_VERSION[[:space:]]*=[[:space:]]*'[^']*'" "$pages_index" 2>/dev/null | head -1 | sed "s/.*'\\(.*\\)'/\\1/")
    echo "  Pages index:       ${pages_ver:-读不到}"
  fi
  if [ -n "$main_ver" ] && [ -n "$pages_ver" ]; then
    if [ "$main_ver" = "$pages_ver" ]; then
      ok "两个站点版本一致"
    else
      bad "两个站点版本**不一致** —— 会出现「从首页点下载拿到旧版」"
    fi
  fi

  # 各产品族版本相互独立（防止批量改版本时互相覆盖）
  if [ -n "$main_site" ] && [ -f "$main_site/assets/site.js" ]; then
    local lawyer suite
    lawyer=$(grep -o "DeepWhale-Lawyer-[0-9.]*" "$main_site/assets/site.js" 2>/dev/null | head -1 | sed 's/.*Lawyer-//')
    suite=$(grep -o "DeepWhale-Suite-[0-9.]*" "$main_site/assets/site.js" 2>/dev/null | head -1 | sed 's/.*Suite-//')
    echo "  主站律师端:        ${lawyer:-读不到}"
    echo "  主站套装:          ${suite:-读不到}"
    if [ -n "$lawyer" ] && [ -n "$suite" ]; then
      if [ "$lawyer" != "$suite" ]; then
        ok "各产品族版本号相互独立（未被批量覆盖）"
      else
        warn "律师端与套装版本号相同 —— 确认版本批量替换脚本的族锚定没失效"
      fi
    fi
  fi
}

# ── 线上页面链接逐条 HEAD ───────────────────────────────────────
# 必须用 -I（HEAD）：用 -o /dev/null 会把每个安装包**整份下载回来**只为看状态码，
# 几个 GB 白等十几分钟（实测踩过）。
cmd_links() {
  local page="$1"
  head2 "线上链接检查"
  echo "  页面: $page"

  local html
  html=$(mktemp)
  curl -sS --max-time 30 "$page" -o "$html" || { bad "页面取不到"; rm -f "$html"; return; }

  local urls
  urls=$(grep -oE 'https?://[A-Za-z0-9._/-]+\.(dmg|exe|zip|deb|AppImage|apk|msi|pkg)' "$html" | sort -u)
  if [ -z "$urls" ]; then
    warn "页面里没抓到下载链接（可能是动态渲染，链接在外部 js 里）"
    rm -f "$html"; return
  fi

  echo
  local n=0 bad_n=0
  while read -r u; do
    [ -n "$u" ] || continue
    n=$((n+1))
    local code=""
    for try in 1 2; do
      code=$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' -I "$u" 2>/dev/null)
      [ "$code" = "200" ] && break
      sleep 2
    done
    if [ "$code" = "200" ]; then
      echo "      ✅ ${u##*/}"
    else
      echo "      ❌ $code  ${u##*/}"
      bad_n=$((bad_n+1))
    fi
  done <<< "$urls"

  echo
  if [ "$bad_n" -eq 0 ]; then
    ok "$n 个链接全部可下载"
  else
    bad "$n 个链接里有 $bad_n 个不是 200"
    echo "        403 = 对象在源站不存在；000 = 网络抖动，重试"
  fi
  rm -f "$html"
}

# ── 发布纪律 ────────────────────────────────────────────────────
cmd_release() {
  local shell_tag="$1" suite_tag="${2:-}"
  head2 "发布纪律"

  if ! command -v gh >/dev/null 2>&1; then warn "未安装 gh，跳过"; return; fi
  if [ -z "$REPO_SLUG" ]; then bad "识别不出仓库 slug，请设 SELFCHECK_REPO_SLUG"; return; fi

  local shell_state
  shell_state=$(gh release view "$shell_tag" --repo "$REPO_SLUG" --json isDraft,isPrerelease 2>/dev/null \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print((('Draft' if d['isDraft'] else '')+('Pre-release' if d['isPrerelease'] else '')) or '正式')" 2>/dev/null)
  echo "  壳 $shell_tag: ${shell_state:-查不到}"
  if [ "$shell_state" = "正式" ]; then
    ok "壳是正式发布（会成为 Latest，自动更新才生效）"
  else
    bad "壳不是正式发布 —— 自动更新不会生效"
  fi

  if [ -n "$suite_tag" ]; then
    local suite_pre
    suite_pre=$(gh release view "$suite_tag" --repo "$REPO_SLUG" --json isPrerelease --jq '.isPrerelease' 2>/dev/null)
    echo "  套装 $suite_tag: isPrerelease=$suite_pre"
    if [ "$suite_pre" = "true" ]; then
      ok "套装已勾 Pre-release（铁律守住）"
    else
      bad "套装**不是** Pre-release —— 会抢走 latest，让桌面端自动更新**静默失效**"
    fi
  fi

  local latest
  latest=$(gh api "repos/$REPO_SLUG/releases/latest" --jq '.tag_name' 2>/dev/null)
  echo "  /releases/latest → ${latest:-查不到}"
  case "$latest" in
    suite-*|*-suite-*) bad "latest 指向了套装！桌面端自动更新已失效，立刻把套装改成 Pre-release" ;;
    v*)                ok "latest 指向壳，正确" ;;
    *)                 warn "latest 状态未知" ;;
  esac
}

# ── 入口 ────────────────────────────────────────────────────────
CMD="${1:-}"
shift || true
case "$CMD" in
  manifest) cmd_manifest "$@" ;;
  versions) cmd_versions ;;
  links)    cmd_links "$@" ;;
  release)  cmd_release "$@" ;;
  config)
    head2 "当前配置"
    echo "  REPO_DIR   = $REPO_DIR"
    echo "  REPO_SLUG  = ${REPO_SLUG:-（未识别）}"
    echo "  MAIN_SITE  = ${SELFCHECK_MAIN_SITE:-（未设置）}"
    ;;
  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 2 ;;
esac

echo
if [ "$FAIL" -eq 0 ]; then
  echo "════ 自检通过（$PASS 项）════"
  exit 0
else
  echo "════ 自检未通过：$FAIL 项需处理 ════"
  exit 1
fi
