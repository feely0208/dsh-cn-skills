/**
 * dsh-cn-pipl-check — 个人信息保护：声明 ↔ 实现对照
 *
 * 把一套「核对隐私政策承诺与代码实现是否一致」的方法注册为 DSH skill，
 * 使 agent 在准备上架、改隐私政策、新增权限或 SDK 时能主动做一次对照。
 *
 * ── 它管什么、不管什么 ──────────────────────────────────────────────
 *   管：权限最小必要、第三方 SDK 清单、用户权利入口（查阅/删除/注销/撤回）、
 *       敏感信息单独同意、数据出境、政策承诺能否逐条落到实现。
 *   不管：对外文案红线（那是 dsh-cn-compliance）、AI 生成内容标识（dsh-cn-ai-labeling）。
 *
 * ── 一条刻意的设计：只取证，不定性 ──────────────────────────────────
 * 扫描脚本输出的是**事实**（代码里有什么权限、哪个文件哪一行），不是"你违规了"。
 * 原因：合规定性要看业务场景、要看监管口径、要看有没有取得同意 —— 这些脚本都看不到。
 * 一份"看起来权威但其实在瞎定性"的报告，比没有报告更危险。
 * 所以技能正文里也反复写了：找不到 ≠ 没有；❌ 只代表"没匹配上"，必须人工确认。
 *
 * ── 与官方 API 的约定 ───────────────────────────────────────────────
 * 依赖 `ctx.skills`（由 @deepseek-ai/dsh-skill 提供）。缺失时插件不做任何事，
 * 不会影响 profile 启动 —— 这是一个可选能力，不该阻断别人启动。
 */

import { readFileSync, existsSync, statSync, chmodSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

/** 本包根目录（lib/ 的上一级） */
const packageRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
/** 随包分发的 skill 与脚本所在目录 */
const skillDir = join(packageRoot, 'skill');

/** 技能正文里用来占位脚本路径的标记 —— 运行期替换成真实绝对路径 */
const SCAN_PATH_PLACEHOLDER = '<scan.sh 路径>';

export const name = 'cn-pipl-check';
export const inject = ['skills'];

/** 技能标识：kebab-case，避免与其它包重名 */
const SKILL_NAME = 'cn-pipl-check';

/** 实际扫描脚本的绝对路径（随包分发；安装后位置由加载器决定） */
export function scanScriptPath() {
  return join(skillDir, 'scan.sh');
}

function skillBody() {
  const raw = readFileSync(join(skillDir, 'pipl-check.md'), 'utf-8');
  // 把占位符替换为真实路径：用户安装到任何位置都能照文档直接跑脚本
  return raw.split(SCAN_PATH_PLACEHOLDER).join(scanScriptPath());
}

export function apply(ctx) {
  // skills 服务缺失时静默跳过：这是一个可选能力，不应阻断 profile 启动
  if (!ctx.skills || typeof ctx.skills.register !== 'function') {
    ctx.logger?.warn?.('[cn-pipl-check] 未找到 skills 服务，跳过技能注册');
    return;
  }

  let content;
  try {
    content = skillBody();
  } catch (error) {
    ctx.logger?.error?.(`[cn-pipl-check] 读取技能正文失败: ${String(error)}`);
    return;
  }

  ctx.skills.register({
    name: SKILL_NAME,
    // 来源标记：'bundled' = 随插件分发的内嵌技能（区别于磁盘上的 project/user 技能）
    source: 'bundled',
    description:
      '个人信息保护合规：核对隐私政策里承诺的与代码里真做的是否一致 —— 权限最小必要、' +
      '第三方 SDK 清单、用户权利入口（查阅/删除/注销/撤回）、敏感信息单独同意、数据出境。',
    whenToUse:
      '准备提交应用市场前、上线或改版隐私政策后、新增权限或接入新 SDK 后，' +
      '以及需要给用户/审核方一份"我们到底收集了什么"的清单时。' +
      '用户提到「隐私政策」「个人信息保护」「PIPL」「权限审计」「上架被驳回」「SDK 清单」时也应使用。',
    content,
  });

  ctx.logger?.info?.(`[cn-pipl-check] 已注册技能 ${SKILL_NAME}`);

  // 脚本随包分发，但发布/安装过程可能丢掉可执行位；缺失时补上，
  // 让用户照技能文档里的命令能直接跑。失败不影响技能本身。
  const scanPath = scanScriptPath();
  if (existsSync(scanPath)) {
    try {
      const mode = statSync(scanPath).mode;
      if ((mode & 0o111) === 0) {
        chmodSync(scanPath, mode | 0o755);
      }
    } catch {
      // 只读文件系统或权限不足：忽略，用户可手动 chmod +x
    }
  }
}
