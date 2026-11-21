// ============================================================================
// MÔ-ĐUN XUẤT THUYẾT MINH WORD (.DOCX), PDF (.PDF), CSV EXCEL, ẢNH PNG & JSON
// ============================================================================
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
    int sizeHalfPt = 23,
    String? colorHex,
    String align = 'left',
  }) {
    final colorTag = colorHex != null ? '<w:color w:val="$colorHex"/>' : '';
    final boldTag = bold ? '<w:b/>' : '';
    return '<w:p>'
        '<w:pPr><w:jc w:val="$align"/><w:spacing w:after="100"/></w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>'
        '$boldTag$colorTag<w:sz w:val="$sizeHalfPt"/></w:rPr>'
        '<w:t xml:space="preserve">${_xmlEscape(text)}</w:t></w:r></w:p>';
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
        '${_docxParagraph(caption, sizeHalfPt: 18, colorHex: "475569", align: "center")}';
  }

  static String _docxTable(List<String> headers, List<List<String>> rows, String headerFill) {
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
          '${_docxParagraph(h, bold: true, sizeHalfPt: 18, colorHex: "FFFFFF", align: "center")}</w:tc>');
    }
    buf.write('</w:tr>');

    for (int r = 0; r < rows.length; r++) {
      final fill = r.isOdd ? 'F1F5F9' : 'FFFFFF';
      buf.write('<w:tr>');
      for (int c = 0; c < rows[r].length; c++) {
        buf.write('<w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="$fill"/></w:tcPr>'
            '${_docxParagraph(rows[r][c], sizeHalfPt: 17, align: c == 0 ? "left" : "right")}</w:tc>');
      }
      buf.write('</w:tr>');
    }
    buf.write('</w:tbl>');
    return buf.toString();
  }

  /// Xuất tệp Microsoft Word (.docx) chuẩn OOXML có ảnh 3D/2D nhúng, kiểm tra bền U% & mất ổn định α_cr
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
        bold: true, sizeHalfPt: 22, colorHex: '0F3D6E', align: 'center'));
    body.write(_docxParagraph('KHOA KỸ THUẬT XÂY DỰNG – BỘ MÔN CÔNG TRÌNH',
        bold: true, sizeHalfPt: 20, colorHex: '334155', align: 'center'));
    body.write(_docxParagraph('THUYẾT MINH KẾT QUẢ PHÂN TÍCH PHI TUYẾN HỆ DÀN (CALFEM)',
        bold: true, sizeHalfPt: 28, colorHex: '0F172A', align: 'center'));
    body.write(_docxParagraph(
        'Giảng viên hướng dẫn: PGS. TS Ngô Hữu Cường  |  Học viên thực hiện: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)  |  Liên hệ: vothanhvang@gmail.com  |  Xuất lúc: $ts',
        sizeHalfPt: 17,
        colorHex: '475569',
        align: 'center'));

    if (hasImage) {
      body.write(_docxImageParagraph(
        pngWidthPx ?? 1200,
        pngHeightPx ?? 740,
        'Hình 1: Mô hình kết cấu & bản đồ màu trường ứng suất/biến dạng (λ = ${loadFactor.toStringAsFixed(2)})',
      ));
    }

    body.write(_docxParagraph('1. THÔNG SỐ ĐẦU VÀO & PHƯƠNG PHÁP PHÂN TÍCH',
        bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    body.write(_docxParagraph('• Mô hình: ${model.name} — ${model.description}'));
    final secSummary = [
      for (int e = 0; e < model.nElems; e++)
        'T${e + 1}: ${model.sectionDimsForElem(e).formatSpec(model.sectionShapeForElem(e))} (L=${model.initialLength(e).toStringAsFixed(0)} mm)',
    ].join(' ; ');
    body.write(_docxParagraph('• Tiết diện, góc xoay & chiều dài các thanh: $secSummary.'));
    final supSummary = [
      for (int i = 0; i < model.nodeSupports.length; i++) 'N${i + 1}: ${model.nodeSupports[i].shortLabel}',
    ].join(' | ');
    body.write(_docxParagraph(
        '• Liên kết gối tựa các nút: $supSummary${model.hasAnySpring ? " (k = ${model.springStiffnessKnMm.toStringAsFixed(1)} kN/mm)" : ""}'));
    body.write(_docxParagraph(
        '• Hệ số tải trọng: λ = ${loadFactor.toStringAsFixed(2)}  |  Vật liệu: E = ${(model.E / 1000).toStringAsFixed(0)} GPa, fy = ${model.fyRef.toStringAsFixed(0)} MPa${model.materialNonlinear ? " (Phi tuyến đàn-dẻo GMNIA, Et/E = ${(model.hardeningRatio * 100).toStringAsFixed(1)}%)" : " (Đàn hồi tuyến tính)"}'));
    body.write(_docxParagraph(
        '• Thuật toán phi tuyến: ${nonlinear.methodName} (Hội tụ: ${nonlinear.converged ? "ĐẠT" : "KHÔNG ĐẠT"}, ${nonlinear.totalIterations} vòng lặp, lõi: ${nonlinear.engineSource}).'));
    if (buckling != null && buckling.hasBucklingMode) {
      body.write(_docxParagraph(
        '• Phân tích mất ổn định trị riêng đàn hồi det(K_e + α_cr·K_g) = 0: Hệ số tới hạn α_cr = ${buckling.alphaCr.toStringAsFixed(2)} (P_cr = ${buckling.pCrKn.toStringAsFixed(1)} kN).',
      ));
    }

    body.write(_docxParagraph('2. TÓM TẮT 7 CÔNG THỨC TOÁN HỌC ÁP DỤNG',
        bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    body.write(_docxParagraph('(1) Định lý Py-ta-go: l = √[(Δx₀ + Δuₓ)² + (Δy₀ + Δuᵧ)²].'));
    body.write(_docxParagraph('(2) Hiệu hai bình phương khử sai số làm tròn: l − L₀ = (l² − L₀²) / (l + L₀).'));
    body.write(_docxParagraph('(3) Lượng giác & Cosin chỉ phương: c = cos θ = (x₂ − x₁)/L ; s = sin θ = (y₂ − y₁)/L.'));
    body.write(_docxParagraph('(4) Khai triển nhị thức Newton: (1 + d)^(1/2) ≈ 1 + d/2 → biến dạng Green-Lagrange.'));
    body.write(_docxParagraph('(5) Đạo hàm, biến phân & tích phân xác định: δ(f²) = 2f·δf ; ∫₀ᴸ (1/L²) dx = 1/L.'));
    body.write(_docxParagraph('(6) Phương pháp tiếp tuyến Newton-Raphson: u^(k+1) = u^(k) + [K_t]⁻¹ · {P − f_int(u^(k))}.'));
    body.write(_docxParagraph('(7) Ổn định tổng thể TCVN 5575 / EN 1993-1-1 & Trị riêng: U = |N|/(χ·A·f_y) ; det(K_e + α_cr·K_g) = 0.'));

    body.write(_docxParagraph('3. BẢNG SO SÁNH CHUYỂN VỊ NÚT & PHẢN LỰC GỐI (TUYẾN TÍNH VS PHI TUYẾN)',
        bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    final nodeRows = <List<String>>[];
    for (int i = 0; i < model.nNodes; i++) {
      nodeRows.add([
        'Nút ${i + 1}',
        linear.uMm[2 * i].toStringAsFixed(5),
        linear.uMm[2 * i + 1].toStringAsFixed(5),
        nonlinear.uMm[2 * i].toStringAsFixed(5),
        nonlinear.uMm[2 * i + 1].toStringAsFixed(5),
        (nonlinear.reactionsN[2 * i] / 1000.0).toStringAsFixed(4),
        (nonlinear.reactionsN[2 * i + 1] / 1000.0).toStringAsFixed(4),
      ]);
    }
    body.write(_docxTable(
      ['Nút', 'ux TT (mm)', 'uy TT (mm)', 'ux PT (mm)', 'uy PT (mm)', 'Rx PT (kN)', 'Ry PT (kN)'],
      nodeRows,
      '1B365D',
    ));

    body.write(_docxParagraph('4. BẢNG NỘI LỰC, ỨNG SUẤT & KIỂM TRA BỀN – ỔN ĐỊNH THANH (TCVN 5575 / EC3)',
        bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    final memRows = <List<String>>[];
    for (int e = 0; e < model.nElems; e++) {
      final shE = model.sectionShapeForElem(e);
      final chk = e < checks.length ? checks[e] : null;
      memRows.add([
        '${e + 1} (${model.memberLabels[e]})',
        model.sectionDimsForElem(e).formatSpec(shE),
        model.initialLength(e).toStringAsFixed(0),
        (nonlinear.nForcesN[e] / 1000.0).toStringAsFixed(3),
        nonlinear.stressMpa[e].toStringAsFixed(2),
        chk != null ? chk.slenderness.toStringAsFixed(1) : '-',
        chk != null ? '${chk.utilizationPct.toStringAsFixed(1)}%' : '-',
        chk != null ? (chk.passed ? 'ĐẠT' : 'VƯỢT') : '-',
      ]);
    }
    body.write(_docxTable(
      ['Thanh', 'Tiết diện', 'L₀ (mm)', 'N PT (kN)', 'σ (MPa)', 'λ mảnh', 'U (%)', 'Kết luận'],
      memRows,
      '0F766E',
    ));

    final probeShape = model.sectionShapeForElem(probe.elemIndex);
    body.write(_docxParagraph('5. KẾT QUẢ KHẢO SÁT & PHẪU THUẬT MẶT CẮT TẠI ĐIỂM ĐANG CHỌN',
        bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    body.write(_docxParagraph(
      '• Vị trí phẫu thuật: Thanh ${probe.memberLabel} (L₀ = ${probe.l0Mm.toStringAsFixed(1)} mm) tại ξ = ${probe.xi.toStringAsFixed(2)} (s = ${probe.sMm.toStringAsFixed(1)} mm), thớ (η = ${probe.etaNorm.toStringAsFixed(2)}, ζ = ${probe.zetaNorm.toStringAsFixed(2)}), tiết diện ${probeShape.label} (${probe.sectionDims.formatSpec(probeShape)}).',
    ));
    body.write(_docxParagraph(
      '• Ứng suất pháp σ_xx = ${probe.sigmaXxMpa.toStringAsFixed(4)} MPa (dọc trục ${probe.sigmaAxialMpa.toStringAsFixed(4)} + uốn P-δ ${probe.sigmaBendingMpa.toStringAsFixed(4)}) | von Mises = ${probe.sigmaVonMisesMpa.toStringAsFixed(4)} MPa | τ_max = ${probe.tauMaxMohrMpa.toStringAsFixed(4)} MPa.',
    ));
    body.write(_docxParagraph(
      '• Biến dạng dọc ε_xx = ${probe.epsXxMicro.toStringAsFixed(2)} με | Co/nở ngang Poisson = ${probe.epsPoissonMicro.toStringAsFixed(2)} με | Góc xoay vật rắn Δθ = ${probe.rotationDeg.toStringAsFixed(5)}°.',
    ));

    body.write(_docxParagraph('6. KIỂM CHỨNG CÂN BẰNG CẤU HÌNH BIẾN DẠNG & NĂNG LƯỢNG',
        bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    body.write(_docxParagraph(
      '• Kiểm tra cân bằng toàn hệ: ∑Fx = ${nonlinear.sumFxN.toStringAsExponential(3)} N | ∑Fy = ${nonlinear.sumFyN.toStringAsExponential(3)} N | ∑M_biến_dạng = ${nonlinear.sumMNmm.toStringAsExponential(3)} N·mm | Phần dư tự do max = ${nonlinear.maxFreeResidualN.toStringAsExponential(3)} N.',
    ));
    body.write(_docxParagraph(
      '• Năng lượng biến dạng tổng: Tuyến tính U_TT = ${(linear.totalEnergyNmm / 1000.0).toStringAsFixed(6)} J  |  Phi tuyến U_PT = ${(nonlinear.totalEnergyNmm / 1000.0).toStringAsFixed(6)} J.',
    ));

    if (connectionReports != null && connectionReports.isNotEmpty) {
      final firstP = connectionReports.first.params;
      body.write(_docxParagraph('7. TÍNH TOÁN & KIỂM TRA LIÊN KẾT CÁC NÚT (TCVN 5575 / EN 1993-1-8)',
          bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
      body.write(_docxParagraph(
        '• Cấu tạo gia công: ${firstP.detailType.label} | Bản mã PL${firstP.gussetThicknessMm.toStringAsFixed(0)} thép ${firstP.steelGrade.code} (fy=${firstP.steelGrade.fyMpa.toStringAsFixed(0)} MPa).',
      ));
      final connRows = <List<String>>[];
      for (final rep in connectionReports) {
        connRows.add([
          'Nút ${rep.nodeIndex + 1} (${rep.supportType.shortLabel})',
          '${rep.gussetWidthMm.toStringAsFixed(0)}×${rep.gussetHeightMm.toStringAsFixed(0)}×${rep.params.gussetThicknessMm.toStringAsFixed(0)}',
          '${rep.maxGussetSigmaMpa.toStringAsFixed(1)} MPa',
          '${rep.maxUtilizationPct.toStringAsFixed(1)}%',
          rep.allPassed ? 'ĐẠT' : 'KHÔNG ĐẠT',
        ]);
      }
      body.write(_docxTable(
        ['Nút & Liên kết', 'Bản mã (mm)', 'σ_eq,max', 'Tỷ lệ max', 'Kết luận'],
        connRows,
        '0F766E',
      ));
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

  /// Xuất tệp Báo cáo PDF (.pdf) nhúng font Unicode tiếng Việt + ảnh 3D/2D + kiểm tra bền U% & Buckling
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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text('TRƯỜNG ĐẠI HỌC BÁCH KHOA – ĐHQG TP. HỒ CHÍ MINH',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: navy)),
                pw.SizedBox(height: 3),
                pw.Text('BÁO CÁO PHÂN TÍCH PHI TUYẾN HỆ DÀN (CALFEM)',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13.5, color: PdfColors.black),
                    textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 2),
                pw.Text(
                    'Giảng viên hướng dẫn: PGS. TS Ngô Hữu Cường | Học viên: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624) | Liên hệ: vothanhvang@gmail.com | Xuất: $ts',
                    style: pw.TextStyle(fontSize: 7.4, color: slate),
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
                  border: pw.Border.all(color: PdfColor.fromHex('#CBD5E1'), width: 0.8),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                padding: const pw.EdgeInsets.all(2),
                child: pw.Image(
                  pw.MemoryImage(viewportPngBytes),
                  height: 195,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'Hình 1: Mô hình kết cấu 3D/2D & bản đồ màu trường ứng suất/biến dạng (λ = ${loadFactor.toStringAsFixed(2)})',
                style: pw.TextStyle(fontSize: 7.5, color: slate),
              ),
            ),
          ],
          pw.SizedBox(height: 6),
          pw.Text('1. Thông số đầu vào, thuật toán & phân tích mất ổn định trị riêng',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: navy)),
          pw.SizedBox(height: 3),
          pw.Text(
            '• Mô hình: ${model.name} — ${model.description}\n'
            '• Tiết diện & góc xoay thanh: ${[for (int e = 0; e < model.nElems; e++) "T${e + 1}: ${model.sectionDimsForElem(e).formatSpec(model.sectionShapeForElem(e))} (L=${model.initialLength(e).toStringAsFixed(0)} mm)"].join(" | ")}\n'
            '• Liên kết nút: ${[for (int i = 0; i < model.nodeSupports.length; i++) "N${i + 1}: ${model.nodeSupports[i].shortLabel}"].join(" | ")}${model.hasAnySpring ? " (k = ${model.springStiffnessKnMm.toStringAsFixed(1)} kN/mm)" : ""}\n'
            '• Hệ số tải λ = ${loadFactor.toStringAsFixed(2)} | Phương pháp: ${nonlinear.methodName} | Vật liệu: fy=${model.fyRef.toStringAsFixed(0)} MPa${model.materialNonlinear ? " (GMNIA đàn-dẻo)" : " (Đàn hồi)"}\n'
            '• Lõi giải: ${nonlinear.engineSource} | Hội tụ: ${nonlinear.converged ? "ĐẠT" : "KHÔNG ĐẠT"} (${nonlinear.totalIterations} vòng lặp)'
            '${(buckling != null && buckling.hasBucklingMode) ? " | Trị riêng mất ổn định α_cr = ${buckling.alphaCr.toStringAsFixed(2)} (P_cr = ${buckling.pCrKn.toStringAsFixed(1)} kN)." : "."}',
            style: const pw.TextStyle(fontSize: 8.2, lineSpacing: 2.2),
          ),
          pw.SizedBox(height: 7),
          pw.Text('2. Bảng chuyển vị nút & phản lực gối (Tuyến tính vs Phi tuyến)',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: navy)),
          pw.SizedBox(height: 3),
          pw.TableHelper.fromTextArray(
            headerDecoration: pw.BoxDecoration(color: navy),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 7.6),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            oddRowDecoration: pw.BoxDecoration(color: lightRow),
            headers: ['Nút', 'ux TT (mm)', 'uy TT (mm)', 'ux PT (mm)', 'uy PT (mm)', 'Rx PT (kN)', 'Ry PT (kN)'],
            data: [
              for (int i = 0; i < model.nNodes; i++)
                [
                  'Nút ${i + 1}',
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
          pw.Text('3. Bảng nội lực, ứng suất & kiểm tra bền – ổn định thanh (TCVN 5575 / EN 1993-1-1)',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: teal)),
          pw.SizedBox(height: 3),
          pw.TableHelper.fromTextArray(
            headerDecoration: pw.BoxDecoration(color: teal),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 7.1),
            cellStyle: const pw.TextStyle(fontSize: 7.0),
            oddRowDecoration: pw.BoxDecoration(color: lightRow),
            headers: ['Thanh', 'Tiết diện', 'L₀ (mm)', 'N PT (kN)', 'σ (MPa)', 'λ mảnh', 'U (%)', 'Trạng thái'],
            data: [
              for (int e = 0; e < model.nElems; e++)
                [
                  'T${e + 1} (${model.memberLabels[e]})',
                  model.sectionDimsForElem(e).formatSpec(model.sectionShapeForElem(e)),
                  model.initialLength(e).toStringAsFixed(0),
                  (nonlinear.nForcesN[e] / 1000).toStringAsFixed(3),
                  nonlinear.stressMpa[e].toStringAsFixed(2),
                  e < checks.length ? checks[e].slenderness.toStringAsFixed(1) : '-',
                  e < checks.length ? '${checks[e].utilizationPct.toStringAsFixed(1)}%' : '-',
                  e < checks.length ? (checks[e].passed ? 'ĐẠT' : 'VƯỢT') : '-',
                ],
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text('4. Khảo sát phẫu thuật mặt cắt & kiểm chứng cân bằng',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: navy)),
          pw.SizedBox(height: 3),
          pw.Text(
            '• Thanh ${probe.memberLabel} (L₀=${probe.l0Mm.toStringAsFixed(1)} mm) tại ξ = ${probe.xi.toStringAsFixed(2)} (s = ${probe.sMm.toStringAsFixed(1)} mm), thớ (η=${probe.etaNorm.toStringAsFixed(2)}, ζ=${probe.zetaNorm.toStringAsFixed(2)}), tiết diện ${model.sectionShapeForElem(probe.elemIndex).label} (${probe.sectionDims.formatSpec(model.sectionShapeForElem(probe.elemIndex))}):\n'
            '  - σ_xx = ${probe.sigmaXxMpa.toStringAsFixed(4)} MPa | von Mises = ${probe.sigmaVonMisesMpa.toStringAsFixed(4)} MPa | τ_max = ${probe.tauMaxMohrMpa.toStringAsFixed(4)} MPa | ε_xx = ${probe.epsXxMicro.toStringAsFixed(2)} με.\n'
            '• Cân bằng cấu hình biến dạng: ∑Fx = ${nonlinear.sumFxN.toStringAsExponential(2)} N, ∑Fy = ${nonlinear.sumFyN.toStringAsExponential(2)} N, ∑M = ${nonlinear.sumMNmm.toStringAsExponential(2)} N·mm.\n'
            '• Năng lượng biến dạng: U_TT = ${(linear.totalEnergyNmm / 1000).toStringAsFixed(6)} J | U_PT = ${(nonlinear.totalEnergyNmm / 1000).toStringAsFixed(6)} J.',
            style: const pw.TextStyle(fontSize: 8.3, lineSpacing: 2.2),
          ),
          if (connectionReports != null && connectionReports.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('5. Tính toán & kiểm tra liên kết các nút (TCVN 5575 / EN 1993-1-8)',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: navy)),
            pw.SizedBox(height: 3),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.8, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: teal),
              cellStyle: const pw.TextStyle(fontSize: 7.6),
              oddRowDecoration: pw.BoxDecoration(color: lightRow),
              headers: ['Nút & Liên kết', 'Bản mã (mm)', 'σ_eq,max', 'Tỷ lệ max', 'Kết luận'],
              data: [
                for (final rep in connectionReports)
                  [
                    'N${rep.nodeIndex + 1} (${rep.supportType.shortLabel})',
                    '${rep.gussetWidthMm.toStringAsFixed(0)}×${rep.gussetHeightMm.toStringAsFixed(0)}×${rep.params.gussetThicknessMm.toStringAsFixed(0)}',
                    '${rep.maxGussetSigmaMpa.toStringAsFixed(1)} MPa',
                    '${rep.maxUtilizationPct.toStringAsFixed(1)}%',
                    rep.allPassed ? 'ĐẠT' : 'KHÔNG ĐẠT',
                  ],
              ],
            ),
          ],
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

    // Thêm UTF-8 BOM (0xEF, 0xBB, 0xBF) để Excel nhận diện tiếng Việt có dấu ngay lập tức!
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
