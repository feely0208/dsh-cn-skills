/**
 * labeling-meta.mjs —— 校验一个真实文件里的 AIGC 文件元数据隐式标识
 *
 * 依据 GB 45438—2025 附录 E（规范性）与 6.1。
 * 只做校验取证，不做合规定性。
 *
 * 用法：
 *   node labeling-meta.mjs <文件路径>
 *   node labeling-meta.mjs --json <文件路径>
 *
 * 退出码：0 = 通过；1 = 发现问题；2 = 用法错误
 */

import { readFileSync } from 'node:fs';

/* ── 附录 E 规定的 7 个要素（规范性，字段名必须逐字一致） ───────────── */
const FIELDS = [
  ['Label', '生成合成标签要素'],
  ['ContentProducer', '生成合成服务提供者要素'],
  ['ProduceID', '内容制作编号要素'],
  ['ReservedCode1', '预留字段 1'],
  ['ContentPropagator', '内容传播服务提供者要素'],
  ['PropagateID', '内容传播编号要素'],
  ['ReservedCode2', '预留字段 2'],
];
const REQUIRED_FIELDS = FIELDS.filter(([k]) => !k.startsWith('Reserved'));

const args = process.argv.slice(2);
const asJson = args.includes('--json');
const target = args.find((a) => !a.startsWith('--'));

if (!target) {
  console.error('用法：node labeling-meta.mjs [--json] <文件路径>');
  process.exit(2);
}

const findings = [];
const notes = [];
const add = (level, clause, message) => findings.push({ level, clause, message });

let raw;
try {
  raw = readFileSync(target);
} catch (error) {
  console.error(`无法读取文件：${target}\n${String(error)}`);
  process.exit(2);
}

// latin1 是字节到字符的一一映射，用于在二进制文件里做 ASCII 字段名检索
const text = raw.toString('latin1');

/* ── 1. 存在性：字段名称或关键词中应包含 "AIGC"（附录 E a） ───────────── */
const aigcHits = [...text.matchAll(/AIGC/g)].length;
if (aigcHits === 0) {
  add('error', 'GB 45438 附录E a)', '文件元数据中未找到含 "AIGC" 的隐式标识扩展字段');
} else {
  notes.push(`"AIGC" 出现 ${aigcHits} 次`);
}

/* 唯一性（6.1 c）的判定放在下面解析出可解析块之后再下结论 —— 按 "AIGC"
   的裸出现次数猜会误判：一份 XMP 里它可能同时作为元素名和 JSON 键出现。 */

/* ── 2. 取出候选 JSON 块 ──────────────────────────────────────────── */
function unescape(structural) {
  return structural
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/\\"/g, '"')
    .replace(/\\\//g, '/');
}

/** 从 start 处的 '{' 起做括号配对，跳过字符串内部 */
function matchBraces(s, start) {
  let depth = 0;
  let inStr = false;
  for (let i = start; i < s.length; i += 1) {
    const c = s[i];
    if (inStr) {
      if (c === '\\') i += 1;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') inStr = true;
    else if (c === '{') depth += 1;
    else if (c === '}') {
      depth -= 1;
      if (depth === 0) return s.slice(start, i + 1);
    }
  }
  return null;
}

/* 收集**所有**可解析的 AIGC 块 —— 用于唯一性判定（6.1 c）。
   按出现次数猜会误判（一份 XMP 里 "AIGC" 可能作为元素名 + JSON 键出现多次），
   所以精确统计"能解析成合规结构"的块数。 */
const normalized = unescape(text);
const blocks = [];
let cursor = 0;
for (;;) {
  const keyIdx = normalized.indexOf('"AIGC"', cursor);
  if (keyIdx < 0) break;
  cursor = keyIdx + 6;
  // 取 "AIGC" 之前最近的一个 '{' —— 即外层对象，形如 {"AIGC":{...}}
  const braceStart = normalized.lastIndexOf('{', keyIdx);
  if (braceStart < 0) continue;
  const block = matchBraces(normalized, braceStart);
  if (!block) continue;
  try {
    const obj = JSON.parse(block);
    const inner = obj && typeof obj === 'object' ? (obj.AIGC ?? obj.aigc) : null;
    if (inner && typeof inner === 'object') blocks.push(inner);
  } catch {
    /* 单个块解析失败不在此处报错，统一在下面按总数判断 */
  }
}

const parsed = blocks[0] ?? null;

if (aigcHits > 0 && blocks.length === 0) {
  // 找到了 "AIGC" 却解析不出合规结构：要么格式不对，要么需要人工确认。
  // 判为 error 而非 warn —— 标为 warn 会让退出码保持 0，把「没验成」伪装成「没问题」。
  add(
    'error',
    'GB 45438 附录E b)',
    '未能解析出完整的 AIGC JSON 块：需人工确认字段结构与转义是否符合附录 E',
  );
}

if (blocks.length > 1) {
  // 6.1 c 是「应」，不是「宜」—— 叠加多份就是违规，必须影响退出码
  add(
    'error',
    'GB 45438 6.1 c)',
    `检出 ${blocks.length} 份可解析的文件元数据隐式标识，同一文件应仅保留一份（导出/复制时应覆盖而非追加）`,
  );
}

/* ── 4. 要素齐备性与类型（附录 E c~i） ─────────────────────────────── */
if (parsed && typeof parsed === 'object') {
  for (const [key, label] of FIELDS) {
    const v = parsed[key];
    if (v === undefined) {
      const level = REQUIRED_FIELDS.some(([k]) => k === key) ? 'error' : 'info';
      add(level, 'GB 45438 附录E', `缺少要素 ${key}（${label}）`);
      continue;
    }
    if (typeof v !== 'string') {
      add('error', 'GB 45438 附录E', `要素 ${key} 的类型应为字符串，实际为 ${typeof v}`);
    }
  }

  /* ── 5. Label 取值（附录 E c） ──────────────────────────────────── */
  const label = parsed.Label;
  if (label !== undefined) {
    if (!['1', '2', '3'].includes(String(label))) {
      add('error', 'GB 45438 附录E c)', `Label 取值应为 "1"/"2"/"3"，实际为 ${JSON.stringify(label)}`);
    } else {
      const meaning = { 1: '属于人工智能生成合成', 2: '可能为', 3: '疑似为' }[String(label)];
      notes.push(`Label = "${label}"（${meaning}）`);
    }
  }

  /* ── 6. 字符集（附录 E j） ─────────────────────────────────────── */
  const allowed = /^[\x21\x23-\x5B\x5D-\x7E]*$/;
  for (const [key] of FIELDS) {
    if (typeof parsed[key] === 'string' && !allowed.test(parsed[key])) {
      add(
        'warn',
        'GB 45438 附录E j)',
        `要素 ${key} 的值含 GB 18030—2022 码位 0x21、0x23~0x5B、0x5D~0x7E 之外的字符`,
      );
    }
  }

  /* ── 7. 首次写入时两两一致（附录 E 注 1） ────────────────────────── */
  const { ContentProducer: cp, ContentPropagator: cg, ProduceID: pi, PropagateID: pg } = parsed;
  if (cp && cg && cp !== cg) {
    notes.push('ContentPropagator 与 ContentProducer 不一致（若已被传播平台改写则属正常）');
  }
  if (pi && pg && pi !== pg) {
    notes.push('PropagateID 与 ProduceID 不一致（若已被传播平台改写则属正常）');
  }
}

/* ── 输出 ─────────────────────────────────────────────────────────── */
const levelRank = { error: 0, warn: 1, info: 2 };
findings.sort((a, b) => levelRank[a.level] - levelRank[b.level]);

if (asJson) {
  console.log(JSON.stringify({ file: target, aigcOccurrences: aigcHits, parsed, notes, findings }, null, 2));
} else {
  console.log(`\n文件：${target}`);
  console.log(`大小：${raw.length} 字节`);
  console.log('─'.repeat(60));
  if (notes.length) {
    console.log('信息：');
    for (const n of notes) console.log(`  · ${n}`);
  }
  if (findings.length === 0) {
    console.log('\n✅ 文件元数据隐式标识格式检查通过（依据 GB 45438—2025 附录 E）');
  } else {
    console.log('\n发现：');
    const tag = { error: '❌', warn: '⚠️ ', info: 'ℹ️ ' };
    for (const f of findings) console.log(`  ${tag[f.level]} [${f.clause}] ${f.message}`);
  }
  console.log('\n注：本脚本只校验格式与要素，不判断该文件是否"应当"带标识。');
}

process.exit(findings.some((f) => f.level === 'error') ? 1 : 0);
