# @deepwhale-cn/dsh-release-selfcheck

> 给 AI Agent 用的**发布前自检**能力。装进 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）后，Agent 在发版、上传安装包、切换下载链接、创建 Release 之前会自动按这套清单自查。

**一句话**：它挡的不是"报错"，而是**「没有报错但事情没做成 / 做错了」**。

---

## 为什么需要它

最常见的发布事故，全都发生在**所有 CI job 都是绿的、日志里没有任何异常**的时候。下面每一条都是真实踩过的坑：

| 事故 | 表面现象 | 真实后果 |
|---|---|---|
| 迁移脚本的临时目录叫了 `assets`，撞上仓库已有的 `assets/` | 工作流"成功" | 把 11 个无关的网站图片一起传上了对象存储 |
| 两个 macOS 构建 job 的产物同名 | 四个 job 全绿 | macOS arm64 **整个丢失**，该平台用户没得下载 |
| 用 `unzip -l` 的输出做断言，把完好的包判成坏包 | 构建"失败" | 正确产物被拦下，排查方向被带偏 |
| 命令行参数 `--key=value` 不被解析器支持 | 脚本打印"无需处理"、退出码 0 | 阈值静默丢失，该做的一件没做 |
| 改一个 JSON 字段时整段配置被顺手删掉 | 构建成功 | 打出签名无效的包，只影响其中一个平台 |
| 验证步骤用 `curl -o /dev/null` 而非 `-I` | 看起来在"验证" | 几个 GB 白下载，白等十几分钟 |

**共同点**：没有报错，但事情没做成或做错了。所以本 skill 的核心不是"看有没有报错"，而是**逐个断言可核对的最终结果**。

---

## 三条铁律

### 1. 断言「结果」，不要断言「过程」

| ❌ | ✅ |
|---|---|
| 函数返回了 `changed=true` | **目标文件里到底有没有那段内容** |
| 所有 job 都 success | **产物清单里每个平台在不在** |
| 命令 exit 0 | **HTTP 状态码是不是 200**（用 `-I`） |
| 日志里没报错 | **下载回来的哈希与原件一致** |

并且：**判据要对着「应该是什么」，不能对着「手里有什么」**。验证器与上传器的过滤规则必须同源——否则会出现"上传器刻意跳过某类文件，验证器却拿整个目录去核对"，于是报出假失败。

### 2. 只上传「显式清单」，不上传「某个目录的全部内容」

目录内容会变，清单不会。这是"多传了 11 个无关文件"那次事故的根因。

### 3. 先自检环境与权限，再验业务逻辑

否则一旦失败，你无法判断是环境问题还是逻辑问题，排查时间成倍增加。

---

## 安装

```bash
npm install @deepwhale-cn/dsh-release-selfcheck
```

然后在你的 DSH profile 里把它列为 bundle：

```json
{
  "dependencies": {
    "@deepwhale-cn/dsh-release-selfcheck": "^0.1.0"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app",
        "@deepwhale-cn/dsh-release-selfcheck"
      ]
    }
  }
}
```

重启后，Agent 在涉及发布的对话里会自动带上这套检查清单。

---

## 自检脚本

技能正文里带一个可直接运行的脚本（路径在注册时自动替换为真实完整路径）：

```bash
SELFCHECK=/path/to/skill/selfcheck.sh      # 由技能正文给出

# 看当前配置与自动推断结果
bash $SELFCHECK config

# 产物清单比对（核心）：多一个要问为什么，少一个要问为什么
bash $SELFCHECK manifest expected.txt ./实际目录

# 版本一致性：包版本 / git tag / 各站点 / 各产品线
bash $SELFCHECK versions

# 线上页面下载链接逐条 HEAD（403 = 源站没有；000 = 网络抖动）
bash $SELFCHECK links https://example.com/download.html

# 发布纪律：主程序是否正式发布、附加发布是否标了 Pre-release、latest 指向谁
bash $SELFCHECK release v1.0.19 suite-v1.0.19
```

### 配置（全部可选，不设则自动推断）

| 环境变量 | 说明 | 默认 |
|---|---|---|
| `SELFCHECK_REPO_DIR` | 仓库根目录 | 从当前目录向上找 `package.json` |
| `SELFCHECK_REPO_SLUG` | 仓库 slug（`owner/repo`） | 从 `git remote origin` 推断 |
| `SELFCHECK_MAIN_SITE` | 主站目录（用于跨站版本比对） | 不设则跳过该项 |
| `SELFCHECK_PAGES_INDEX` | 静态托管站的 index 路径 | `<repo>/docs/index.html` |

```bash
SELFCHECK_MAIN_SITE=/path/to/main-site bash $SELFCHECK versions
```

---

## 覆盖范围

- **A. 产物清单** —— 预期 vs 实际逐一比对，防止多传/漏传
- **B. 版本一致性** —— 包版本、git tag、多个站点、多个产品线互不覆盖
- **C. 平台与架构** —— 解包看二进制头，不只看文件名；随包载荷架构要与包一致
- **D. 上传内容过滤** —— 该排除的排除，但同名不同用途的别一刀切
- **E. 站点上线前** —— 从线上页面抽链接、逐条 HEAD、部署后再验
- **F. 发布纪律** —— 正式/预发布标记、latest 不被附加发布抢走
- **G. 对外内容合规** —— 与合规审核 skill 配合（本 skill 管"东西对不对"，它管"话能不能说"）
- **H. 现场清理** —— 进程回收、临时文件清理、**不误删别人的文件**

另含一节**「已知假阳性」**，防止检查本身误伤（例如下载目录里出现 `.blockmap` 是正常的、锁文件里的敏感词是 base64 巧合）。

---

## 注意

- 本 skill 提供的是**检查方法与判据**，不是任何具体项目的发布脚本；命令里的仓库名、站点路径都需按你的情况配置。
- 脚本只做能机械核对的部分。**架构是否正确、清单是否合理这类判断，仍需人（或 Agent）来看**。
- 依赖 `ctx.skills`（由 `@deepseek-ai/dsh-skill` 提供）。该服务缺失时插件静默跳过，不会影响 profile 启动。

---

## 相关

- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) —— DSH 本体
- 同系列：`@deepwhale-cn/dsh-cn-compliance`（对外内容合规红线审核）、
  `@deepwhale-cn/dsh-cn-doc-formatter`（中文公文排版）
- 深鲸官网：<https://deepwhale.org.cn>

## License

MIT
