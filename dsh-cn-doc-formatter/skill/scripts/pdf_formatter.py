#!/usr/bin/env python3
"""
党政机关公文排版格式生成器 — PDF 文档
严格遵循 GB/T 9704-2012 标准
"""

import argparse
import glob
import os

from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, KeepTogether
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT, TA_JUSTIFY


# 字号（磅）
FONT_SIZES = {
    '二号': 22,
    '三号': 16,
    '四号': 14,
}

# 行距（磅）
LINE_SPACING = {
    'title': 36,
    'body': 28,
}

# 页边距（cm）
MARGINS = {
    'top': 3.7,
    'bottom': 3.5,
    'left': 2.8,
    'right': 2.6,
}

# 三号字（16pt）字符宽度（磅），用于缩进换算
CHAR_PT = 16

# 各排版元素使用的字体（注册成功后按可用性调整）
FONTS = {
    'title': 'FangBold',      # 标题：仿宋加粗（二号）
    'body':  'FangSC',        # 正文：仿宋（四号）
    'h1':    'FangBold',      # 一级标题：仿宋加粗（三号）
    'h2':    'FangBold',      # 二级标题：仿宋加粗（三号）
    'h3':    'FangBold',      # 三级标题：仿宋加粗（三号）
    'h4':    'FangBold',      # 四级标题：仿宋加粗（三号）
    'mi_ji': 'FangSC',        # 版头：仿宋（与全文一致）
    'page':  'FangSC',        # 页码：仿宋
}


def _first_file(patterns):
    for pat in patterns:
        hits = sorted(glob.glob(pat, recursive=True))
        if hits:
            return hits[0]
    return None


_HERE = os.path.dirname(os.path.abspath(__file__))


def _font_search_dirs():
    """用户自备字体的查找目录（按优先级，跨平台，只返回真实存在的目录）。"""
    home = os.path.expanduser('~')
    local = os.environ.get('LOCALAPPDATA', '')
    candidates = [
        os.environ.get('DSH_CN_FONT_DIR', ''),            # 1) 显式指定目录
        os.path.join(_HERE, '..', 'fonts'),               # 2) 用户放进插件自己的 fonts/
        os.path.join(home, 'Library', 'Fonts'),           # 3) macOS 用户字体
        os.path.join(home, '.fonts'),                     #    Linux 用户字体
        os.path.join(home, '.local', 'share', 'fonts'),   #    Linux 用户字体
        os.path.join(local, 'Microsoft', 'Windows', 'Fonts') if local else '',
        'C:/Windows/Fonts',                               #    Windows 系统字体
        '/usr/share/fonts',                               #    Linux 系统字体
        '/usr/local/share/fonts',
    ]
    return [d for d in candidates if d and os.path.isdir(d)]


# 仿宋在各平台的常见文件名（不同来源命名不一）
FANGSONG_NAMES = [
    'FangS-SC.ttf',            # WPS 自带（方正仿宋）
    'simfang.ttf', 'SIMFANG.TTF',   # Windows 仿宋
    'FangSong.ttf', 'FangSong_GB2312.ttf',
    'STFangsong.ttf',          # macOS 华文仿宋
    'FandolFang-Regular.otf',  # TeX Live 开源仿宋
    '仿宋.ttf', '仿宋_GB2312.ttf',
]
FANGSONG_BOLD_NAMES = [
    'FangS-SC-Bold.ttf',
    'simfangb.ttf', 'SIMFANGB.TTF',
    'FangSong-Bold.ttf',
    'FandolFang-Bold.otf',
]


def _find_font(names):
    """在用户字体目录里按文件名找字体，返回第一个命中的绝对路径。"""
    dirs = _font_search_dirs()
    for d in dirs:
        for name in names:
            hit = _first_file([os.path.join(d, name), os.path.join(d, '**', name)])
            if hit:
                return hit
    return None


# WPS Office 自带方正仿宋（常规体），作为最后的外部兜底
_WPS_FANGSONG = [
    '/Applications/wpsoffice.app/Contents/Resources/office6/fonts/FangS-SC.ttf',
    '/Applications/WPS Office.app/Contents/Resources/office6/fonts/FangS-SC.ttf',
    '/Applications/WPS*.app/Contents/Resources/office6/fonts/FangS-SC.ttf',
]


def register_fonts():
    """注册字体（TTC 用 subfontIndex 指定字面）。

    ⚠ 仿宋字体**不随本插件分发**。方正仿宋的授权允许在文档中使用，但不允许再分发
    字体文件本身，因此改为查找**用户自备**的字体，顺序如下：

      1. 环境变量 DSH_CN_FANGSONG / DSH_CN_FANGSONG_BOLD 直接指定文件（最高优先）
      2. 环境变量 DSH_CN_FONT_DIR 指定的目录
      3. 插件自己 fonts/ 目录（用户自行放入）
      4. 系统字体目录（macOS / Windows / Linux）
      5. WPS Office 安装目录（自带方正仿宋）

    全部找不到时退回系统宋体，并在 stderr 给出可操作的获取指引。
    """
    songti = _first_file([
        '/System/Library/Fonts/Supplemental/Songti.ttc',
        '/System/Library/Fonts/STHeiti Light.ttc',
    ])

    # ① 显式指定优先
    explicit = os.environ.get('DSH_CN_FANGSONG', '').strip()
    fangsong = _first_file([explicit]) if explicit else None
    # ②③④ 按目录与文件名查找
    if not fangsong:
        fangsong = _find_font(FANGSONG_NAMES)
    # ⑤ WPS 兜底
    if not fangsong:
        fangsong = _first_file(_WPS_FANGSONG)

    explicit_bold = os.environ.get('DSH_CN_FANGSONG_BOLD', '').strip()
    bold_fang = _first_file([explicit_bold]) if explicit_bold else None
    if not bold_fang:
        bold_fang = _find_font(FANGSONG_BOLD_NAMES)

    ok = {}

    def reg(name, path, sub=None):
        try:
            pdfmetrics.registerFont(
                TTFont(name, path, subfontIndex=sub) if sub is not None
                else TTFont(name, path))
            ok[name] = True
        except Exception:
            ok[name] = False

    reg('SongSC', songti, 6)        # 宋体-简 常规体（兜底）
    reg('SongSCBold', songti, 1)    # 宋体-简 粗体（兜底）
    if fangsong:
        reg('FangSC', fangsong)     # 仿宋（用户自备，TrueType）
    if bold_fang:
        reg('FangBold', bold_fang)  # 仿宋加粗（用户自备）

    # 仿宋缺失时给出可操作的提示，避免静默退宋体导致排版不达标
    if not ok.get('FangSC'):
        import sys as _sys
        print('[提示] 未找到仿宋字体，PDF 将退回宋体，与「全文仿宋」规范不符。\n'
              '       本插件不随包分发字体（方正仿宋授权不允许再分发字体文件），\n'
              '       请自备仿宋字体，任选一种方式：\n'
              '         1) 环境变量直接指定：export DSH_CN_FANGSONG=/path/to/仿宋.ttf\n'
              '         2) 指定查找目录：    export DSH_CN_FONT_DIR=~/my-fonts\n'
              '         3) 放进插件自己的：  <插件目录>/fonts/\n'
              '         4) 装到系统字体目录：macOS ~/Library/Fonts/ ／ '
              'Windows C:\\Windows\\Fonts\\ ／ Linux ~/.fonts/\n'
              '         5) 安装 WPS Office（自带方正仿宋）\n'
              '       可用文件名举例：FangS-SC.ttf、simfang.ttf、STFangsong.ttf、\n'
              '                       FandolFang-Regular.otf（TeX Live 开源仿宋）',
              file=_sys.stderr)

    # 字体缺失时回退
    if not ok.get('FangSC'):
        for key in ('body', 'mi_ji', 'page'):
            FONTS[key] = 'SongSC'
    if not ok.get('FangBold'):
        if ok.get('FangSC'):
            # 有仿宋但没有仿宋粗体（用户自备字体时的常态）：
            # 标题继续用仿宋，保住「全文统一仿宋」这条硬规范。
            # reportlab 不做合成粗体，这里宁可不粗也不换字体族。
            for key in ('title', 'h1', 'h2', 'h3', 'h4'):
                FONTS[key] = 'FangSC'
            import sys as _sys
            print('[提示] 未提供仿宋加粗字体，标题将使用常规仿宋（不加粗）。\n'
                  '       如需加粗，用 DSH_CN_FANGSONG_BOLD 指定加粗字体文件。',
                  file=_sys.stderr)
        else:
            # 仿宋整体缺失 → 标题退宋体粗体
            for key in ('title', 'h1', 'h2', 'h3', 'h4'):
                FONTS[key] = 'SongSCBold' if ok.get('SongSCBold') else 'SongSC'
    if not ok.get('SongSC'):
        raise RuntimeError('系统缺少宋体字体，无法生成 PDF')


def make_style(font_name, font_size, alignment=TA_LEFT, leading=None,
               first_line_indent=0, left_indent=0, right_indent=0):
    """创建段落样式（wordWrap='CJK' 保证中文逐字换行）"""
    if leading is None:
        leading = font_size * 1.75
    return ParagraphStyle(
        f'style_{font_name}_{font_size}_{alignment}_{first_line_indent}_{left_indent}_{right_indent}',
        parent=getSampleStyleSheet()['Normal'],
        fontName=font_name,
        fontSize=font_size,
        alignment=alignment,
        firstLineIndent=first_line_indent,
        leftIndent=left_indent,
        rightIndent=right_indent,
        leading=leading,
        spaceBefore=0,
        spaceAfter=0,
        wordWrap='CJK',
    )


def markup_text(text):
    """转义 XML（全文统一仿宋，不再单独换西文字体）"""
    return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def text_width_chars(text):
    """估算文本宽度（三号字为单位：汉字/全角=1，半角数字字母=0.5）"""
    return sum(0.5 if ord(ch) < 128 else 1.0 for ch in text)


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


def on_page(canvas, doc):
    """每页页脚页码：- n -，宋体四号，单页码居右空一字，双页码居左空一字"""
    canvas.saveState()
    canvas.setFont(FONTS['page'], FONT_SIZES['四号'])
    text = f'- {canvas.getPageNumber()} -'
    y = doc.bottomMargin * 0.55
    if canvas.getPageNumber() % 2 == 1:
        x = doc.pagesize[0] - doc.rightMargin - CHAR_PT
        canvas.drawRightString(x, y, text)
    else:
        x = doc.leftMargin + CHAR_PT
        canvas.drawString(x, y, text)
    canvas.restoreState()


def generate_pdf(args):
    """生成 PDF 文档"""
    register_fonts()

    output_path = args.output
    if not os.path.exists(output_path):
        os.makedirs(output_path)
    filepath = os.path.join(output_path, args.filename or '公文.pdf')

    doc = SimpleDocTemplate(
        filepath,
        pagesize=A4,
        topMargin=MARGINS['top'] * cm,
        bottomMargin=MARGINS['bottom'] * cm,
        leftMargin=MARGINS['left'] * cm,
        rightMargin=MARGINS['right'] * cm,
    )

    story = []
    body_size = FONT_SIZES['四号']
    heading_size = FONT_SIZES['三号']
    body_leading = LINE_SPACING['body']
    body_indent = int(2 * body_size)      # 正文首行缩进 2 字
    heading_indent = int(2 * heading_size)  # 小标题左空 2 字
    right4 = int(4 * body_size)    # 右空 4 字（按四号字宽）

    # === 版头信息 ===
    for text in (args.fen_hao, args.mi_ji, args.jin_ji_chengdu):
        if text:
            style = make_style(FONTS['mi_ji'], heading_size, TA_LEFT,
                               leading=body_leading)
            story.append(Paragraph(markup_text(text), style))

    if args.fa_wen_zi_hao:
        if args.shang_xing_wen:
            style = make_style(FONTS['body'], body_size, TA_LEFT,
                               leading=body_leading, left_indent=CHAR_PT)
        else:
            style = make_style(FONTS['body'], body_size, TA_CENTER,
                               leading=body_leading)
        story.append(Paragraph(markup_text(args.fa_wen_zi_hao), style))

    # === 标题 ===
    if args.title:
        title_style = make_style(FONTS['title'], FONT_SIZES['二号'], TA_CENTER,
                                 leading=LINE_SPACING['title'])
        story.append(Paragraph(markup_text(args.title), title_style))

    # === 正文 ===
    if args.body:
        for kind, payload in split_table_blocks(args.body):
            if kind == 'table':
                story.append(make_table(payload, make_style, body_size, markup_text))
                story.append(Spacer(1, body_leading * 0.5))
                continue
            line = payload.strip()
            if not line:
                continue
            if is_level1_title(line):
                font, size = FONTS['h1'], heading_size
            elif is_level2_title(line):
                font, size = FONTS['h2'], heading_size
            elif is_level3_title(line):
                font, size = FONTS['h3'], heading_size
            elif is_level4_title(line):
                font, size = FONTS['h4'], heading_size
            else:
                font, size = FONTS['body'], body_size
            line_indent = heading_indent if size == heading_size else body_indent
            style = make_style(font, size, TA_JUSTIFY,
                               first_line_indent=line_indent,
                               leading=body_leading)
            story.append(Paragraph(markup_text(line), style))

    # === 附件说明 ===
    if args.attachment:
        story.append(Spacer(1, body_leading))
        style = make_style(FONTS['body'], body_size, TA_JUSTIFY,
                           first_line_indent=body_indent, leading=body_leading)
        story.append(Paragraph(markup_text(args.attachment), style))

    # === 发文机关署名和日期 ===
    if args.sender or args.date:
        sign_block = [Spacer(1, body_leading * 3)]
        if args.sender and args.date:
            sender_indent = max(0, round((4 + (text_width_chars(args.date)
                                               - text_width_chars(args.sender)) / 2)
                                         * body_size))
        else:
            sender_indent = right4
        if args.sender:
            style = make_style(FONTS['body'], body_size, TA_RIGHT,
                               leading=body_leading, right_indent=sender_indent)
            sign_block.append(Paragraph(markup_text(args.sender), style))
        if args.date:
            style = make_style(FONTS['body'], body_size, TA_RIGHT,
                               leading=body_leading, right_indent=right4)
            sign_block.append(Paragraph(markup_text(args.date), style))
        story.append(KeepTogether(sign_block))

    doc.build(story, onFirstPage=on_page, onLaterPages=on_page)
    print(f'PDF 文档已生成: {filepath}')
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


def make_table(rows, make_style, body_size, markup_text):
    """把二维数组渲染成**真 PDF 表格**（可跨页、带边框、表头加粗效果）。"""
    from reportlab.platypus import Table, TableStyle
    from reportlab.lib import colors
    from reportlab.lib.units import cm

    if not rows:
        return Spacer(1, 1)
    ncol = max(len(r) for r in rows)
    # 列宽按内容长度加权（越长的列越宽），避免窄列挤成一团
    weights = []
    for ci in range(ncol):
        w = max((len(r[ci]) for r in rows if ci < len(r)), default=4)
        weights.append(max(w, 5))
    total = float(sum(weights))
    avail = A4[0] - 2.8 * cm - 2.6 * cm
    widths = [avail * w / total for w in weights]

    cell_style = make_style(FONTS['body'], 9.5, TA_JUSTIFY, leading=13)
    data = []
    for ri, row in enumerate(rows):
        cells = []
        for ci in range(ncol):
            txt = row[ci] if ci < len(row) else ''
            cells.append(Paragraph(markup_text(txt), cell_style))
        data.append(cells)
    t = Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([
        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#9aa3ad')),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LEFTPADDING', (0, 0), (-1, -1), 4),
        ('RIGHTPADDING', (0, 0), (-1, -1), 4),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    return t


def main():
    parser = argparse.ArgumentParser(description='党政机关公文排版格式生成器 (.pdf)')
    parser.add_argument('--output', required=True, help='输出目录')
    parser.add_argument('--filename', default='公文.pdf', help='文件名')
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
    generate_pdf(args)


if __name__ == '__main__':
    main()
