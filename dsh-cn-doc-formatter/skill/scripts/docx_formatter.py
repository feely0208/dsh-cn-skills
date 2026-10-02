#!/usr/bin/env python3
"""
党政机关公文排版格式生成器 — Word 文档 (.docx)
严格遵循 GB/T 9704-2012 标准
"""

import argparse
import os
import subprocess

from docx import Document
from docx.shared import Pt, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement


# 字号对照（磅 → pt）
FONT_SIZES = {
    '二号': Pt(22),
    '三号': Pt(16),
    '四号': Pt(14),
}

# 全文统一仿宋。按优先级探测，取第一个本机真实存在的字体族名。
#
# ⚠ 2026-09-22 修正（原实现有两个缺陷，导致 docx 声明的字体在任何系统都找不到）：
#   1. 原 _font_installed() 用 `fc-list` 探测 —— macOS 没有这个命令，
#      异常被吞掉后恒返回 False，于是永远走回退分支。已改为直接读字体文件的
#      name 表（fontTools），macOS / Windows / Linux 通用。
#   2. 原回退名写作 'FandolFang'，而该字体真实族名是 'FandolFang R'（带空格与 R）。
#      写错的名字在任何系统都匹配不到，Word 打开会静默替换字体。
#   现在改为逐个候选名实测，避免再写错。
FONT_CANDIDATES = [
    '仿宋_GB2312',    # Windows 标准公文仿宋
    'FangS-SC',       # 方正仿宋（WPS 自带；本插件不随包分发，需用户自备）
    '仿宋',            # Windows 自带仿宋的另一族名
    'FandolFang R',   # macOS 常见仿宋替代（注意真实族名带空格与 R）
    'STFangsong',     # macOS 华文仿宋
    'Songti SC',      # 最后回退：宋体
]

# 本插件**不随包分发字体**（方正仿宋授权不允许再分发字体文件），因此这里既扫系统
# 字体目录，也认用户显式指定的目录 —— 与 pdf_formatter.py 的查找顺序保持一致。
_FONT_SEARCH_DIRS = [
    os.environ.get('DSH_CN_FONT_DIR', ''),                        # 显式指定目录
    os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'fonts'),  # 用户放进插件
    os.path.expanduser('~/Library/Fonts'),                        # macOS 用户字体
    os.path.expanduser('~/.fonts'),                               # Linux 用户字体
    os.path.expanduser('~/.local/share/fonts'),
    os.path.join(os.environ.get('LOCALAPPDATA', '') or '', 'Microsoft', 'Windows', 'Fonts'),
    'C:\\Windows\\Fonts',
    '/System/Library/Fonts',
    '/System/Library/Fonts/Supplemental',
    '/Library/Fonts',
    '/usr/share/fonts',
    '/usr/local/share/fonts',
]


def _iter_font_files():
    exts = ('.ttf', '.otf', '.ttc', '.TTF', '.OTF', '.TTC')
    for d in _FONT_SEARCH_DIRS:
        if not os.path.isdir(d):
            continue
        for root, _dirs, files in os.walk(d):
            for fn in files:
                if fn.endswith(exts):
                    yield os.path.join(root, fn)


def _installed_families():
    """扫描本机字体文件，返回所有真实存在的字体族名。

    直接读文件而不依赖 fc-list，因此在 macOS 上也能正确工作。
    结果带缓存，避免重复解析。
    """
    global _FAMILY_CACHE
    if _FAMILY_CACHE is not None:
        return _FAMILY_CACHE
    fams = set()
    try:
        from fontTools.ttLib import TTFont, TTCollection
    except ImportError:
        _FAMILY_CACHE = fams
        return fams
    for path in _iter_font_files():
        try:
            if path.lower().endswith('.ttc'):
                fonts = TTCollection(path, lazy=True).fonts
            else:
                fonts = [TTFont(path, lazy=True)]
            for t in fonts:
                for r in t['name'].names:
                    if r.nameID in (1, 16):        # 族名 / 排版族名
                        try:
                            fams.add(r.toUnicode().strip())
                        except Exception:
                            pass
        except Exception:
            continue
    _FAMILY_CACHE = fams
    return fams


_FAMILY_CACHE = None

FOUND_FONTS = _installed_families()
CN_FONT = next((f for f in FONT_CANDIDATES if f in FOUND_FONTS), FONT_CANDIDATES[1])

# 首选字体缺失时给出可操作的提示（不静默降级为宋体，否则排版规范不达标）
if CN_FONT != FONT_CANDIDATES[0]:
    _missing = FONT_CANDIDATES[0]
    if _missing not in FOUND_FONTS:
        import sys as _sys
        print(f'[提示] 未找到标准公文仿宋「{_missing}」，已改用「{CN_FONT}」。'
              f'如需完全符合 GB2312 规范，请安装仿宋_GB2312 字体。', file=_sys.stderr)


# 字体映射：(西文字体, 中文字体) — 全文统一仿宋
FONT_MAP = {
    'title':      (CN_FONT, CN_FONT),  # 标题：仿宋加粗
    'body':       (CN_FONT, CN_FONT),  # 正文：仿宋
    'h1':         (CN_FONT, CN_FONT),  # 一级标题：仿宋加粗
    'h2':         (CN_FONT, CN_FONT),  # 二级标题：仿宋加粗
    'h3':         (CN_FONT, CN_FONT),  # 三级标题：仿宋加粗
    'h4':         (CN_FONT, CN_FONT),  # 四级标题：仿宋加粗
    'mi_ji':      (CN_FONT, CN_FONT),  # 版头：仿宋
    'attachment': (CN_FONT, CN_FONT),  # 附件说明：仿宋
    'issuer':     (CN_FONT, CN_FONT),  # 发文机关署名：仿宋
    'page_num':   (CN_FONT, CN_FONT),  # 页码：仿宋
}

# 行距（磅）— 固定值，正文 28 磅，标题 36 磅
LINE_SPACING = {
    'title': 36,
    'body': 28,
}

# 三号字（16pt）的字符宽度（磅），用于缩进换算
CHAR_PT = 16


def set_font(run, font_key, font_size, bold=False):
    """设置 run 字体：西文用 Times New Roman，中文用映射字体"""
    ascii_font, east_asia_font = FONT_MAP[font_key]
    rPr = run._element.get_or_add_rPr()
    for rFonts in rPr.findall(qn('w:rFonts')):
        rPr.remove(rFonts)
    rFonts = OxmlElement('w:rFonts')
    rFonts.set(qn('w:ascii'), ascii_font)
    rFonts.set(qn('w:hAnsi'), ascii_font)
    rFonts.set(qn('w:eastAsia'), east_asia_font)
    rFonts.set(qn('w:cs'), east_asia_font)
    rPr.insert(0, rFonts)
    run.font.size = font_size
    run.font.bold = bold


def set_line_spacing_exact(para, pt):
    """设置固定值行距（28/36 磅），并清除段前段后距"""
    pPr = para._element.get_or_add_pPr()
    spacing = pPr.find(qn('w:spacing'))
    if spacing is None:
        spacing = OxmlElement('w:spacing')
        pPr.append(spacing)
    spacing.set(qn('w:line'), str(int(pt * 20)))       # 磅 → twip
    spacing.set(qn('w:lineRule'), 'exact')
    spacing.set(qn('w:before'), '0')
    spacing.set(qn('w:after'), '0')


def _clear_ind(pPr):
    for ind in pPr.findall(qn('w:ind')):
        pPr.remove(ind)


def set_indent(para, first_line_chars=0, left_chars=0, right_chars=0,
               char_pt=CHAR_PT):
    """按“字符数”设置缩进（Word 优先按 firstLineChars/leftChars/rightChars 计算）"""
    pPr = para._element.get_or_add_pPr()
    _clear_ind(pPr)
    ind = OxmlElement('w:ind')
    if first_line_chars:
        ind.set(qn('w:firstLine'), str(int(first_line_chars * char_pt * 20)))
        ind.set(qn('w:firstLineChars'), str(int(first_line_chars * 100)))
    if left_chars:
        ind.set(qn('w:left'), str(int(left_chars * char_pt * 20)))
        ind.set(qn('w:leftChars'), str(int(left_chars * 100)))
    if right_chars:
        ind.set(qn('w:right'), str(int(right_chars * char_pt * 20)))
        ind.set(qn('w:rightChars'), str(int(right_chars * 100)))
    pPr.append(ind)


def add_styled_paragraph(doc, text, font_key, font_size,
                         line_spacing_pt=28, bold=False,
                         align=WD_ALIGN_PARAGRAPH.JUSTIFY,
                         first_line_chars=None, left_chars=None,
                         right_chars=None):
    """添加带格式的段落"""
    para = doc.add_paragraph()
    para.alignment = align
    set_line_spacing_exact(para, line_spacing_pt)
    if first_line_chars or left_chars or right_chars:
        set_indent(para, first_line_chars=first_line_chars or 0,
                   left_chars=left_chars or 0,
                   right_chars=right_chars or 0,
                   char_pt=font_size.pt)
    run = para.add_run(text)
    set_font(run, font_key, font_size, bold)
    return para


def add_title(doc, text, font_size=FONT_SIZES['二号']):
    """标题：居中，二号加粗，小标宋"""
    return add_styled_paragraph(
        doc, text, 'title', font_size,
        line_spacing_pt=LINE_SPACING['title'],
        align=WD_ALIGN_PARAGRAPH.CENTER,
        bold=True,
    )


def add_body_text(doc, text):
    """正文段落：首行缩进 2 字，四号仿宋"""
    return add_styled_paragraph(
        doc, text, 'body', FONT_SIZES['四号'],
        line_spacing_pt=LINE_SPACING['body'],
        first_line_chars=2,
    )


def add_level1_title(doc, text):
    """一级标题：黑体，三号加粗，左空二字"""
    return add_styled_paragraph(
        doc, text, 'h1', FONT_SIZES['三号'],
        line_spacing_pt=LINE_SPACING['body'],
        first_line_chars=2,
        bold=True,
    )


def add_level2_title(doc, text):
    """二级标题：楷体，三号加粗，左空二字"""
    return add_styled_paragraph(
        doc, text, 'h2', FONT_SIZES['三号'],
        line_spacing_pt=LINE_SPACING['body'],
        first_line_chars=2,
        bold=True,
    )


def add_level3_title(doc, text):
    """三级标题：仿宋，三号加粗，左空二字"""
    return add_styled_paragraph(
        doc, text, 'h3', FONT_SIZES['三号'],
        line_spacing_pt=LINE_SPACING['body'],
        first_line_chars=2,
        bold=True,
    )


def add_level4_title(doc, text):
    """四级标题：仿宋，三号加粗，左空二字"""
    return add_styled_paragraph(
        doc, text, 'h4', FONT_SIZES['三号'],
        line_spacing_pt=LINE_SPACING['body'],
        first_line_chars=2,
        bold=True,
    )


def add_attachment(doc, text):
    """附件说明：仿宋，四号，首行缩进 2 字"""
    return add_styled_paragraph(
        doc, text, 'attachment', FONT_SIZES['四号'],
        line_spacing_pt=LINE_SPACING['body'],
        first_line_chars=2,
    )


def add_signature(doc, issuer, date_text):
    """发文机关署名和成文日期：距正文下空 3 行；日期右空 4 字，署名以日期为准居中"""
    for _ in range(3):
        p = doc.add_paragraph()
        set_line_spacing_exact(p, LINE_SPACING['body'])
    if issuer and date_text:
        sender_chars = max(0, round(4 + (text_width_chars(date_text)
                                         - text_width_chars(issuer)) / 2))
    else:
        sender_chars = 4
    if issuer:
        add_styled_paragraph(doc, issuer, 'issuer', FONT_SIZES['四号'],
                             align=WD_ALIGN_PARAGRAPH.RIGHT,
                             right_chars=sender_chars)
    if date_text:
        add_styled_paragraph(doc, date_text, 'issuer', FONT_SIZES['四号'],
                             align=WD_ALIGN_PARAGRAPH.RIGHT, right_chars=4)


def text_width_chars(text):
    """估算文本宽度（三号字为单位：汉字/全角=1，半角数字字母=0.5）"""
    return sum(0.5 if ord(ch) < 128 else 1.0 for ch in text)


def set_page_setup(doc):
    """页面参数 + 文档网格（每面 22 行，28 磅行距）"""
    section = doc.sections[0]
    section.page_width = Cm(21)
    section.page_height = Cm(29.7)
    section.top_margin = Cm(3.7)
    section.bottom_margin = Cm(3.5)
    section.left_margin = Cm(2.8)
    section.right_margin = Cm(2.6)
    section.footer_distance = Cm(2.8)

    sectPr = section._sectPr
    # 移除模板自带的默认 docGrid，避免重复
    for grid in sectPr.findall(qn('w:docGrid')):
        sectPr.remove(grid)
    docGrid = OxmlElement('w:docGrid')
    docGrid.set(qn('w:type'), 'lines')
    docGrid.set(qn('w:linePitch'), '560')  # 28 磅 = 560 twip
    sectPr.append(docGrid)


def add_header_info(doc, fen_hao='', mi_ji='', jin_ji_chengdu='',
                    fa_wen_zi_hao='', shang_xing_wen=False):
    """可选版头信息（红头文件用）：份号/密级/紧急程度黑体；发文字号仿宋"""
    if not any([fen_hao, mi_ji, jin_ji_chengdu, fa_wen_zi_hao]):
        return
    for text in (fen_hao, mi_ji, jin_ji_chengdu):
        if text:
            add_styled_paragraph(doc, text, 'mi_ji', FONT_SIZES['三号'],
                                 line_spacing_pt=LINE_SPACING['body'],
                                 align=WD_ALIGN_PARAGRAPH.LEFT)
    if fa_wen_zi_hao:
        if shang_xing_wen:
            add_styled_paragraph(doc, fa_wen_zi_hao, 'issuer',
                                 FONT_SIZES['三号'],
                                 line_spacing_pt=LINE_SPACING['body'],
                                 align=WD_ALIGN_PARAGRAPH.LEFT,
                                 left_chars=1)
        else:
            add_styled_paragraph(doc, fa_wen_zi_hao, 'issuer',
                                 FONT_SIZES['三号'],
                                 line_spacing_pt=LINE_SPACING['body'],
                                 align=WD_ALIGN_PARAGRAPH.CENTER)


def _add_page_field_run(para, font_key, font_size, result_text='1'):
    """在段落中插入 PAGE 域，格式：- {PAGE} -"""
    run = para.add_run()
    set_font(run, font_key, font_size)
    r = run._element

    def el(tag, **attrs):
        e = OxmlElement(tag)
        for k, v in attrs.items():
            e.set(qn(k), v)
        return e

    r.append(el('w:fldChar', **{'w:fldCharType': 'begin'}))
    instr = el('w:instrText', **{'xml:space': 'preserve'})
    instr.text = 'PAGE'
    r.append(instr)
    r.append(el('w:fldChar', **{'w:fldCharType': 'separate'}))
    t = OxmlElement('w:t')
    t.text = result_text
    r.append(t)
    r.append(el('w:fldChar', **{'w:fldCharType': 'end'}))
    return run


def add_page_number(doc):
    """页脚页码：- 1 -，宋体四号；单页码居右空一字，双页码居左空一字"""
    section = doc.sections[0]
    doc.settings.odd_and_even_pages_header_footer = True

    odd_footer = section.footer
    odd_footer.is_linked_to_previous = False
    para = odd_footer.paragraphs[0]
    para.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    set_line_spacing_exact(para, LINE_SPACING['body'])
    set_indent(para, right_chars=1)
    _build_page_number_paragraph(para)

    even_footer = section.even_page_footer
    even_footer.is_linked_to_previous = False
    epara = even_footer.paragraphs[0]
    epara.alignment = WD_ALIGN_PARAGRAPH.LEFT
    set_line_spacing_exact(epara, LINE_SPACING['body'])
    set_indent(epara, left_chars=1)
    _build_page_number_paragraph(epara)


def _build_page_number_paragraph(para):
    r1 = para.add_run('- ')
    set_font(r1, 'page_num', FONT_SIZES['四号'])
    _add_page_field_run(para, 'page_num', FONT_SIZES['四号'])
    r3 = para.add_run(' -')
    set_font(r3, 'page_num', FONT_SIZES['四号'])


def is_level1_title(line):
    """一级标题：一、二、三……"""
    return bool(line and line[0] in '一二三四五六七八九十'
                and len(line) > 1 and line[1] == '、')


def is_level2_title(line):
    """二级标题：（一）（二）（三）……"""
    return bool(line and line.startswith('（') and len(line) >= 4
                and line[1] in '一二三四五六七八九十' and line[2] == '）')


def is_level3_title(line):
    """三级标题：1. 2. 3. ……（半角或全角点）"""
    return bool(line and line[:1].isdigit() and len(line) >= 2
                and line[1] in '.．')


def is_level4_title(line):
    """四级标题：（1）（2）（3）……"""
    return bool(line and line.startswith('（') and len(line) >= 4
                and line[1].isdigit() and line[2] == '）')


def generate_docx(args):
    """生成 Word 文档"""
    doc = Document()
    set_page_setup(doc)

    add_header_info(doc,
                    fen_hao=args.fen_hao,
                    mi_ji=args.mi_ji,
                    jin_ji_chengdu=args.jin_ji_chengdu,
                    fa_wen_zi_hao=args.fa_wen_zi_hao,
                    shang_xing_wen=args.shang_xing_wen)

    if args.title:
        add_title(doc, args.title)

    if args.body:
        for kind, payload in split_table_blocks(args.body):
            if kind == 'table':
                add_table(doc, payload)
                continue
            line = payload.strip()
            if not line:
                continue
            if is_level1_title(line):
                add_level1_title(doc, line)
            elif is_level2_title(line):
                add_level2_title(doc, line)
            elif is_level3_title(line):
                add_level3_title(doc, line)
            elif is_level4_title(line):
                add_level4_title(doc, line)
            else:
                add_body_text(doc, line)

    if args.attachment:
        doc.add_paragraph()
        add_attachment(doc, args.attachment)

    if args.sender or args.date:
        add_signature(doc, args.sender or '', args.date or '')

    add_page_number(doc)

    output_path = args.output
    if not os.path.exists(output_path):
        os.makedirs(output_path)
    filepath = os.path.join(output_path, args.filename or '公文.docx')
    doc.save(filepath)
    print(f'Word 文档已生成: {filepath}')
    return filepath


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


def add_table(doc, rows):
    """把二维数组渲染成**真 Word 表格**（带边框、仿宋、五号 10.5pt、表头加粗）。

    与全文风格一致：字体用同一个仿宋族（CN_FONT），行距用固定值保持紧凑。
    单元格里换行会出现孤立标点的问题由上游 md_adapter 负责合并。
    """
    from docx.enum.table import WD_TABLE_ALIGNMENT
    from docx.shared import Pt
    from docx.oxml.ns import qn
    from docx.oxml import OxmlElement
    from docx.enum.text import WD_LINE_SPACING

    if not rows:
        return
    ncol = max(len(r) for r in rows)
    table = doc.add_table(rows=0, cols=ncol)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    for ri, row in enumerate(rows):
        cells = table.add_row().cells
        for ci in range(ncol):
            txt = row[ci] if ci < len(row) else ''
            cell = cells[ci]
            cell.text = ''
            p = cell.paragraphs[0]
            p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
            p.paragraph_format.line_spacing = Pt(16)
            run = p.add_run(txt)
            run.font.name = CN_FONT
            run.font.size = Pt(10.5)
            run.bold = (ri == 0)
            try:
                run._element.rPr.rFonts.set(qn('w:eastAsia'), CN_FONT)
            except Exception:
                pass
            tcPr = cell._tc.get_or_add_tcPr()
            borders = OxmlElement('w:tcBorders')
            for edge in ('top', 'left', 'bottom', 'right'):
                el = OxmlElement('w:' + edge)
                el.set(qn('w:val'), 'single')
                el.set(qn('w:sz'), '6')
                el.set(qn('w:color'), '808080')
                borders.append(el)
            tcPr.append(borders)
    add_body_text(doc, '')


def main():
    parser = argparse.ArgumentParser(description='党政机关公文排版格式生成器 (.docx)')
    parser.add_argument('--output', required=True, help='输出目录')
    parser.add_argument('--filename', default='公文.docx', help='文件名')
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
    generate_docx(args)


if __name__ == '__main__':
    main()
