#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_output.py — 输出自检

生成 docx / pdf 后核对是否真的符合本 skill 的排版规范。
原先没有这一步，字体名写错、页边距没生效这类问题不会被发现。

用法
----
  python verify_output.py --dir <输出目录> [--title <标题>]

退出码 0 = 全部通过，1 = 有不符合项。
"""
import argparse
import glob
import os
import sys

# 规范值（与 SKILL.md 保持一致）
SPEC = {
    'margin_top_cm': 3.7,
    'margin_bottom_cm': 3.5,
    'margin_left_cm': 2.8,
    'margin_right_cm': 2.6,
    'title_pt': 22,          # 二号
    'h1_pt': 16,             # 三号
    'body_pt': 14,           # 四号
    'title_leading_pt': (33, 36),
    'body_leading_pt': 28,
    'tol': 0.15,             # 容差
}

PASS, FAIL, WARN = '✅', '❌', '⚠️ '


def check_docx(path):
    """核对 docx 的页面设置与字号、行距、字体"""
    issues, notes = [], []
    try:
        from docx import Document
        from docx.oxml.ns import qn
    except ImportError:
        return ['未安装 python-docx，跳过 docx 检查'], []

    d = Document(path)
    s = d.sections[0]

    # 页边距
    for name, got, want in (
        ('上边距', s.top_margin.cm, SPEC['margin_top_cm']),
        ('下边距', s.bottom_margin.cm, SPEC['margin_bottom_cm']),
        ('左边距', s.left_margin.cm, SPEC['margin_left_cm']),
        ('右边距', s.right_margin.cm, SPEC['margin_right_cm']),
    ):
        if abs(got - want) > SPEC['tol']:
            issues.append(f'{name} {got:.2f}cm，应为 {want}cm')
        else:
            notes.append(f'{name} {got:.2f}cm ✓')

    # 段落：字号 / 行距 / 字体
    kinds = {}
    fonts = set()
    for p in d.paragraphs:
        t = p.text.strip()
        if not t or not p.runs:
            continue
        r = p.runs[0]
        sz = r.font.size.pt if r.font.size else None
        bold = bool(r.font.bold)
        leading = None
        pPr = p._element.find(qn('w:pPr'))
        if pPr is not None:
            sp = pPr.find(qn('w:spacing'))
            if sp is not None and sp.get(qn('w:line')):
                leading = int(sp.get(qn('w:line'))) / 20.0    # twip → pt
        rPr = r._element.find(qn('w:rPr'))
        if rPr is not None:
            rf = rPr.find(qn('w:rFonts'))
            if rf is not None:
                ea = rf.get(qn('w:eastAsia'))
                if ea:
                    fonts.add(ea)
        kinds.setdefault((sz, bold), []).append((t[:22], leading))

    # 标题：22pt 加粗
    if not any(sz == SPEC['title_pt'] and b for (sz, b) in kinds):
        issues.append(f'未找到 {SPEC["title_pt"]}pt 加粗的标题（二号）')
    else:
        notes.append(f'标题 {SPEC["title_pt"]}pt 加粗 ✓')

    # 一级标题：16pt 加粗
    if not any(sz == SPEC['h1_pt'] and b for (sz, b) in kinds):
        issues.append(f'未找到 {SPEC["h1_pt"]}pt 加粗的一级标题（三号）')
    else:
        notes.append(f'一级标题 {SPEC["h1_pt"]}pt 加粗 ✓')

    # 正文：14pt 不加粗，行距 28pt
    body_ok = False
    for (sz, b), items in kinds.items():
        if sz == SPEC['body_pt'] and not b:
            leads = [l for _t, l in items if l is not None]
            if leads:
                avg = sum(leads) / len(leads)
                if abs(avg - SPEC['body_leading_pt']) > 1.5:
                    issues.append(f'正文行距 {avg:.1f}pt，应为 {SPEC["body_leading_pt"]}pt')
                else:
                    notes.append(f'正文 {sz}pt / 行距 {avg:.0f}pt ✓')
                    body_ok = True
            else:
                issues.append('正文段落未设置固定行距')
            break
    if not body_ok and not any(i.startswith('正文') for i in issues):
        issues.append(f'未找到 {SPEC["body_pt"]}pt 不加粗的正文段落（四号）')

    # 字体一致性
    if len(fonts) > 1:
        issues.append(f'全文出现多种字体：{sorted(fonts)}，规范要求统一仿宋')
    elif fonts:
        notes.append(f'全文统一字体：{sorted(fonts)[0]} ✓')
    else:
        warnings_only = True

    # 字体是否本机真实存在（避免 Word 静默替换）
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from docx_formatter import FOUND_FONTS
        for f in fonts:
            if f and f not in FOUND_FONTS:
                issues.append(f'字体「{f}」本机不存在，Word 会替换为其他字体')
    except Exception:
        pass

    return issues, notes


def check_pdf(path):
    """核对 PDF 是否嵌入并使用仿宋"""
    issues, notes = [], []
    try:
        from pypdf import PdfReader
    except ImportError:
        return ['未安装 pypdf，跳过 pdf 检查'], []

    r = PdfReader(path)
    notes.append(f'页数 {len(r.pages)}')
    embedded = set()
    for pg in r.pages:
        try:
            res = pg.get('/Resources')
            fonts = res.get('/Font') if res else None
            if fonts:
                for _k, v in fonts.items():
                    o = v.get_object()
                    base = str(o.get('/BaseFont', ''))
                    if base:
                        embedded.add(base)
        except Exception:
            pass
    if embedded:
        names = ', '.join(sorted(embedded)[:6])
        notes.append(f'嵌入字体 {len(embedded)} 种：{names}')
        if not any('Fang' in x or '仿宋' in x or 'Song' in x for x in embedded):
            issues.append(f'PDF 未使用仿宋字体，实际：{sorted(embedded)}')
    else:
        issues.append('PDF 未检出嵌入字体')

    # 尺寸应为 A4
    try:
        mb = r.pages[0].mediabox
        w_cm, h_cm = float(mb.width) / 28.3465, float(mb.height) / 28.3465
        if abs(w_cm - 21.0) > 0.3 or abs(h_cm - 29.7) > 0.3:
            issues.append(f'页面尺寸 {w_cm:.1f}×{h_cm:.1f}cm，应为 A4 21.0×29.7cm')
        else:
            notes.append(f'页面 A4 {w_cm:.1f}×{h_cm:.1f}cm ✓')
    except Exception:
        pass

    return issues, notes


def main():
    ap = argparse.ArgumentParser(description='排版输出自检')
    ap.add_argument('--dir', required=True, help='输出目录')
    a = ap.parse_args()

    d = a.dir
    docx = glob.glob(os.path.join(d, '*.docx'))
    pdf = glob.glob(os.path.join(d, '*.pdf'))
    txt = glob.glob(os.path.join(d, '*.txt'))

    all_issues = []
    print('════ 排版输出自检 ════')
    print(f'  目录：{d}')
    print(f'  docx {len(docx)} / pdf {len(pdf)} / txt {len(txt)}')
    print()

    for f in docx:
        print(f'  ── {os.path.basename(f)}')
        iss, notes = check_docx(f)
        for n in notes:
            print(f'     {PASS} {n}')
        for i in iss:
            print(f'     {FAIL} {i}')
        all_issues += iss
        print()

    for f in pdf:
        print(f'  ── {os.path.basename(f)}')
        iss, notes = check_pdf(f)
        for n in notes:
            print(f'     {PASS} {n}')
        for i in iss:
            print(f'     {FAIL} {i}')
        all_issues += iss
        print()

    if not docx and not pdf:
        print('  ⚠️  目录下没有 docx / pdf，无法自检')
        return 1

    print('════ 结果 ════')
    if all_issues:
        print(f'  {FAIL} {len(all_issues)} 项不符合规范：')
        for i in all_issues:
            print(f'     · {i}')
        return 1
    print(f'  {PASS} 全部符合排版规范')
    return 0


if __name__ == '__main__':
    sys.exit(main())
