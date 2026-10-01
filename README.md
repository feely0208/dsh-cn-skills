# DSH 中文合规与工程技能集

> 给 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）用的中文场景插件集。
> 面向**中国大陆市场**的合规审核、公文排版，以及通用但容易踩坑的发布自检。

[![npm](https://img.shields.io/badge/npm-@deepwhale--cn-cc3534)](https://www.npmjs.com/org/deepwhale-cn)
[![license](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

---

## 为什么有这个仓库

DSH 的插件生态里**绝大多数内容是英文的**，而面向中国大陆市场的合规要求（广告法极限词、
网络工具用语红线、公文格式国家标准、备案与隐私表述）**没有现成的成套工具**。

结果就是：每一个在中国做产品的团队，都要自己重新踩一遍同样的坑 ——
被广告法极限词卡住、备案信息写错、公文排版不符合 GB/T 9704、
发布流程里"没有报错但事情没做成"的事故反复发生。

这个仓库把这些经验固化成 **DSH 技能（skill）**，装上就能用，也可以按自己的情况改。

---

## 包含哪些技能

| 包 | 管什么 | 什么时候用 |
|---|---|---|
| [`@deepwhale-cn/dsh-cn-compliance`](./dsh-cn-compliance) | **话能不能说** —— 对外内容合规红线审核：网络工具用语、广告法极限词、绝对化承诺、内部文件公网暴露 | 改官网、写公开文档、发公众号、写 App 内文案时 |
| [`@deepwhale-cn/dsh-cn-doc-formatter`](./dsh-cn-doc-formatter) | **公文怎么排** —— 按 GB/T 9704-2012 生成 `.docx` / `.pdf` / `.txt`，附输出自检 | 写公文、通知、报告时 |
| [`@deepwhale-cn/dsh-release-selfcheck`](./dsh-release-selfcheck) | **东西对不对** —— 发布前自检：产物清单比对、版本一致性、架构正确性、上线前逐链接检查、发布纪律 | 发版、上传安装包、切换下载链接、创建 Release 时 |
| [`@deepwhale-cn/dsh-cn-ai-labeling`](./dsh-cn-ai-labeling) | **AI 标识做没做** —— 对照《人工智能生成合成内容标识办法》与强制性国标 GB 45438—2025，核对显式/隐式标识、导出链路与上架材料 | 做 AI 产品、设计导出功能、准备上架应用市场时 |
| [`@deepwhale-cn/dsh-cn-pipl-check`](./dsh-cn-pipl-check) | **说的和做的是否一致** —— 个人信息保护：权限最小必要、第三方 SDK 清单、用户权利入口（查阅/删除/注销/撤回）、敏感信息单独同意、数据出境 | 准备上架、改隐私政策、新增权限或 SDK 时 |
| [`@deepwhale-cn/dsh-cn-appstore-preflight`](./dsh-cn-appstore-preflight) | **上架能不能过** —— 应用市场预检：App 备案、隐私政策可达性、权限使用场景说明、账号注销入口、未成年人保护、上架材料骨架 | 提交应用市场之前、被驳回后定位原因时 |
| [`@deepwhale-cn/dsh-secret-scan`](./dsh-secret-scan) | **有没有把密钥交出去** —— 密钥与敏感信息扫描：云厂商 AK、令牌、私钥、凭据文件是否被 git 跟踪、内网 IP 与内部域名。**通用，不限中国** | 提交前、开源前、发布前、交接时 |

这些包的边界是刻意分开的：**合规管「话」，标识管「AI 链路」，隐私对照管「说的和做的是否一致」，上架预检管「材料与流程」，密钥扫描管「有没有把凭据交出去」，自检管「东西」**，不能互相替代。

---

## 安装

```bash
npm install @deepwhale-cn/dsh-cn-compliance \
              @deepwhale-cn/dsh-cn-doc-formatter \
              @deepwhale-cn/dsh-release-selfcheck \
              @deepwhale-cn/dsh-cn-ai-labeling \
              @deepwhale-cn/dsh-cn-pipl-check \
              @deepwhale-cn/dsh-cn-appstore-preflight \
              @deepwhale-cn/dsh-secret-scan
```

然后在 DSH profile 的 `package.json` 里把它们列为 bundle：

```json
{
  "dependencies": {
    "@deepwhale-cn/dsh-cn-compliance": "^0.1.1",
    "@deepwhale-cn/dsh-cn-doc-formatter": "^0.1.1",
    "@deepwhale-cn/dsh-release-selfcheck": "^0.1.0",
    "@deepwhale-cn/dsh-cn-ai-labeling": "^0.1.0"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app",
        "@deepwhale-cn/dsh-cn-compliance",
        "@deepwhale-cn/dsh-cn-doc-formatter",
        "@deepwhale-cn/dsh-release-selfcheck",
        "@deepwhale-cn/dsh-cn-ai-labeling"
      ]
    }
  }
}
```

重启 DSH，Agent 在相关对话里就会自动带上这些技能。

---

## 设计原则

### 1. 误报比漏报更致命

合规扫描最容易犯的错不是"漏掉敏感词"，而是**误报太多**：
锁文件里的 base64 哈希恰好含 `VPN`、CSS 里的 `绝对定位` 是布局术语、
代码注释里的"永远不执行"是技术描述 —— 这些都被报出来的话，
**人读几次就不再看报告了**，真正的风险反而被淹没。

所以这些工具都花了大量精力在**误报规避**上，并在技能正文里明确列出
「已知假阳性」，告诉大家哪些命中是正常的、不要去改。

### 2. 断言「结果」，不断言「过程」

`release-selfcheck` 整条思路来自一个反复出现的现象：**最常见的发布事故，
都发生在所有 CI 都是绿的、日志里没有任何异常的时候**。

- 临时目录名撞上仓库已有目录 → 无关文件被一起上传，而工作流报"成功"
- 两个构建任务的产物同名 → 一个平台整个丢失，而所有任务全绿
- 用某条命令的输出做断言 → 完好的包被判成坏包，排查方向被带偏

对策只有一句：**断言可核对的最终结果**（文件里到底有没有那段内容、
产物清单里每个平台在不在、HTTP 状态码是不是 200），
而不是"函数返回成功""命令 exit 0"。

### 3. 本仓库自身会命中合规扫描 —— 这是设计使然

拿合规扫描去扫**本仓库**，一定会报出大量命中：合规插件**必须包含**它要检测的那些词
（否则无法检测），技能正文也必须**逐字引用**它们才能说清"哪些该报、哪些不该报"。

**这不代表内容违规，也不要去改。** 判断标准很简单：
看命中的**上下文**是在「列词表 / 解释规则」，还是在「对用户做宣称」。
前者是工具的实现，后者才是风险。

### 4. 插件不内置敏感词表

合规插件**不携带政治敏感词表** —— 避免插件自身成为敏感内容的载体。
这部分需要人工审核或使用专门的第三方工具。工具能做的是**把机械可查的部分查干净**。

---

## 每个包的详情

- [dsh-cn-compliance](./dsh-cn-compliance/README.md) —— 对外内容合规红线审核
- [dsh-cn-doc-formatter](./dsh-cn-doc-formatter/README.md) —— 中文公文排版
- [dsh-release-selfcheck](./dsh-release-selfcheck/README.md) —— 发布前自检
- [dsh-cn-ai-labeling](./dsh-cn-ai-labeling/README.md) —— AI 生成合成内容标识合规自检

---

## 贡献

欢迎提 Issue 补充**真实踩过的坑** —— 尤其是"误报"和"漏报"两类：

- 你遇到了规则误报（把正常内容判成风险）？告诉我们上下文，这类反馈最有价值
- 你踩到了规则没覆盖的合规问题？欢迎补充

比"多加几个词"更有价值的，是**把规则变得更准**。

---

## English

A collection of **Chinese-market skills for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)**:

- **`dsh-cn-compliance`** — content compliance review for the China market
  (advertising-law superlatives, network-tool terminology, internal-file exposure)
- **`dsh-cn-doc-formatter`** — Chinese official document typesetting per GB/T 9704-2012
- **`dsh-release-selfcheck`** — release preflight: artifact manifest diffing,
  version consistency, architecture verification, link checks, release discipline
- **`dsh-cn-ai-labeling`** — AI-generated content labeling self-check against
  China's mandatory national standard GB 45438—2025 (explicit/implicit labels,
  file metadata format, export paths, app-store submission)

The release preflight is domain-agnostic and useful for any project that ships
build artifacts to multiple channels — its whole point is catching failures that
**leave every CI job green**.

## License

[MIT](./LICENSE)

---

由 [深鲸 DeepWhale](https://deepwhale.org.cn) 维护。
