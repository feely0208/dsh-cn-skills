#!/usr/bin/env python3
"""
党政机关公文排版格式生成器 — 纯文本文件 (.txt)
保留标题层级结构，无格式标记
"""

import argparse
import os
import sys


def generate_txt(args):
    """生成纯文本文件"""
    output_path = args.output
    if not os.path.exists(output_path):
        os.makedirs(output_path)

    filename = args.filename or '公文.txt'
    filepath = os.path.join(output_path, filename)

    lines = []

    # 版头信息
    if args.fen_hao:
        lines.append(args.fen_hao)
    if args.mi_ji:
        lines.append(args.mi_ji)
    if args.jin_ji_chengdu:
        lines.append(args.jin_ji_chengdu)
    if args.fa_wen_zi_hao:
        lines.append(args.fa_wen_zi_hao)
    # 标题
    if args.title:
        lines.append('')
        lines.append(args.title)
        lines.append('')

    # 正文
    if args.body:
        for kind, payload in split_table_blocks(args.body):
            if kind == 'table':
                # 纯文本表格：按列宽对齐（中文字符按 2 宽计算）
                ncol = max(len(r) for r in payload)
                widths = [0] * ncol
                for row in payload:
                    for ci, c in enumerate(row):
                        w = sum(2 if ord(ch) > 127 else 1 for ch in c)
                        widths[ci] = max(widths[ci], w)

                def pad(s, w):
                    n = sum(2 if ord(ch) > 127 else 1 for ch in s)
                    return s + ' ' * max(0, w - n)

                for ri, row in enumerate(payload):
                    cells = [pad(row[ci] if ci < len(row) else '', widths[ci]) for ci in range(ncol)]
                    lines.append('  ' + '  '.join(cells).rstrip())
                    if ri == 0:
                        lines.append('  ' + '-' * (sum(widths) + 2 * (ncol - 1)))
                lines.append('')
                continue
            line = payload.strip()
            if not line:
                continue
            # 检测标题级别（与 docx/pdf 脚本保持一致的严格规则）
            if is_heading(line):
                lines.append(line)
                lines.append('')
            else:
                lines.append(line)
                lines.append('')

    # 附件说明
    if args.attachment:
        lines.append('')
        lines.append(args.attachment)
        lines.append('')

    # 发文机关署名和日期
    if args.sender or args.date:
        lines.append('')
        lines.append('')
        if args.sender:
            lines.append(args.sender)
        if args.date:
            lines.append(args.date)

    # 写入文件
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f'纯文本文件已生成: {filepath}')
    return filepath


def is_heading(line):
    """严格检测各类标题：一、/（一）/1. /（1）"""
    if line and line[0] in '一二三四五六七八九十' and len(line) > 1 and line[1] == '、':
        return True
    if (line and line.startswith('（') and len(line) >= 4
            and line[1] in '一二三四五六七八九十' and line[2] == '）'):
        return True
    if line and line[:1].isdigit() and len(line) >= 2 and line[1] in '.．':
        return True
    if (line and line.startswith('（') and len(line) >= 4
            and line[1].isdigit() and line[2] == '）'):
        return True
    return False


def _table_sep(line):
    """markdown 表格的分隔行（|---|---|）。"""
    import re as _re
    return bool(_re.match(r'^\s*\|[\s:|-]+\|\s*$', line))


def split_table_blocks(body):
    """把正文切成 [('line', 文本) | ('table', [[单元格,…], …])]。

    约定：**连续以 | 开头**的行视为一个 markdown 表格（含可选分隔行）。
    这样 md_adapter 原样透传 md 表格时，下游就能渲染成真表格；
    不在表格里的 | 行也照样按表格处理（旧行为是拍平，新行为更好）。
    """
    blocks, buf = [], []

    def flush():
        if not buf:
            return
        rows = []
        for r in buf:
            if _table_sep(r):
                continue
            cells = [c.strip() for c in r.strip().strip('|').split('|')]
            if any(cells):
                rows.append(cells)
        if rows:
            blocks.append(('table', rows))

    for raw in body.split('\n'):
        if raw.strip().startswith('|'):
            buf.append(raw.rstrip())
            continue
        flush()
        buf = []
        blocks.append(('line', raw))
    flush()
    return blocks


def main():
    parser = argparse.ArgumentParser(description='党政机关公文排版格式生成器 (.txt)')
    parser.add_argument('--output', required=True, help='输出目录')
    parser.add_argument('--filename', default='公文.txt', help='文件名')
    parser.add_argument('--title', default='', help='标题')
    parser.add_argument('--body', default='', help='正文内容（多行用换行分隔）')
    parser.add_argument('--sender', default='', help='发文机关署名')
    parser.add_argument('--date', default='', help='成文日期')
    parser.add_argument('--attachment', default='', help='附件说明')
    parser.add_argument('--fen_hao', default='', help='份号')
    parser.add_argument('--mi_ji', default='', help='密级')
    parser.add_argument('--jin_ji_chengdu', default='', help='紧急程度')
    parser.add_argument('--fa_wen_zi_hao', default='', help='发文字号')
    parser.add_argument('--shang_xing_wen', action='store_true',
                        help='上行文（发文字号左空一字）')

    args = parser.parse_args()
    generate_txt(args)


if __name__ == '__main__':
    main()
