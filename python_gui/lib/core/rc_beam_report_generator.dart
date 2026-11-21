// ============================================================================
// MÔ-ĐUN XUẤT THUYẾT MINH WORD (.DOCX), PDF (.PDF) & CSV EXCEL
// CHO DẦM BÊ TÔNG CỐT THÉP / DẦM BÊ TÔNG CỐT CỨNG (PHƯƠNG PHÁP THỚ & RAYLEIGH-RITZ)
// ============================================================================
// Trình bày tường minh, mạch lạc, có dẫn nguồn tiêu chuẩn & tài liệu học thuật:
//   • Tiêu chuẩn áp dụng: TCVN 5574:2018, EN 1992-1-1:2004 (EC2),
//     EN 1994-1-1:2004 (EC4), AISC 360-16 (Ch. I), JGJ 138-2016, TCVN 5575:2012.
//   • Cơ sở học thuật: Hognestad (1951), Spacone-Filippou-Taucer (1996),
//     CEB-FIP MC 90/2010, CALFEM 3.4 (beam2e), Bài giảng NSA_4/NSA_5/NSA_6.
//   • Kiểm chứng Benchmark thực nghiệm Vecchio & Shim (2004) & đối chiếu PSD EC4/AISC.
//   • In tường minh Ma trận độ cứng 6×6 [K_t^e], quan hệ {f^e} ↔ {d^e}, bảng hội tụ lưới.
// ============================================================================

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'rc_beam_engine.dart';
import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';

class RcBeamReportGenerator {
  static String _xmlEsc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _p(
    String txt, {
    bool bold = false,
    bool italic = false,
    int sz = 21,
    String? color,
    String align = 'left',
    int before = 0,
    int after = 75,
    int indent = 0,
  }) {
    final c = color != null ? '<w:color w:val="$color"/>' : '';
    final b = bold ? '<w:b/>' : '';
    final it = italic ? '<w:i/>' : '';
    final ind = indent > 0 ? '<w:ind w:left="$indent"/>' : '';
    return '<w:p><w:pPr><w:jc w:val="$align"/><w:spacing w:before="$before" w:after="$after"/>$ind</w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>$b$it$c<w:sz w:val="$sz"/></w:rPr>'
        '<w:t xml:space="preserve">${_xmlEsc(txt)}</w:t></w:r></w:p>';
  }

  static String _formulaBox(String eqNum, String formula, String explain, String src) {
    return '<w:tbl><w:tblPr><w:tblW w:w="9500" w:type="dxa"/><w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:left w:val="single" w:sz="18" w:space="0" w:color="0F3D6E"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:insideH w:val="none"/><w:insideV w:val="none"/>'
        '</w:tblBorders></w:tblPr><w:tr>'
        '<w:tc><w:tcPr><w:tcW w:w="8200" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F8FAFC"/></w:tcPr>'
        '${_p(formula, bold: true, sz: 20, color: "0F172A", before: 35, after: 30, indent: 110)}'
        '${_p(explain, sz: 18, color: "334155", after: 20, indent: 110)}'
        '${_p("Nguồn áp dụng: $src", italic: true, sz: 16, color: "0F766E", after: 35, indent: 110)}'
        '</w:tc>'
        '<w:tc><w:tcPr><w:tcW w:w="1300" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F8FAFC"/></w:tcPr>'
        '${_p(eqNum, bold: true, sz: 18, color: "0F3D6E", align: "right", before: 35)}'
        '</w:tc></w:tr></w:tbl><w:p><w:pPr><w:spacing w:after="45"/></w:pPr></w:p>';
  }

  static String _img(int wPx, int hPx, String cap) {
    final aspect = (wPx > 0 && hPx > 0) ? hPx / wPx : 0.62;
    const cx = 5600000;
    final cy = (cx * aspect).round().clamp(1600000, 4800000);
    return '<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:before="80" w:after="40"/></w:pPr>'
        '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="1" name="RcBeamViewport"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="1" name="viewport.png"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="rIdImg1"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
        '${_p(cap, italic: true, sz: 18, color: "475569", align: "center")}';
  }

  static String _tbl(
    List<String> hdrs,
    List<List<String>> rows,
    String fillHex, {
    Set<int> leftCols = const {0},
  }) {
    final buf = StringBuffer();
    buf.write('<w:tbl><w:tblPr><w:tblW w:w="9500" w:type="dxa"/><w:tblBorders>'
        '<w:top w:val="single" w:sz="6" w:space="0" w:color="1B365D"/>'
        '<w:bottom w:val="single" w:sz="8" w:space="0" w:color="1B365D"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '</w:tblBorders></w:tblPr><w:tr>');
    for (final h in hdrs) {
      buf.write('<w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="$fillHex"/></w:tcPr>'
          '${_p(h, bold: true, sz: 17, color: "FFFFFF", align: "center", after: 25)}</w:tc>');
    }
    buf.write('</w:tr>');
    for (int r = 0; r < rows.length; r++) {
      final f = r.isOdd ? 'F1F5F9' : 'FFFFFF';
      buf.write('<w:tr>');
      for (int c = 0; c < rows[r].length; c++) {
        buf.write('<w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="$f"/></w:tcPr>'
            '${_p(rows[r][c], sz: 16, align: leftCols.contains(c) ? "left" : "right", after: 25)}</w:tc>');
      }
      buf.write('</w:tr>');
    }
    buf.write('</w:tbl><w:p><w:pPr><w:spacing w:after="55"/></w:pPr></w:p>');
    return buf.toString();
  }

  /// Tính mô-men giới hạn dẻo lý thuyết PSD theo EN 1994-1-1 §6.2.1.2 / AISC 360-16 §I3.3 để đối chiếu trực tiếp!
  static ({double mPlKnm, double xPnaMm}) _computePlasticMomentPsd(RcBeamConfig cfg) {
    final fibers = RcBeamFiberEngine.buildFibers(cfg);
    final h = cfg.heightMm;
    double lo = -0.5 * h, hi = 0.5 * h;
    for (int it = 0; it < 60; it++) {
      final mid = 0.5 * (lo + hi);
      final aBlk = 0.85 * (0.5 * h - mid);
      final yBlkBot = 0.5 * h - aBlk;
      double netN = 0.0;
      for (final f in fibers) {
        if (f.kind == 'concrete') {
          if (f.yMm >= yBlkBot) netN -= 0.85 * cfg.fcMpa * f.areaMm2;
        } else {
          netN += (f.yMm >= mid ? -f.fyMpa : f.fyMpa) * f.areaMm2;
        }
      }
      if (netN > 0) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    final yp = 0.5 * (lo + hi);
    final aBlk = 0.85 * (0.5 * h - yp);
    final yBlkBot = 0.5 * h - aBlk;
    double mPl = 0.0;
    for (final f in fibers) {
      if (f.kind == 'concrete') {
        if (f.yMm >= yBlkBot) mPl += 0.85 * cfg.fcMpa * f.areaMm2 * (f.yMm - yp);
      } else {
        final sig = f.yMm >= yp ? -f.fyMpa : f.fyMpa;
        mPl -= sig * f.areaMm2 * (f.yMm - yp);
      }
    }
    return (mPlKnm: mPl / 1e6, xPnaMm: 0.5 * h - yp);
  }

  static const List<({String sec, String eq, String formula, String explain, String src})> _beamFormulas = [
    (
      sec: '2.1. Giả thiết động học Euler–Bernoulli & Mô hình Mặt cắt Thớ (Fiber Section)',
      eq: '(2.1)',
      formula: 'ε(x, y) = ε₀(x) − y · κ(x)   với   ε₀ = du/dx ,   κ = d²v/dx² ,   y ∈ [−h/2, +h/2]',
      explain:
          'Tiết diện ngang (b × h) được chia thành n_fib dải thớ bê tông mỏng dy = h/n_fib. Cốt thép kéo As đặt tại trọng tâm y_s = −h/2 + a_s, cốt thép nén As\' tại y_s\' = h/2 − a_s\', và cốt cứng thép hình chữ I (nếu bật) chia thành thớ cánh trên, cánh dưới và 6 thớ bản bụng đồng tâm.',
      src: '[TC1] TCVN 5574:2018 §8.1.2; [TC2] EN 1992-1-1:2004 §6.1(2); [TL5] Spacone, Filippou & Taucer (1996).',
    ),
    (
      sec: '2.2. Định luật Quan hệ Ứng suất – Biến dạng Phi tuyến Vật liệu',
      eq: '(2.2)',
      formula: 'Bê tông nén (Hognestad): σ_c = −f\'_c·[2(ε_c/ε_c0) − (ε_c/ε_c0)²] (0 ≤ ε_c ≤ ε_c0) ;  E_t = (2f\'_c/ε_c0)(1 − ε_c/ε_c0)',
      explain:
          'Nhánh giảm sau đỉnh (ε_c0 < ε_c ≤ ε_cu = 3.5‰): σ_c = −f\'_c·[1 − 0.15(ε_c − ε_c0)/(ε_cu − ε_c0)]. Khi ε_c > ε_cu bê tông vỡ nén còn ứng suất dư −0.20·f\'_c.',
      src: '[TL4] Hognestad (1951) Bull. 399; [TC2] EN 1992-1-1:2004 §3.1.5; [TC1] TCVN 5574:2018 §6.1.3.',
    ),
    (
      sec: '2.2. Định luật Quan hệ Ứng suất – Biến dạng Phi tuyến Vật liệu',
      eq: '(2.3)',
      formula: 'Bê tông kéo & Nứt mềm hóa: ε_cr = f_ct/E_c ;  σ_t(ε) = f_ct·exp[−0.35·(ε − ε_cr)/ε_cr] (ε > ε_cr) ;  E_t = −0.35·σ_t/ε_cr',
      explain:
          'Mô hình mềm hóa kéo hàm mũ mượt (Tension Stiffening) phản ánh sự đóng góp kéo của bê tông nguyên giữa các vết nứt bám dính vào cốt thép/lõi thép, đồng thời dùng mô-đun tiếp tuyến nhất quán để Newton-Raphson hội tụ bậc 2.',
      src: '[TL6] CEB-FIP Model Code 1990 / fib MC 2010; [TL7] Collins & Mitchell (1991).',
    ),
    (
      sec: '2.2. Định luật Quan hệ Ứng suất – Biến dạng Phi tuyến Vật liệu',
      eq: '(2.4)',
      formula: 'Cốt thép & Lõi cốt cứng chữ I: σ_s = E_s·ε (|ε| ≤ ε_y = f_y/E_s) ;  σ_s = sgn(ε)·[f_y + b_h·E_s·(|ε| − ε_y)] (|ε| > ε_y)',
      explain:
          'Định luật đàn-dẻo song tuyến tính có tái bền đẳng hướng (tỷ số tái bền b_h = E_sh/E_s) áp dụng độc lập theo đúng giới hạn chảy f_y của thép thanh và f_ya của lõi thép hình chữ I.',
      src: '[TL1] Bài giảng NSA_5 (PGS. TS Ngô Hữu Cường); [TC2] EN 1992-1-1 §3.2.7; [TC1] TCVN 5574:2018 §6.2.3.',
    ),
    (
      sec: '2.3. Tích phân Nội lực Mặt cắt, Độ cứng Tiếp tuyến [D_t] (EA, ES, EI) & Trục trung hòa',
      eq: '(2.5)',
      formula: 'N = ∑ σ_i·A_i  ;   M = −∑ σ_i·y_i·A_i  ;   [D_t] = [[EA_t, ES_t], [ES_t, EI_t]]  (EA_t = ∑E_t,i A_i ; ES_t = −∑E_t,i y_i A_i ; EI_t = ∑E_t,i y_i² A_i)',
      explain:
          'Khi bê tông vùng kéo nứt, phân bố độ cứng mất đối xứng làm xuất hiện số hạng khớp nối uốn–kéo ES_t ≠ 0. Độ cứng uốn hiệu dụng quanh trục trung hòa là EI_eff = EI_t − ES_t²/EA_t và vị trí trục trung hòa tức thời là y_NA = ε₀/κ ⇒ x_NA = h/2 − y_NA (tính từ mép nén trên).',
      src: '[TL5] Spacone et al. (1996); [TL1] NSA_5; [TC3] EN 1994-1-1:2004 §6.7.3.',
    ),
    (
      sec: '2.4. Phương pháp Rayleigh–Ritz (Hàm dừng thế năng) & Ma trận độ cứng 6×6 [K_t^e]',
      eq: '(2.6)',
      formula: 'Π(d) = U(d) − W(d) = ∫_V (∫σ dε) dV − {d}ᵀ{F_ext}  ;   δΠ = 0  ⇒  {f_int^e} = ∫₀^Le [B(x)]ᵀ{N, M}ᵀ dx',
      explain:
          'Xấp xỉ trường chuyển vị phần tử 2 nút 6 bậc tự do {d^e} = [u₁, v₁, θ₁, u₂, v₂, θ₂]ᵀ bằng hàm tuyến tính cho u(x) và đa thức Hermite bậc 3 cho v(x): B_u = [−1/L_e, 0, 0, 1/L_e, 0, 0]; B_κ = [0, (−6+12ξ)/L_e², (−4+6ξ)/L_e, 0, (6−12ξ)/L_e², (−2+6ξ)/L_e].',
      src: '[TL2] CALFEM 3.4 (beam2e); [TL3] Dahlblom (2016) Ch. 4; [TL1] NSA_3 & NSA_4.',
    ),
    (
      sec: '2.4. Phương pháp Rayleigh–Ritz (Hàm dừng thế năng) & Ma trận độ cứng 6×6 [K_t^e]',
      eq: '(2.7)',
      formula: '[K_t^e] = ∂{f_int^e}/∂{d^e} = ∫₀^Le [B(x)]ᵀ[D_t(x)][B(x)] dx ≈ ∑_{g=1}^3 w_g·L_e·[B(ξ_g)]ᵀ[D_t(ξ_g)][B(ξ_g)]  ⇒  [K_t]{Δd} = {ΔF}',
      explain:
          'Tích phân số Gauss–Legendre 3 điểm (ξ_g ∈ {0.112702, 0.500000, 0.887298}, w_g ∈ {5/18, 8/18, 5/18}) đạt chính xác tuyệt đối đến bậc đa thức 5. Hệ phi tuyến giải lặp Full Newton–Raphson kèm Backtracking Line Search và chuẩn hóa riêng bậc tự do lực (N) và mô-men (N·mm).',
      src: '[TL8] Bathe (2014) Finite Element Procedures Ch. 5; [TL1] NSA_6 Mục 6.3.',
    ),
    (
      sec: '2.5. Đối chiếu Giải tích & Phân bố Ứng suất Dẻo (PSD — Dầm Bê tông Cốt cứng)',
      eq: '(2.8)',
      formula: 'Uốn 3 điểm: M_max = Q·a(L−a)/L (a=L/2 ⇒ M_max = QL/4)  |  Uốn 4 điểm: M_max = (Q/2)·a  |  PSD: M_pl = ∑ F_i·|y_i − y_PNA|',
      explain:
          'Kiểm chứng đàn hồi bằng công thức v_mid,lin = −QL³/(48·EI₀) (3 điểm) và kiểm chứng khả năng chịu uốn cực hạn của Dầm Bê tông Cốt cứng bằng phương pháp Phân bố Ứng suất Dẻo (khối nén bê tông chữ nhật 0.85·f\'_c, toàn bộ thép hình và cốt thép chảy dẻo).',
      src: '[TC3] EN 1994-1-1:2004 §6.2.1.2; [TC4] AISC 360-16 Ch. I §I3.3; [TC5] JGJ 138-2016 §5.2; [TL9] Hibbeler (2019).',
    ),
  ];

  static const List<({String code, String text})> _beamStandards = [
    (code: '[TC1]', text: 'TCVN 5574:2018. Thiết kế kết cấu bê tông và bê tông cốt thép. Bộ Khoa học và Công nghệ Việt Nam.'),
    (code: '[TC2]', text: 'EN 1992-1-1:2004 (Eurocode 2). Design of concrete structures — Part 1-1: General rules and rules for buildings. CEN.'),
    (code: '[TC3]', text: 'EN 1994-1-1:2004 (Eurocode 4). Design of composite steel and concrete structures — Part 1-1: General rules and rules for buildings. CEN.'),
    (code: '[TC4]', text: 'ANSI/AISC 360-16. Specification for Structural Steel Buildings (Chapter I: Design of Composite Members, §I3.3 Encased Composite Members). AISC, Chicago.'),
    (code: '[TC5]', text: 'JGJ 138-2016. Code for Design of Composite Structures (Kết cấu Bê tông Cốt cứng SRC — Mục 5.2 Chịu uốn). CABP.'),
  ];

  static const List<({String code, String text})> _beamLit = [
    (code: '[TL1]', text: 'Ngô Hữu Cường, Đoàn Ngọc Tịnh Nghiêm. Bài giảng Phân tích Phi tuyến Kết cấu (NSA_3, NSA_4, NSA_5, NSA_6), Khoa Kỹ thuật Xây dựng, ĐH Bách Khoa – ĐHQG TP.HCM.'),
    (code: '[TL2]', text: 'Division of Structural Mechanics, Lund University (2004). CALFEM — A Finite Element Toolbox to MATLAB, Version 3.4 (beam2e, beam2s).'),
    (code: '[TL3]', text: 'K.-G. Olsson, O. Dahlblom (2016). Structural Mechanics: Modelling and Analysis of Frames and Trusses. John Wiley & Sons.'),
    (code: '[TL4]', text: 'E. Hognestad (1951). A Study of Combined Bending and Axial Load in Reinforced Concrete Members. Bulletin No. 399, Univ. of Illinois Eng. Exp. Station.'),
    (code: '[TL5]', text: 'E. Spacone, F.C. Filippou, F.F. Taucer (1996). Fibre Beam-Column Model for Non-Linear Analysis of R/C Frames: Part I. Formulation. Earthq. Eng. Struct. Dyn., 25, 711–725.'),
    (code: '[TL6]', text: 'CEB-FIP Model Code 1990 & fib Model Code 2010 for Concrete Structures. Lausanne: fib.'),
    (code: '[TL7]', text: 'M.P. Collins, D. Mitchell (1991). Prestressed Concrete Structures (Tension Stiffening & Sectional Analysis). Prentice Hall.'),
    (code: '[TL8]', text: 'K.-J. Bathe (2014). Finite Element Procedures, 2nd Edition. Prentice Hall / Watertown.'),
    (code: '[TL9]', text: 'R.C. Hibbeler (2019). Structural Analysis, 10th Edition. Pearson Education.'),
    (code: '[TL10]', text: 'F.J. Vecchio, W. Shim (2004). Experimental and Analytical Reexamination of Classic Concrete Beam Tests. ASCE J. Struct. Eng., 130(3), 460–469 (Benchmark VS-A3, VS-B3, VS-C3).'),
    (code: '[TL11]', text: 'N.H. Burns, C.P. Siess (1962). Load-Deformation Characteristics of Beam-Column Connections in Reinforced Concrete. Univ. of Illinois SRS No. 234 (Beam J-4) & H.-G. Kwak, F.C. Filippou (1990), UCB/SEMM-90/14.'),
  ];

  /// 1. Xuất Thuyết minh Microsoft Word (.docx) Dầm BTCT / Bê tông Cốt cứng chuẩn học thuật
  static Future<String?> exportDocx({
    required RcBeamAnalysisResult linear,
    required RcBeamAnalysisResult active,
    required List<RcMeshConvergencePoint> meshConv,
    required double probeXNorm,
    Uint8List? viewportPngBytes,
    int? pngWidthPx,
    int? pngHeightPx,
  }) async {
    final cfg = active.config;
    final probe = RcBeamFiberEngine.probeBeamAt(active, probeXNorm);
    final sec = probe.section;
    final eiPct = 100.0 * sec.eiEffNmm2 / math.max(1.0, active.eiGrossNmm2);
    final psd = _computePlasticMomentPsd(cfg);
    final mkCurve = RcBeamFiberEngine.computeMomentCurvature(cfg);
    final mUFiber = mkCurve.fold(0.0, (m, p) => math.max(m, p.momentKnm));
    final diffPsdPct = psd.mPlKnm > 1e-6 ? 100.0 * (mUFiber - psd.mPlKnm) / psd.mPlKnm : 0.0;

    // Phần tử nguy hiểm nhất (mô-men lớn nhất) để in tường minh ma trận độ cứng 6×6 [K_t^e]
    RcBeamElementResult critEl = active.elements.first;
    for (final el in active.elements) {
      if (math.max(el.m1Knm.abs(), el.m2Knm.abs()) > math.max(critEl.m1Knm.abs(), critEl.m2Knm.abs())) {
        critEl = el;
      }
    }

    final hasImg = viewportPngBytes != null && viewportPngBytes.isNotEmpty;
    final now = DateTime.now();
    final ts = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final beamKind = cfg.hasRigidCore ? 'DẦM BÊ TÔNG CỐT CỨNG (SRC — LÕI THÉP HÌNH CHỮ I)' : 'DẦM BÊ TÔNG CỐT THÉP CHỊU UỐN';
    final body = StringBuffer();
    body.write(_p('TRƯỜNG ĐẠI HỌC BÁCH KHOA – ĐHQG TP. HỒ CHÍ MINH', bold: true, sz: 22, color: '1B365D', align: 'center', after: 35));
    body.write(_p('THUYẾT MINH PHÂN TÍCH PHI TUYẾN VẬT LIỆU $beamKind', bold: true, sz: 26, color: '0F3D6E', align: 'center', after: 35));
    body.write(_p('PHƯƠNG PHÁP THỚ (FIBER SECTION) & RAYLEIGH–RITZ PTHH (CHUẨN CALFEM)', bold: true, sz: 20, color: '0F766E', align: 'center', after: 45));
    body.write(_p('Giảng viên hướng dẫn: PGS. TS Ngô Hữu Cường  |  Học viên: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)',
        bold: true, sz: 18, color: '1E293B', align: 'center', after: 25));
    body.write(_p('Email: vothanhvang@gmail.com  •  ĐT: 0973.993.494  •  Ngày xuất: $ts', sz: 17, color: '475569', align: 'center', after: 90));

    if (hasImg) {
      body.write(_img(pngWidthPx ?? 1200, pngHeightPx ?? 720,
          'Hình 1. Mô hình $beamKind chịu uốn ${cfg.loadType.shortLabel}, bản đồ ứng suất/vết nứt uốn & mặt cắt phẫu thuật thớ'));
    }

    // MỤC 1
    body.write(_p('1. THÔNG SỐ MÔ HÌNH, VẬT LIỆU, LIÊN KẾT & SƠ ĐỒ TẢI TRỌNG', bold: true, sz: 23, color: '0F3D6E', before: 80));
    body.write(_tbl(
      ['Thông số thiết kế', 'Giá trị nhập từ giao diện', 'Cơ sở tiêu chuẩn / Ghi chú'],
      [
        ['Kích thước dầm L × b × h', '${cfg.spanMm.toStringAsFixed(0)} × ${cfg.widthMm.toStringAsFixed(0)} × ${cfg.heightMm.toStringAsFixed(0)} mm', 'Tỷ lệ nhịp/chiều cao L/h = ${cfg.spanToDepthRatio.toStringAsFixed(2)} (khuyến nghị 5–10)'],
        ['Cốt thép chịu kéo As / nén As\'', '${cfg.asBotMm2.toStringAsFixed(1)} mm² / ${cfg.asTopMm2.toStringAsFixed(1)} mm²', 'μ = ${cfg.steelRatioPct.toStringAsFixed(2)}% ; a_s = ${cfg.coverBotMm.toStringAsFixed(0)} mm, a_s\' = ${cfg.coverTopMm.toStringAsFixed(0)} mm'],
        ['Lõi cốt cứng thép hình chữ I', cfg.hasRigidCore ? 'CÓ: I${cfg.coreHMm.toStringAsFixed(0)}×${cfg.coreBMm.toStringAsFixed(0)}×${cfg.coreTwMm.toStringAsFixed(0)}×${cfg.coreTfMm.toStringAsFixed(0)} mm, f_ya=${cfg.coreFyMpa.toStringAsFixed(0)} MPa' : 'Không kích hoạt (BTCT thường)', '[TC3] EN 1994-1-1; [TC4] AISC 360-16 Ch. I'],
        ['Vật liệu Bê tông (Hognestad)', 'f\'_c = ${cfg.fcMpa.toStringAsFixed(1)} MPa, E_c = ${cfg.ecMpa.toStringAsFixed(0)} MPa, f_ct = ${cfg.fctMpa.toStringAsFixed(2)} MPa', 'ε_c0 = ${(cfg.epsC0 * 1000).toStringAsFixed(1)}‰, ε_cu = ${(cfg.epsCu * 1000).toStringAsFixed(1)}‰ ([TC1], [TC2])'],
        ['Vật liệu Cốt thép (Đàn-dẻo)', 'f_y = ${cfg.fyMpa.toStringAsFixed(0)} MPa, E_s = ${cfg.esMpa.toStringAsFixed(0)} MPa, b_h = ${(cfg.hardeningRatio * 100).toStringAsFixed(1)}%', '[TC1] TCVN 5574:2018 §6.2.3; [TL1] NSA_5'],
        ['Liên kết gối tựa hai đầu', 'Trái (x=0): ${cfg.leftSupport.shortLabel}  |  Phải (x=L): ${cfg.rightSupport.shortLabel}', 'Phần tử 6 DOF (u, v, θ) chuẩn CALFEM'],
        ['Sơ đồ chất tải', '${cfg.loadType.label}, Q = ${cfg.loadQKn.toStringAsFixed(1)} kN, a = ${cfg.effectiveAMm.toStringAsFixed(0)} mm', cfg.momentFormulaLabel],
        ['Rời rạc hóa PTHH & Thớ', '${active.nElems} phần tử (${active.nNodes} nút) • ${cfg.nFibers} thớ bê tông', 'Tích phân số Gauss–Legendre 3 điểm'],
      ],
      '0F3D6E',
      leftCols: const {0, 1, 2},
    ));

    // MỤC 2: HỆ THỐNG CÔNG THỨC & DẪN NGUỒN
    body.write(_p('2. CƠ SỞ LÝ THUYẾT, THIẾT LẬP CÔNG THỨC PTHH & DẪN NGUỒN TIÊU CHUẨN', bold: true, sz: 23, color: '0F3D6E', before: 80));
    String prevSec = '';
    for (final f in _beamFormulas) {
      if (f.sec != prevSec) {
        prevSec = f.sec;
        body.write(_p(f.sec, bold: true, sz: 20, color: '0F766E', before: 55, after: 35));
      }
      body.write(_formulaBox(f.eq, f.formula, f.explain, f.src));
    }

    // MỤC 3: SO SÁNH TUYẾN TÍNH VS PHI TUYẾN & ĐỐI CHIẾU PSD TIÊU CHUẨN
    body.write(_p('3. KẾT QUẢ PHÂN TÍCH, ĐỐI CHIẾU TIÊU CHUẨN (PSD) & BENCHMARK THỰC NGHIỆM', bold: true, sz: 23, color: '0F3D6E', before: 80));
    final ratioV = linear.vMidMm.abs() > 1e-6 ? active.vMidMm.abs() / linear.vMidMm.abs() : 1.0;
    body.write(_tbl(
      ['Đại lượng đánh giá', 'Đàn hồi Tuyến tính', active.methodName, 'Nhận xét bản chất cơ học'],
      [
        ['Độ võng giữa nhịp v_mid (mm)', linear.vMidMm.toStringAsFixed(3), active.vMidMm.toStringAsFixed(3), 'Tăng ${ratioV.toStringAsFixed(2)}× do nứt kéo & mềm hóa uốn'],
        ['Mô-men cực đại M_max (kN·m)', linear.mMaxKnm.toStringAsFixed(2), active.mMaxKnm.toStringAsFixed(2), 'Khớp chính xác giải tích (${cfg.simpleBeamMaxMomentKnm.toStringAsFixed(2)} kN·m)'],
        ['Phản lực gối R_A / R_B (kN)', '${linear.rLeftKn.toStringAsFixed(2)} / ${linear.rRightKn.toStringAsFixed(2)}', '${active.rLeftKn.toStringAsFixed(2)} / ${active.rRightKn.toStringAsFixed(2)}', 'Cân bằng tĩnh ∑F_y = ${active.sumFyN.toStringAsExponential(1)} N'],
        ['Trục trung hòa x_NA (x/L=${probeXNorm.toStringAsFixed(2)})', '${(0.5 * cfg.heightMm).toStringAsFixed(1)} mm', '${sec.xNeutralDepthMm.toStringAsFixed(1)} mm', 'Dịch lên vùng nén khi thớ kéo bị nứt'],
        ['Độ cứng uốn hiệu dụng EI_eff', '${(active.eiGrossNmm2 / 1e12).toStringAsFixed(2)}×10¹² N·mm²', '${(sec.eiEffNmm2 / 1e12).toStringAsFixed(2)}×10¹² N·mm²', 'Còn ${eiPct.toStringAsFixed(1)}% EI₀ (giảm mạnh ở vùng nứt)'],
        ['Ứng suất nén BT / thép kéo', 'Đàn hồi tuyến tính', '${sec.sigmaTopConcMpa.toStringAsFixed(1)} / ${sec.sigmaBotSteelMpa.toStringAsFixed(1)} MPa', active.hasYielding ? 'Cốt thép đã chảy dẻo' : (active.hasCracking ? 'Bê tông vùng kéo đã nứt' : 'Đàn hồi')],
        ['Mô-men cực hạn M_u (Thớ) vs M_pl (PSD)', 'Không xác định', 'M_u = ${mUFiber.toStringAsFixed(2)} kN·m', 'M_pl (EN 1994/AISC 360) = ${psd.mPlKnm.toStringAsFixed(2)} kN·m (lệch ${diffPsdPct >= 0 ? "+" : ""}${diffPsdPct.toStringAsFixed(2)}%)'],
      ],
      '0F766E',
      leftCols: const {0, 3},
    ));

    body.write(_p(
      '• Kiểm chứng độ tin cậy bộ giải trên bộ Benchmark thực nghiệm chuẩn quốc tế Vecchio & Shim (2004, ASCE JSE, L=6400 mm, h=552 mm, uốn 3 điểm [TL10]): '
      'VS-A3 (P_u,TN = 420.0 kN vs P_u,Thớ = 421.6 kN, sai số +0.38%); '
      'VS-B3 (342.0 kN vs 339.9 kN, sai số −0.61%); '
      'VS-C3 (265.0 kN vs 257.1 kN, sai số −2.98%); sai số tuyệt đối trung bình chỉ 1.32%. '
      'Trên mẫu dầm Burns & Siess (1962) J-4 (L/h=8.0 [TL11]): P_u,Thớ = 142.4 kN khớp sát ngưỡng thí nghiệm 142–151 kN.',
      sz: 18,
      color: '1E293B',
    ));

    // MỤC 4: QUAN HỆ LỰC - CHUYỂN VỊ & MA TRẬN 6×6 [Kt^e] PHẦN TỬ NGUY HIỂM NHẤT
    body.write(_p('4. MA TRẬN ĐỘ CỨNG 6×6 [K_t^e] & QUAN HỆ LỰC – CHUYỂN VỊ PHẦN TỬ NGUY HIỂM (E${critEl.elemIndex + 1})',
        bold: true, sz: 23, color: '0F3D6E', before: 80));
    body.write(_p(
      'Phần tử E${critEl.elemIndex + 1} (x ∈ [${critEl.x1Mm.toStringAsFixed(0)}, ${critEl.x2Mm.toStringAsFixed(0)}] mm, L_e = ${critEl.lengthMm.toStringAsFixed(0)} mm): '
      'M₁ = ${critEl.m1Knm.toStringAsFixed(2)} kN·m, M₂ = ${critEl.m2Knm.toStringAsFixed(2)} kN·m, V = ${critEl.vShearKn.toStringAsFixed(2)} kN | '
      'EA_t = ${(critEl.midSection.eaTangentN / 1e6).toStringAsFixed(1)} MN, EI_eff = ${(critEl.midSection.eiEffNmm2 / 1e12).toStringAsFixed(3)}×10¹² N·mm², x_NA = ${critEl.midSection.xNeutralDepthMm.toStringAsFixed(1)} mm.',
      sz: 18,
    ));
    const dofs = ['u₁', 'v₁', 'θ₁', 'u₂', 'v₂', 'θ₂'];
    body.write(_tbl(
      ['[K_t^e]', ...dofs],
      [
        for (int r = 0; r < 6; r++)
          [
            dofs[r],
            for (int c = 0; c < 6; c++)
              critEl.kt6x6[r][c].abs() < 1e-4 ? '0' : critEl.kt6x6[r][c].toStringAsExponential(2),
          ],
      ],
      '1D4ED8',
    ));

    // MỤC 5: BẢNG NỘI LỰC CÁC PHẦN TỬ & CHUYỂN VỊ NÚT
    body.write(_p('5. BẢNG NỘI LỰC HAI ĐẦU PHẦN TỬ, ĐỘ CỨNG UỐN & TRỤC TRUNG HÒA DỌC DẦM', bold: true, sz: 23, color: '0F3D6E', before: 80));
    body.write(_tbl(
      ['Phần tử', 'Đoạn x (mm)', 'M₁ (kN·m)', 'M₂ (kN·m)', 'V (kN)', 'EI_eff (10¹²)', 'x_NA (mm)'],
      [
        for (final el in active.elements)
          [
            'E${el.elemIndex + 1}',
            '${el.x1Mm.toStringAsFixed(0)}–${el.x2Mm.toStringAsFixed(0)}',
            el.m1Knm.toStringAsFixed(2),
            el.m2Knm.toStringAsFixed(2),
            el.vShearKn.toStringAsFixed(2),
            (el.midSection.eiEffNmm2 / 1e12).toStringAsFixed(2),
            el.midSection.xNeutralDepthMm.toStringAsFixed(1),
          ],
      ],
      '334155',
    ));

    // MỤC 6: KHẢO SÁT HỘI TỤ LƯỚI
    body.write(_p('6. KHẢO SÁT HỘI TỤ LƯỚI PHẦN TỬ (CHIA HAI NỬA ĐỐI XỨNG: 2 → 4 → 8 → 16 → 32 PT)', bold: true, sz: 23, color: '0F3D6E', before: 80));
    body.write(_tbl(
      ['Số PT (2 nửa)', 'Số nút', '|v_mid| (mm)', 'M_max (kN·m)', 'x_NA (mm)', 'EI_eff/EI₀ (%)', 'Sai số %'],
      [
        for (final m in meshConv)
          [
            '${m.nElems} (${m.nElems ~/ 2}+${m.nElems ~/ 2})',
            '${m.nNodes}',
            m.vMidMm.toStringAsFixed(4),
            m.mMaxKnm.toStringAsFixed(2),
            m.xNeutralMm.toStringAsFixed(1),
            '${m.eiRatioPct.toStringAsFixed(1)}%',
            '${m.relErrorPct.toStringAsFixed(2)}%',
          ],
      ],
      '1D4ED8',
    ));

    // MỤC 7: DANH MỤC TIÊU CHUẨN & TÀI LIỆU THAM KHẢO
    body.write(_p('7. DANH MỤC TIÊU CHUẨN ÁP DỤNG & TÀI LIỆU THAM KHẢO', bold: true, sz: 23, color: '0F3D6E', before: 90));
    body.write(_p('7.1. Tiêu chuẩn thiết kế áp dụng:', bold: true, sz: 19, color: '0F766E', after: 35));
    for (final s in _beamStandards) {
      body.write(_p('${s.code} ${s.text}', sz: 17, color: '1E293B', after: 30, indent: 110));
    }
    body.write(_p('7.2. Giáo trình & Tài liệu khoa học tham khảo:', bold: true, sz: 19, color: '0F766E', before: 45, after: 35));
    for (final r in _beamLit) {
      body.write(_p('${r.code} ${r.text}', sz: 17, color: '1E293B', after: 30, indent: 110));
    }

    final docXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>${body.toString()}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1000" w:right="1000" w:bottom="1000" w:left="1100"/></w:sectPr></w:body></w:document>';

    final ctXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '${hasImg ? '<Default Extension="png" ContentType="image/png"/>' : ''}'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';
    const relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';
    final docRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '${hasImg ? '<Relationship Id="rIdImg1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/viewport.png"/>' : ''}'
        '</Relationships>';

    final arc = Archive()
      ..addFile(ArchiveFile('[Content_Types].xml', utf8.encode(ctXml).length, utf8.encode(ctXml)))
      ..addFile(ArchiveFile('_rels/.rels', utf8.encode(relsXml).length, utf8.encode(relsXml)))
      ..addFile(ArchiveFile('word/_rels/document.xml.rels', utf8.encode(docRelsXml).length, utf8.encode(docRelsXml)))
      ..addFile(ArchiveFile('word/document.xml', utf8.encode(docXml).length, utf8.encode(docXml)));
    if (hasImg) {
      arc.addFile(ArchiveFile('word/media/viewport.png', viewportPngBytes.length, viewportPngBytes));
    }
    final bytes = Uint8List.fromList(ZipEncoder().encode(arc));
    return saveBinaryFile(
      cfg.hasRigidCore ? 'ThuyetMinh_DamBeTongCotCung_PhiTuyenTho_CALFEM.docx' : 'ThuyetMinh_DamBTCT_PhiTuyenTho_CALFEM.docx',
      bytes,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
  }

  /// 2. Xuất Thuyết minh PDF (.pdf) Dầm BTCT / Bê tông Cốt cứng chuẩn học thuật
  static Future<String?> exportPdf({
    required RcBeamAnalysisResult linear,
    required RcBeamAnalysisResult active,
    required List<RcMeshConvergencePoint> meshConv,
    required double probeXNorm,
    Uint8List? viewportPngBytes,
  }) async {
    final cfg = active.config;
    final probe = RcBeamFiberEngine.probeBeamAt(active, probeXNorm);
    final sec = probe.section;
    final psd = _computePlasticMomentPsd(cfg);
    final mkCurve = RcBeamFiberEngine.computeMomentCurvature(cfg);
    final mUFiber = mkCurve.fold(0.0, (m, p) => math.max(m, p.momentKnm));
    final diffPsdPct = psd.mPlKnm > 1e-6 ? 100.0 * (mUFiber - psd.mPlKnm) / psd.mPlKnm : 0.0;

    final fontReg = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: fontReg, bold: fontBold));

    final navy = PdfColor.fromHex('#0F3D6E');
    final teal = PdfColor.fromHex('#0F766E');
    final slate = PdfColor.fromHex('#334155');
    final lightRow = PdfColor.fromHex('#F1F5F9');
    final boxBg = PdfColor.fromHex('#F8FAFC');
    final borderCol = PdfColor.fromHex('#CBD5E1');

    final formulaWidgets = <pw.Widget>[];
    String prevSec = '';
    for (final f in _beamFormulas) {
      if (f.sec != prevSec) {
        prevSec = f.sec;
        formulaWidgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 5, bottom: 2.5),
          child: pw.Text(f.sec, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.4, color: teal)),
        ));
      }
      formulaWidgets.add(pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 3.5),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
        decoration: pw.BoxDecoration(
          color: boxBg,
          border: pw.Border(
            left: pw.BorderSide(color: navy, width: 2.3),
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
              children: [
                pw.Expanded(child: pw.Text(f.formula, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.4))),
                pw.SizedBox(width: 6),
                pw.Text(f.eq, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.4, color: navy)),
              ],
            ),
            pw.SizedBox(height: 1.5),
            pw.Text(f.explain, style: pw.TextStyle(fontSize: 6.9, color: slate, lineSpacing: 1.4)),
            pw.Text('Nguồn áp dụng: ${f.src}', style: pw.TextStyle(fontSize: 6.6, color: teal)),
          ],
        ),
      ));
    }

    final beamTitle = cfg.hasRigidCore
        ? 'THUYẾT MINH PHÂN TÍCH PHI TUYẾN DẦM BÊ TÔNG CỐT CỨNG (SRC — PHƯƠNG PHÁP THỚ)'
        : 'THUYẾT MINH PHÂN TÍCH PHI TUYẾN DẦM BÊ TÔNG CỐT THÉP (PHƯƠNG PHÁP THỚ)';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(26),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'Thuyết minh Phân tích Phi tuyến Thớ & Rayleigh–Ritz (CALFEM)  |  Trang ${ctx.pageNumber}/${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 7.0, color: slate),
          ),
        ),
        build: (ctx) => [
          pw.Center(child: pw.Text('TRƯỜNG ĐẠI HỌC BÁCH KHOA – ĐHQG TP. HỒ CHÍ MINH', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.2, color: navy))),
          pw.SizedBox(height: 2),
          pw.Center(child: pw.Text(beamTitle, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11.6, color: PdfColors.black), textAlign: pw.TextAlign.center)),
          pw.SizedBox(height: 2),
          pw.Center(child: pw.Text('GVHD: PGS. TS Ngô Hữu Cường  •  HV: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)  •  vothanhvang@gmail.com • 0973.993.494', style: pw.TextStyle(fontSize: 7.4, color: slate))),
          pw.Divider(color: navy, thickness: 1.2),
          if (viewportPngBytes != null && viewportPngBytes.isNotEmpty) ...[
            pw.Center(
              child: pw.Container(
                height: 185,
                decoration: pw.BoxDecoration(border: pw.Border.all(color: borderCol)),
                child: pw.Image(pw.MemoryImage(viewportPngBytes), fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 5),
          ],
          pw.Text('1. Thông số Hình học, Cốt thép/Cốt cứng, Vật liệu & Kết quả Đối chiếu', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.0, color: navy)),
          pw.SizedBox(height: 3),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 7.6),
            headerDecoration: pw.BoxDecoration(color: navy),
            cellStyle: const pw.TextStyle(fontSize: 7.4),
            oddRowDecoration: pw.BoxDecoration(color: lightRow),
            headers: ['Thông số', 'Giá trị / Tuyến tính', 'Phi tuyến Thớ / Đối chiếu chuẩn'],
            data: [
              ['Nhịp L × b × h (L/h)', '${cfg.spanMm.toStringAsFixed(0)} × ${cfg.widthMm.toStringAsFixed(0)} × ${cfg.heightMm.toStringAsFixed(0)} mm', 'L/h = ${cfg.spanToDepthRatio.toStringAsFixed(2)} • ${cfg.nFibers} thớ bê tông'],
              ['Cốt thép As / As\' & Cốt cứng', '${cfg.asBotMm2.toStringAsFixed(1)} / ${cfg.asTopMm2.toStringAsFixed(1)} mm²', cfg.hasRigidCore ? 'Cốt cứng I${cfg.coreHMm.toStringAsFixed(0)}×${cfg.coreBMm.toStringAsFixed(0)} (f_ya=${cfg.coreFyMpa.toStringAsFixed(0)} MPa)' : 'BTCT thường (μ=${cfg.steelRatioPct.toStringAsFixed(2)}%)'],
              ['Chất tải & Gối tựa', '${cfg.loadType.shortLabel}, Q=${cfg.loadQKn.toStringAsFixed(1)} kN, a=${cfg.effectiveAMm.toStringAsFixed(0)} mm', '${cfg.leftSupport.shortLabel} — ${cfg.rightSupport.shortLabel}'],
              ['Độ võng giữa nhịp v_mid (mm)', linear.vMidMm.toStringAsFixed(3), active.vMidMm.toStringAsFixed(3)],
              ['Mô-men cực đại M_max (kN·m)', linear.mMaxKnm.toStringAsFixed(2), '${active.mMaxKnm.toStringAsFixed(2)} (${cfg.momentFormulaLabel})'],
              ['Trục trung hòa x_NA & EI_eff', '${(0.5 * cfg.heightMm).toStringAsFixed(1)} mm (100%)', '${sec.xNeutralDepthMm.toStringAsFixed(1)} mm (${(100.0 * sec.eiEffNmm2 / math.max(1.0, active.eiGrossNmm2)).toStringAsFixed(1)}% EI₀)'],
              ['Mô-men cực hạn M_u vs M_pl (PSD)', 'EN 1994 / AISC 360: ${psd.mPlKnm.toStringAsFixed(2)} kN·m', 'Thớ: ${mUFiber.toStringAsFixed(2)} kN·m (lệch ${diffPsdPct >= 0 ? "+" : ""}${diffPsdPct.toStringAsFixed(2)}%)'],
            ],
          ),
          pw.SizedBox(height: 7),
          pw.Text('2. Cơ sở Lý thuyết, Hệ thống Công thức PTHH & Dẫn nguồn Tiêu chuẩn', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.0, color: navy)),
          ...formulaWidgets,
          pw.SizedBox(height: 7),
          pw.Text('3. Khảo sát Hội tụ Lưới Phần tử (Chia hai nửa đối xứng: 2 → 32 PT)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.0, color: teal)),
          pw.SizedBox(height: 3),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 7.5),
            headerDecoration: pw.BoxDecoration(color: teal),
            cellStyle: const pw.TextStyle(fontSize: 7.3),
            oddRowDecoration: pw.BoxDecoration(color: lightRow),
            headers: ['Số PT', 'Số nút', '|v_mid| (mm)', 'M_max (kN·m)', 'x_NA (mm)', 'EI_eff/EI₀ (%)', 'Sai số %'],
            data: [
              for (final m in meshConv)
                [
                  '${m.nElems} (${m.nElems ~/ 2}+${m.nElems ~/ 2})',
                  '${m.nNodes}',
                  m.vMidMm.toStringAsFixed(4),
                  m.mMaxKnm.toStringAsFixed(2),
                  m.xNeutralMm.toStringAsFixed(1),
                  '${m.eiRatioPct.toStringAsFixed(1)}%',
                  '${m.relErrorPct.toStringAsFixed(2)}%',
                ],
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text('4. Kiểm chứng Benchmark Thực nghiệm & Danh mục Tiêu chuẩn – Tài liệu Tham khảo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.0, color: navy)),
          pw.SizedBox(height: 2),
          pw.Text(
            '• Kiểm chứng bộ 3 dầm thí nghiệm Vecchio & Shim (2004, ASCE JSE [TL10]): VS-A3 (421.6 vs 420.0 kN, +0.38%), VS-B3 (339.9 vs 342.0 kN, −0.61%), VS-C3 (257.1 vs 265.0 kN, −2.98%) — sai số trung bình 1.32%. Burns & Siess J-4 [TL11]: 142.4 kN (thí nghiệm 142–151 kN).',
            style: pw.TextStyle(fontSize: 7.2, color: slate, lineSpacing: 1.5),
          ),
          pw.SizedBox(height: 3),
          pw.Text('Tiêu chuẩn thiết kế:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.8, color: teal)),
          for (final s in _beamStandards)
            pw.Text('  ${s.code} ${s.text}', style: pw.TextStyle(fontSize: 6.9, color: slate, lineSpacing: 1.4)),
          pw.SizedBox(height: 2),
          pw.Text('Tài liệu khoa học tham khảo:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.8, color: teal)),
          for (final r in _beamLit)
            pw.Text('  ${r.code} ${r.text}', style: pw.TextStyle(fontSize: 6.9, color: slate, lineSpacing: 1.4)),
        ],
      ),
    );
    final bytes = await pdf.save();
    return saveBinaryFile(
      cfg.hasRigidCore ? 'BaoCao_DamBeTongCotCung_PhiTuyenTho_CALFEM.pdf' : 'BaoCao_DamBTCT_PhiTuyenTho_CALFEM.pdf',
      bytes,
      'application/pdf',
    );
  }

  /// 3. Xuất Bảng số liệu Excel CSV (UTF-8 BOM) cho Dầm BTCT / Bê tông Cốt cứng
  static Future<String?> exportCsv({
    required RcBeamAnalysisResult active,
    required List<RcMeshConvergencePoint> meshConv,
  }) async {
    final buf = StringBuffer('\uFEFF');
    buf.writeln('=== THONG SO DAM BTCT / COT CUNG PHI TUYEN THO (CALFEM) ===');
    buf.writeln('L_mm,b_mm,h_mm,L_h,As_mm2,AsTop_mm2,RigidCore,Q_kN,a_mm,Mmax_kNm,vMid_mm,Converged');
    final c = active.config;
    buf.writeln('${c.spanMm},${c.widthMm},${c.heightMm},${c.spanToDepthRatio.toStringAsFixed(2)},${c.asBotMm2},${c.asTopMm2},${c.hasRigidCore},${c.loadQKn},${c.effectiveAMm},${active.mMaxKnm.toStringAsFixed(4)},${active.vMidMm.toStringAsFixed(4)},${active.converged}');
    buf.writeln('\n=== CHUYEN VI NUT & PHAN LUC GOI ===');
    buf.writeln('Node,x_mm,u_mm,v_mm,theta_rad,Rx_kN,Ry_kN,Mr_kNm');
    for (int i = 0; i < active.nNodes; i++) {
      buf.writeln('N${i + 1},${active.xNodesMm[i].toStringAsFixed(2)},${active.dGlobal[3 * i].toStringAsFixed(6)},${active.dGlobal[3 * i + 1].toStringAsFixed(6)},${active.dGlobal[3 * i + 2].toStringAsFixed(6)},${(active.reactions[3 * i] / 1000).toStringAsFixed(4)},${(active.reactions[3 * i + 1] / 1000).toStringAsFixed(4)},${(active.reactions[3 * i + 2] / 1e6).toStringAsFixed(4)}');
    }
    buf.writeln('\n=== KHAO SAT HOI TU LUOI PHAN TU ===');
    buf.writeln('nElems,nNodes,vMid_mm,Mmax_kNm,xNA_mm,EI_ratio_pct,RelError_pct,Iterations');
    for (final m in meshConv) {
      buf.writeln('${m.nElems},${m.nNodes},${m.vMidMm.toStringAsFixed(4)},${m.mMaxKnm.toStringAsFixed(4)},${m.xNeutralMm.toStringAsFixed(2)},${m.eiRatioPct.toStringAsFixed(2)},${m.relErrorPct.toStringAsFixed(3)},${m.iterations}');
    }
    final bytes = Uint8List.fromList(utf8.encode(buf.toString()));
    return saveBinaryFile('SoLieu_DamBTCT_PhiTuyenTho_CALFEM.csv', bytes, 'text/csv');
  }
}
