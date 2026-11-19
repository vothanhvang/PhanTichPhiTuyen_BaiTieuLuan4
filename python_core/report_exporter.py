# -*- coding: utf-8 -*-
"""
================================================================================
MÔ-ĐUN 5: BỘ XUẤT THUYẾT MINH TỰ ĐỘNG ĐỊNH DẠNG WORD (.DOCX) VÀ PDF (.PDF)
================================================================================
Mục đích:
  Tích hợp trực tiếp vào phần mềm tính toán (cả CLI Python lẫn giao diện Flutter
  Desktop qua API cục bộ) để người dùng khi thay đổi bất kỳ thông số nào (L, E, A,
  P, loại mặt cắt, phương pháp giải) đều có thể nhấn nút "Xuất Thuyết Minh Word"
  hoặc "Xuất Báo Cáo PDF" và nhận ngay báo cáo chuyên nghiệp đầy đủ:
    - Tóm tắt đầu vào & công thức cơ học / toán học áp dụng (có dẫn nguồn sách)
    - Bảng chuyển vị nút & phản lực gối (so sánh Tuyến tính vs Phi tuyến)
    - Bảng nội lực, ứng suất, biến dạng & hiệu ứng thanh 1-2 hồi sinh
    - Kết quả khảo sát điểm & phẫu thuật mặt cắt (nếu có)
    - Nhận xét bản chất vật lý tự động theo kết quả thực tế!

  Hỗ trợ đầy đủ tiếng Việt có dấu trên cả Word (.docx dùng `python-docx` với font
  Times New Roman) và PDF (.pdf dùng `reportlab` nhúng font Unicode Windows
  Times New Roman / Arial / DejaVuSans).
================================================================================
"""

from __future__ import annotations
import os
import datetime
from typing import Dict, Any, Optional
import numpy as np

from docx import Document
from docx.shared import Inches, Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn

from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

from .truss_models import TrussModel
from .nonlinear_solvers import AnalysisResult


def _shade_cell(cell, hex_color: str) -> None:
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{hex_color}"/>')
    cell._tc.get_or_add_tcPr().append(shading)


def _set_table_borders(table) -> None:
    tblPr = table._tbl.tblPr
    borders = parse_xml(
        f'<w:tblBorders {nsdecls("w")}>'
        '<w:top w:val="single" w:sz="6" w:space="0" w:color="1B365D"/>'
        '<w:bottom w:val="single" w:sz="8" w:space="0" w:color="1B365D"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        "</w:tblBorders>"
    )
    tblPr.append(borders)


def export_quick_docx_report(
    output_path: str,
    model: TrussModel,
    res_linear: AnalysisResult,
    res_nonlinear: AnalysisResult,
    res_bar2g: Optional[AnalysisResult] = None,
    buckling_info: Optional[Dict[str, Any]] = None,
    probe_info: Optional[Dict[str, Any]] = None,
    author_name: str = "Võ Thanh Vang (MSHV: 2670624)",
) -> str:
    """
    Xuất thuyết minh kết quả tính toán tức thời sang tệp Microsoft Word (.docx).
    """
    doc = Document()
    for sec in doc.sections:
        sec.top_margin = Cm(2.0)
        sec.bottom_margin = Cm(2.0)
        sec.left_margin = Cm(2.2)
        sec.right_margin = Cm(2.0)

    style_normal = doc.styles["Normal"]
    style_normal.font.name = "Times New Roman"
    style_normal.font.size = Pt(11.5)
    style_normal.font.color.rgb = RGBColor(0x1E, 0x29, 0x3B)

    # Tiêu đề
    p_org = doc.add_paragraph()
    p_org.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r_org = p_org.add_run("TRƯỜNG ĐẠI HỌC BÁCH KHOA – ĐHQG TP. HỒ CHÍ MINH\nKHOA KỸ THUẬT XÂY DỰNG – BỘ MÔN CÔNG TRÌNH")
    r_org.bold = True
    r_org.font.size = Pt(11)
    r_org.font.color.rgb = RGBColor(0x0F, 0x3D, 0x6E)

    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r_title = p_title.add_run(
        "\nTHUYẾT MINH KẾT QUẢ PHÂN TÍCH PHI TUYẾN HÌNH HỌC HỆ DÀN\nDỰA TRÊN THUẬT TOÁN CALFEM (bar2e / bar2g / COROTATIONAL UL)"
    )
    r_title.bold = True
    r_title.font.size = Pt(14)
    r_title.font.color.rgb = RGBColor(0x0F, 0x17, 0x2A)

    p_meta = doc.add_paragraph()
    p_meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_meta.add_run(
        f"Học viên: {author_name}  |  GVHD: PGS.TS. Ngô Hữu Cường\n"
        f"Thời gian xuất báo cáo: {datetime.datetime.now().strftime('%d/%m/%Y %H:%M:%S')}"
    ).italic = True

    def add_h(text: str):
        p = doc.add_paragraph()
        p.paragraph_format.space_before = Pt(10)
        p.paragraph_format.space_after = Pt(4)
        r = p.add_run(text)
        r.bold = True
        r.font.size = Pt(12.5)
        r.font.color.rgb = RGBColor(0x0F, 0x3D, 0x6E)

    # 1. Thông số mô hình
    add_h("1. THÔNG SỐ HÌNH HỌC, VẬT LIỆU VÀ TẢI TRỌNG ĐẦU VÀO")
    doc.add_paragraph(model.description)
    p_inp = doc.add_paragraph()
    p_inp.add_run(
        f"• Mô-đun đàn hồi Young: E = {model.E:,.1f} MPa ({model.E/1000:.1f} GPa); "
        f"Hệ số Poisson: ν = {model.nu:.2f}.\n"
        f"• Số nút: {model.n_nodes} ({model.n_dofs} bậc tự do tổng cộng, "
        f"{len(model.constrained_dofs_0based)} ràng buộc gối, {len(model.free_dofs_0based)} bậc tự do tự do).\n"
        f"• Phương pháp phi tuyến chính: {res_nonlinear.method_name} "
        f"(Hội tụ: {'ĐẠT' if res_nonlinear.converged else 'KHÔNG ĐẠT'})."
    )

    # 2. Tóm tắt công thức áp dụng
    add_h("2. TÓM TẮT CÔNG THỨC CƠ HỌC & DẪN NGUỒN TÀI LIỆU")
    doc.add_paragraph(
        "• Độ cứng tuyến tính CALFEM bar2e (calfem34.pdf tr. 5.3-2 / PDF tr. 60): "
        "Ke = (EA/L) · Gᵀ · [[1, -1], [-1, 1]] · G.\n"
        "• Độ cứng phi tuyến hình học CALFEM bar2g (calfem34.pdf tr. 5.3-3; Dahlblom 2016 PT 9.35-9.38 tr. 259): "
        "K̄e = (EA/L)·K̄e0 + (N/L)·K̄eσ.\n"
        "• Đồng chuyển động Corotational UL (Jeffers 2026 Mục 8.3 tr. 186; Yang 2025 Chương 4 tr. 119): "
        "l = √[(x₂'-x₁')² + (y₂'-y₁')²], ε_eng = (l - L₀)/L₀, N = EA·ε_eng, "
        "Kt = (EA/L₀)(n·nᵀ) + (N/l)(I - n·nᵀ).\n"
        "• Thuật toán lặp Newton-Raphson (Bài giảng NSA_6 Mục 6.3.1 Slides 10-14; McGuire 2000 Mục 12.3.1): "
        "[Kt]·{Δu} = λ{f_ref} - {f_int(u)}."
    )

    # 3. Bảng chuyển vị nút & phản lực
    add_h("3. KẾT QUẢ CHUYỂN VỊ NÚT VÀ PHẢN LỰC GỐI TỰA")
    t1 = doc.add_table(rows=1, cols=7)
    t1.alignment = WD_TABLE_ALIGNMENT.CENTER
    _set_table_borders(t1)
    headers1 = ["Nút", "ux Tuyến tính (mm)", "uy Tuyến tính (mm)", "ux Phi tuyến (mm)", "uy Phi tuyến (mm)", "Rx Phi tuyến (kN)", "Ry Phi tuyến (kN)"]
    for j, h in enumerate(headers1):
        c = t1.rows[0].cells[j]
        c.text = h
        _shade_cell(c, "1B365D")
        for r in c.paragraphs[0].runs:
            r.bold = True
            r.font.size = Pt(9.5)
            r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
    for i in range(model.n_nodes):
        row = t1.add_row().cells
        vals = [
            f"Nút {i+1}",
            f"{res_linear.u[2*i]:+.6f}",
            f"{res_linear.u[2*i+1]:+.6f}",
            f"{res_nonlinear.u[2*i]:+.6f}",
            f"{res_nonlinear.u[2*i+1]:+.6f}",
            f"{res_nonlinear.reactions[2*i]/1000.0:+.6f}",
            f"{res_nonlinear.reactions[2*i+1]/1000.0:+.6f}",
        ]
        for j, v in enumerate(vals):
            row[j].text = v
            if i % 2 == 1:
                _shade_cell(row[j], "F1F5F9")
            for r in row[j].paragraphs[0].runs:
                r.font.size = Pt(9.5)

    # 4. Bảng nội lực, ứng suất, biến dạng
    add_h("4. KẾT QUẢ NỘI LỰC, ỨNG SUẤT VÀ BIẾN DẠNG CÁC THANH DÀN")
    t2 = doc.add_table(rows=1, cols=7)
    t2.alignment = WD_TABLE_ALIGNMENT.CENTER
    _set_table_borders(t2)
    headers2 = ["Thanh", "Diện tích A (mm²)", "N Tuyến tính (kN)", "N Phi tuyến (kN)", "σ Phi tuyến (MPa)", "ε (με)", "Chênh lệch ΔN (N)"]
    for j, h in enumerate(headers2):
        c = t2.rows[0].cells[j]
        c.text = h
        _shade_cell(c, "0F766E")
        for r in c.paragraphs[0].runs:
            r.bold = True
            r.font.size = Pt(9.5)
            r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
    for e in range(model.n_elems):
        row = t2.add_row().cells
        vals = [
            f"{e+1} ({model.member_labels[e]})",
            f"{model.areas[e]:.2f}",
            f"{res_linear.N[e]/1000.0:+.5f}",
            f"{res_nonlinear.N[e]/1000.0:+.5f}",
            f"{res_nonlinear.stress[e]:+.4f}",
            f"{res_nonlinear.strain[e]*1e6:+.2f}",
            f"{res_nonlinear.N[e] - res_linear.N[e]:+.3f}",
        ]
        for j, v in enumerate(vals):
            row[j].text = v
            if e % 2 == 1:
                _shade_cell(row[j], "F0FDFA")
            for r in row[j].paragraphs[0].runs:
                r.font.size = Pt(9.5)

    # 5. Kiểm chứng cân bằng & năng lượng
    add_h("5. KIỂM CHỨNG CÂN BẰNG CẤU HÌNH BIẾN DẠNG & BẢN CHẤT CƠ HỌC")
    eq = res_nonlinear.equilibrium_check
    doc.add_paragraph(
        f"• Cân bằng lực cấu hình biến dạng: ∑Fx = {eq['sum_Fx_N']:.3e} N; "
        f"∑Fy = {eq['sum_Fy_N']:.3e} N; ∑M = {eq['sum_M_Nmm']:.3e} N·mm; "
        f"Phần dư tự do lớn nhất = {eq['max_free_residual_N']:.3e} N.\n"
        f"• Năng lượng biến dạng tổng: Tuyến tính U_lin = {res_linear.total_energy/1000.0:.6f} J | "
        f"Phi tuyến U_nl = {res_nonlinear.total_energy/1000.0:.6f} J."
    )
    if buckling_info and buckling_info.get("modes_calfem_bar2g"):
        a_cr = buckling_info["modes_calfem_bar2g"][0]["alpha_cr"]
        p_cr = a_cr * buckling_info["P_ref_kN"]
        doc.add_paragraph(
            f"• Tải tới hạn đàn hồi tổng thể (trị riêng CALFEM bar2g): α_cr = {a_cr:,.2f} "
            f"=> P_cr = {p_cr:,.1f} kN."
        )
    if probe_info:
        add_h("6. KẾT QUẢ KHẢO SÁT & PHẪU THUẬT MẶT CẮT TẠI ĐIỂM ĐANG CHỌN")
        doc.add_paragraph(
            f"• Thanh {probe_info['member_label']} tại vị trí chuẩn hóa ξ = {probe_info['xi']:.2f} "
            f"(s = {probe_info['s_along_bar_mm']:.1f} mm), thớ (η={probe_info['fiber_eta_norm']:.2f}, ζ={probe_info['fiber_zeta_norm']:.2f}):\n"
            f"  - Ứng suất dọc trục σ_xx = {probe_info['sigma_xx_MPa']:+.4f} MPa | "
            f"Ứng suất von Mises = {probe_info['sigma_von_mises_MPa']:.4f} MPa | "
            f"τ_max (Mohr) = {probe_info['tau_max_mohr_MPa']:.4f} MPa.\n"
            f"  - Biến dạng dọc ε_xx = {probe_info['eps_xx_microstrain']:+.2f} με | "
            f"Co/nở ngang Poisson ε_yy = ε_zz = {probe_info['eps_yy_poisson_microstrain']:+.2f} με.\n"
            f"  - Góc xoay vật rắn thanh Δθ = {probe_info['rotation_delta_deg']:+.5f}°."
        )

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    doc.save(output_path)
    return output_path


def _register_unicode_pdf_fonts() -> tuple[str, str]:
    """Đăng ký font hệ thống Windows hỗ trợ trọn vẹn tiếng Việt có dấu cho ReportLab."""
    candidates = [
        ("VNSerif", "C:/Windows/Fonts/times.ttf", "VNSerifBold", "C:/Windows/Fonts/timesbd.ttf"),
        ("VNSans", "C:/Windows/Fonts/arial.ttf", "VNSansBold", "C:/Windows/Fonts/arialbd.ttf"),
        ("VNSegoe", "C:/Windows/Fonts/segoeui.ttf", "VNSegoeBold", "C:/Windows/Fonts/segoeuib.ttf"),
    ]
    for reg_name, reg_path, bold_name, bold_path in candidates:
        if os.path.exists(reg_path) and os.path.exists(bold_path):
            if reg_name not in pdfmetrics.getRegisteredFontNames():
                pdfmetrics.registerFont(TTFont(reg_name, reg_path))
            if bold_name not in pdfmetrics.getRegisteredFontNames():
                pdfmetrics.registerFont(TTFont(bold_name, bold_path))
            return reg_name, bold_name
    return "Helvetica", "Helvetica-Bold"


def export_quick_pdf_report(
    output_path: str,
    model: TrussModel,
    res_linear: AnalysisResult,
    res_nonlinear: AnalysisResult,
    buckling_info: Optional[Dict[str, Any]] = None,
    probe_info: Optional[Dict[str, Any]] = None,
    author_name: str = "Võ Thanh Vang (MSHV: 2670624)",
) -> str:
    """
    Xuất báo cáo kết quả tính toán tức thời sang tệp PDF chuẩn A4 tiếng Việt có dấu.
    """
    font_reg, font_bold = _register_unicode_pdf_fonts()
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    doc = SimpleDocTemplate(
        output_path,
        pagesize=A4,
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=18 * mm,
        bottomMargin=18 * mm,
    )
    styles = getSampleStyleSheet()
    s_title = ParagraphStyle("VNTitle", parent=styles["Title"], fontName=font_bold, fontSize=14, leading=18, textColor=colors.HexColor("#0F3D6E"))
    s_sub = ParagraphStyle("VNSub", parent=styles["Normal"], fontName=font_reg, fontSize=9.5, leading=13, alignment=1, textColor=colors.HexColor("#475569"))
    s_h = ParagraphStyle("VNH", parent=styles["Heading2"], fontName=font_bold, fontSize=11.5, leading=15, spaceBefore=10, spaceAfter=4, textColor=colors.HexColor("#0F3D6E"))
    s_body = ParagraphStyle("VNBody", parent=styles["Normal"], fontName=font_reg, fontSize=10, leading=14, textColor=colors.HexColor("#1E293B"))

    story = [
        Paragraph("TRƯỜNG ĐẠI HỌC BÁCH KHOA – ĐHQG TP. HỒ CHÍ MINH", s_sub),
        Paragraph("BÁO CÁO KẾT QUẢ PHÂN TÍCH PHI TUYẾN HÌNH HỌC HỆ DÀN (CALFEM)", s_title),
        Paragraph(
            f"Học viên: {author_name} | GVHD: PGS.TS. Ngô Hữu Cường | "
            f"Ngày xuất: {datetime.datetime.now().strftime('%d/%m/%Y %H:%M')}",
            s_sub,
        ),
        Spacer(1, 6 * mm),
        Paragraph("1. Thông số mô hình & phương pháp tính", s_h),
        Paragraph(
            f"{model.description}<br/>"
            f"• Phương pháp phi tuyến: <b>{res_nonlinear.method_name}</b> "
            f"(Hội tụ: {'ĐẠT' if res_nonlinear.converged else 'KHÔNG ĐẠT'}).<br/>"
            f"• Mô-đun đàn hồi E = {model.E:,.1f} MPa; Hệ số Poisson ν = {model.nu:.2f}.",
            s_body,
        ),
        Paragraph("2. Bảng chuyển vị nút & phản lực gối (Tuyến tính vs Phi tuyến)", s_h),
    ]

    data_nodes = [["Nút", "ux TT (mm)", "uy TT (mm)", "ux PT (mm)", "uy PT (mm)", "Rx PT (kN)", "Ry PT (kN)"]]
    for i in range(model.n_nodes):
        data_nodes.append(
            [
                f"Nút {i+1}",
                f"{res_linear.u[2*i]:+.5f}",
                f"{res_linear.u[2*i+1]:+.5f}",
                f"{res_nonlinear.u[2*i]:+.5f}",
                f"{res_nonlinear.u[2*i+1]:+.5f}",
                f"{res_nonlinear.reactions[2*i]/1000.0:+.4f}",
                f"{res_nonlinear.reactions[2*i+1]/1000.0:+.4f}",
            ]
        )
    tbl1 = Table(data_nodes, repeatRows=1)
    tbl1.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1B365D")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), font_bold),
                ("FONTNAME", (0, 1), (-1, -1), font_reg),
                ("FONTSIZE", (0, 0), (-1, -1), 8.5),
                ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
                ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#CBD5E1")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F8FAFC")]),
            ]
        )
    )
    story.append(tbl1)

    story.append(Paragraph("3. Bảng nội lực, ứng suất và biến dạng các phần tử thanh", s_h))
    data_mem = [["Thanh", "A (mm²)", "N TT (kN)", "N PT (kN)", "σ PT (MPa)", "ε (με)", "ΔN (N)"]]
    for e in range(model.n_elems):
        data_mem.append(
            [
                f"{e+1} ({model.member_labels[e]})",
                f"{model.areas[e]:.1f}",
                f"{res_linear.N[e]/1000.0:+.4f}",
                f"{res_nonlinear.N[e]/1000.0:+.4f}",
                f"{res_nonlinear.stress[e]:+.4f}",
                f"{res_nonlinear.strain[e]*1e6:+.2f}",
                f"{res_nonlinear.N[e] - res_linear.N[e]:+.3f}",
            ]
        )
    tbl2 = Table(data_mem, repeatRows=1)
    tbl2.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0F766E")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), font_bold),
                ("FONTNAME", (0, 1), (-1, -1), font_reg),
                ("FONTSIZE", (0, 0), (-1, -1), 8.5),
                ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
                ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#CBD5E1")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F0FDFA")]),
            ]
        )
    )
    story.append(tbl2)

    eq = res_nonlinear.equilibrium_check
    story.append(Paragraph("4. Kiểm chứng cân bằng & nhận xét bản chất cơ học", s_h))
    story.append(
        Paragraph(
            f"• Kiểm tra cân bằng cấu hình biến dạng: ∑Fx = {eq['sum_Fx_N']:.3e} N; "
            f"∑Fy = {eq['sum_Fy_N']:.3e} N; ∑M = {eq['sum_M_Nmm']:.3e} N·mm.<br/>"
            f"• Năng lượng biến dạng tổng: Tuyến tính = {res_linear.total_energy/1000.0:.6f} J | "
            f"Phi tuyến = {res_nonlinear.total_energy/1000.0:.6f} J.",
            s_body,
        )
    )
    if probe_info:
        story.append(Paragraph("5. Kết quả khảo sát & phẫu thuật mặt cắt", s_h))
        story.append(
            Paragraph(
                f"Thanh {probe_info['member_label']} tại ξ = {probe_info['xi']:.2f}: "
                f"σ_xx = {probe_info['sigma_xx_MPa']:+.4f} MPa; "
                f"ε_xx = {probe_info['eps_xx_microstrain']:+.2f} με; "
                f"ε_Poisson = {probe_info['eps_yy_poisson_microstrain']:+.2f} με; "
                f"Góc xoay Δθ = {probe_info['rotation_delta_deg']:+.5f}°.",
                s_body,
            )
        )

    doc.build(story)
    return output_path
