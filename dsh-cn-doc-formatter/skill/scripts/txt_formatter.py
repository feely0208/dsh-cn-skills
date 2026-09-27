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
        body_lines = args.body.strip().split('\n')
        for line in body_lines:
            line = line.strip()
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
