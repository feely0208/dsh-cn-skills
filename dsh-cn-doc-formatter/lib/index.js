/**
 * @deepwhale-cn/dsh-cn-doc-formatter — 中文公文排版
 *
 * 把 GB/T 9704-2012 党政机关公文格式的排版方法注册为 DSH skill，
 * 使 agent 在需要生成公文时能按规范产出 .docx / .pdf / .txt。
 *
 * ── 关于字体（本插件最重要的设计约束）────────────────────────────────
 * 本插件**不随包分发任何字体文件**。公文规范要求的仿宋（方正仿宋等）是商业字体，
 * 其授权允许在文档中使用，但不允许再分发字体文件本身。因此这里是「排版引擎」，
 * 字体由用户自备，通过环境变量或系统字体目录提供：
 *
 *   DSH_CN_FANGSONG       仿宋常规体文件的完整路径（最高优先）
 *   DSH_CN_FANGSONG_BOLD  仿宋加粗体（可选）
 *   DSH_CN_FONT_DIR       一个目录，脚本在其中按文件名查找
 *
 * 找不到时的行为见 skill/scripts/pdf_formatter.py 的 register_fonts()：
 * 退回系统宋体并在 stderr 打印可操作的指引，不会静默失败。
 *
 * ── 技能标识 ────────────────────────────────────────────────────────
 * SKILL_NAME 取 'cn-doc-formatter' 而非 'chinese-doc-formatter'：后者是很多用户
 * 本地已有的私有技能名，重名会与用户自己的技能冲突。加 cn- 前缀以示这是插件内嵌版本。
 *
 * ── 与官方 API 的约定 ───────────────────────────────────────────────
 * 依赖 `ctx.skills`（由 @deepseek-ai/dsh-skill 提供）。缺失时插件不做任何事，
 * 不会影响 profile 启动。
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

/** 本包根目录（lib/ 的上一级） */
const packageRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
/** 随包分发的 skill 与脚本所在目录 */
const skillDir = join(packageRoot, 'skill');

/** 技能正文里用来占位脚本目录的标记 —— 运行期替换成真实完整路径 */
const SKILL_DIR_PLACEHOLDER = '<skill目录>';

export const name = 'cn-doc-formatter';
export const inject = ['skills'];

/** 技能标识：kebab-case。刻意避开 'chinese-doc-formatter'，见文件头说明 */
const SKILL_NAME = 'cn-doc-formatter';

/** 随包分发的 skill 目录完整路径（安装后位置由加载器决定） */
export function skillDirPath() {
  return skillDir;
}

function skillBody() {
  const raw = readFileSync(join(skillDir, 'chinese-doc-formatter.md'), 'utf-8');
  // 把占位符替换为真实路径：用户安装到任何位置都能照文档直接跑脚本
  return raw.split(SKILL_DIR_PLACEHOLDER).join(skillDir);
}

export function apply(ctx) {
  // skills 服务缺失时静默跳过：这是一个可选能力，不应阻断 profile 启动
  if (!ctx.skills || typeof ctx.skills.register !== 'function') {
    ctx.logger?.warn?.('[cn-doc-formatter] 未找到 skills 服务，跳过技能注册');
    return;
  }

  let content;
  try {
    content = skillBody();
  } catch (error) {
    ctx.logger?.error?.(`[cn-doc-formatter] 读取技能正文失败: ${String(error)}`);
    return;
  }

  ctx.skills.register({
    name: SKILL_NAME,
    // 来源标记：'bundled' = 随插件分发的内嵌技能（区别于磁盘上的 project/user 技能）
    source: 'bundled',
    description:
      '中文公文排版生成器。按 GB/T 9704-2012 规范生成 Word(.docx)、PDF、TXT 中文文书，' +
      '涵盖字体字号、行距、页边距、标题层级与页码。涉及排版、格式、文书、公文、' +
      '字体、行距等需求时使用。',
    whenToUse:
      '需要生成或排版中文公文/正式文书时使用——通知、报告、函、决定、意见等。' +
      '用户提到「排版」「格式」「docx」「pdf」「word」「文书」「公文」「字体」「行距」' +
      '时也必须使用。',
    content,
  });

  ctx.logger?.info?.(`[cn-doc-formatter] 已注册技能 ${SKILL_NAME}`);
}
