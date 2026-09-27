/**
 * dsh-release-selfcheck — 发布前自检
 *
 * 把一套"发布前自检"的方法论注册为 DSH skill，使 agent 在发版、上传安装包、
 * 切换下载链接、创建 Release 之前，能主动把「不该发的发出去了」「该发的没发成」
 * 「发了但没人能下」这三类问题挡住。
 *
 * ── 它解决的是什么 ──────────────────────────────────────────────────
 * 不是"看有没有报错"，而是**逐个断言可核对的最终结果**。因为最常见的发布事故
 * 都是「没有报错但事情没做成 / 做错了」：
 *   · 临时目录名撞上仓库已有目录 → 把无关文件一起传了上去，而工作流报"成功"
 *   · 两个构建 job 的产物同名 → 其中一个平台整个丢失，而所有 job 全绿
 *   · 用某条命令的输出做断言 → 把完好的包判成坏包，排查方向被带偏
 *   · 命令行参数写法不被解析器支持 → 阈值静默丢失，该做的一件没做
 *
 * ── 三条铁律（技能正文里有完整展开与真实事故对照）────────────────────
 *   1. 断言「结果」，不断言「过程」；判据要对着"应该是什么"，不能对着"手里有什么"
 *   2. 只上传「显式清单」，不上传「某个目录的全部内容」
 *   3. 先自检环境与权限，再验业务逻辑
 *
 * ── 与合规审核 skill 的分工 ─────────────────────────────────────────
 * 本 skill 管「东西对不对」；合规 skill 管「话能不能说」。两者都要跑。
 *
 * ── 与官方 API 的约定 ───────────────────────────────────────────────
 * 依赖 `ctx.skills`（由 @deepseek-ai/dsh-skill 提供）。缺失时插件不做任何事，
 * 不会影响 profile 启动。
 *
 * ── 通用性 ─────────────────────────────────────────────────────────
 * skill 正文与脚本已**去除项目专属硬编码**：仓库目录、仓库 slug、站点目录
 * 全部可在运行期用环境变量覆盖，不设则自动推断（见技能正文第四节）。
 * "DeepWhale 落地配置"作为一节示例保留，其它项目按自己情况替换即可。
 */

import { readFileSync, existsSync, statSync, chmodSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

/** 本包根目录（lib/ 的上一级） */
const packageRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
/** 随包分发的 skill 与脚本所在目录 */
const skillDir = join(packageRoot, 'skill');

/** 技能正文里用来占位脚本路径的标记 —— 运行期替换成真实完整路径 */
const SCRIPT_PLACEHOLDER = '<selfcheck.sh 路径>';

export const name = 'release-selfcheck';
export const inject = ['skills'];

/** 技能标识：kebab-case，避免与其它包重名 */
const SKILL_NAME = 'release-selfcheck';

/** 实际自检脚本的完整路径（随包分发；安装后位置由加载器决定） */
export function scriptPath() {
  return join(skillDir, 'selfcheck.sh');
}

function skillBody() {
  const raw = readFileSync(join(skillDir, 'SKILL.md'), 'utf-8');
  // 把占位符替换为真实的完整路径：用户安装到任何位置都能照文档直接跑脚本
  return raw.split(SCRIPT_PLACEHOLDER).join(scriptPath());
}

export function apply(ctx) {
  // skills 服务缺失时静默跳过：这是一个可选能力，不应阻断 profile 启动
  if (!ctx.skills || typeof ctx.skills.register !== 'function') {
    ctx.logger?.warn?.('[release-selfcheck] 未找到 skills 服务，跳过技能注册');
    return;
  }

  let content;
  try {
    content = skillBody();
  } catch (error) {
    ctx.logger?.error?.(`[release-selfcheck] 读取技能正文失败: ${String(error)}`);
    return;
  }

  ctx.skills.register({
    name: SKILL_NAME,
    // 来源标记：'bundled' = 随插件分发的内嵌技能
    source: 'bundled',
    description:
      '软件发布前的自检：产物清单比对（防止把无关文件一起上传）、版本一致性、' +
      '平台与架构正确性、上传内容过滤、站点上线前逐链接 404 检查、发布纪律' +
      '（预发布标记、latest 不被抢）、现场清理。',
    whenToUse:
      '在发版、上传安装包、切换下载链接、创建 Release 之前使用；尤其当流程涉及' +
      '「构建产物分发到多个渠道」（对象存储 / CDN / GitHub Release / 应用商店）时。' +
      '用户提到「发版」「上线」「发布」「上架」「同步」「自检」「检查一下」时也应使用。',
    content,
  });

  ctx.logger?.info?.(`[release-selfcheck] 已注册技能 ${SKILL_NAME}`);

  // 脚本随包分发，但发布/安装过程可能丢掉可执行位；缺失时补上，
  // 让用户照技能文档里的命令能直接跑。失败不影响技能本身。
  const p = scriptPath();
  if (existsSync(p)) {
    try {
      const mode = statSync(p).mode;
      if ((mode & 0o111) === 0) chmodSync(p, mode | 0o755);
    } catch {
      // 只读文件系统或权限不足：忽略，用户可手动 chmod +x
    }
  }
}
