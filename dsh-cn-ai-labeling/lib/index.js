/**
 * dsh-cn-ai-labeling — AI 生成合成内容标识合规自检
 *
 * 把《人工智能生成合成内容标识办法》与强制性国标 GB 45438—2025 的要求，
 * 变成一套 agent 在产品设计、开发、发版前可以逐条执行的自检流程。
 *
 * ── 为什么单独一个包 ────────────────────────────────────────────────
 * 与 @deepwhale-cn/dsh-cn-compliance 的边界：
 *   · dsh-cn-compliance      —— 发布前扫「对外文案」（广告法、红线词、备案展示）
 *   · dsh-cn-ai-labeling     —— 开发时查「产品实现」（标识是否写进了代码与导出物）
 * 生命周期不同、使用者不同，装一个不应该拖另一个，故独立发包。
 *
 * ── 设计原则 ────────────────────────────────────────────────────────
 * 1. 规则只来自官方原文。条款号与数值逐条摘自：
 *      《人工智能生成合成内容标识办法》 https://www.gov.cn/zhengce/zhengceku/202503/content_7014286.htm
 *      《互联网信息服务深度合成管理规定》 https://www.gov.cn/zhengce/zhengceku/2022-12/12/content_5731431.htm
 *      GB 45438—2025                https://www.tc260.org.cn/upload/2025-03-15/1742009439794081593.pdf
 *    不凭记忆写规则，不确定的条款号不写进结论。
 * 2. 详尽但不误伤。GB 45438 附录 A/B/C/D/F 均为资料性，只有附录 E 是规范性；
 *    数字水印是「准许」不是「应」。技能正文专设一节列出不构成强制要求的项 ——
 *    误报多了，人就再也不看报告了。
 * 3. 先判主体，再查功能。义务主体是「生成合成服务提供者」，纯工具方不是义务主体，
 *    不能给工具方扣「未标识」的帽子。
 *
 * ── 与官方 API 的约定 ───────────────────────────────────────────────
 * 依赖 ctx.skills（由 @deepseek-ai/dsh-skill 提供）。缺失时静默跳过，
 * 不影响 profile 启动。
 */

import { readFileSync, existsSync, statSync, chmodSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

/** 本包根目录（lib/ 的上一级） */
const packageRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
/** 随包分发的 skill 与脚本所在目录 */
const skillDir = join(packageRoot, 'skill');

/** 技能正文里用来占位脚本路径的标记 —— 运行期替换成真实绝对路径 */
const SCAN_PATH_PLACEHOLDER = '<labeling-check.sh 路径>';

export const name = 'cn-ai-labeling';
export const inject = ['skills'];

/** 技能标识：kebab-case，避免与其它包重名 */
const SKILL_NAME = 'cn-ai-labeling-audit';

/** 取证脚本的绝对路径（随包分发；安装后位置由加载器决定） */
export function checkScriptPath() {
  return join(skillDir, 'labeling-check.sh');
}

function skillBody() {
  const raw = readFileSync(join(skillDir, 'ai-labeling-audit.md'), 'utf-8');
  // 把占位符替换为真实路径：用户安装到任何位置都能照文档直接跑脚本
  return raw.split(SCAN_PATH_PLACEHOLDER).join(checkScriptPath());
}

export function apply(ctx) {
  // skills 服务缺失时静默跳过：这是一个可选能力，不应阻断 profile 启动
  if (!ctx.skills || typeof ctx.skills.register !== 'function') {
    ctx.logger?.warn?.('[cn-ai-labeling] 未找到 skills 服务，跳过技能注册');
    return;
  }

  let content;
  try {
    content = skillBody();
  } catch (error) {
    ctx.logger?.error?.(`[cn-ai-labeling] 读取技能正文失败: ${String(error)}`);
    return;
  }

  ctx.skills.register({
    name: SKILL_NAME,
    // 来源标记：'bundled' = 随插件分发的内嵌技能（区别于磁盘上的 project/user 技能）
    source: 'bundled',
    description:
      'AI 生成合成内容标识合规自检：对照《人工智能生成合成内容标识办法》与强制性国标 ' +
      'GB 45438—2025，判定义务主体、逐条核对显式标识（文本/图片/音频/视频/虚拟场景/交互界面）' +
      '与隐式标识（文件元数据格式、唯一性）、导出链路与上架材料，并明确哪些项不构成强制要求。',
    whenToUse:
      '在产品设计、开发、发版前，检查 AI 生成内容标识是否落实时使用。典型信号：' +
      '「AI 标识」「生成合成标识」「GB 45438」「显式标识」「隐式标识」「AIGC 元数据」' +
      '「水印」「导出文件要不要带标识」「上架应用市场要什么材料」。' +
      '涉及导出 Word/Excel/PPT/PDF/图片/音视频，或产品面向中国大陆市场时也应主动使用。',
    content,
  });

  ctx.logger?.info?.(`[cn-ai-labeling] 已注册技能 ${SKILL_NAME}`);

  // 脚本随包分发，但发布/安装过程可能丢掉可执行位；缺失时补上，
  // 让用户照技能文档里的命令能直接跑。失败不影响技能本身。
  for (const script of ['labeling-check.sh']) {
    const p = join(skillDir, script);
    if (!existsSync(p)) continue;
    try {
      const mode = statSync(p).mode;
      if ((mode & 0o111) === 0) {
        chmodSync(p, mode | 0o755);
      }
    } catch {
      // 只读文件系统或权限不足：忽略，用户可手动 chmod +x
    }
  }
}
