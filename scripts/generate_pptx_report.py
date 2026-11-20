# -*- coding: utf-8 -*-
"""
================================================================================
SCRIPT TẠO BÀI TRÌNH CHIẾU POWERPOINT (.PPTX) 16:9 CHUYÊN NGHIỆP BÁO CÁO TRƯỚC LỚP
================================================================================
Gồm 22 slide widescreen (13.333 x 7.5 in) thiết kế hiện đại chuẩn kỹ thuật:
  - Dẫn nguồn chi tiết số trang sách & PDF
  - Tóm tắt Toán cấp 3 & Công thức cơ học CALFEM trước khi giải
  - Trình bày từng bước siêu trực quan, so sánh 4 mô hình & 6 thuật toán
  - Nêu bật 5 phát hiện bản chất vật lý (Thanh 1-2 hồi sinh, Đòn bẩy R1y≠R4y,
    Mềm hóa vs Cứng hóa, Độ nhạy tải lớn 1P→500P, Bật nhảy Snap-Through 78.45 MN)
  - Giới thiệu kiến trúc Python + Flutter 2D/3D ANSYS + Phẫu thuật + .exe/.apk/GitHub
================================================================================
"""

from __future__ import annotations
import json
import os
from typing import List, Optional, Tuple

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

# Bảng màu chuẩn CAE chuyên nghiệp
C_DARK = RGBColor(0x0B, 0x16, 0x2C)
C_NAVY = RGBColor(0x0F, 0x3D, 0x6E)
C_TEAL = RGBColor(0x0F, 0x76, 0x6E)
C_CYAN = RGBColor(0x06, 0xB6, 0xD4)
C_RED = RGBColor(0xDC, 0x26, 0x26)
C_AMBER = RGBColor(0xD9, 0x77, 0x06)
C_TEXT = RGBColor(0x1E, 0x29, 0x3B)
C_MUTED = RGBColor(0x47, 0x55, 0x69)
C_BG = RGBColor(0xF8, 0xFA, 0xFC)
C_WHITE = RGBColor(0xFF, 0xFF, 0xFF)
C_BORDER = RGBColor(0xCB, 0xD5, 0xE1)
C_LIGHT_BLUE = RGBColor(0xEF, 0xF6, 0xFF)
C_LIGHT_TEAL = RGBColor(0xF0, 0xFD, 0xFA)
C_LIGHT_AMBER = RGBColor(0xFF, 0xFB, 0xEB)

FONT_MAIN = "Segoe UI"
FONT_CODE = "Consolas"


def _set_slide_bg(slide, color: RGBColor) -> None:
    bg = slide.background
    fill = bg.fill
    fill.solid()
    fill.fore_color.rgb = color


def _add_header(slide, title: str, subtitle: str, slide_num: int, total: int = 22) -> None:
    _set_slide_bg(slide, C_BG)
    # Dải thanh trên cùng màu Navy
    bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0), Inches(0), Inches(13.333), Inches(0.92))
    bar.fill.solid()
    bar.fill.fore_color.rgb = C_NAVY
    bar.line.fill.background()

    # Đường nhấn Cyan mỏng dưới thanh tiêu đề
    acc = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0), Inches(0.92), Inches(13.333), Inches(0.055))
    acc.fill.solid()
    acc.fill.fore_color.rgb = C_CYAN
    acc.line.fill.background()

    # Tiêu đề chính & phụ
    tb = slide.shapes.add_textbox(Inches(0.45), Inches(0.08), Inches(11.6), Inches(0.8))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    p1 = tf.paragraphs[0]
    r1 = p1.add_run()
    r1.text = title
    r1.font.name = FONT_MAIN
    r1.font.size = Pt(21)
    r1.font.bold = True
    r1.font.color.rgb = C_WHITE

    p2 = tf.add_paragraph()
    r2 = p2.add_run()
    r2.text = subtitle
    r2.font.name = FONT_MAIN
    r2.font.size = Pt(11)
    r2.font.color.rgb = RGBColor(0xBA, 0xE6, 0xFD)

    # Số trang góc trên phải
    nb = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(12.25), Inches(0.2), Inches(0.8), Inches(0.48))
    nb.fill.solid()
    nb.fill.fore_color.rgb = C_TEAL
    nb.line.fill.background()
    ntf = nb.text_frame
    ntf.vertical_anchor = MSO_ANCHOR.MIDDLE
    np0 = ntf.paragraphs[0]
    np0.alignment = PP_ALIGN.CENTER
    nr = np0.add_run()
    nr.text = f"{slide_num:02d}/{total}"
    nr.font.name = FONT_MAIN
    nr.font.size = Pt(11.5)
    nr.font.bold = True
    nr.font.color.rgb = C_WHITE

    # Footer chân trang mảnh
    ft = slide.shapes.add_textbox(Inches(0.45), Inches(7.16), Inches(12.4), Inches(0.28))
    ftf = ft.text_frame
    fp = ftf.paragraphs[0]
    fr = fp.add_run()
    fr.text = "ĐH Bách Khoa TP.HCM  •  Tiểu luận Phân tích Phi tuyến Kết cấu (CALFEM)  •  Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)"
    fr.font.name = FONT_MAIN
    fr.font.size = Pt(8.8)
    fr.font.color.rgb = C_MUTED


def _add_card(
    slide,
    left: float,
    top: float,
    width: float,
    height: float,
    title: str,
    bullets: List[str],
    accent: RGBColor = C_NAVY,
    fill_color: RGBColor = C_WHITE,
    font_size: float = 12.2,
) -> None:
    card = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(left), Inches(top), Inches(width), Inches(height))
    card.fill.solid()
    card.fill.fore_color.rgb = fill_color
    card.line.color.rgb = C_BORDER
    card.line.width = Pt(1.0)
    card.adjustments[0] = 0.04

    # Thanh nhấn bên trái card
    strip = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(left), Inches(top + 0.08), Inches(0.08), Inches(height - 0.16))
    strip.fill.solid()
    strip.fill.fore_color.rgb = accent
    strip.line.fill.background()

    tb = slide.shapes.add_textbox(Inches(left + 0.2), Inches(top + 0.1), Inches(width - 0.3), Inches(height - 0.18))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0

    p0 = tf.paragraphs[0]
    p0.space_after = Pt(5)
    r0 = p0.add_run()
    r0.text = title
    r0.font.name = FONT_MAIN
    r0.font.size = Pt(font_size + 1.5)
    r0.font.bold = True
    r0.font.color.rgb = accent

    for b in bullets:
        p = tf.add_paragraph()
        p.space_after = Pt(4)
        p.line_spacing = 1.15
        r = p.add_run()
        r.text = b
        r.font.name = FONT_MAIN
        r.font.size = Pt(font_size)
        r.font.color.rgb = C_TEXT


def _add_table(
    slide,
    left: float,
    top: float,
    width: float,
    height: float,
    headers: List[str],
    rows: List[List[str]],
    head_color: RGBColor = C_NAVY,
    font_size: float = 10.2,
) -> None:
    shape = slide.shapes.add_table(len(rows) + 1, len(headers), Inches(left), Inches(top), Inches(width), Inches(height))
    tbl = shape.table
    for j, h in enumerate(headers):
        cell = tbl.cell(0, j)
        cell.fill.solid()
        cell.fill.fore_color.rgb = head_color
        cell.vertical_anchor = MSO_ANCHOR.MIDDLE
        p = cell.text_frame.paragraphs[0]
        p.alignment = PP_ALIGN.CENTER
        r = p.add_run()
        r.text = h
        r.font.name = FONT_MAIN
        r.font.size = Pt(font_size)
        r.font.bold = True
        r.font.color.rgb = C_WHITE

    for r_idx, row_data in enumerate(rows):
        for j, val in enumerate(row_data):
            cell = tbl.cell(r_idx + 1, j)
            cell.fill.solid()
            cell.fill.fore_color.rgb = C_WHITE if r_idx % 2 == 0 else RGBColor(0xF1, 0xF5, 0xF9)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            p = cell.text_frame.paragraphs[0]
            p.alignment = PP_ALIGN.LEFT if j == 0 else PP_ALIGN.RIGHT
            if len(val) > 22:
                p.alignment = PP_ALIGN.LEFT
            r = p.add_run()
            r.text = val
            r.font.name = FONT_MAIN
            r.font.size = Pt(font_size - 0.4)
            r.font.color.rgb = C_TEXT


def _add_picture_fit(slide, img_path: str, left: float, top: float, max_w: float, max_h: float) -> None:
    if not os.path.exists(img_path):
        return
    from PIL import Image
    with Image.open(img_path) as im:
        iw, ih = im.size
    ratio = iw / ih
    w = max_w
    h = w / ratio
    if h > max_h:
        h = max_h
        w = h * ratio
    x = left + 0.5 * (max_w - w)
    y = top + 0.5 * (max_h - h)
    slide.shapes.add_picture(img_path, Inches(x), Inches(y), width=Inches(w), height=Inches(h))


def build_pptx(base_dir: str) -> str:
    with open(os.path.join(base_dir, "results", "full_analysis_results.json"), "r", encoding="utf-8") as f:
        data = json.load(f)
    fig_dir = os.path.join(base_dir, "results", "figures")
    debai_img = r"F:\3_DATA_E\4_HocTap\Phan tich phi tuyen ket cau\BaiTapNhom\DeBai\1.jpg"

    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)
    blank = prs.slide_layouts[6]

    TOTAL = 22

    # ==========================================================================
    # SLIDE 1: TRANG BÌA CHUYÊN NGHIỆP
    # ==========================================================================
    s1 = prs.slides.add_slide(blank)
    _set_slide_bg(s1, C_DARK)
    # Khối đồ họa trang trí bên phải
    deco1 = s1.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0), Inches(0), Inches(0.28), Inches(7.5))
    deco1.fill.solid()
    deco1.fill.fore_color.rgb = C_CYAN
    deco1.line.fill.background()
    deco2 = s1.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.28), Inches(0), Inches(13.053), Inches(0.95))
    deco2.fill.solid()
    deco2.fill.fore_color.rgb = C_NAVY
    deco2.line.fill.background()

    tb0 = s1.shapes.add_textbox(Inches(0.7), Inches(0.16), Inches(12.0), Inches(0.7))
    p = tb0.text_frame.paragraphs[0]
    r = p.add_run()
    r.text = "ĐẠI HỌC QUỐC GIA TP. HỒ CHÍ MINH  •  TRƯỜNG ĐẠI HỌC BÁCH KHOA  •  KHOA KỸ THUẬT XÂY DỰNG"
    r.font.name = FONT_MAIN
    r.font.size = Pt(13)
    r.font.bold = True
    r.font.color.rgb = RGBColor(0xE0, 0xF2, 0xFE)

    tb1 = s1.shapes.add_textbox(Inches(0.8), Inches(1.45), Inches(11.8), Inches(2.9))
    tf1 = tb1.text_frame
    tf1.word_wrap = True
    p_sub = tf1.paragraphs[0]
    rs = p_sub.add_run()
    rs.text = "BÁO CÁO TIỂU LUẬN MÔN PHÂN TÍCH PHI TUYẾN KẾT CẤU"
    rs.font.name = FONT_MAIN
    rs.font.size = Pt(16)
    rs.font.bold = True
    rs.font.color.rgb = C_CYAN

    p_main = tf1.add_paragraph()
    p_main.space_before = Pt(10)
    rm = p_main.add_run()
    rm.text = "PHÂN TÍCH PHI TUYẾN HÌNH HỌC HỆ DÀN PHẲNG\nDỰA VÀO CALFEM (bar2e / bar2g / UL / TL)"
    rm.font.name = FONT_MAIN
    rm.font.size = Pt(28)
    rm.font.bold = True
    rm.font.color.rgb = C_WHITE

    p_desc = tf1.add_paragraph()
    p_desc.space_before = Pt(12)
    rd = p_desc.add_run()
    rd.text = "Đối chiếu Tuyến tính – Phi tuyến – SAP2000 – Snap-Through  |  Lõi Python & Giao diện 2D/3D ANSYS bằng Flutter Dart"
    rd.font.name = FONT_MAIN
    rd.font.size = Pt(15)
    rd.font.color.rgb = RGBColor(0x94, 0xA3, 0xB8)

    # Thẻ thông tin tác giả & giảng viên
    card_meta = s1.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.8), Inches(4.75), Inches(11.7), Inches(1.95))
    card_meta.fill.solid()
    card_meta.fill.fore_color.rgb = RGBColor(0x11, 0x1E, 0x38)
    card_meta.line.color.rgb = C_CYAN
    card_meta.line.width = Pt(1.2)
    mtf = card_meta.text_frame
    mtf.word_wrap = True
    mtf.margin_left = Inches(0.3)
    mtf.margin_top = Inches(0.22)
    meta_lines = [
        ("Giảng viên hướng dẫn:   ", "PGS.TS. NGÔ HỮU CƯỜNG", C_WHITE),
        ("Học viên thực hiện:       ", "LÂM PHÚC TÂM (2670621) - VÕ THANH VANG (2670624)", C_CYAN),
        ("Sản phẩm bàn giao:        ", "Word (.docx) • PDF • PowerPoint • Python Core • Flutter 2D/3D (.exe, .apk, GitHub Web)", RGBColor(0xCB, 0xD5, 0xE1)),
        ("Kho mã nguồn & Demo:   ", "https://github.com/vothanhvang/PhanTichPhiTuyen_BaiTieuLuan4", RGBColor(0x34, 0xD3, 0x99)),
    ]
    for i, (k, v, vc) in enumerate(meta_lines):
        mp = mtf.paragraphs[0] if i == 0 else mtf.add_paragraph()
        mp.alignment = PP_ALIGN.LEFT
        mp.space_after = Pt(5)
        rk = mp.add_run()
        rk.text = k
        rk.font.name = FONT_MAIN
        rk.font.size = Pt(13)
        rk.font.bold = True
        rk.font.color.rgb = RGBColor(0x94, 0xA3, 0xB8)
        rv = mp.add_run()
        rv.text = v
        rv.font.name = FONT_MAIN
        rv.font.size = Pt(13)
        rv.font.bold = i < 2
        rv.font.color.rgb = vc

    # ==========================================================================
    # SLIDE 2: LỘ TRÌNH TRÌNH BÀY & MỤC TIÊU
    # ==========================================================================
    s2 = prs.slides.add_slide(blank)
    _add_header(s2, "Mục tiêu & Lộ trình Báo cáo Tiểu luận", "Kết hợp tư duy trực quan dễ hiểu tới học sinh cấp 3 và chiều sâu cơ học tính toán hiện đại", 2, TOTAL)
    steps_s2 = [
        ("01 • Cơ sở & Dẫn nguồn", "Hệ thống hóa đầy đủ Bài giảng NSA_1–NSA_6, CALFEM 3.4, Dahlblom (2016), McGuire (2000), Jeffers (2026) & Yang (2025) kèm số trang.", C_NAVY),
        ("02 • Tóm tắt Toán & Cơ học", "Tóm lược 6 công thức Toán cấp 3 (Py-ta-go, Nhị thức Newton, Tiếp tuyến, Đòn bẩy) và 4 cấp mô hình CALFEM + 6 thuật toán giải.", C_TEAL),
        ("03 • Kiểm chứng Sách gốc", "Xác minh lõi Python CALFEM khớp 100% CALFEM exs3.m và khớp từng chữ số 6 vòng lặp Example 9.1 (Dahlblom tr. 261).", C_CYAN),
        ("04 • Giải Bài toán 5 Thanh", "Giải chi tiết từng bước đề bài 1.jpg (P = 208 kN): Tuyến tính vs bar2g bậc 2 vs Corotational UL vs Total Lagrangian NSA_4.", C_NAVY),
        ("05 • 5 Bản chất Vật lý Sâu", "Thanh 1–2 hồi sinh, Đòn bẩy R₁y ≠ R₄y, Mềm hóa (+P) vs Cứng hóa (−P), Độ nhạy 1P→500P và Bật nhảy Snap-Through thực thụ!", C_RED),
        ("06 • Phần mềm 2D/3D ANSYS", "Demo lõi Python + giao diện Flutter Dart 2D/3D có Phẫu thuật mặt cắt, xuất Word/PDF, đóng gói .exe/.apk & chạy trên GitHub.", C_AMBER),
    ]
    for idx, (st, sd, col) in enumerate(steps_s2):
        r_i, c_i = divmod(idx, 3)
        _add_card(s2, 0.45 + c_i * 4.22, 1.25 + r_i * 2.82, 3.98, 2.55, st, [sd], accent=col, font_size=12.0)

    # ==========================================================================
    # SLIDE 3: BẢNG DẪN NGUỒN CHI TIẾT TÀI LIỆU & SỐ TRANG
    # ==========================================================================
    s3 = prs.slides.add_slide(blank)
    _add_header(s3, "Hệ thống Tài liệu Áp dụng & Dẫn nguồn Chi tiết", "Mọi công thức trong bài đều được đối chiếu chính xác đến từng chương, phương trình, trang sách và trang PDF", 3, TOTAL)
    _add_table(
        s3, 0.45, 1.2, 12.43, 5.65,
        ["Tài liệu nguồn", "Công thức / Nội dung áp dụng trực tiếp", "Số trang (Sách / PDF)"],
        [
            ["[TL1] Bài giảng NSA_1–NSA_6\n(PGS.TS. Ngô Hữu Cường)", "Cấp phân tích; Hooke & Poisson; Công ảo; Biến dạng hữu hạn ε_fin & [k_g] thanh dọc trục (NSA_4 4.1.1); P-δ DAF; 6 thuật toán giải (NSA_6 6.2–6.3).", "NSA_4: Slides 5–12, 20–27 (PDF 2–7)\nNSA_6: Slides 3–25 (PDF 1–7)"],
            ["[TL2] CALFEM 3.4 Manual\n(Lund University)", "Hàm bar2e, bar2g, bar2s, assem, solveq, extract; Ma trận K̄e = K̄e0 + (N/L)·K̄eσ; Ví dụ chuẩn exs3.m, exn1.m, exn2.m.", "Mục 5.3 tr. 5.3-1..5 (PDF 59–63)\nMục 6.2 PDF 160–165; exs3 PDF 233–236"],
            ["[TL3] Olsson & Dahlblom (2016)\nStructural Mechanics — CALFEM", "Chương 9 Geometrical Non-Linearity: Lặp K(Q̄x)a = f PT (9.1–9.3); Trị riêng det K = 0 (9.4–9.7); Thanh bar2g (9.35–9.38); Example 9.1.", "Chương 9: Sách tr. 251–262 (PDF 265–276)\nExample 9.1: Sách tr. 260–261 (PDF 274–275)"],
            ["[TL4] McGuire, Gallagher & Ziemian\nMatrix Structural Analysis 2E (2000)", "Chương 8–9: Biến dạng hữu hạn PT (9.1), Công ảo (9.2–9.5), [k_g] thanh dọc trục (9.9); Chương 12: Euler, RK2, NR, Disp/Arc-Length, Trị riêng.", "Ch. 9: Sách tr. 242–249 (PDF 263–270)\nCh. 12: Sách tr. 339–362 (PDF 360–383)"],
            ["[TL5] Jeffers (2026) & [TL6] Yang (2025)\n& [TL7] Hibbeler (2017/2019)", "Jeffers Ch. 8: Total Lagrangian (8.1) vs Corotational (8.3); Yang Ch. 4: Quy tắc khách quan vật rắn; Hibbeler: Poisson, Mohr, Euler P_cr = π²EI/L².", "Jeffers tr. 171–196; Yang tr. 117–144\nHibbeler Mech tr. 113, 686; Struct Ch. 14"],
        ],
        head_color=C_NAVY, font_size=10.2,
    )

    # ==========================================================================
    # SLIDE 4: TRỰC GIÁC CẤP 3 — PHI TUYẾN HÌNH HỌC LÀ GÌ?
    # ==========================================================================
    s4 = prs.slides.add_slide(blank)
    _add_header(s4, "Góc hiểu nhanh Cấp 3: Bản chất của Phi tuyến Hình học", "Giải thích bằng 3 ví dụ đời thường giúp học sinh THPT hiểu ngay sự khác biệt giữa Tuyến tính và Phi tuyến", 4, TOTAL)
    _add_card(
        s4, 0.45, 1.25, 3.95, 5.55,
        "1. Dây đàn Guitar (Hiệu ứng KÉO CỨNG)",
        [
            "• Dây chùng (N = 0): gảy nhẹ ở giữa dây võng rất sâu → độ cứng ngang bằng 0.",
            "• Vặn khóa căng dây (N > 0): cùng lực gảy đó dây chỉ võng rất ít → lực KÉO tạo thêm độ cứng ngang (+N/L)!",
            "• Kết luận: Trong kết cấu chịu kéo, phi tuyến hình học làm hệ CỨNG HƠN (Stress Stiffening).",
        ],
        accent=C_TEAL, fill_color=C_LIGHT_TEAL, font_size=12.5,
    )
    _add_card(
        s4, 4.68, 1.25, 3.95, 5.55,
        "2. Thước nhựa bị Nén (Hiệu ứng P-Δ)",
        [
            "• Đặt thước nhựa thẳng đứng, ấn NÉN hai đầu (N < 0).",
            "• Càng ấn mạnh, chỉ cần chạm ngang rất nhẹ thước đã cong vồng ra — lực NÉN trừ bớt độ cứng ngang (−|N|/L)!",
            "• Khi lực nén đủ lớn làm tổng độ cứng tụt về 0 (det K = 0) → MẤT ỔN ĐỊNH (Buckling)!",
        ],
        accent=C_RED, fill_color=RGBColor(0xFE, 0xF2, 0xF2), font_size=12.5,
    )
    _add_card(
        s4, 8.91, 1.25, 3.95, 5.55,
        "3. Nắp chai thiếc (Bật nhảy Snap-Through)",
        [
            "• Khi ấn đỉnh vòm xuống, góc nghiêng hai cánh vòm dẹt dần → khả năng chống đỡ giảm (Mềm hóa).",
            "• Tới Đỉnh Giới Hạn (Limit Point), nắp chai 'tách!' một tiếng bật ngược sang phía bên kia!",
            "• BẤT NGỜ: Chính hệ dàn 5 thanh của đề bài có chữ V (3–2–4) bị đẩy LÊN nên cũng có Bật nhảy Snap-Through!",
        ],
        accent=C_NAVY, fill_color=C_LIGHT_BLUE, font_size=12.5,
    )

    # ==========================================================================
    # SLIDE 5: TÓM TẮT CÔNG THỨC TOÁN PHỔ THÔNG CẤP 3
    # ==========================================================================
    s5 = prs.slides.add_slide(blank)
    _add_header(s5, "Tóm tắt 6 Công thức Toán học Phổ thông Cấp 3 Áp dụng", "Yêu cầu 4: Hệ thống hóa nền tảng Toán học phổ thông trước khi áp dụng lập trình & giải bài", 5, TOTAL)
    math_cards = [
        ("1. Py-ta-go & Hằng đẳng thức lớp 8", "l = √[(Δx₀+Δux)² + (Δy₀+Δuy)²]\nl − L₀ = [Δux(2Δx₀+Δux) + Δuy(2Δy₀+Δuy)] / (l + L₀)\n→ Khử triệt tiêu số học, giữ trọn 16 chữ số chính xác!", C_NAVY),
        ("2. Lượng giác & Cosin chỉ phương (Lớp 10)", "c = cos θ = Δx / L  ;   s = sin θ = Δy / L\nc² + s² = 1\n→ Chiếu chuyển vị & lực giữa hệ địa phương và tổng thể.", C_TEAL),
        ("3. Nhị thức Newton (Lớp 11 — NSA_4 Slide 8)", "(1 + d)^(1/2) ≈ 1 + (1/2)·d   (khi |d| ≪ 1)\n→ Dẫn trực tiếp biến dạng hữu hạn Green-Lagrange:\nε_fin = du/dx + ½(du/dx)² + ½(dv/dx)².", C_CYAN),
        ("4. Đạo hàm & Tích phân cơ bản (Lớp 11–12)", "δ(f²) = 2·f·δf   ;   ∫₀ᴸ (1/L²) dx = 1/L\n→ Lấy biến phân công ảo nội δW_int suy ra thẳng ma trận độ cứng hình học [k_g]!", C_AMBER),
        ("5. Tiếp tuyến Newton-Raphson (Lớp 11–12)", "u^(k+1) = u^(k) + [Kt(u^(k))]⁻¹ · (λP − f_int(u^(k)))\n→ Giải phương trình phi tuyến bằng lặp tuyến tính hóa với tốc độ hội tụ bậc 2 cực nhanh.", C_RED),
        ("6. Đòn bẩy Vật lý 10 & Trị riêng Ma trận", "Đòn bẩy biến dạng: R₄y·(2L + u₄x) + P·(L + u₂x) = 0\nTrị riêng ổn định: det(Ke + α_cr·Kg) = 0\n→ Giải thích R₁y ≠ R₄y và tìm tải tới hạn đàn hồi.", C_NAVY),
    ]
    for idx, (mt, mb, col) in enumerate(math_cards):
        ri, ci = divmod(idx, 3)
        _add_card(s5, 0.45 + ci * 4.22, 1.2 + ri * 2.88, 3.98, 2.66, mt, [mb], accent=col, font_size=11.3)

    # ==========================================================================
    # SLIDE 6: TÓM TẮT 4 CẤP MÔ HÌNH CƠ HỌC CALFEM
    # ==========================================================================
    s6 = prs.slides.add_slide(blank)
    _add_header(s6, "Tóm tắt 4 Cấp Mô hình Cơ học CALFEM & Giải mã [k_g]", "Yêu cầu 3: Phân biệt rõ bản chất giữa bar2e, bar2g bậc 2 gốc, Corotational UL và Total Lagrangian (NSA_4)", 6, TOTAL)
    _add_table(
        s6, 0.45, 1.2, 12.43, 3.7,
        ["Cấp mô hình & Nguồn", "Biến dạng & Cấu hình cân bằng", "Ma trận độ cứng phần tử [K_T] (địa phương)", "Phạm vi & Bản chất"],
        [
            ["1. Tuyến tính (bar2e)\ncalfem34.pdf tr. 5.3-2", "ε = (u₂−u₁)/L₀\nCấu hình BAN ĐẦU X", "K_e0 = (EA/L₀)·[[1,0,-1,0], ...]\n(Không có thành phần hình học)", "Chuẩn đối chiếu SAP2000; bỏ qua ảnh hưởng lực dọc N."],
            ["2. CALFEM bar2g Bậc 2 gốc\nDahlblom Ch. 9 PT 9.35–9.38", "ε tuyến tính (bar2s)\nTọa độ GỐC X, thêm N·θ", "K̄e = K_e0 + (N/L₀)·diag_trans(0,1,0,1)\nLặp cập nhật lực dọc N^(k)", "Bắt hiệu ứng P-Δ; chưa cập nhật tọa độ & giãn dài Py-ta-go."],
            ["3. Corotational UL (CALFEM-UL)\nJeffers 8.3; Yang Ch. 4", "ε_eng = (l − L₀)/L₀\nCấu hình BIẾN DẠNG x=X+u", "K_T = (EA/L₀)(nnᵀ) + (N/l)(I−nnᵀ)\n= bar2g đánh giá tại cấu hình hiện tại!", "Chính xác cho chuyển vị & góc xoay lớn bất kỳ; khách quan vật rắn!"],
            ["4. Total Lagrangian (NSA_4)\nNSA_4 Slides 6–12; McGuire 9.9", "ε_GL = (l² − L₀²)/(2L₀²)\nQuy chiếu ban đầu X (PK2)", "K_g = (S_N/L₀)·[[I, −I], [−I, I]]\nCó cả +1,−1 trên phương dọc trục!", "Khớp 100% công thức Slide 11–12 NSA_4; trùng khít UL khi ε ≪ 1."],
        ],
        head_color=C_NAVY, font_size=9.8,
    )
    _add_card(
        s6, 0.45, 5.1, 12.43, 1.85,
        "💡 Điểm sáng Học thuật — Tại sao [k_g] của CALFEM bar2g (0 trên trục dọc) khác [k_g] của Bài giảng NSA_4 (1 trên trục dọc)?",
        [
            "• CALFEM bar2g / Corotational UL dùng biến dạng kỹ thuật ε_eng = (l−L₀)/L₀ (lực dọc thực Cauchy N) → khi đạo hàm bậc hai chiều dài l theo chuyển vị dọc, số hạng dọc trục tự triệt tiêu, chỉ còn thành phần ngang (N/l).",
            "• Bài giảng NSA_4 (McGuire PT 9.9) giữ lại ½(du/dx)² trong biến dạng Green-Lagrange ε_GL (lực Piola-Kirchhoff loại 2) → xuất hiện thêm (S_N/L₀) trên cả trục dọc. Khi biến dạng đàn hồi nhỏ (ε ≈ 2,6×10⁻⁴), hai mô hình sai khác chỉ ~0,015%!",
        ],
        accent=C_AMBER, fill_color=C_LIGHT_AMBER, font_size=11.2,
    )

    # ==========================================================================
    # SLIDE 7: TÓM TẮT 6 THUẬT TOÁN GIẢI PHI TUYẾN (NSA_6)
    # ==========================================================================
    s7 = prs.slides.add_slide(blank)
    _add_header(s7, "Hệ thống 6 Thuật toán Giải Phi tuyến (Bài giảng NSA_6)", "Triển khai đầy đủ từ phương pháp bước đơn (Euler, RK2) đến lặp cân bằng & truy vết sau tới hạn", 7, TOTAL)
    _add_table(
        s7, 0.45, 1.25, 12.43, 5.5,
        ["Nhóm", "Thuật toán (NSA_6 & McGuire Ch. 12)", "Nguyên lý toán học cốt lõi", "Khả năng vượt Limit Point?"],
        [
            ["Bước đơn\n(Single-Step)", "1. Euler bước đơn (NSA_6 6.2, Slide 4)", "[Kt(u_{i-1})] {dΔ_i} = dλ_i {P_ref}; không hiệu chỉnh lực dư R.", "Không (sai số tích lũy lớn)"],
            ["Bước đơn\n(Single-Step)", "2. Runge-Kutta bậc 2 RK2 (Slide 5)", "Dự báo nửa bước u_mid → đánh giá [Kt(u_mid)] cho bước chính.", "Không (nhưng sai số nhỏ hơn Euler)"],
            ["Lặp cân bằng\n(Iterative)", "3. Full Newton-Raphson (Mục 6.3.1)", "Giữ dλ = 0 khi lặp; cập nhật [Kt] mỗi bước con để khử R → 0.", "Không vượt được điểm đỉnh A"],
            ["Lặp cân bằng\n(Iterative)", "4. Modified NR (Mục 6.3.4, Slide 21)", "Giữ nguyên [K_i^0] đầu bước cho mọi vòng lặp con → giảm lập Kt.", "Không vượt được điểm đỉnh A"],
            ["Sau tới hạn\n(Post-Limit)", "5. Điều khiển chuyển vị (Mục 6.3.2)", "Khống chế bậc tự do q không đổi khi lặp: dλ = −du_q'' / du_q'.", "CÓ — Vượt êm Snap-Through!"],
            ["Sau tới hạn\n(Post-Limit)", "6. Chiều dài cung Arc-Length (6.3.3)", "Ràng buộc mặt phẳng pháp tuyến {Δu}ᵀ{du} + ψ²s²Δλ·dλ = 0.", "TOÀN NĂNG — Snap-Through & Snap-Back!"],
        ],
        head_color=C_TEAL, font_size=10.5,
    )

    # ==========================================================================
    # SLIDE 8: KIỂM CHỨNG BENCHMARK SÁCH GỐC (EXS3 & DAHLBLOM EXAMPLE 9.1)
    # ==========================================================================
    s8 = prs.slides.add_slide(blank)
    _add_header(s8, "Kiểm chứng Lõi Python CALFEM trên 2 Ví dụ Chuẩn Sách gốc", "Xác minh bộ hàm bar2e, bar2g, bar2s, assem, solveq trùng khít 100% trước khi giải đề bài", 8, TOTAL)
    ex91 = data["benchmark_dahlblom_ex9_1"]["iterations"]
    book_ex91 = [
        ("−41,067", "−65,867", "−10,2667", "+0,3333"),
        ("−44,653", "−108,477", "−11,1632", "+1,4682"),
        ("−44,569", "−109,106", "−11,1421", "+1,4905"),
        ("−44,544", "−108,843", "−11,1359", "+1,4835"),
        ("−44,544", "−108,833", "−11,1360", "+1,4833"),
        ("−44,544", "−108,835", "−11,1360", "+1,4833"),
    ]
    rows_b = [
        [f"Vòng {k+1}", f"{book_ex91[k][0]} | {ex91[k]['u_mm'][4]:.3f}", f"{book_ex91[k][1]} | {ex91[k]['u_mm'][5]:.3f}",
         f"{book_ex91[k][2]} | {ex91[k]['N_N'][0]/1e6:.4f}", f"{book_ex91[k][3]} | {ex91[k]['N_N'][1]/1e6:+.4f}"]
        for k in range(6)
    ]
    _add_table(
        s8, 0.45, 1.25, 8.2, 4.4,
        ["Dahlblom Ex 9.1\n(tr. 261)", "a₅ (mm)\nSách | Python", "a₆ (mm)\nSách | Python", "Q₁ (MN)\nSách | Python", "Q₂ (MN)\nSách | Python"],
        rows_b, head_color=C_TEAL, font_size=10.0,
    )
    _add_card(
        s8, 8.85, 1.25, 4.03, 5.55,
        "Kết luận Kiểm chứng (6/6 PASS)",
        [
            "✓ Dahlblom Ex 9.1 (bar2g): Khớp TỪNG CHỮ SỐ cả 6 vòng lặp Bảng 1 sách tr. 261! (a₆ tăng gấp 1,65 lần do nén P-Δ).",
            "✓ CALFEM 3.4 exs3.m: u₅ = −0,3979 mm (sách −0,398), u₆ = −1,1523 mm (sách −1,152), ΔN < 0,5 N.",
            "✓ Tính khách quan vật rắn (Yang 2025): Xoay thanh cứng 37° sinh lực giả = 0,00×10⁰ N!",
            "✓ Kiểm tra tiếp tuyến sai phân trung tâm: sai số Frobenius = 3,47×10⁻¹³!",
        ],
        accent=C_NAVY, fill_color=C_LIGHT_BLUE, font_size=11.3,
    )
    _add_card(
        s8, 0.45, 5.8, 8.2, 1.0,
        "Kiểm chứng đồng bộ Dart Core vs Python Core",
        ["Bộ unit test tự động `flutter test` xác nhận lõi Dart chạy trên Android/Web khớp < 10⁻¹⁰ mm so với lõi Python NumPy!"],
        accent=C_TEAL, fill_color=C_LIGHT_TEAL, font_size=11.0,
    )

    # ==========================================================================
    # SLIDE 9: ĐỀ BÀI HỆ DÀN 4 NÚT – 5 THANH (1.JPG) & SỐ HÓA CALFEM
    # ==========================================================================
    s9 = prs.slides.add_slide(blank)
    _add_header(s9, "Đề bài Hệ Dàn 4 Nút – 5 Thanh & Mô hình Hóa CALFEM", "Số liệu đầu vào từ DeBai/1.jpg quy đổi thống nhất về hệ N – mm – MPa", 9, TOTAL)
    _add_picture_fit(s9, debai_img, 0.45, 1.2, 5.8, 5.65)
    _add_card(
        s9, 6.45, 1.2, 6.43, 2.2,
        "Thông số đầu vào & Điều kiện biên",
        [
            "• L = 1000 mm; E = 200.000 MPa (200 GPa); A = 2001 mm²; P = 208.000 N hướng LÊN (+Y) tại Nút 2.",
            "• Hai thanh chéo 3–2 và 2–4 có diện tích 2√2·A = 5659,68 mm².",
            "• Gối Nút 1 (0, 0): Khớp cố định (ux1 = uy1 = 0). Gối Nút 4 (2000, 1000): Con lăn trên (uy4 = 0, ux4 tự do).",
            "• Tổng 8 DOF − 3 gối = 5 bậc tự do tự do [ux2, uy2, ux3, uy3, ux4].",
        ],
        accent=C_NAVY, fill_color=C_WHITE, font_size=11.2,
    )
    _add_table(
        s9, 6.45, 3.55, 6.43, 3.3,
        ["Thanh", "Nút i→j", "L₀ (mm)", "Aₑ (mm²)", "EAₑ/L₀", "Edof"],
        [
            ["1", "1→2", "1000,0", "2001,0", "400.200", "[1,1,2,3,4]"],
            ["2", "1→3", "1000,0", "2001,0", "400.200", "[2,1,2,5,6]"],
            ["3", "3→4", "2000,0", "2001,0", "200.100", "[3,5,6,7,8]"],
            ["4", "3→2", "1414,2", "5659,7", "800.400", "[4,5,6,3,4]"],
            ["5", "2→4", "1414,2", "5659,7", "800.400", "[5,3,4,7,8]"],
        ],
        head_color=C_TEAL, font_size=9.8,
    )

    # ==========================================================================
    # SLIDE 10: BƯỚC 1 — NGHIỆM CƠ SỞ TUYẾN TÍNH & MÔ PHỎNG ỨNG SUẤT ANSYS
    # ==========================================================================
    s10 = prs.slides.add_slide(blank)
    _add_header(s10, "Bước 1: Nghiệm Cơ sở Tuyến tính (bar2e = SAP2000) & Bản đồ Ứng suất", "Hệ tĩnh định m + r = 5 + 3 = 2j = 8; CALFEM bar2e khớp Giải tích & SAP2000 tới 1,21×10⁻¹⁷ mm", 10, TOTAL)
    _add_picture_fit(s10, os.path.join(fig_dir, "fig01_mo_hinh_va_bien_dang.png"), 0.4, 1.15, 12.53, 4.55)
    _add_card(
        s10, 0.45, 5.8, 12.43, 1.18,
        "Điểm mốc cơ sở Tuyến tính (q = PL/EA = 0,519740 mm)",
        [
            "• Chuyển vị: u₂x = 0; u₂y = 5q/4 = +0,649675 mm; u₃x = −0,129935 mm; u₃y = +0,259870 mm; u₄x = +0,389805 mm.",
            "• Nội lực & Ứng suất: Thanh 1–2 = 0 kN (không lực!); Thanh 1–3 & 3–4 = +104 kN (Kéo, +51,97 MPa); Thanh 3–2 & 2–4 = −147,08 kN (Nén, −25,99 MPa); R₁y = R₄y = −104 kN.",
        ],
        accent=C_NAVY, fill_color=C_LIGHT_BLUE, font_size=11.0,
    )

    # ==========================================================================
    # SLIDE 11: BƯỚC 2 & 3 — GIẢI PHI TUYẾN HÌNH HỌC CALFEM (bar2g & UL FULL NR)
    # ==========================================================================
    s11 = prs.slides.add_slide(blank)
    _add_header(s11, "Bước 2 & 3: Quá trình Lặp Phi tuyến Hình học (CALFEM-UL Full NR)", "Chia 10 bước gia tải λ = 0,1..1,0 (NSA_6 Slide 24); hội tụ bậc hai đạt phần dư < 10⁻¹¹ N chỉ sau 2–3 vòng lặp/bước", 11, TOTAL)
    nr_hist = data["corotational_nr"]["history"]
    rows_s11 = [
        [f"Bước {h['step']}", f"{h['lambda']:.1f}", f"{h['lambda']*208:.1f}", f"{h['u_mm'][3]:.6f}", f"{h['u_mm'][6]:.6f}", f"{h['N_N'][0]:+.4f}", f"{h['iterations']}", f"{h['residual_inf_N']:.2e}"]
        for h in nr_hist[1:]
    ]
    _add_table(
        s11, 0.45, 1.2, 8.45, 5.65,
        ["Bước", "λ", "λP (kN)", "u₂y (mm)", "u₄x (mm)", "N₁₂ (N)", "Lặp", "||Rf||∞ (N)"],
        rows_s11, head_color=C_NAVY, font_size=9.5,
    )
    _add_card(
        s11, 9.1, 1.2, 3.78, 5.65,
        "Kiểm chứng Tại bước cuối λ = 1",
        [
            "• N₁₂ tăng theo quy luật BẬC HAI (từ 0,136 N ở λ=0,1 lên 13,552 N ở λ=1,0 — tăng đúng 100 lần khi tải tăng 10 lần!).",
            "• Tiếp tuyến sai phân trung tâm:\n  ||Kt_FD − Kt|| / ||Kt|| = 3,47×10⁻¹³.",
            "• Cân bằng cấu hình biến dạng:\n  ∑Fx = 0; ∑Fy = 0;\n  ∑M_deformed < 10⁻⁶ N·mm.",
            "• Quy tắc đòn bẩy biến dạng:\n  R₄y·(2L+u₄x) + P·(L+u₂x) ≈ 0!",
        ],
        accent=C_TEAL, fill_color=C_LIGHT_TEAL, font_size=11.3,
    )

    # ==========================================================================
    # SLIDE 12: ĐỐI CHIẾU 6 THUẬT TOÁN GIẢI PHI TUYẾN (NSA_6)
    # ==========================================================================
    s12 = prs.slides.add_slide(blank)
    _add_header(s12, "So sánh 6 Thuật toán Giải Phi tuyến trong Bài giảng NSA_6", "Minh họa rõ sai số tích lũy của Euler, độ chính xác của RK2 và sự đánh đổi giữa Full NR vs Modified NR", 12, TOTAL)
    _add_picture_fit(s12, os.path.join(fig_dir, "fig05_so_sanh_thuat_toan_NSA6.png"), 0.4, 1.15, 12.53, 4.45)
    _add_card(
        s12, 0.45, 5.7, 12.43, 1.28,
        "Nhận xét thực hành lựa chọn thuật toán",
        [
            "• Euler bước đơn tích lũy lực dư lớn (21,6 N ở 1P; > 1,8 MN ở 250P) vì không lặp khử R. RK2 giảm sai số hàng nghìn lần nhưng vẫn không triệt tiêu hoàn toàn lực dư.",
            "• Full NR hội tụ bậc 2 cực nhanh (chỉ 4 vòng lặp/bước ở 250P = 41 lần lập Kt); Modified NR chỉ lập Kt 10 lần nhưng tốn 123 vòng lặp con. Cả hai cho nghiệm cân bằng chuẩn tuyệt đối!",
        ],
        accent=C_NAVY, fill_color=C_LIGHT_BLUE, font_size=10.8,
    )

    # ==========================================================================
    # SLIDE 13: TỔNG HỢP SO SÁNH 4 MÔ HÌNH TẠI P = 208 kN
    # ==========================================================================
    s13 = prs.slides.add_slide(blank)
    _add_header(s13, "So sánh Định lượng 4 Mô hình tại Tải Đề bài P = 208 kN", "Tất cả 3 mô hình phi tuyến đều đồng thuận về xu hướng mềm hóa (+u₂y), hồi sinh thanh 1–2 và lệch phản lực gối", 13, TOTAL)
    _add_picture_fit(s13, os.path.join(fig_dir, "fig02_so_sanh_noi_luc_ung_suat.png"), 0.4, 1.12, 12.53, 3.85)
    rl, rb, rc, rt = data["linear"], data["bar2g_second_order"], data["corotational_nr"], data["total_lagrangian"]
    _add_table(
        s13, 0.45, 5.08, 12.43, 1.9,
        ["Mô hình phân tích", "u₂y (mm)", "Δu₂y vs TT", "N₁₂ (N)", "N₃₂ (kN)", "R₁y (kN)", "R₄y (kN)"],
        [
            ["1. Tuyến tính (bar2e / SAP2000)", f"{rl['u_mm'][3]:.6f}", "0,000%", "0,0000", f"{rl['N_N'][3]/1e3:.4f}", "−104,0000", "−104,0000"],
            ["2. CALFEM bar2g (Bậc 2 gốc)", f"{rb['u_mm'][3]:.6f}", "+0,048%", f"{rb['N_N'][0]:+.4f}", f"{rb['N_N'][3]/1e3:.4f}", f"{rb['reactions_N'][1]/1e3:.4f}", f"{rb['reactions_N'][7]/1e3:.4f}"],
            ["3. Corotational UL (Full NR)", f"{rc['u_mm'][3]:.6f}", "+0,072%", f"{rc['N_N'][0]:+.4f}", f"{rc['N_N'][3]/1e3:.4f}", f"{rc['reactions_N'][1]/1e3:.4f}", f"{rc['reactions_N'][7]/1e3:.4f}"],
            ["4. Total Lagrangian (NSA_4)", f"{rt['u_mm'][3]:.6f}", "+0,057%", f"{rt['N_N'][0]:+.4f}", f"{rt['N_N'][3]/1e3:.4f}", f"{rt['reactions_N'][1]/1e3:.4f}", f"{rt['reactions_N'][7]/1e3:.4f}"],
        ],
        head_color=C_NAVY, font_size=9.8,
    )

    # ==========================================================================
    # SLIDE 14: BẢN CHẤT VẬT LÝ 1 & 2 (THANH 1-2 HỒI SINH & ĐÒN BẨY PHẢN LỰC)
    # ==========================================================================
    s14 = prs.slides.add_slide(blank)
    _add_header(s14, "Bản chất Vật lý 1 & 2: Thanh 1–2 'Hồi sinh' & Bất đối xứng Phản lực", "Hai hiện tượng cơ học tuyệt đẹp có thể giải thích trọn vẹn chỉ bằng Định lý Py-ta-go và Quy tắc đòn bẩy!", 14, TOTAL)
    _add_card(
        s14, 0.45, 1.25, 6.05, 5.55,
        "1. Vì sao Thanh không lực 1–2 đột ngột chịu KÉO (+13,55 N)?",
        [
            "• Trong tuyến tính: tại Nút 1 không có lực ngang ngoài, thanh 1–3 thẳng đứng → bắt buộc N₁₂ = 0.",
            "• Trong phi tuyến hình học, hai cơ chế cùng hoạt động:",
            "   (a) Thanh đứng 1–3 chịu kéo lớn (+104 kN) nhưng đầu trên Nút 3 dịch sang TRÁI u₃x = −0,130 mm → thanh 1–3 nghiêng nhẹ sang trái góc θ ≈ 1,30×10⁻⁴ rad → sinh lực ngang kéo Nút 1 sang trái ≈ 13,55 N!",
            "   (b) Vì gối 1 không có phản lực ngang (R₁x = 0), thanh 1–2 BẮT BUỘC phải kéo sang phải đúng N₁₂ = +13,55 N để giữ cân bằng Nút 1!",
            "   (c) Đồng thời theo Py-ta-go khi Nút 2 nhấc lên, thanh 1–2 bị kéo giãn như dây căng (luôn chịu KÉO ở cả hai chiều tải +P và −P!).",
        ],
        accent=C_TEAL, fill_color=C_LIGHT_TEAL, font_size=12.0,
    )
    _add_card(
        s14, 6.82, 1.25, 6.05, 5.55,
        "2. Vì sao |R₁y| = 104,020 kN lớn hơn |R₄y| = 103,980 kN?",
        [
            "• Ở hình dạng ban đầu, lực P nằm chính giữa nhịp 2L = 2000 mm nên mỗi gối gánh đúng 50% (−104,000 kN).",
            "• Khi biến dạng dưới tải +P: gối con lăn Nút 4 trượt sang PHẢI u₄x = +0,3898 mm, còn Nút 2 hơi dịch sang TRÁI u₂x = −0,00018 mm.",
            "• Áp dụng Quy tắc đòn bẩy Vật lý 10 trên cấu hình BIẾN DẠNG:",
            "     R₄y = −P · (L + u₂x) / (2L + u₄x)",
            "         = −208.000 × 999,9998 / 2000,3898 = −103,9797 kN!",
            "     R₁y = −208,000 − (−103,9797) = −104,0203 kN!",
            "• Ý nghĩa: Nhịp gối mở rộng → tải lệch gần gối 1 hơn → gối 1 gánh nặng hơn gối 4 đúng 40,57 N!",
        ],
        accent=C_NAVY, fill_color=C_LIGHT_BLUE, font_size=12.0,
    )

    # ==========================================================================
    # SLIDE 15: BẢN CHẤT VẬT LÝ 3 — MỀM HÓA (+P) VS CỨNG HÓA (−P)
    # ==========================================================================
    s15 = prs.slides.add_slide(blank)
    _add_header(s15, "Bản chất Vật lý 3: Bất đối xứng Mềm hóa (+P) vs Cứng hóa (−P)", "Tuyến tính hoàn toàn đối xứng khi đảo chiều lực — Phi tuyến hình học cho thấy hai ứng xử trái ngược nhau!", 15, TOTAL)
    _add_picture_fit(s15, os.path.join(fig_dir, "fig03_mem_hoa_va_cung_hoa.png"), 0.4, 1.15, 12.53, 4.65)
    _add_card(
        s15, 0.45, 5.88, 12.43, 1.08,
        "Bản chất cơ học",
        [
            "• Lực +P hướng LÊN: hai thanh chéo (3–2, 2–4) bị NÉN và dẹt dần (góc < 45°) → mất độ cứng (MỀM HÓA). Lực −P hướng XUỐNG: hai thanh chéo chịu KÉO và dốc lên (> 45°) → hiệu ứng dây võng (CỨNG HÓA). Thanh 1–2 luôn KÉO ở cả hai chiều!",
        ],
        accent=C_RED, fill_color=RGBColor(0xFE, 0xF2, 0xF2), font_size=11.0,
    )

    # ==========================================================================
    # SLIDE 16: BẢN CHẤT VẬT LÝ 4 — ĐỘ NHẠY TẢI LỚN 1P → 500P
    # ==========================================================================
    s16 = prs.slides.add_slide(blank)
    _add_header(s16, "Bản chất Vật lý 4: Sự Bùng nổ Phi tuyến khi Tăng tải (1P → 500P)", "Tại tải đề bài (1P) sai lệch chỉ 0,072% (chuyển vị nhỏ hợp lệ), nhưng bùng nổ lên +303% khi vượt điểm bật nhảy!", 16, TOTAL)
    _add_picture_fit(s16, os.path.join(fig_dir, "fig04_do_nhay_phi_tuyen_theo_tai.png"), 0.4, 1.12, 12.53, 3.85)
    ls = data["load_scale_study"]
    _add_table(
        s16, 0.45, 5.05, 12.43, 1.95,
        ["Mức tải", "1P (208 kN)", "10P (2,08 MN)", "50P (10,4 MN)", "100P (20,8 MN)", "250P (52 MN)", "500P (104 MN — Đã bật nhảy!)"],
        [
            ["u₂y Tuyến tính (mm)", *[f"{r['u2y_lin_mm']:.2f}" for r in ls]],
            ["u₂y Corotational (mm)", *[f"{r['u2y_corot_mm']:.2f}" for r in ls]],
            ["Lệch Phi tuyến / TT", *[f"{r['pct_diff_corot_vs_lin']:+.2f}%" for r in ls]],
            ["Lực thanh 1–2, N₁₂ (kN)", *[f"{r['N12_corot_kN']:+.2f}" for r in ls]],
        ],
        head_color=C_AMBER, font_size=9.5,
    )

    # ==========================================================================
    # SLIDE 17: BẢN CHẤT VẬT LÝ 5 — PHÁT HIỆN BẬT NHẢY SNAP-THROUGH THỰC THỤ!
    # ==========================================================================
    s17 = prs.slides.add_slide(blank)
    _add_header(s17, "Phát hiện Đột phá: Bật nhảy Snap-Through thực thụ của Dàn 5 Thanh!", "Truy vết toàn phần bằng Điều khiển chuyển vị / Chiều dài cung (NSA_6 6.3.2–6.3.3)", 17, TOTAL)
    _add_picture_fit(s17, os.path.join(fig_dir, "fig06_duong_cong_can_bang_snap_through.png"), 0.4, 1.15, 12.53, 4.65)
    _add_card(
        s17, 0.45, 5.88, 12.43, 1.1,
        "Bài học Vàng về Ổn định Kết cấu (McGuire Ch. 8 & Jeffers Ch. 8)",
        [
            "• Dàn 5 thanh đạt Điểm Giới Hạn thực P_lim = 78,45 MN tại u₂y = 480 mm rồi rơi vào nhánh mất ổn định (đỏ, det Kt < 0) xuống thung lũng 2,80 MN (u₂y = 840 mm) trước khi cứng hóa lại dạng dây căng! Tải trị riêng tuyến tính hóa (346 MN) ĐÁNH GIÁ CAO QUÁ MỨC GẤP 4,41 LẦN!",
        ],
        accent=C_RED, fill_color=RGBColor(0xFE, 0xF2, 0xF2), font_size=10.8,
    )

    # ==========================================================================
    # SLIDE 18: PHÂN TÍCH TRỊ RIÊNG BUCKLING & GIỚI HẠN THIẾT KẾ THỰC TẾ
    # ==========================================================================
    s18 = prs.slides.add_slide(blank)
    _add_header(s18, "Phân tích Trị riêng Tải tới hạn Đàn hồi & Ranh giới Thực tế", "Giải (Ke + α_cr·Kg)·φ = 0 bằng CALFEM bar2g (NSA_4 Mục 4.2 & Dahlblom Mục 9.1)", 18, TOTAL)
    _add_picture_fit(s18, os.path.join(fig_dir, "fig07_dang_mat_on_dinh_buckling.png"), 0.4, 1.15, 12.53, 4.45)
    _add_card(
        s18, 0.45, 5.7, 12.43, 1.28,
        "Lưu ý kỹ thuật quan trọng (tránh hiểu nhầm khi thiết kế công trình thật)",
        [
            "• Mode 1 trị riêng (CALFEM bar2g): α_cr = 1.663,45 → P_cr = 346,0 MN (Mode 1 NSA_4: 418,9 MN). Đây là mất ổn định TỔNG THỂ đàn hồi lý tưởng.",
            "• Trên kết cấu thép thực (fy = 250 MPa): thanh kéo 1–3 & 3–4 chảy dẻo sớm tại P ≈ 1.000 kN (λ ≈ 4,81), còn thanh nén chéo 3–2 bị oằn cục bộ Euler P_cr = π²EI/L² trước rất xa tải bật nhảy đàn hồi → Thiết kế thực phải xét đồng thời phi tuyến vật liệu & oằn cục bộ!",
        ],
        accent=C_NAVY, fill_color=C_LIGHT_BLUE, font_size=10.8,
    )

    # ==========================================================================
    # SLIDE 19: PHẪU THUẬT MẶT CẮT NGANG & MỔ DỌC THANH (ANSYS SURGICAL LAB)
    # ==========================================================================
    s19 = prs.slides.add_slide(blank)
    _add_header(s19, "Chức năng 'Phẫu thuật Mặt cắt' & Khảo sát Nội bộ chuẩn ANSYS", "Cắt mở thanh tại tọa độ ξ bất kỳ — soi ứng suất thớ (η, ζ), hiệu ứng Poisson và khuếch đại P-δ (NSA_4 Slide 27)", 19, TOTAL)
    _add_picture_fit(s19, os.path.join(fig_dir, "fig08_phau_thuat_mat_cat_ANSYS.png"), 0.4, 1.15, 12.53, 4.6)
    _add_card(
        s19, 0.45, 5.85, 12.43, 1.12,
        "Giá trị trực quan của tính năng Phẫu thuật 3D trong phần mềm",
        [
            "• Cho phép chuyển đổi tức thì 4 tiết diện 3D tương đương diện tích Aₑ (Chữ I, Ống tròn, Hộp vuông, Tròn đặc), quan sát thót/phình ngang Poisson ε_yy = −ν·ε_xx và bật sai lệch ban đầu e₀/L để thấy ứng suất nén cực đại lệch hai mép do mô-men bậc hai N·e₀·DAF!",
        ],
        accent=C_TEAL, fill_color=C_LIGHT_TEAL, font_size=10.8,
    )

    # ==========================================================================
    # SLIDE 20: KIẾN TRÚC LẬP TRÌNH PYTHON (`python_core/`)
    # ==========================================================================
    s20 = prs.slides.add_slide(blank)
    _add_header(s20, "Kiến trúc Lõi Tính toán Python (Chú thích Tiếng Việt Đầy đủ)", "Tách lớp mô-đun rõ ràng để Thầy hướng dẫn và các bạn trong lớp đọc mã nguồn như giáo trình tương tác", 20, TOTAL)
    _add_table(
        s20, 0.45, 1.2, 12.43, 4.0,
        ["Mô-đun Python", "Các hàm cốt lõi", "Nhiệm vụ & Ý nghĩa sư phạm"],
        [
            ["calfem_elements.py", "bar2e, bar2g, bar2s, assem, solveq, extract, bar2g_corotational, bar2g_total_lagrangian", "Đúng chuẩn CALFEM 3.4 + 2 công thức chuyển vị lớn khử sai số làm tròn."],
            ["truss_models.py", "TrussModel, CrossSectionSpec, create_assignment_5bar_truss, create_dahlblom_example_9_1", "Mô hình đề bài tham số hóa + các bài toán benchmark sách gốc + tiết diện 3D."],
            ["nonlinear_solvers.py", "6 bộ giải NSA_6 (Euler, RK2, Full NR, Mod NR, Disp Control, Arc-Length) + Buckling Eigen", "Giải trọn vẹn từ tuyến tính đến bật nhảy Snap-Through & kiểm tra tiếp tuyến."],
            ["probe_dissection.py", "probe_member_at, dissect_cross_section, compute_longitudinal_profile", "Nội suy chuyển vị/ứng suất tại mọi vị trí (e, ξ, η, ζ) & phẫu thuật mặt cắt."],
            ["report_exporter.py & api_server.py", "export_quick_docx_report, export_quick_pdf_report, CalfemAPIHandler", "Xuất thuyết minh Word/PDF tự động & đóng gói `calfem_engine.exe` cho Windows."],
        ],
        head_color=C_NAVY, font_size=10.2,
    )
    _add_card(
        s20, 0.45, 5.38, 12.43, 1.55,
        "Bộ Kiểm thử Tự động (`python_core/test_verification.py`) & Đóng gói PyInstaller",
        [
            "• Lệnh chạy kiểm thử: `python -m python_core.test_verification` — tự động xác minh toàn bộ 6 trụ cột khoa học (exs3, Dahlblom Ex 9.1, giải tích 5 thanh, xoay vật rắn 37°, tiếp tuyến sai phân 3,47×10⁻¹³, cân bằng đòn bẩy biến dạng & Snap-Through).",
            "• Đóng gói thành tệp độc lập `calfem_engine.exe` nhúng trực tiếp vào ứng dụng Flutter Windows để chạy trên bất kỳ máy tính Windows nào không cần cài Python!",
        ],
        accent=C_TEAL, fill_color=C_LIGHT_TEAL, font_size=11.0,
    )

    # ==========================================================================
    # SLIDE 21: GIAO DIỆN FLUTTER DART 2D/3D ANSYS & TRIỂN KHAI ĐA NỀN TẢNG
    # ==========================================================================
    s21 = prs.slides.add_slide(blank)
    _add_header(s21, "Giao diện Flutter Dart 2D/3D chuẩn ANSYS & Đóng gói Đa nền tảng", "Một mã nguồn chạy mượt 120Hz trên Windows (.exe), Android (.apk — Xiaomi Pad 8 Pro & 13T Pro) và GitHub Web!", 21, TOTAL)
    app_shot = os.path.join(fig_dir, "fig09_app_flutter_3d_ansys.png")
    if os.path.exists(app_shot):
        _add_picture_fit(s21, app_shot, 0.45, 1.18, 7.6, 5.7)
        _add_card(
            s21, 8.25, 1.18, 4.63, 5.7,
            "Tính năng Nổi bật & Đóng gói",
            [
                "• Chế độ 2D & 3D ANSYS thật: đổ bóng Phong 3D, xoay 360°, Pan, Zoom, nút ISO/XY/XZ/YZ, thang màu cầu vồng.",
                "• Phẫu thuật 3D cắt mở thanh tại vị trí ξ & soi ứng suất/biến dạng bên trong mặt cắt ngang.",
                "• Xuất thuyết minh Word (.docx) & PDF (.pdf) 1 chạm ngay trong ứng dụng!",
                "• Windows (.exe): Chạy trực tiếp trên mọi máy Windows, kết nối live Python `calfem_engine.exe`.",
                "• Android (.apk ARM64): Giao diện 3 cột trên Xiaomi Pad 8 Pro & 5 tab cảm ứng trên Xiaomi 13T Pro.",
                "• Chạy trực tiếp trên GitHub Pages:\nvothanhvang.github.io/\nPhanTichPhiTuyen_BaiTieuLuan4/",
            ],
            accent=C_NAVY, fill_color=C_LIGHT_BLUE, font_size=11.0,
        )
    else:
        _add_card(
            s21, 0.45, 1.25, 6.0, 5.55,
            "Trải nghiệm Mô phỏng 2D/3D chuẩn ANSYS trong Flutter Dart",
            [
                "• Màn hình 2D & 3D thật (Phong Shading + Z-Buffer): dựng khối 3D tiết diện chữ I / Ống tròn / Hộp / Tròn đặc + khớp trụ 3D.",
                "• Điều khiển y hệt ANSYS: Kéo xoay 3D 360°, kéo phải/2 ngón Pan, cuộn/chụm Zoom, góc nhìn nhanh ISO/XY/XZ/YZ.",
                "• Chế độ 'Phẫu thuật 3D': mặt cắt xanh lơ cắt xuyên thanh tại ξ, làm trong suốt phần sau để soi mặt cắt & mũi tên nội lực!",
                "• Tích hợp sẵn 1 chạm xuất Thuyết minh Word (.docx) & Báo cáo PDF (.pdf) ngay trên mọi thiết bị!",
            ],
            accent=C_NAVY, fill_color=C_LIGHT_BLUE, font_size=12.0,
        )
        _add_card(
            s21, 6.8, 1.25, 6.08, 5.55,
            "Đóng gói 3 Nền tảng & Chạy trực tiếp trên GitHub",
            [
                "1. Windows x64 (.exe): `releases/PhanTichPhiTuyen_CALFEM_Windows_x64.exe` — mở là chạy trên mọi PC Windows 10/11, tự kết nối lõi Python `calfem_engine.exe`!",
                "2. Android ARM64 (.apk): `releases/PhanTichPhiTuyen_CALFEM_Android_arm64.apk` — bố cục thích ứng 3 cột trên Xiaomi Pad 8 Pro (11.2\") và 5 tab gọn đẹp trên Xiaomi 13T Pro (6.67\").",
                "3. Chạy trực tiếp trên GitHub Pages: `https://vothanhvang.github.io/PhanTichPhiTuyen_BaiTieuLuan4/` — Thầy và các bạn trong lớp mở trình duyệt dùng ngay không cần cài đặt!",
            ],
            accent=C_TEAL, fill_color=C_LIGHT_TEAL, font_size=12.0,
        )

    # ==========================================================================
    # SLIDE 22: KẾT LUẬN & CẢM ƠN
    # ==========================================================================
    s22 = prs.slides.add_slide(blank)
    _set_slide_bg(s22, C_DARK)
    strip22 = s22.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0), Inches(0), Inches(13.333), Inches(0.14))
    strip22.fill.solid()
    strip22.fill.fore_color.rgb = C_CYAN
    strip22.line.fill.background()

    _add_card(
        s22, 0.7, 0.7, 11.93, 4.15,
        "TỔNG KẾT NHỮNG ĐÓNG GÓP CHÍNH CỦA TIỂU LUẬN",
        [
            "1. Hoàn chỉnh lời giải Phi tuyến Hình học CALFEM 4 cấp (bar2e → bar2g → Corotational UL → Total Lagrangian NSA_4) và 6 thuật toán giải (NSA_6), xác minh tuyệt đối trên Dahlblom Example 9.1 & CALFEM exs3.m.",
            "2. Giải mã tường minh 5 bản chất vật lý cốt lõi (học sinh cấp 3 vẫn hiểu rõ): hồi sinh thanh 1–2, đòn bẩy phản lực biến dạng, mềm hóa (+P) vs cứng hóa (−P), bùng nổ phi tuyến tải lớn và phát hiện bật nhảy Snap-Through thực P_lim = 78,45 MN (thấp hơn 4,41 lần tải trị riêng!).",
            "3. Xây dựng trọn bộ hệ sinh thái phần mềm Python + Flutter Dart 2D/3D chuẩn ANSYS có Phẫu thuật mặt cắt & xuất Word/PDF, đóng gói sẵn .exe Windows, .apk Android (Xiaomi Pad 8 Pro & 13T Pro) và triển khai chạy trực tiếp trên GitHub!",
        ],
        accent=C_CYAN, fill_color=RGBColor(0x11, 0x1E, 0x38), font_size=13.0,
    )
    # Đổi màu chữ nội dung card cuối sang trắng sáng trên nền tối
    for sh in s22.shapes:
        if sh.has_text_frame:
            for idx_p, p in enumerate(sh.text_frame.paragraphs):
                if idx_p > 0:
                    for r in p.runs:
                        r.font.color.rgb = RGBColor(0xE2, 0xE8, 0xF0)

    tb_end = s22.shapes.add_textbox(Inches(0.7), Inches(5.15), Inches(11.93), Inches(1.85))
    etf = tb_end.text_frame
    etf.word_wrap = True
    pe1 = etf.paragraphs[0]
    pe1.alignment = PP_ALIGN.CENTER
    re1 = pe1.add_run()
    re1.text = "TRÂN TRỌNG CẢM ƠN PGS.TS. NGÔ HỮU CƯỜNG VÀ CÁC BẠN ĐÃ LẮNG NGHE!"
    re1.font.name = FONT_MAIN
    re1.font.size = Pt(22)
    re1.font.bold = True
    re1.font.color.rgb = C_WHITE

    pe2 = etf.add_paragraph()
    pe2.alignment = PP_ALIGN.CENTER
    pe2.space_before = Pt(10)
    re2 = pe2.add_run()
    re2.text = "Mời Thầy và các bạn trải nghiệm trực tiếp Demo phần mềm 2D/3D ANSYS & Phẫu thuật mặt cắt tại:\nhttps://vothanhvang.github.io/PhanTichPhiTuyen_BaiTieuLuan4/"
    re2.font.name = FONT_MAIN
    re2.font.size = Pt(13.5)
    re2.font.color.rgb = RGBColor(0x34, 0xD3, 0x99)

    out_pptx = os.path.join(base_dir, "BaoCao_PhanTichPhiTuyenHinhHoc_CALFEM.pptx")
    prs.save(out_pptx)
    print(f"Đã tạo thành công bài trình chiếu PowerPoint ({TOTAL} slide): {out_pptx}")
    return out_pptx


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    build_pptx(root)
