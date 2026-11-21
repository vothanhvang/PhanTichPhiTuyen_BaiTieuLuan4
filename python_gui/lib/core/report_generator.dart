// ============================================================================
// MÔ-ĐUN XUẤT THUYẾT MINH WORD (.DOCX), PDF (.PDF), CSV EXCEL, ẢNH PNG & JSON
// ============================================================================
// Trình bày đầy đủ, tường minh, mạch lạc:
//   • Hệ thống công thức toán học – cơ học kết cấu – kiểm tra bền/ổn định/liên kết
//   • Dẫn nguồn rõ ràng từng tiêu chuẩn (TCVN 5575, EN 1993-1-1, EN 1993-1-8,
//     EN 1992-1-1, TCVN 5574, EN 1337) & giáo trình học phần (NSA_1..NSA_6,
//     CALFEM 3.4, Dahlblom 2016, McGuire 2000, Jeffers 2026, Yang 2025, Hibbeler)
//   • Bảng số liệu thế số trực tiếp, kiểm tra chi tiết từng thanh & từng liên kết nút
// Hoạt động 100% đa nền tảng: Windows (.exe), Android (.apk) và Web!
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'calfem_engine.dart';
import 'connection_calculator.dart';
import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';

class FlutterReportGenerator {
  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _docxParagraph(
    String text, {
    bool bold = false,
    bool italic = false,
    int sizeHalfPt = 22,
    String? colorHex,
    String align = 'left',
    int spaceBefore = 0,
    int spaceAfter = 80,
    int indentLeft = 0,
  }) {
    final colorTag = colorHex != null ? '<w:color w:val="$colorHex"/>' : '';
    final boldTag = bold ? '<w:b/>' : '';
    final italicTag = italic ? '<w:i/>' : '';
    final indTag = indentLeft > 0 ? '<w:ind w:left="$indentLeft"/>' : '';
    return '<w:p>'
        '<w:pPr><w:jc w:val="$align"/><w:spacing w:before="$spaceBefore" w:after="$spaceAfter"/>$indTag</w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>'
        '$boldTag$italicTag$colorTag<w:sz w:val="$sizeHalfPt"/></w:rPr>'
        '<w:t xml:space="preserve">${_xmlEscape(text)}</w:t></w:r></w:p>';
  }

  /// Khung công thức nổi bật có đánh số phương trình căn phải trong Word OOXML
  static String _docxFormulaBox(String eqNum, String formula, String explanation, String sourceRef) {
    return '<w:tbl><w:tblPr>'
        '<w:tblW w:w="9500" w:type="dxa"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:left w:val="single" w:sz="18" w:space="0" w:color="0F3D6E"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:insideH w:val="none"/><w:insideV w:val="none"/>'
        '</w:tblBorders></w:tblPr>'
        '<w:tr>'
        '<w:tc><w:tcPr><w:tcW w:w="8200" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F8FAFC"/></w:tcPr>'
        '${_docxParagraph(formula, bold: true, sizeHalfPt: 21, colorHex: "0F172A", spaceBefore: 40, spaceAfter: 35, indentLeft: 120)}'
        '${_docxParagraph(explanation, sizeHalfPt: 18, colorHex: "334155", spaceAfter: 25, indentLeft: 120)}'
        '${_docxParagraph("Nguồn áp dụng: $sourceRef", italic: true, sizeHalfPt: 17, colorHex: "0F766E", spaceAfter: 40, indentLeft: 120)}'
        '</w:tc>'
        '<w:tc><w:tcPr><w:tcW w:w="1300" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F8FAFC"/></w:tcPr>'
        '${_docxParagraph(eqNum, bold: true, sizeHalfPt: 19, colorHex: "0F3D6E", align: "right", spaceBefore: 40)}'
        '</w:tc>'
        '</w:tr></w:tbl>'
        '<w:p><w:pPr><w:spacing w:after="50"/></w:pPr></w:p>';
  }

  /// Chèn ảnh PNG chụp khung nhìn 3D/2D trực tiếp vào tài liệu Word OOXML (`<w:drawing>`)
  static String _docxImageParagraph(int widthPx, int heightPx, String caption) {
    final aspect = (widthPx > 0 && heightPx > 0) ? heightPx / widthPx : 0.62;
    const int cx = 5600000; // ~15.5 cm (vừa khổ giấy A4 trừ lề)
    final int cy = (cx * aspect).round().clamp(1600000, 4800000);
    return '<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:before="80" w:after="40"/></w:pPr>'
        '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="1" name="Viewport3D2D"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic>'
        '<pic:nvPicPr><pic:cNvPr id="1" name="viewport.png"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="rIdImg1"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic>'
        '</a:graphicData></a:graphic>'
        '</wp:inline>'
        '</w:drawing></w:r></w:p>'
        '${_docxParagraph(caption, italic: true, sizeHalfPt: 18, colorHex: "475569", align: "center")}';
  }

  static String _docxTable(
    List<String> headers,
    List<List<String>> rows,
    String headerFill, {
    Set<int> leftAlignCols = const {0},
  }) {
    final buf = StringBuffer();
    buf.write('<w:tbl><w:tblPr>'
        '<w:tblW w:w="9500" w:type="dxa"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="6" w:space="0" w:color="1B365D"/>'
        '<w:bottom w:val="single" w:sz="8" w:space="0" w:color="1B365D"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '</w:tblBorders></w:tblPr>');

    buf.write('<w:tr>');
    for (final h in headers) {
      buf.write('<w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="$headerFill"/></w:tcPr>'
          '${_docxParagraph(h, bold: true, sizeHalfPt: 17, colorHex: "FFFFFF", align: "center", spaceAfter: 30)}</w:tc>');
    }
    buf.write('</w:tr>');

    for (int r = 0; r < rows.length; r++) {
      final fill = r.isOdd ? 'F1F5F9' : 'FFFFFF';
      buf.write('<w:tr>');
      for (int c = 0; c < rows[r].length; c++) {
        final align = leftAlignCols.contains(c) ? 'left' : 'right';
        buf.write('<w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="$fill"/></w:tcPr>'
            '${_docxParagraph(rows[r][c], sizeHalfPt: 16, align: align, spaceAfter: 25)}</w:tc>');
      }
      buf.write('</w:tr>');
    }
    buf.write('</w:tbl><w:p><w:pPr><w:spacing w:after="60"/></w:pPr></w:p>');
    return buf.toString();
  }

  /// Danh mục hệ thống công thức chuẩn kèm dẫn nguồn dùng chung cho cả Word & PDF
  static const List<({String section, String eqNum, String formula, String explain, String source})> _trussFormulaCatalog = [
    (
      section: '2.1. Động học thanh biến dạng lớn & Biến dạng dọc trục',
      eqNum: '(2.1)',
      formula: 'L₀ = √[(x₂ − x₁)² + (y₂ − y₁)²] ;  l = √[(Δx₀ + Δuₓ)² + (Δy₀ + Δuᵧ)²] ;  Δl = l − L₀ = (l² − L₀²) / (l + L₀)',
      explain:
          'Chiều dài ban đầu L₀, chiều dài sau biến dạng l và độ giãn dài tuyệt đối Δl tính bằng hằng đẳng thức hiệu hai bình phương để triệt tiêu sai số mất chữ số có nghĩa khi Δl ≪ L₀.',
      source: '[TL1] Bài giảng NSA_4 (Slides 5–12); [TL5] Jeffers (2026) Ch. 8 Mục 8.3; [TL6] Yang et al. (2025) Ch. 4 tr. 117–128.',
    ),
    (
      section: '2.1. Động học thanh biến dạng lớn & Biến dạng dọc trục',
      eqNum: '(2.2)',
      formula: 'ε_Corot = (l − L₀) / L₀  (Corotational UL)   |   ε_GL = (l² − L₀²) / (2·L₀²) = ε_L + ε_NL  (Green-Lagrange TL)',
      explain:
          'Trong đó ε_L = (Δx₀·Δuₓ + Δy₀·Δuᵧ)/L₀² là thành phần tuyến tính, ε_NL = (Δuₓ² + Δuᵧ²)/(2·L₀²) là thành phần phi tuyến bậc 2 bất biến theo phép quay vật rắn (Rigid-Body Objectivity).',
      source: '[TL1] NSA_4 Slides 5–10; [TL4] McGuire et al. (2000) Ch. 9 PT (9.1) tr. 242; [TL5] Jeffers (2026) Ch. 8 Mục 8.1.',
    ),
    (
      section: '2.2. Ma trận độ cứng tiếp tuyến phần tử [K_t] & Giải lặp phi tuyến',
      eqNum: '(2.3)',
      formula: '[K_t^e] = [K_m^e] + [K_g^e] = (E_t·A / L) · n·nᵀ + (N / L) · (I_r − n·nᵀ)   (với n = [−c, −s, c, s]ᵀ)',
      explain:
          '[K_m^e] là ma trận độ cứng vật liệu dọc trục thanh (c = cos θ, s = sin θ ở cấu hình hiện tại đối với Corotational UL hoặc ban đầu đối với CALFEM bar2g); [K_g^e] là ma trận độ cứng hình học phụ thuộc lực dọc N (kéo N > 0 làm cứng hóa, nén N < 0 làm mềm hóa ngang).',
      source: '[TL2] CALFEM 3.4 (bar2e, bar2g, Mục 5.3 tr. 5.3-1..5); [TL3] Dahlblom (2016) Ch. 9 PT (9.13)–(9.38) tr. 251–261; [TL1] NSA_4 Mục 4.1.1.',
    ),
    (
      section: '2.2. Ma trận độ cứng tiếp tuyến phần tử [K_t] & Giải lặp phi tuyến',
      eqNum: '(2.4)',
      formula: '{R(u)} = λ·{F_ref} − {F_int(u)} = 0  ⇒  [K_t(u^(k))]·{Δu^(k)} = {R(u^(k))} ;  u^(k+1) = u^(k) + {Δu^(k)}',
      explain:
          'Giải hệ phương trình cân bằng phi tuyến theo nguyên lý công ảo δW_int = δW_ext bằng phương pháp lặp Full Newton-Raphson (cập nhật [K_t] mỗi vòng), Modified NR, Euler / RK2 gia tăng tải, và điều khiển cung Arc-Length (Crisfield) để vượt qua điểm giới hạn bật nhảy Snap-Through. Điều kiện hội tụ: ||R||_∞ < 10⁻⁶ N.',
      source: '[TL1] NSA_3 & NSA_6 Mục 6.3.1–6.3.5 (Slides 3–25); [TL4] McGuire et al. (2000) Ch. 12 tr. 339–362.',
    ),
    (
      section: '2.3. Phi tuyến vật liệu đàn-dẻo (GMNIA) & Trị riêng mất ổn định đàn hồi',
      eqNum: '(2.5)',
      formula: 'σ(ε) = E·ε (|ε| ≤ ε_y = f_y/E) ;  σ(ε) = sgn(ε)·[f_y + β·E·(|ε| − ε_y)]  ⇒  E_t = β·E (|ε| > ε_y)',
      explain:
          'Mô hình đàn-dẻo song tuyến tính có tái bền đẳng hướng (hệ số tái bền β = E_t/E). Khi phân tích kết hợp phi tuyến hình học + vật liệu (GMNIA), mô-đun tiếp tuyến E_t thay thế E trong ma trận độ cứng vật liệu [K_m^e].',
      source: '[TL1] Bài giảng NSA_5 (Phân tích Phi tuyến Vật liệu — Lý thuyết dẻo & tái bền); [TC2] EN 1993-1-1:2005 §5.4.3.',
    ),
    (
      section: '2.3. Phi tuyến vật liệu đàn-dẻo (GMNIA) & Trị riêng mất ổn định đàn hồi',
      eqNum: '(2.6)',
      formula: 'det([K_e] + α_cr · [K_g(N_ref)]) = 0   ⇒   P_cr = α_cr · P_ref',
      explain:
          'Bài toán trị riêng mất ổn định đàn hồi tuyến tính hóa (Elastic Eigenvalue Buckling) xác định hệ số tải tới hạn nhỏ nhất α_cr > 0 và dạng mất ổn định tổng thể của hệ dàn.',
      source: '[TL1] NSA_4 Mục 4.2 (Slides 20–27); [TL3] Dahlblom (2016) Ch. 9 PT (9.4)–(9.7) tr. 253; [TC2] EN 1993-1-1:2005 §5.2.1.',
    ),
    (
      section: '2.4. Kiểm tra Bền & Ổn định Tổng thể Thanh chịu Kéo / Nén đúng tâm',
      eqNum: '(2.7)',
      formula: 'Thanh kéo: N_t,Rd = A·f_y / γ_M0   |   Thanh nén: i_min = √(I_min/A) ; λ = L₀/i_min ; λ̄ = λ / (π·√(E/f_y))',
      explain:
          'Kiểm tra độ bền kéo đúng tâm (γ_M0 = 1.00) và độ mảnh quy đổi λ̄ cho thanh nén hai đầu khớp (chiều dài tính toán L_cr = L₀). Bán kính quán tính nhỏ nhất i_min xét đúng tiết diện thực tế (12 dạng tiết diện kể cả xoay góc β).',
      source: '[TC2] EN 1993-1-1:2005 §6.2.3 & §6.3.1.3; [TC1] TCVN 5575:2012 §7.1.1 & §7.2.2 (TCVN 5575:2024).',
    ),
    (
      section: '2.4. Kiểm tra Bền & Ổn định Tổng thể Thanh chịu Kéo / Nén đúng tâm',
      eqNum: '(2.8)',
      formula: 'Φ = 0.5·[1 + α·(λ̄ − 0.2) + λ̄²] ;  χ = min(1.0 , 1 / [Φ + √(Φ² − λ̄²)]) ;  N_b,Rd = χ·A·f_y / γ_M1 ;  U = |N|/N_Rd × 100%',
      explain:
          'Hệ số sai lệch ban đầu α lấy theo đường cong ổn định: α = 0.21 (đường cong a: ống tròn CHS / hộp kín RHS), α = 0.34 (đường cong b: thép hình chữ I), α = 0.49 (đường cong c: thép góc L, 2L, C, 2C, T, đặc). Đạt chuẩn khi U ≤ 100% và |σ| < f_y.',
      source: '[TC2] EN 1993-1-1:2005 §6.3.1.2 PT (6.49), Bảng 6.1–6.2; [TC1] TCVN 5575:2012 §7.2.2 & Phụ lục D (Bảng D.1).',
    ),
    (
      section: '2.5. Phẫu thuật Mặt cắt, Ứng suất Thớ cục bộ & Biến dạng ngang Poisson',
      eqNum: '(2.9)',
      formula: 'σ_xx(ξ,η,ζ) = N/A + M_(P-δ)·y/I ;  σ_vM = |σ_xx| ;  τ_max = |σ_xx|/2 (Mohr) ;  ε_⊥ = −ν·ε_xx  (ν = 0.30)',
      explain:
          'Với thanh nén có độ cong ban đầu e₀ = L₀/500, mô-men uốn bậc hai P-δ dọc thân thanh là M_(P-δ)(ξ) = |N|·e₀·[1/(1 − |N|/P_E)]·sin(πξ) với P_E = π²EI/L₀² là lực tới hạn cột Euler. Năng lượng biến dạng tổng: U = ∑ ½·E·A·L₀·ε².',
      source: '[TL7] Hibbeler, Mechanics of Materials 10E (2017) PT (3-6), (4-1), (13-5) tr. 113, 144, 686; [TL1] NSA_4 Slides 14–19.',
    ),
    (
      section: '2.6. Tính toán & Kiểm tra Liên kết Nút Kết cấu Thép & Gối tựa Móng',
      eqNum: '(2.10)',
      formula: 'Bu-lông 2 mặt cắt: F_v,Rd = 2·α_v·f_ub·A_s / γ_M2 ;  Ép mặt: F_b,Rd = 2.5·α_b·f_u·d·t_g / γ_M2 ;  F_Rd(1) = min(F_v,Rd, F_b,Rd)',
      explain:
          'Hệ số vật liệu γ_M0 = 1.00, γ_M2 = 1.25; α_v = 0.6 (cấp 4.6, 5.6, 8.8) hoặc 0.5 (cấp 10.9); α_b = min(e₁/(3d₀), f_ub/f_u, 1.0). Xé khối (Block Tearing): V_eff,Rd = f_u·A_nt/γ_M2 + (f_y/√3)·A_nv/γ_M0.',
      source: '[TC3] EN 1993-1-8:2005 Bảng 3.4 (§3.6.1) & §3.10.2 (Block Tearing); [TC1] TCVN 5575:2012 §8.2.2.',
    ),
    (
      section: '2.6. Tính toán & Kiểm tra Liên kết Nút Kết cấu Thép & Gối tựa Móng',
      eqNum: '(2.11)',
      formula: 'Hàn góc 2 mép: a = 0.7·h_f ; f_vw,d = (f_u/√3)/(β_w·γ_M2) ; F_w,Rd = 2·a·l_w·f_vw,d  |  Whitmore: b_w = p₂ + 2·l_conn·tan30°',
      explain:
          'Kiểm tra đường hàn góc chịu cắt dọc 2 mép thanh và mặt cắt hữu hiệu bản mã Whitmore (góc truyền lực 30°): σ_w = |N|/(b_w·t_g) ≤ χ_g·f_y/γ_M0 (χ_g = 0.85 cho thanh nén, 1.0 cho thanh kéo). Chốt bản lề Clevis kiểm tra đủ 3 điều kiện: cắt F_v,Rd = 2·0.6·A·f_up/γ_M2, ép mặt F_b,Rd = 1.5·t_g·d·f_y/γ_M0 và uốn M_Rd = 1.5·W_el·f_yp/γ_M0.',
      source: '[TC3] EN 1993-1-8:2005 §4.5.3.3 (Hàn góc) & §3.13.2 Bảng 3.10 (Chốt); [TC1] TCVN 5575:2012 §8.1.2; [TL8] Whitmore (1952) & AISC Part 9.',
    ),
    (
      section: '2.6. Tính toán & Kiểm tra Liên kết Nút Kết cấu Thép & Gối tựa Móng',
      eqNum: '(2.12)',
      formula: 'Bản đế móng: p_c = N/(B_bp·L_bp) ≤ f_jd = 1.5·(0.85·f_ck/1.5)  |  Con lăn Hertz: σ_H = √[F·E/(π·L·R·(1−ν²))] ≤ [σ_H]',
      explain:
          'Kiểm tra ép cục bộ bê tông dưới bản đế gối cố định (kèm tổ hợp cắt-kéo cụm 4 bu-lông neo V/V_Rd + N/(1.4·N_Rd) ≤ 1.0), ứng suất tiếp xúc Hertz trên cặp trục con lăn thép tôi (Ø60×160 mm) và hành trình đàn hồi gối lò xo F_s = k·δ_s, năng lượng tích trữ U_s = ½·k·δ_s².',
      source: '[TC3] EN 1993-1-8:2005 §6.2.5; [TC5] EN 1992-1-1:2004 §6.7; [TC4] TCVN 5574:2018 §8.1.5; [TC6] EN 1337-3 & EN 1337-4.',
    ),
  ];

  static const List<({String code, String text})> _standardsRefs = [
    (
      code: '[TC1]',
      text: 'TCVN 5575:2012 (và TCVN 5575:2024). Kết cấu thép — Tiêu chuẩn thiết kế. Bộ Khoa học và Công nghệ Việt Nam.',
    ),
    (
      code: '[TC2]',
      text: 'EN 1993-1-1:2005 (Eurocode 3). Design of steel structures — Part 1-1: General rules and rules for buildings. CEN, Brussels.',
    ),
    (
      code: '[TC3]',
      text: 'EN 1993-1-8:2005 (Eurocode 3). Design of steel structures — Part 1-8: Design of joints. CEN, Brussels.',
    ),
    (
      code: '[TC4]',
      text: 'TCVN 5574:2018. Thiết kế kết cấu bê tông và bê tông cốt thép. Bộ Khoa học và Công nghệ Việt Nam.',
    ),
    (
      code: '[TC5]',
      text: 'EN 1992-1-1:2004 (Eurocode 2). Design of concrete structures — Part 1-1: General rules and rules for buildings. CEN, Brussels.',
    ),
    (
      code: '[TC6]',
      text: 'EN 1337-3:2005 & EN 1337-4:2004. Structural bearings — Elastomeric bearings & Roller bearings. CEN, Brussels.',
    ),
  ];

  static const List<({String code, String text})> _literatureRefs = [
    (
      code: '[TL1]',
      text: 'Ngô Hữu Cường, Đoàn Ngọc Tịnh Nghiêm. Bài giảng học phần Phân tích Phi tuyến Kết cấu (NSA_1 đến NSA_6), Khoa Kỹ thuật Xây dựng, Trường ĐH Bách Khoa – ĐHQG TP. Hồ Chí Minh.',
    ),
    (
      code: '[TL2]',
      text: 'Division of Structural Mechanics, Lund University (2004). CALFEM — A Finite Element Toolbox to MATLAB, Version 3.4 (Mục 5.3 bar2e/bar2g/bar2s, Mục 6.2 assem/solveq, ví dụ exs3/exn1/exn2).',
    ),
    (
      code: '[TL3]',
      text: 'K.-G. Olsson, O. Dahlblom (2016). Structural Mechanics: Modelling and Analysis of Frames and Trusses. John Wiley & Sons (Ch. 3 tr. 53–65; Ch. 9 tr. 251–262, Example 9.1).',
    ),
    (
      code: '[TL4]',
      text: 'W. McGuire, R.H. Gallagher, R.D. Ziemian (2000). Matrix Structural Analysis, 2nd Edition. John Wiley & Sons (Ch. 8–9 tr. 216–249; Ch. 12 tr. 339–362).',
    ),
    (
      code: '[TL5]',
      text: 'A.E. Jeffers (2026). Linear and Nonlinear Methods of Matrix Structural Analysis. John Wiley & Sons (Ch. 6–8 tr. 135–196).',
    ),
    (
      code: '[TL6]',
      text: 'Y.-B. Yang et al. (2025). Physics-Based Computational Methods for Nonlinear Framed Structures. Springer (Ch. 4: Rigid-Body Objectivity, tr. 117–144).',
    ),
    (
      code: '[TL7]',
      text: 'R.C. Hibbeler (2017/2019). Mechanics of Materials (10th Ed. SI) & Structural Analysis (10th Ed.). Pearson Education.',
    ),
    (
      code: '[TL8]',
      text: 'R.E. Whitmore (1952). Experimental Investigation of Stresses in Gusset Plates, Bull. No. 16, Univ. of Tennessee; AISC Steel Construction Manual (15th Ed., Part 9).',
    ),
  ];

  /// Xuất tệp Microsoft Word (.docx) chuẩn OOXML có đầy đủ công thức, dẫn nguồn tiêu chuẩn/tài liệu, ảnh 3D/2D & bảng tính chi tiết
  static Future<String?> exportDocx({
    required TrussModelData model,
    required TrussAnalysisResult linear,
    required TrussAnalysisResult nonlinear,
    required ProbeInspection probe,
    required double loadFactor,
    List<NodeConnectionReport>? connectionReports,
    List<MemberDesignCheck>? designChecks,
    BucklingAnalysisResult? buckling,
    Uint8List? viewportPngBytes,
    int? pngWidthPx,
    int? pngHeightPx,
  }) async {
    final checks = designChecks ?? CalfemNonlinearEngine.checkMembers(model, nonlinear);
    final hasImage = viewportPngBytes != null && viewportPngBytes.isNotEmpty;
    final now = DateTime.now();
    final ts = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final body = StringBuffer();
    body.write(_docxParagraph('TRƯỜNG ĐẠI HỌC BÁCH KHOA – ĐHQG TP. HỒ CHÍ MINH',
        bold: true, sizeHalfPt: 22, colorHex: '0F3D6E', align: 'center', spaceAfter: 40));
    body.write(_docxParagraph('KHOA KỸ THUẬT XÂY DỰNG – BỘ MÔN CÔNG TRÌNH',
        bold: true, sizeHalfPt: 20, colorHex: '334155', align: 'center', spaceAfter: 60));
    body.write(_docxParagraph('THUYẾT MINH TÍNH TOÁN PHÂN TÍCH PHI TUYẾN KẾT CẤU HỆ DÀN (CALFEM 3.4)',
        bold: true, sizeHalfPt: 26, colorHex: '0F172A', align: 'center', spaceAfter: 40));
    body.write(_docxParagraph(
        'Giảng viên hướng dẫn: PGS. TS Ngô Hữu Cường  |  Học viên: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)',
        bold: true,
        sizeHalfPt: 18,
        colorHex: '1E293B',
        align: 'center',
        spaceAfter: 30));
    body.write(_docxParagraph(
        'Email: vothanhvang@gmail.com  •  ĐT: 0973.993.494  •  Ngày xuất thuyết minh: $ts',
        sizeHalfPt: 17,
        colorHex: '475569',
        align: 'center',
        spaceAfter: 100));

    if (hasImage) {
      body.write(_docxImageParagraph(
        pngWidthPx ?? 1200,
        pngHeightPx ?? 740,
        'Hình 1. Mô hình kết cấu 3D/2D, bản đồ phân bố nội lực/ứng suất & vị trí phẫu thuật mặt cắt (λ = ${loadFactor.toStringAsFixed(2)})',
      ));
    }

    // MỤC 1
    body.write(_docxParagraph('1. THÔNG SỐ ĐẦU VÀO, MÔ HÌNH KẾT CẤU & PHẠM VI TIÊU CHUẨN ÁP DỤNG',
        bold: true, sizeHalfPt: 23, colorHex: '0F3D6E', spaceBefore: 100));
    final secSummary = [
      for (int e = 0; e < model.nElems; e++)
        'T${e + 1}: ${model.sectionDimsForElem(e).formatSpec(model.sectionShapeForElem(e))} (L₀=${model.initialLength(e).toStringAsFixed(0)} mm, A=${model.areas[e].toStringAsFixed(0)} mm²)',
    ].join(' ; ');
    final supSummary = [
      for (int i = 0; i < model.nodeSupports.length; i++) 'N${i + 1}: ${model.nodeSupports[i].shortLabel}',
    ].join(' | ');
    body.write(_docxTable(
      ['Hạng mục', 'Thông số mô hình đang tính toán', 'Cơ sở tiêu chuẩn / Tài liệu'],
      [
        ['Mô hình kết cấu', '${model.name} (${model.nNodes} nút, ${model.nElems} thanh) — ${model.description}', '[TL1] NSA_4; [TL2] CALFEM 3.4'],
        ['Tiết diện & Chiều dài thanh', secSummary, '[TC1] TCVN 5575; [TC2] EN 1993-1-1'],
        ['Liên kết gối tựa nút', '$supSummary${model.hasAnySpring ? " (k = ${model.springStiffnessKnMm.toStringAsFixed(1)} kN/mm)" : ""}', '[TC3] EN 1993-1-8; [TC6] EN 1337'],
        [
          'Vật liệu & Chế độ phân tích',
          'E = ${(model.E / 1000).toStringAsFixed(0)} GPa, fy = ${model.fyRef.toStringAsFixed(0)} MPa, ν = 0.30 | ${model.materialNonlinear ? "Phi tuyến vật liệu đàn-dẻo GMNIA (β = ${(model.hardeningRatio * 100).toStringAsFixed(1)}%)" : "Đàn hồi tuyến tính (GNIA)"}',
          '[TL1] NSA_5; [TC2] EN 1993-1-1 §5.4',
        ],
        [
          'Thuật toán & Hội tụ số',
          '${nonlinear.methodName} (λ = ${loadFactor.toStringAsFixed(2)}) | Hội tụ: ${nonlinear.converged ? "ĐẠT" : "CHƯA ĐẠT"} (${nonlinear.totalIterations} vòng lặp, lõi ${nonlinear.engineSource})',
          '[TL1] NSA_6 Mục 6.3; [TL4] McGuire Ch. 12',
        ],
        [
          'Trị riêng mất ổn định đàn hồi',
          (buckling != null && buckling.hasBucklingMode)
              ? 'α_cr = ${buckling.alphaCr.toStringAsFixed(2)} ⇒ P_cr = ${buckling.pCrKn.toStringAsFixed(1)} kN (det[K_e + α_cr·K_g] = 0)'
              : 'Hệ không có dạng mất ổn định nén tuyến tính hóa',
          '[TL1] NSA_4 Mục 4.2; [TC2] EN 1993-1-1 §5.2.1',
        ],
      ],
      '0F3D6E',
      leftAlignCols: const {0, 1, 2},
    ));

    // MỤC 2: CHI TIẾT CÔNG THỨC TÍNH TOÁN & DẪN NGUỒN
    body.write(_docxParagraph('2. CƠ SỞ LÝ THUYẾT, HỆ THỐNG CÔNG THỨC TÍNH TOÁN & DẪN NGUỒN TIÊU CHUẨN',
        bold: true, sizeHalfPt: 23, colorHex: '0F3D6E', spaceBefore: 100));
    body.write(_docxParagraph(
      'Toàn bộ kết quả chuyển vị, nội lực, ứng suất thớ, ổn định cấu kiện và kiểm tra liên kết trong thuyết minh được thiết lập tường minh từ các hệ thức cơ học phi tuyến và điều khoản tiêu chuẩn hiện hành sau đây:',
      sizeHalfPt: 20,
      colorHex: '334155',
    ));
    String lastSec = '';
    for (final item in _trussFormulaCatalog) {
      if (item.section != lastSec) {
        lastSec = item.section;
        body.write(_docxParagraph(item.section, bold: true, sizeHalfPt: 21, colorHex: '0F766E', spaceBefore: 70, spaceAfter: 40));
      }
      body.write(_docxFormulaBox(item.eqNum, item.formula, item.explain, item.source));
    }

    // MỤC 3
    body.write(_docxParagraph('3. KẾT QUẢ CHUYỂN VỊ NÚT & PHẢN LỰC GỐI (TUYẾN TÍNH VS PHI TUYẾN)',
        bold: true, sizeHalfPt: 23, colorHex: '0F3D6E', spaceBefore: 90));
    final nodeRows = <List<String>>[];
    for (int i = 0; i < model.nNodes; i++) {
      nodeRows.add([
        'Nút ${i + 1} (${model.nodeSupports[i].shortLabel})',
        linear.uMm[2 * i].toStringAsFixed(5),
        linear.uMm[2 * i + 1].toStringAsFixed(5),
        nonlinear.uMm[2 * i].toStringAsFixed(5),
        nonlinear.uMm[2 * i + 1].toStringAsFixed(5),
        (nonlinear.reactionsN[2 * i] / 1000.0).toStringAsFixed(4),
        (nonlinear.reactionsN[2 * i + 1] / 1000.0).toStringAsFixed(4),
      ]);
    }
    body.write(_docxTable(
      ['Nút (Liên kết)', 'u_x TT (mm)', 'u_y TT (mm)', 'u_x PT (mm)', 'u_y PT (mm)', 'R_x PT (kN)', 'R_y PT (kN)'],
      nodeRows,
      '1B365D',
    ));

    // MỤC 4
    body.write(_docxParagraph('4. NỘI LỰC, ỨNG SUẤT & KIỂM TRA BỀN – ỔN ĐỊNH TỪNG THANH (TCVN 5575 / EN 1993-1-1)',
        bold: true, sizeHalfPt: 23, colorHex: '0F3D6E', spaceBefore: 90));
    body.write(_docxParagraph(
      'Áp dụng công thức (2.7)–(2.8) theo EN 1993-1-1:2005 §6.2.3 & §6.3.1.2 (tương đương TCVN 5575:2012 §7.1–7.2): thanh kéo kiểm tra N_t,Rd = A·f_y/γ_M0; thanh nén kiểm tra ổn định uốn dọc N_b,Rd = χ·A·f_y/γ_M1 với hệ số giảm cường độ χ xác định từ độ mảnh λ = L₀/i_min và đường cong ổn định (a/b/c).',
      sizeHalfPt: 19,
      colorHex: '334155',
    ));
    final memRows = <List<String>>[];
    for (int e = 0; e < model.nElems; e++) {
      final shE = model.sectionShapeForElem(e);
      final chk = e < checks.length ? checks[e] : null;
      memRows.add([
        'T${e + 1} (${model.memberLabels[e]})',
        model.sectionDimsForElem(e).formatSpec(shE),
        model.initialLength(e).toStringAsFixed(0),
        (nonlinear.nForcesN[e] / 1000.0).toStringAsFixed(3),
        nonlinear.stressMpa[e].toStringAsFixed(2),
        chk != null ? chk.slenderness.toStringAsFixed(1) : '-',
        chk != null ? chk.chiBuckling.toStringAsFixed(3) : '-',
        chk != null ? chk.nCapacityKn.toStringAsFixed(1) : '-',
        chk != null ? '${chk.utilizationPct.toStringAsFixed(1)}%' : '-',
        chk != null ? (chk.passed ? 'ĐẠT' : 'VƯỢT') : '-',
      ]);
    }
    body.write(_docxTable(
      ['Thanh', 'Tiết diện', 'L₀ (mm)', 'N PT (kN)', 'σ (MPa)', 'λ', 'χ', 'N_Rd (kN)', 'U (%)', 'Kết luận'],
      memRows,
      '0F766E',
      leftAlignCols: const {0, 1},
    ));

    // MỤC 5
    final probeShape = model.sectionShapeForElem(probe.elemIndex);
    body.write(_docxParagraph('5. KHẢO SÁT PHẪU THUẬT MẶT CẮT & THẾ SỐ TƯỜNG MINH TẠI ĐIỂM ĐANG CHỌN',
        bold: true, sizeHalfPt: 23, colorHex: '0F3D6E', spaceBefore: 90));
    body.write(_docxParagraph(
      '• Vị trí khảo sát: Thanh T${probe.elemIndex + 1} (${probe.memberLabel}), L₀ = ${probe.l0Mm.toStringAsFixed(1)} mm, vị trí dọc trục ξ = ${probe.xi.toStringAsFixed(2)} (s = ${probe.sMm.toStringAsFixed(1)} mm), thớ (η = ${probe.etaNorm.toStringAsFixed(2)}, ζ = ${probe.zetaNorm.toStringAsFixed(2)}), tiết diện ${probeShape.label} (${probe.sectionDims.formatSpec(probeShape)}).',
      sizeHalfPt: 19,
    ));
    body.write(_docxParagraph(
      '• Thế số theo công thức (2.9) [TL7]: σ_xx = σ_axial + σ_bending(P-δ) = ${probe.sigmaAxialMpa.toStringAsFixed(4)} + ${probe.sigmaBendingMpa.toStringAsFixed(4)} = ${probe.sigmaXxMpa.toStringAsFixed(4)} MPa; ứng suất tương đương von Mises σ_vM = ${probe.sigmaVonMisesMpa.toStringAsFixed(4)} MPa; ứng suất tiếp cực đại vòng tròn Mohr τ_max = |σ_xx|/2 = ${probe.tauMaxMohrMpa.toStringAsFixed(4)} MPa.',
      sizeHalfPt: 19,
    ));
    body.write(_docxParagraph(
      '• Biến dạng dọc trục ε_xx = ${probe.epsXxMicro.toStringAsFixed(2)} με; biến dạng co/nở ngang Poisson ε_⊥ = −0.30·ε_xx = ${probe.epsPoissonMicro.toStringAsFixed(2)} με; góc xoay vật rắn thanh Δθ = ${probe.rotationDeg.toStringAsFixed(5)}°.',
      sizeHalfPt: 19,
    ));

    // MỤC 6
    body.write(_docxParagraph('6. KIỂM CHỨNG CÂN BẰNG CẤU HÌNH BIẾN DẠNG & NĂNG LƯỢNG BIẾN DẠNG',
        bold: true, sizeHalfPt: 23, colorHex: '0F3D6E', spaceBefore: 90));
    body.write(_docxParagraph(
      '• Kiểm tra phương trình cân bằng tĩnh trên cấu hình sau biến dạng [TL1] NSA_4: ∑Fx = ${nonlinear.sumFxN.toStringAsExponential(3)} N  |  ∑Fy = ${nonlinear.sumFyN.toStringAsExponential(3)} N  |  ∑M_biến_dạng = ${nonlinear.sumMNmm.toStringAsExponential(3)} N·mm  |  Phần dư bậc tự do lớn nhất ||R||_∞ = ${nonlinear.maxFreeResidualN.toStringAsExponential(3)} N.',
      sizeHalfPt: 19,
    ));
    body.write(_docxParagraph(
      '• Tổng thế năng biến dạng đàn hồi [TL7]: Tuyến tính U_TT = ${(linear.totalEnergyNmm / 1000.0).toStringAsFixed(6)} J  |  Phi tuyến U_PT = ${(nonlinear.totalEnergyNmm / 1000.0).toStringAsFixed(6)} J.',
      sizeHalfPt: 19,
    ));

    // MỤC 7: CHI TIẾT TỪNG HẠNG MỤC KIỂM TRA LIÊN KẾT NÚT KÈM CÔNG THỨC THẾ SỐ & ĐIỀU KHOẢN TIÊU CHUẨN
    if (connectionReports != null && connectionReports.isNotEmpty) {
      final firstP = connectionReports.first.params;
      body.write(_docxParagraph('7. TÍNH TOÁN & KIỂM TRA CHI TIẾT LIÊN KẾT CÁC NÚT (TCVN 5575 / EN 1993-1-8)',
          bold: true, sizeHalfPt: 23, colorHex: '0F3D6E', spaceBefore: 90));
      body.write(_docxParagraph(
        '• Cấu tạo gia công: ${firstP.detailType.label} | Bản mã PL${firstP.gussetThicknessMm.toStringAsFixed(0)} thép ${firstP.steelGrade.code} (f_y = ${firstP.steelGrade.fyMpa.toStringAsFixed(0)} MPa, f_u = ${firstP.steelGrade.fuMpa.toStringAsFixed(0)} MPa, γ_M0 = 1.00, γ_M2 = 1.25).',
        sizeHalfPt: 19,
      ));
      // Bảng tổng hợp theo nút
      final connSummaryRows = <List<String>>[
        for (final rep in connectionReports)
          [
            'Nút ${rep.nodeIndex + 1} (${rep.supportType.shortLabel})',
            '${rep.gussetWidthMm.toStringAsFixed(0)}×${rep.gussetHeightMm.toStringAsFixed(0)}×${rep.params.gussetThicknessMm.toStringAsFixed(0)}',
            '(${rep.rxKn.toStringAsFixed(1)}, ${rep.ryKn.toStringAsFixed(1)})',
            '${rep.maxGussetSigmaMpa.toStringAsFixed(1)} MPa',
            '${rep.maxUtilizationPct.toStringAsFixed(1)}%',
            rep.allPassed ? 'ĐẠT' : 'KHÔNG ĐẠT',
          ],
      ];
      body.write(_docxTable(
        ['Nút & Liên kết', 'Bản mã (mm)', 'R_x, R_y (kN)', 'σ_eq,max', 'U_max', 'Kết luận'],
        connSummaryRows,
        '0F766E',
      ));

      // Bảng diễn giải chi tiết từng hạng mục kiểm tra, thế số & điều khoản tiêu chuẩn
      body.write(_docxParagraph('7.1. Bảng diễn giải chi tiết công thức thế số & điều khoản tiêu chuẩn cho từng nút:',
          bold: true, sizeHalfPt: 20, colorHex: '0F766E', spaceBefore: 40));
      final detailRows = <List<String>>[];
      for (final rep in connectionReports) {
        for (final item in rep.checks) {
          detailRows.add([
            'N${rep.nodeIndex + 1}: ${item.category}',
            '${item.demandLabel} ≤ ${item.capacityLabel}',
            item.formulaText,
            item.clauseRef,
            '${item.utilizationPct.toStringAsFixed(1)}% (${item.passed ? "ĐẠT" : "VƯỢT"})',
          ]);
        }
      }
      body.write(_docxTable(
        ['Hạng mục kiểm tra', 'Điều kiện kiểm tra', 'Công thức & Thế số chi tiết', 'Tiêu chuẩn', 'U (%)'],
        detailRows,
        '334155',
        leftAlignCols: const {0, 1, 2, 3},
      ));
    }

    // MỤC 8: DANH MỤC TIÊU CHUẨN & TÀI LIỆU THAM KHẢO
    body.write(_docxParagraph('8. DANH MỤC TIÊU CHUẨN ÁP DỤNG & TÀI LIỆU THAM KHẢO',
        bold: true, sizeHalfPt: 23, colorHex: '0F3D6E', spaceBefore: 100));
    body.write(_docxParagraph('8.1. Tiêu chuẩn thiết kế áp dụng:', bold: true, sizeHalfPt: 20, colorHex: '0F766E', spaceAfter: 40));
    for (final s in _standardsRefs) {
      body.write(_docxParagraph('${s.code} ${s.text}', sizeHalfPt: 18, colorHex: '1E293B', spaceAfter: 35, indentLeft: 120));
    }
    body.write(_docxParagraph('8.2. Giáo trình & Tài liệu khoa học tham khảo:', bold: true, sizeHalfPt: 20, colorHex: '0F766E', spaceBefore: 50, spaceAfter: 40));
    for (final r in _literatureRefs) {
      body.write(_docxParagraph('${r.code} ${r.text}', sizeHalfPt: 18, colorHex: '1E293B', spaceAfter: 35, indentLeft: 120));
    }

    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
            xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
  <w:body>
    ${body.toString()}
    <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1000" w:bottom="1000" w:left="1100"/></w:sectPr>
  </w:body>
</w:document>''';

    final contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  ${hasImage ? '<Default Extension="png" ContentType="image/png"/>' : ''}
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    const docRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdImg1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/viewport.png"/>
</Relationships>''';

    final archive = Archive();
    void addXml(String name, String content) {
      final data = utf8.encode(content);
      archive.addFile(ArchiveFile(name, data.length, data));
    }

    addXml('[Content_Types].xml', contentTypes);
    addXml('_rels/.rels', rels);
    addXml('word/document.xml', documentXml);
    if (hasImage) {
      addXml('word/_rels/document.xml.rels', docRels);
      archive.addFile(ArchiveFile('word/media/viewport.png', viewportPngBytes.length, viewportPngBytes));
    }

    final encoded = ZipEncoder().encode(archive);
    final bytes = Uint8List.fromList(encoded);
    const fileName = 'ThuyetMinh_CALFEM_PhiTuyen.docx';
    return saveBinaryFile(
      fileName,
      bytes,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
  }

  /// Xuất tệp Thuyết minh PDF (.pdf) chuẩn học thuật đầy đủ công thức, dẫn nguồn, ảnh 3D/2D & bảng tính chi tiết
  static Future<String?> exportPdf({
    required TrussModelData model,
    required TrussAnalysisResult linear,
    required TrussAnalysisResult nonlinear,
    required ProbeInspection probe,
    required double loadFactor,
    List<NodeConnectionReport>? connectionReports,
    List<MemberDesignCheck>? designChecks,
    BucklingAnalysisResult? buckling,
    Uint8List? viewportPngBytes,
  }) async {
    final checks = designChecks ?? CalfemNonlinearEngine.checkMembers(model, nonlinear);
    final fontReg = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    final now = DateTime.now();
    final ts = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontReg, bold: fontBold),
    );

    final navy = PdfColor.fromHex('#0F3D6E');
    final teal = PdfColor.fromHex('#0F766E');
    final slate = PdfColor.fromHex('#334155');
    final lightRow = PdfColor.fromHex('#F1F5F9');
    final boxBg = PdfColor.fromHex('#F8FAFC');
    final borderCol = PdfColor.fromHex('#CBD5E1');

    pw.Widget pdfFormulaCard(({String section, String eqNum, String formula, String explain, String source}) item) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: pw.BoxDecoration(
          color: boxBg,
          border: pw.Border(
            left: pw.BorderSide(color: navy, width: 2.5),
            top: pw.BorderSide(color: borderCol, width: 0.5),
            right: pw.BorderSide(color: borderCol, width: 0.5),
            bottom: pw.BorderSide(color: borderCol, width: 0.5),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(item.formula, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.7, color: PdfColors.black)),
                ),
                pw.SizedBox(width: 6),
                pw.Text(item.eqNum, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.6, color: navy)),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Text(item.explain, style: pw.TextStyle(fontSize: 7.1, color: slate, lineSpacing: 1.5)),
            pw.SizedBox(height: 1.5),
            pw.Text('Nguồn áp dụng: ${item.source}', style: pw.TextStyle(fontSize: 6.8, color: teal)),
          ],
        ),
      );
    }

    final formulaWidgets = <pw.Widget>[];
    String lastSec = '';
    for (final item in _trussFormulaCatalog) {
      if (item.section != lastSec) {
        lastSec = item.section;
        formulaWidgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 5, bottom: 3),
          child: pw.Text(item.section, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.6, color: teal)),
        ));
      }
      formulaWidgets.add(pdfFormulaCard(item));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'Thuyết minh Phân tích Phi tuyến CALFEM — ĐH Bách Khoa TP.HCM  |  Trang ${ctx.pageNumber}/${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 7.0, color: slate),
          ),
        ),
        build: (context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text('TRƯỜNG ĐẠI HỌC BÁCH KHOA – ĐHQG TP. HỒ CHÍ MINH',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: navy)),
                pw.SizedBox(height: 2),
                pw.Text('THUYẾT MINH TÍNH TOÁN PHÂN TÍCH PHI TUYẾN HỆ DÀN (CALFEM 3.4)',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12.6, color: PdfColors.black),
                    textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 2),
                pw.Text(
                    'GVHD: PGS. TS Ngô Hữu Cường  |  HV: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)  |  vothanhvang@gmail.com • 0973.993.494  |  Xuất: $ts',
                    style: pw.TextStyle(fontSize: 7.2, color: slate),
                    textAlign: pw.TextAlign.center),
              ],
            ),
          ),
          pw.Divider(color: navy, thickness: 1.2),
          if (viewportPngBytes != null && viewportPngBytes.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderCol, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                padding: const pw.EdgeInsets.all(2),
                child: pw.Image(pw.MemoryImage(viewportPngBytes), height: 185, fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'Hình 1. Mô hình kết cấu 3D/2D & bản đồ màu trường ứng suất/biến dạng (λ = ${loadFactor.toStringAsFixed(2)})',
                style: pw.TextStyle(fontSize: 7.4, color: slate),
              ),
            ),
          ],
          pw.SizedBox(height: 6),
          pw.Text('1. Thông số đầu vào, thuật toán & phạm vi tiêu chuẩn áp dụng',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.2, color: navy)),
          pw.SizedBox(height: 3),
          pw.Text(
            '• Mô hình: ${model.name} (${model.nNodes} nút, ${model.nElems} thanh) — ${model.description}\n'
            '• Tiết diện & chiều dài thanh: ${[for (int e = 0; e < model.nElems; e++) "T${e + 1}: ${model.sectionDimsForElem(e).formatSpec(model.sectionShapeForElem(e))} (L₀=${model.initialLength(e).toStringAsFixed(0)} mm)"].join(" | ")}\n'
            '• Liên kết nút: ${[for (int i = 0; i < model.nodeSupports.length; i++) "N${i + 1}: ${model.nodeSupports[i].shortLabel}"].join(" | ")}${model.hasAnySpring ? " (k = ${model.springStiffnessKnMm.toStringAsFixed(1)} kN/mm)" : ""}\n'
            '• Tải trọng & vật liệu: λ = ${loadFactor.toStringAsFixed(2)} | E = ${(model.E / 1000).toStringAsFixed(0)} GPa, fy = ${model.fyRef.toStringAsFixed(0)} MPa${model.materialNonlinear ? " (GMNIA đàn-dẻo, β=${(model.hardeningRatio * 100).toStringAsFixed(1)}%)" : " (Đàn hồi)"}\n'
            '• Thuật toán: ${nonlinear.methodName} | Hội tụ: ${nonlinear.converged ? "ĐẠT" : "CHƯA ĐẠT"} (${nonlinear.totalIterations} vòng lặp, lõi ${nonlinear.engineSource})'
            '${(buckling != null && buckling.hasBucklingMode) ? " | Trị riêng mất ổn định α_cr = ${buckling.alphaCr.toStringAsFixed(2)} (P_cr = ${buckling.pCrKn.toStringAsFixed(1)} kN)." : "."}',
            style: const pw.TextStyle(fontSize: 7.8, lineSpacing: 2.0),
          ),

          pw.SizedBox(height: 7),
          pw.Text('2. Cơ sở lý thuyết, hệ thống công thức tính toán chi tiết & dẫn nguồn',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.2, color: navy)),
          ...formulaWidgets,

          pw.SizedBox(height: 7),
          pw.Text('3. Bảng chuyển vị nút & phản lực gối (Tuyến tính vs Phi tuyến)',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.2, color: navy)),
          pw.SizedBox(height: 3),
          pw.TableHelper.fromTextArray(
            headerDecoration: pw.BoxDecoration(color: navy),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 7.3),
            cellStyle: const pw.TextStyle(fontSize: 7.2),
            oddRowDecoration: pw.BoxDecoration(color: lightRow),
            headers: ['Nút', 'u_x TT (mm)', 'u_y TT (mm)', 'u_x PT (mm)', 'u_y PT (mm)', 'R_x PT (kN)', 'R_y PT (kN)'],
            data: [
              for (int i = 0; i < model.nNodes; i++)
                [
                  'N${i + 1} (${model.nodeSupports[i].shortLabel})',
                  linear.uMm[2 * i].toStringAsFixed(5),
                  linear.uMm[2 * i + 1].toStringAsFixed(5),
                  nonlinear.uMm[2 * i].toStringAsFixed(5),
                  nonlinear.uMm[2 * i + 1].toStringAsFixed(5),
                  (nonlinear.reactionsN[2 * i] / 1000).toStringAsFixed(4),
                  (nonlinear.reactionsN[2 * i + 1] / 1000).toStringAsFixed(4),
                ],
            ],
          ),

          pw.SizedBox(height: 8),
          pw.Text('4. Bảng nội lực, ứng suất & kiểm tra bền – ổn định thanh (TCVN 5575 / EN 1993-1-1)',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.2, color: teal)),
          pw.SizedBox(height: 3),
          pw.TableHelper.fromTextArray(
            headerDecoration: pw.BoxDecoration(color: teal),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 6.8),
            cellStyle: const pw.TextStyle(fontSize: 6.7),
            oddRowDecoration: pw.BoxDecoration(color: lightRow),
            headers: ['Thanh', 'Tiết diện', 'L₀', 'N PT (kN)', 'σ (MPa)', 'λ', 'χ', 'N_Rd (kN)', 'U (%)', 'KQ'],
            data: [
              for (int e = 0; e < model.nElems; e++)
                [
                  'T${e + 1} (${model.memberLabels[e]})',
                  model.sectionDimsForElem(e).formatSpec(model.sectionShapeForElem(e)),
                  model.initialLength(e).toStringAsFixed(0),
                  (nonlinear.nForcesN[e] / 1000).toStringAsFixed(2),
                  nonlinear.stressMpa[e].toStringAsFixed(2),
                  e < checks.length ? checks[e].slenderness.toStringAsFixed(1) : '-',
                  e < checks.length ? checks[e].chiBuckling.toStringAsFixed(3) : '-',
                  e < checks.length ? checks[e].nCapacityKn.toStringAsFixed(1) : '-',
                  e < checks.length ? '${checks[e].utilizationPct.toStringAsFixed(1)}%' : '-',
                  e < checks.length ? (checks[e].passed ? 'ĐẠT' : 'VƯỢT') : '-',
                ],
            ],
          ),

          pw.SizedBox(height: 8),
          pw.Text('5. Phẫu thuật mặt cắt & kiểm chứng cân bằng cấu hình biến dạng',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.2, color: navy)),
          pw.SizedBox(height: 3),
          pw.Text(
            '• Thanh T${probe.elemIndex + 1} (${probe.memberLabel}, L₀=${probe.l0Mm.toStringAsFixed(1)} mm) tại ξ = ${probe.xi.toStringAsFixed(2)} (s = ${probe.sMm.toStringAsFixed(1)} mm), thớ (η=${probe.etaNorm.toStringAsFixed(2)}, ζ=${probe.zetaNorm.toStringAsFixed(2)}), tiết diện ${model.sectionShapeForElem(probe.elemIndex).label} (${probe.sectionDims.formatSpec(model.sectionShapeForElem(probe.elemIndex))}):\n'
            '  - Thế số PT (2.9): σ_xx = ${probe.sigmaAxialMpa.toStringAsFixed(3)} + ${probe.sigmaBendingMpa.toStringAsFixed(3)} = ${probe.sigmaXxMpa.toStringAsFixed(4)} MPa | von Mises = ${probe.sigmaVonMisesMpa.toStringAsFixed(4)} MPa | τ_max = ${probe.tauMaxMohrMpa.toStringAsFixed(4)} MPa | ε_xx = ${probe.epsXxMicro.toStringAsFixed(2)} με | ε_⊥ = ${probe.epsPoissonMicro.toStringAsFixed(2)} με.\n'
            '• Cân bằng cấu hình biến dạng: ∑Fx = ${nonlinear.sumFxN.toStringAsExponential(2)} N, ∑Fy = ${nonlinear.sumFyN.toStringAsExponential(2)} N, ∑M = ${nonlinear.sumMNmm.toStringAsExponential(2)} N·mm, ||R||_∞ = ${nonlinear.maxFreeResidualN.toStringAsExponential(2)} N.\n'
            '• Năng lượng biến dạng tổng: U_TT = ${(linear.totalEnergyNmm / 1000).toStringAsFixed(6)} J  |  U_PT = ${(nonlinear.totalEnergyNmm / 1000).toStringAsFixed(6)} J.',
            style: const pw.TextStyle(fontSize: 7.7, lineSpacing: 2.0),
          ),

          if (connectionReports != null && connectionReports.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('6. Tính toán & kiểm tra chi tiết liên kết các nút (TCVN 5575 / EN 1993-1-8)',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.2, color: navy)),
            pw.SizedBox(height: 3),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6.7, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: teal),
              cellStyle: const pw.TextStyle(fontSize: 6.5),
              oddRowDecoration: pw.BoxDecoration(color: lightRow),
              headers: ['Hạng mục (Nút)', 'Điều kiện', 'Công thức & Thế số', 'Tiêu chuẩn', 'U (%)'],
              data: [
                for (final rep in connectionReports)
                  for (final item in rep.checks)
                    [
                      'N${rep.nodeIndex + 1}: ${item.category}',
                      '${item.demandLabel} ≤ ${item.capacityLabel}',
                      item.formulaText,
                      item.clauseRef,
                      '${item.utilizationPct.toStringAsFixed(1)}% ${item.passed ? "ĐẠT" : "VƯỢT"}',
                    ],
              ],
            ),
          ],

          pw.SizedBox(height: 8),
          pw.Text('7. Danh mục Tiêu chuẩn áp dụng & Tài liệu tham khảo',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.2, color: navy)),
          pw.SizedBox(height: 3),
          pw.Text('7.1. Tiêu chuẩn thiết kế:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.0, color: teal)),
          for (final s in _standardsRefs)
            pw.Text('  ${s.code} ${s.text}', style: pw.TextStyle(fontSize: 7.1, color: slate, lineSpacing: 1.5)),
          pw.SizedBox(height: 3),
          pw.Text('7.2. Giáo trình & Tài liệu khoa học:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.0, color: teal)),
          for (final r in _literatureRefs)
            pw.Text('  ${r.code} ${r.text}', style: pw.TextStyle(fontSize: 7.1, color: slate, lineSpacing: 1.5)),
        ],
      ),
    );

    final bytes = await pdf.save();
    const fileName = 'BaoCao_CALFEM_PhiTuyen.pdf';
    return saveBinaryFile(fileName, bytes, 'application/pdf');
  }

  /// Xuất bảng số liệu CSV chuẩn UTF-8 BOM (mở trực tiếp bằng Microsoft Excel không lỗi font tiếng Việt)
  static Future<String?> exportCsv({
    required TrussModelData model,
    required TrussAnalysisResult linear,
    required TrussAnalysisResult nonlinear,
    required List<MemberDesignCheck> designChecks,
    required BucklingAnalysisResult buckling,
    required double loadFactor,
  }) async {
    final buf = StringBuffer();
    buf.writeln('PHÂN TÍCH PHI TUYẾN HỆ DÀN (CALFEM 3.4)');
    buf.writeln('Mô hình,"${model.name}"');
    buf.writeln('Thuật toán,"${nonlinear.methodName}",Hệ số tải λ,${loadFactor.toStringAsFixed(3)}');
    if (buckling.hasBucklingMode) {
      buf.writeln('Trị riêng mất ổn định α_cr,${buckling.alphaCr.toStringAsFixed(4)},P_cr (kN),${buckling.pCrKn.toStringAsFixed(3)}');
    }
    buf.writeln();
    buf.writeln('BẢNG 1 - CHUYỂN VỊ NÚT & PHẢN LỰC GỐI');
    buf.writeln('Nút,X (mm),Y (mm),ux TT (mm),uy TT (mm),ux PT (mm),uy PT (mm),Rx PT (kN),Ry PT (kN)');
    for (int i = 0; i < model.nNodes; i++) {
      buf.writeln(
        'N${i + 1},${model.coords[i][0].toStringAsFixed(2)},${model.coords[i][1].toStringAsFixed(2)},'
        '${linear.uMm[2 * i].toStringAsFixed(6)},${linear.uMm[2 * i + 1].toStringAsFixed(6)},'
        '${nonlinear.uMm[2 * i].toStringAsFixed(6)},${nonlinear.uMm[2 * i + 1].toStringAsFixed(6)},'
        '${(nonlinear.reactionsN[2 * i] / 1000.0).toStringAsFixed(5)},${(nonlinear.reactionsN[2 * i + 1] / 1000.0).toStringAsFixed(5)}',
      );
    }
    buf.writeln();
    buf.writeln('BẢNG 2 - NỘI LỰC & KIỂM TRA BỀN - ỔN ĐỊNH THANH (TCVN 5575 / EN 1993-1-1)');
    buf.writeln('Thanh,Nút nối,Tiết diện,Góc xoay (°),L0 (mm),A (mm2),N TT (kN),N PT (kN),σ PT (MPa),ε (με),Độ mảnh λ,Hệ số χ,Khả năng N_Rd (kN),Tỷ số U (%),Kết luận');
    for (int e = 0; e < model.nElems; e++) {
      final dims = model.sectionDimsForElem(e);
      final shapeE = model.sectionShapeForElem(e);
      final chk = e < designChecks.length ? designChecks[e] : null;
      buf.writeln(
        'T${e + 1},"${model.memberLabels[e]}","${dims.formatSpec(shapeE)}",${dims.rotationDeg.toStringAsFixed(1)},'
        '${model.initialLength(e).toStringAsFixed(2)},${model.areas[e].toStringAsFixed(2)},'
        '${(linear.nForcesN[e] / 1000.0).toStringAsFixed(4)},${(nonlinear.nForcesN[e] / 1000.0).toStringAsFixed(4)},'
        '${nonlinear.stressMpa[e].toStringAsFixed(4)},${(nonlinear.strain[e] * 1e6).toStringAsFixed(2)},'
        '${chk?.slenderness.toStringAsFixed(2) ?? ""},${chk?.chiBuckling.toStringAsFixed(4) ?? ""},'
        '${chk?.nCapacityKn.toStringAsFixed(3) ?? ""},${chk?.utilizationPct.toStringAsFixed(2) ?? ""},'
        '${chk != null ? (chk.passed ? "ĐẠT" : "VƯỢT") : ""}',
      );
    }
    if (nonlinear.iterResidualsN.isNotEmpty) {
      buf.writeln();
      buf.writeln('BẢNG 3 - LỊCH SỬ HỘI TỤ NEWTON-RAPHSON (BƯỚC GIA TẢI CUỐI)');
      buf.writeln('Vòng lặp k,Lực dư ||R||_inf (N)');
      for (int k = 0; k < nonlinear.iterResidualsN.length; k++) {
        buf.writeln('$k,${nonlinear.iterResidualsN[k].toStringAsExponential(6)}');
      }
    }

    final utf8Bytes = utf8.encode(buf.toString());
    final bomBytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8Bytes]);
    return saveBinaryFile('SoLieu_CALFEM_PhiTuyen.csv', bomBytes, 'text/csv');
  }

  /// Lưu ảnh PNG độ phân giải cao từ khung nhìn 3D / 2D
  static Future<String?> exportPngSnapshot(Uint8List pngBytes) async {
    return saveBinaryFile('MoHinh_CALFEM_3D_2D.png', pngBytes, 'image/png');
  }

  /// Lưu tệp dự án mô hình dàn (.json)
  static Future<String?> exportProjectJson(String jsonContent) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonContent));
    return saveBinaryFile('DuAn_CALFEM_PhiTuyen.json', bytes, 'application/json');
  }

  /// Mở tệp dự án mô hình dàn (.json) từ máy
  static Future<String?> importProjectJson() async {
    return openTextFile(ext: 'json');
  }
}
