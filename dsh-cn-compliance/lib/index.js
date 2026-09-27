/**
 * dsh-cn-compliance — 中国大陆对外内容合规红线审核
 *
 * 把一套面向中国大陆市场的合规审核方法注册为 DSH skill，使 agent 在写官网文案、
 * 公开文档、App 内文案、宣传物料时能主动查出风险。
 *
 * ── 覆盖的合规面 ────────────────────────────────────────────────────
 *  · A 类  网络工具用语（VPN / 翻墙 / 科学上网 等，绝对红线）
 *  · A- 类 擦边词（内网穿透 / 隧道，需语境判断）
 *  · B 类  广告法极限用语（国家级 / 唯一 / 最好 等）
 *  · C 类  绝对化承诺（永久免费 / 零风险 / 绝不泄露）
 *  · D 类  地图与领土
 *  · E 类  数据与隐私承诺
 *  · F 类  AI 生成内容标识
 *  · G 类  资质与备案
 *  · H 类  比较与贬低
 *  · I 类  内部文件公网暴露（信息安全 + 合规双风险）
 *
 * ── 关于词表与误报 ──────────────────────────────────────────────────
 * 本插件**不内置政治敏感词表**（避免插件自身含敏感内容），C 类需人工审或
 * 使用第三方工具。词表规则的重点不在"列了多少词"，而在**误报规避**：
 * 「穿透」单独出现是 UI 术语（点击穿透），只在网络语境同现时才判风险；
 * 「100%」要避开 CSS 的 `0%,100%` 与 `width:100%`。这两条是扫描结果可用与否的分水岭
 * ——误报多了，人就再也不看报告了。
 *
 * ── 与官方 API 的约定 ───────────────────────────────────────────────
 * 依赖 `ctx.skills`（由 @deepseek-ai/dsh-skill 提供）与 `ctx.tools`（可选，
 * 用于把扫描脚本暴露成模型工具）。两者缺失时插件不做任何事，不会影响 profile 启动。
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

export const name = 'cn-compliance';
export const inject = ['skills'];

/** 技能标识：kebab-case，避免与其它包重名 */
const SKILL_NAME = 'cn-compliance-audit';

/** 实际扫描脚本的绝对路径（随包分发；安装后位置由加载器决定） */
export function scanScriptPath() {
  return join(skillDir, 'scan.sh');
}

function skillBody() {
  const raw = readFileSync(join(skillDir, 'compliance-audit.md'), 'utf-8');
  // 把占位符替换为真实路径：用户安装到任何位置都能照文档直接跑脚本
  return raw.split(SCAN_PATH_PLACEHOLDER).join(scanScriptPath());
}

export function apply(ctx) {
  // skills 服务缺失时静默跳过：这是一个可选能力，不应阻断 profile 启动
  if (!ctx.skills || typeof ctx.skills.register !== 'function') {
    ctx.logger?.warn?.('[cn-compliance] 未找到 skills 服务，跳过技能注册');
    return;
  }

  let content;
  try {
    content = skillBody();
  } catch (error) {
    ctx.logger?.error?.(`[cn-compliance] 读取技能正文失败: ${String(error)}`);
    return;
  }

  ctx.skills.register({
    name: SKILL_NAME,
    // 来源标记：'bundled' = 随插件分发的内嵌技能（区别于磁盘上的 project/user 技能）
    source: 'bundled',
    description:
      '中国大陆对外内容合规红线审核：扫描网络工具用语、广告法极限词、绝对化承诺、' +
      '内部文件公网暴露等敏感项，并给出修复原则。适用于官网、公开文档、App 内文案、' +
      '公众号与宣传物料。',
    whenToUse:
      '在发布或修改面向中国大陆用户的对外内容前后使用——官网页面、GitHub 公开文档、' +
      'App 内用户可见文案、公众号推文、宣传物料。用户提到「合规」「敏感词」「红线」' +
      '「审核一下」「会不会有问题」时也应使用。',
    content,
  });

  ctx.logger?.info?.(`[cn-compliance] 已注册技能 ${SKILL_NAME}`);

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
