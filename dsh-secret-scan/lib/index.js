/**
 * dsh-secret-scan — 密钥与敏感信息扫描
 *
 * 把一套「提交前/发布前扫一遍密钥」的方法注册为 DSH skill。
 * 它是这一组技能里唯一**通用**的（不限中国大陆）—— "密钥进了仓库"是所有团队都会踩的坑。
 *
 * ── 它管什么、不管什么 ──────────────────────────────────────────────
 *   管：高置信令牌、私钥/证书文件、凭据文件是否被 git 跟踪、配置里的敏感赋值、
 *       内网 IP 与内部域名。
 *   不管：内部文件的**公网暴露面**（那是 dsh-cn-compliance 的 I 类）。
 *   两者的交集是"内部信息"，但一个看暴露面，一个看版本控制。
 *
 * ── 两条刻意的设计 ──────────────────────────────────────────────────
 *  1. **输出默认打码**（只留前后几位）。扫描工具把完整密钥打进终端/日志，
 *     等于换个地方又泄露一次 —— 所以要看全必须显式 --reveal。
 *  2. **技能正文里，处置顺序比扫描本身更重要**：先轮换密钥，再清理代码。
 *     删代码不会让已泄露的密钥失效（还在 git 历史、日志、远端副本里）。
 *     一个只教人"删掉就好"的工具，是在帮倒忙。
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

export const name = 'secret-scan';
export const inject = ['skills'];

/** 技能标识：kebab-case，避免与其它包重名 */
const SKILL_NAME = 'secret-scan';

/** 实际扫描脚本的绝对路径（随包分发；安装后位置由加载器决定） */
export function scanScriptPath() {
  return join(skillDir, 'scan.sh');
}

function skillBody() {
  const raw = readFileSync(join(skillDir, 'secret-scan.md'), 'utf-8');
  // 把占位符替换为真实路径：用户安装到任何位置都能照文档直接跑脚本
  return raw.split(SCAN_PATH_PLACEHOLDER).join(scanScriptPath());
}

export function apply(ctx) {
  // skills 服务缺失时静默跳过：这是一个可选能力，不应阻断 profile 启动
  if (!ctx.skills || typeof ctx.skills.register !== 'function') {
    ctx.logger?.warn?.('[secret-scan] 未找到 skills 服务，跳过技能注册');
    return;
  }

  let content;
  try {
    content = skillBody();
  } catch (error) {
    ctx.logger?.error?.(`[secret-scan] 读取技能正文失败: ${String(error)}`);
    return;
  }

  ctx.skills.register({
    name: SKILL_NAME,
    // 来源标记：'bundled' = 随插件分发的内嵌技能（区别于磁盘上的 project/user 技能）
    source: 'bundled',
    description:
      '密钥与敏感信息扫描：提交前/发布前找出代码里的 API Key、令牌、私钥、凭据文件与内部域名。' +
      '输出默认打码，退出码可作 pre-commit / CI 卡口。',
    whenToUse:
      '提交前、开源前、发布前、把仓库转公开前，以及交接/外包交付时清点。' +
      '怀疑泄露后做排查时也应使用（此时第一件事是**轮换密钥**，不是删代码）。' +
      '用户提到「密钥泄露」「AK/SK」「token 提交了」「.env」「开源前检查」时同样适用。',
    content,
  });

  ctx.logger?.info?.(`[secret-scan] 已注册技能 ${SKILL_NAME}`);

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
