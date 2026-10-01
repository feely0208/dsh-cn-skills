# @deepwhale-cn/dsh-secret-scan

**密钥与敏感信息扫描** —— 给 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 用的 skill 插件。

提交前、发布前、开源前，把不该出现在代码里的东西找出来。

这是这一组技能里唯一**通用**的（不限中国大陆）—— 因为"密钥进了仓库"是所有技术团队都会踩的坑。

## 它查什么

| 类别 | 内容 |
|---|---|
| 🔴 **高置信令牌** | 云厂商 Access Key（AKIA/LTAI/AKID）、GitHub/npm/Slack 令牌、Google API Key |
| 🔴 **私钥与证书** | `id_rsa`、`*.pem`/`*.p12`/`*.jks`，以及嵌在代码里的 PEM 私钥内容 |
| 🔴 **凭据文件进了 git** | `.env`、`credentials.json`、`.npmrc` 等是否已被 `git ls-files` 跟踪 |
| 🟠 **配置里的敏感赋值** | `password=` / `token=` / `api_key=` 这类硬编码（误报较多，逐条看） |
| 🟠 **内部信息** | 内网 IP（`10.` / `192.168.` / `172.16-31.`）、内部域名（`.corp` / `.internal`） |

**退出码 1 = 有高置信命中**，可直接挂到 pre-commit 或 CI 上。

## 两条刻意的设计

**1. 输出默认打码**（只留前后 4 位）。

扫描工具把完整密钥打进终端或日志，等于换个地方又泄露一次。要看全必须显式 `--reveal`，
而且别把输出存进文件或贴进聊天。

**2. 技能正文里，处置顺序比扫描本身更重要**：

```
1. 轮换密钥  →  2. 清理代码  →  3. 再决定要不要改写历史
```

**删代码不会让已泄露的密钥失效** —— 它还在 git 历史、已推送的远端副本、CI 日志与缓存、
你的 shell 历史和编辑器备份里。判断标准很简单：**这个密钥有没有离开过你的机器？**

一个只教人"删掉就好"的工具，是在帮倒忙。

## 误报怎么办

文档里的示例值（`your-api-key-here`、`sk-example-...`）**已自动过滤**。测试用的假密钥建议
写成含 `example` / `dummy` 的明显假值，同样会被过滤。

剩下的 🟠 逐条看上下文 —— 但**别因为误报多就不看报告了**，那正是这类工具失效的方式。

## 安装

```bash
dsh plugin --profile <profile> add @deepwhale-cn/dsh-secret-scan
```

## 用法

```bash
# 脚本路径由插件注册时注入到技能正文里，或到安装目录找 skill/scan.sh
scan.sh --dir /path/to/repo          # 默认打码
scan.sh --dir /path/to/repo --reveal # ⚠️ 打印完整密钥，仅排障时用
```

## 与相邻技能的边界

| 包 | 管什么 |
| --- | --- |
| **`dsh-secret-scan`** | **内部信息进了代码仓库**（该不该提交、提交了怎么补救） |
| `dsh-cn-compliance` 的 I 类 | **内部文件的公网暴露面**（被搜索引擎或公开链接读到） |

两者的交集是"内部信息"，但一个看**版本控制**，一个看**暴露面**。

## 许可

MIT
