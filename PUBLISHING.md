# 发布说明

四个包各自独立发布到 npm（`@deepwhale-cn` scope，public）。

## 发布命令

```bash
cd dsh-cn-compliance      && npm publish --access public
cd dsh-cn-doc-formatter   && npm publish --access public
cd dsh-release-selfcheck  && npm publish --access public
cd dsh-cn-ai-labeling     && npm publish --access public
```

改版本号后先 `npm pack --dry-run` 看一眼要发的内容（本项目实测：7 / 12 / 7 / 8 个文件）。

## ⚠️ 发布不可逆（别指望"发错了删掉就行"）

npm 官方文档 [npm-unpublish](https://docs.npmjs.com/cli/v10/commands/npm-unpublish) 原文：

> Even if a package version is unpublished, that specific name and version
> combination can never be reused. In order to publish the package again,
> a new version number must be used.
>
> With the default registry (`registry.npmjs.org`), unpublish is only allowed
> with versions published in the last **72 hours**.

三条硬约束：

1. **只有 72 小时内**能 unpublish，超过只能发邮件找 support@npmjs.com。
2. **版本号永久烧掉** —— 发过 `0.1.0`，就永远不能再发一个不同的 `0.1.0`，只能 `0.1.1`。
3. **整个包被撤下后，24 小时内不能再发新版本。**

所以**发布前必须验证**，不能"先发再改"。发错了的正确做法是**发下一个版本去覆盖**（配合
`npm deprecate` 提示旧版），而不是撤回。

## ⚠️ 桌面端是从 npm 拉的，不是本地源码

`dsh-desktop/scripts/build-bundled-plugins.js` 从 **npm 已发布的正式包**下载载荷，
理由写在脚本注释里：发出去的应该是经过验证的发布制品，本地源码可能带着未发布的改动。

推论：**改了 skill 内容，光提交源码不起作用** —— 必须发布新版本，
再重跑 `node scripts/build-bundled-plugins.js`，桌面端才会带上新内容。

该脚本的 `PLUGINS` 清单决定了哪些包随桌面端分发 —— **新增包要同时加进这个清单**，
否则发布了也不会随包分发。

## ⚠️ npm 正在收紧凭据（两件事都要知道）

1. **绕过 2FA 的 token 正在被限制** —— 账号变更类操作已于 2026 年 8 月受限，
   **直接发布将于 2027 年 1 月移除**。
2. 因此**不要把发布做成"长期靠一个 token"**。真要在 CI 里自动发布，
   应当改走 **npm Trusted Publishing**（基于 OIDC，不存在长期密钥）。

**当前的做法**：本地发布时临时建一个勾了 Bypass 2FA 的 granular token，
**发完立刻吊销**。攻击窗口只有几分钟，且 token 从未离开本机。

## Token 需要哪些权限（2026-09 实测）

| 项 | 值 |
|---|---|
| Permissions | Read and write (publish and stage) |
| Select packages | All packages |
| **Organizations → Permissions** | **Read and write** |
| **Organizations → Select organizations** | **必须勾选 `deepwhale-cn`** |
| Bypass 2FA | 勾上（否则每次 publish 都要 OTP） |

**最容易漏的是 Organizations 那一节**：不勾组织，即使 Packages 给了读写，
发布 `@deepwhale-cn/xxx` 仍会被拒，而且报错不会直说是组织权限的问题。

## 发布后怎么验证

```bash
npm view @deepwhale-cn/dsh-release-selfcheck version repository.url homepage
```

注意 npm 有**传播延迟**：已发布的包通常在 1 分钟内可见，
**全新包可能要 3–5 分钟**。期间 `npm view` 返回 404 是正常的，不是发布失败。

功能层面的验证（比 `npm view` 更有意义）：

```bash
mkdir /tmp/t && cd /tmp/t && npm init -y && npm install @deepwhale-cn/dsh-release-selfcheck
node --input-type=module -e "
import { apply } from '@deepwhale-cn/dsh-release-selfcheck';
let r=null; apply({skills:{register:x=>{r=x;}},logger:{info(){},warn(){}}});
console.log(r ? '注册成功: '+r.name : '注册失败');
"
```

## 仓库与 npm 的关系

npm 包里的 `repository.directory` 指向本仓库的对应子目录 —— 改代码请改仓库，
不要把 `node_modules` 里的副本当成源码。

---

## ⚠️ 新包发布后，元数据会有几分钟读不到（实测 4–6 分钟）

**现象**：`npm publish` 明确返回成功（`+ @deepwhale-cn/xxx@0.1.0`），但紧接着：

- `npm view @deepwhale-cn/xxx` → **404**
- `npm install @deepwhale-cn/xxx` → **404**
- `curl https://registry.npmjs.org/@deepwhale-cn%2Fxxx` → **404**

**这不是发布失败**，是 registry 读侧的传播延迟。2026-10-01 实测两次：

| 包 | 首次可读 |
| --- | --- |
| `dsh-cn-pipl-check` | 约 4 分钟 |
| `dsh-cn-appstore-preflight` | 约 5.5 分钟 |

**怎么确认它到底发出去没有**（三个证据，按可靠性排序）：

1. **再发一次** —— 若已发布，会报
   `You cannot publish over the previously published versions: 0.1.0.`
   出现这句 = 服务端确实已经收了。
2. **直接取 tarball**（它比 packument 先可用）：
   ```sh
   curl -sI "https://registry.npmjs.org/@deepwhale-cn/<pkg>/-/<pkg>-0.1.0.tgz"
   ```
   200 且大小与本地 `npm pack` 一致 = 包内容在库里。
3. 等 packument 变 200，再 `npm install` 复验。

> 别看到 404 就重新发或升版本号 —— 那会白白烧掉一个版本号（npm 的版本号永久不可重用）。
