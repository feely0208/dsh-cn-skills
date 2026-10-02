#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
md_adapter.py — Markdown → 党政机关公文正文格式 转换器

背景
----
本 skill 原有的 docx/pdf 脚本只接受「已按公文层级排好」的纯文本
（一、/（一）/ 1. /（1））。实际使用中内容常以 Markdown 写就，
直接喂进去会整篇被当作正文，层级丢失。

本模块把 Markdown 转成脚本可识别的公文正文格式：
  # 标题          → 由调用方作为 --title 传入（此处丢弃）
  ## 一、小节      → 一、小节          （一级标题）
  ### 1.1 小节     → （一）小节        （二级标题）
  #### 更深        → 1. 小节           （三级标题）
  - 列表项         → 正文（保留缩进）
  | 表格 |        → 逐行转成「表头：值」的正文句子
  > 引用块         → 正文（连续行自动合并，避免断句处出现孤立标点）
  其余             → 正文

用法
----
  from md_adapter import md_to_body
  body = md_to_body(open('x.md', encoding='utf-8').read())
"""
import re

# 一级标题中文序号
CN = ['〇', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
      '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
      '二十一', '二十二', '二十三', '二十四', '二十五', '二十六', '二十七', '二十八', '二十九', '三十']
# 二级标题中文序号（括号内）
SUBCN = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
         '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
         '二十一', '二十二', '二十三', '二十四', '二十五', '二十六', '二十七', '二十八', '二十九', '三十']


def clean_inline(t: str) -> str:
    """去掉行内 Markdown 标记，保留纯文本"""
    t = re.sub(r'\*\*([^*]+)\*\*', r'\1', t)
    t = re.sub(r'__([^_]+)__', r'\1', t)
    t = re.sub(r'\*([^*\n]+)\*', r'\1', t)
    t = re.sub(r'`([^`]+)`', r'\1', t)
    t = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', t)
    return t.strip()


def join_soft_breaks(md: str) -> str:
    """合并软换行：同一段的连续普通行拼成一行。

    源文档常在同一段内手动折行；若逐行当独立段落，
    会在断句处留下孤立标点（例如单独一行的「、」）。
    引用块（> 开头）同样并入上一段。
    """
    out, buf = [], ''
    special = re.compile(r'^(#{1,6}\s|\s*[-*+]\s|\s*\d+[.、]\s|\s*\||\s*---|\s*```)')

    def flush():
        nonlocal buf
        if buf:
            out.append(buf)
            buf = ''

    for raw in md.split('\n'):
        line = raw.rstrip()
        if not line.strip():
            flush()
            out.append('')
            continue
        if line.lstrip().startswith('>'):
            txt = line.lstrip()[1:].strip()
            if not txt:
                flush()
                continue
            buf = (buf + txt) if buf else txt
            continue
        if special.match(line):
            flush()
            out.append(line)
            continue
        buf = (buf + line.strip()) if buf else line.strip()
    flush()
    return '\n'.join(out)


def md_to_body(md: str, drop_meta: bool = False) -> str:
    """Markdown → 公文正文。

    drop_meta=True 时丢弃开头的元信息行（用途/编制日期等），
    用于「文档内不出现自指性说明」的场景。
    """
    md = join_soft_breaks(md)
    lines = md.split('\n')
    out = []
    h1 = h2 = 0
    table_rows = []
    head_seen = False

    def flush_table():
        nonlocal table_rows
        if not table_rows:
            return
        # ── 表格：**原样保留**（markdown 管道形式）──────────────────────
        # 原来这里把表格拍平成「表头：值；表头：值。」—— 那是本 skill 早期没有
        # 表格支持时的权宜做法。2026-10-02 起 docx / pdf / txt 三个 formatter
        # 都会把连续 | 行渲染成**真表格**，所以这里透传即可（拍平反而丢信息）。
        out.extend(table_rows)
        table_rows = []

    for raw in lines:
        line = raw.rstrip()

        if line.strip().startswith('|'):
            table_rows.append(line)
            continue
        elif table_rows:
            flush_table()

        if not line.strip() or re.match(r'^\s*---+\s*$', line):
            continue
        if line.strip().startswith('```'):
            continue

        m = re.match(r'^(#{1,6})\s+(.*)$', line)
        if m:
            level, text = len(m.group(1)), clean_inline(m.group(2))
            if level == 1:
                continue                                  # 作为文档标题另行传入
            if level == 2:
                h1 += 1
                h2 = 0
                text = re.sub(r'^[〇一二三四五六七八九十]+、\s*', '', text)
                out.append(f'{CN[h1] if h1 < len(CN) else h1}、{text}')
            elif level == 3:
                h2 += 1
                text = re.sub(r'^\d+(\.\d+)*\s*', '', text)
                out.append(f'（{SUBCN[h2] if h2 < len(SUBCN) else h2}）{text}')
            else:
                text = re.sub(r'^\d+(\.\d+)*\s*', '', text)
                out.append(f'1. {text}')
            continue

        m = re.match(r'^\s*[-*+]\s+(.*)$', line) or re.match(r'^\s*\d+[.、]\s+(.*)$', line)
        if m:
            t = clean_inline(m.group(1))
            if t:
                out.append('　　' + t)
            continue

        t = clean_inline(line)
        if t:
            # 元信息（用途/编制日期/编制说明/说明）在 drop_meta 时丢弃
            if drop_meta and re.match(r'^(用途|编制日期|编制说明|说明)\s*[：:]', t):
                continue
            out.append('　　' + t)

    flush_table()
    return '\n'.join(out)


if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser(description='Markdown → 公文正文格式')
    ap.add_argument('--input', required=True, help='输入 .md 文件')
    ap.add_argument('--output', help='输出 .txt（省略则打印到 stdout）')
    ap.add_argument('--drop-meta', action='store_true', help='丢弃开头的元信息行')
    a = ap.parse_args()
    body = md_to_body(open(a.input, encoding='utf-8').read(), drop_meta=a.drop_meta)
    if a.output:
        open(a.output, 'w', encoding='utf-8').write(body)
        print(f'已写出: {a.output}')
    else:
        print(body)
