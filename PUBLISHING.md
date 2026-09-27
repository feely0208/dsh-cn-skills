# 发布说明

三个包各自独立发布到 npm（`@deepwhale-cn` scope，public）。

## 发布命令

```bash
cd dsh-cn-compliance      && npm publish --access public
cd dsh-cn-doc-formatter   && npm publish --access public
cd dsh-release-selfcheck  && npm publish --access public
```

改版本号后先 `npm pack --dry-run` 看一眼要发的内容（本项目实测：7 / 12 / 7 个文件）。

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
