/**
 * dsh-cn-appstore-preflight — 国内应用市场上架预检
 *
 * 把一套「上架前体检」的方法注册为 DSH skill：从上架材料的角度，
 * 在提交应用市场之前把会被驳回的地方先找出来。
 *
 * ── 它管什么、不管什么 ──────────────────────────────────────────────
 *   管：App 备案、隐私政策可达性、权限使用场景说明、账号注销入口、未成年人保护、
 *       上架材料清单（包名/版本/软著/SDK 清单…）。
 *   不管：隐私声明与实现是否一致（dsh-cn-pipl-check）、
 *         对外文案红线（dsh-cn-compliance）、AI 生成内容标识（dsh-cn-ai-labeling）。
 *   本技能**不重复**上面三件事，而是在需要时把它们的结果收进来当输入。
 *
 * ── 一条刻意的纪律：不杜撰具体条款 ──────────────────────────────────
 * 各应用市场的要求不同且会变。技能正文与扫描脚本里都明确写了
 * 「以目标市场的官方最新公告为准，本清单只是通用骨架」。
 * 编一条"看起来很像"的规定比不写更糟糕 —— 用户会照着它准备材料，然后在提交时被打回。
 *
 * ── 与官方 API 的约定 ───────────────────────────────────────────────
 * 依赖 `ctx.skills`（由 @deepseek-ai/dsh-skill 提供）。缺失时插件不做任何事，
 * 不会影响 profile 启动。
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

export const name = 'cn-appstore-preflight';
export const inject = ['skills'];

/** 技能标识：kebab-case，避免与其它包重名 */
const SKILL_NAME = 'cn-appstore-preflight';

/** 实际扫描脚本的绝对路径（随包分发；安装后位置由加载器决定） */
export function scanScriptPath() {
  return join(skillDir, 'scan.sh');
}

function skillBody() {
  const raw = readFileSync(join(skillDir, 'appstore-preflight.md'), 'utf-8');
  // 把占位符替换为真实路径：用户安装到任何位置都能照文档直接跑脚本
  return raw.split(SCAN_PATH_PLACEHOLDER).join(scanScriptPath());
}

export function apply(ctx) {
  // skills 服务缺失时静默跳过：这是一个可选能力，不应阻断 profile 启动
  if (!ctx.skills || typeof ctx.skills.register !== 'function') {
    ctx.logger?.warn?.('[cn-appstore-preflight] 未找到 skills 服务，跳过技能注册');
    return;
  }

  let content;
  try {
    content = skillBody();
  } catch (error) {
    ctx.logger?.error?.(`[cn-appstore-preflight] 读取技能正文失败: ${String(error)}`);
    return;
  }

  ctx.skills.register({
    name: SKILL_NAME,
    // 来源标记：'bundled' = 随插件分发的内嵌技能（区别于磁盘上的 project/user 技能）
    source: 'bundled',
    description:
      '国内应用市场上架预检：App 备案、隐私政策可达性、权限使用场景说明、账号注销入口、' +
      '未成年人保护、上架材料清单 —— 在提交市场之前先找出会被驳回的地方。',
    whenToUse:
      '准备首次上架、版本更新重新提交审核、或被驳回后定位原因时。' +
      '要为新市场（华为/小米/OPPO/vivo/应用宝/鸿蒙）准备材料时也应使用。' +
      '用户提到「上架」「应用市场」「审核被拒」「备案」「软著」「提审材料」时同样适用。',
    content,
  });

  ctx.logger?.info?.(`[cn-appstore-preflight] 已注册技能 ${SKILL_NAME}`);

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
