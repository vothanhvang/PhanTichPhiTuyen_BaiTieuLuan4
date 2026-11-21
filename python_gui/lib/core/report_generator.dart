// ============================================================================
// MÔ-ĐUN XUẤT THUYẾT MINH WORD (.DOCX) VÀ PDF (.PDF) TRỰC TIẾP TRONG FLUTTER
// ============================================================================
// Chạy 100% đa nền tảng:
//   - Windows (.exe)  : Lưu trực tiếp vào Documents\CALFEM_PhiTuyen_BaoCao\
//   - Android (.apk)  : Lưu trực tiếp vào Download\CALFEM_PhiTuyen\ trên
//                       Xiaomi Pad 8 Pro và Xiaomi 13T Pro!
//   - GitHub Web      : Tự động tải tệp .docx / .pdf xuống trình duyệt!
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

  static String _docxParagraph(String text, {bool bold = false, int sizeHalfPt = 23, String? colorHex, String align = 'left'}) {
    final colorTag = colorHex != null ? '<w:color w:val="$colorHex"/>' : '';
    final boldTag = bold ? '<w:b/>' : '';
    return '<w:p>'
        '<w:pPr><w:jc w:val="$align"/><w:spacing w:after="100"/></w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>'
        '$boldTag$colorTag<w:sz w:val="$sizeHalfPt"/></w:rPr>'
        '<w:t xml:space="preserve">${_xmlEscape(text)}</w:t></w:r></w:p>';
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

    // Hàng tiêu đề
    buf.write('<w:tr>');
    for (final h in headers) {
      buf.write('<w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="$headerFill"/></w:tcPr>'
          '${_docxParagraph(h, bold: true, sizeHalfPt: 19, colorHex: "FFFFFF", align: "center")}</w:tc>');
    }
    buf.write('</w:tr>');

    // Các hàng dữ liệu
    for (int r = 0; r < rows.length; r++) {
      final fill = r.isOdd ? 'F1F5F9' : 'FFFFFF';
      buf.write('<w:tr>');
      for (int c = 0; c < rows[r].length; c++) {
        buf.write('<w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="$fill"/></w:tcPr>'
            '${_docxParagraph(rows[r][c], sizeHalfPt: 19, align: c == 0 ? "left" : "right")}</w:tc>');
      }
      buf.write('</w:tr>');
    }
    buf.write('</w:tbl>');
    return buf.toString();
  }

  /// Xuất tệp Microsoft Word (.docx) chuẩn OOXML có đầy đủ tiếng Việt có dấu
  static Future<String?> exportDocx({
    required TrussModelData model,
    required TrussAnalysisResult linear,
    required TrussAnalysisResult nonlinear,
    required ProbeInspection probe,
    required double loadFactor,
    List<NodeConnectionReport>? connectionReports,
  }) async {
    final now = DateTime.now();
    final ts = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final body = StringBuffer();
    body.write(_docxParagraph('TRƯỜNG ĐẠI HỌC BÁCH KHOA – ĐHQG TP. HỒ CHÍ MINH', bold: true, sizeHalfPt: 22, colorHex: '0F3D6E', align: 'center'));
    body.write(_docxParagraph('KHOA KỸ THUẬT XÂY DỰNG – BỘ MÔN CÔNG TRÌNH', bold: true, sizeHalfPt: 20, colorHex: '334155', align: 'center'));
    body.write(_docxParagraph('THUYẾT MINH KẾT QUẢ PHÂN TÍCH PHI TUYẾN HÌNH HỌC HỆ DÀN (CALFEM)', bold: true, sizeHalfPt: 28, colorHex: '0F172A', align: 'center'));
    body.write(_docxParagraph('Giảng viên hướng dẫn: PGS. TS Ngô Hữu Cường  |  Học viên thực hiện: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)  |  Liên hệ: vothanhvang@gmail.com  |  Xuất lúc: $ts', sizeHalfPt: 17, colorHex: '475569', align: 'center'));

    body.write(_docxParagraph('1. THÔNG SỐ ĐẦU VÀO & PHƯƠNG PHÁP PHÂN TÍCH', bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    body.write(_docxParagraph('• Mô hình: ${model.name} — ${model.description}'));
    final secSummary = [
      for (int e = 0; e < model.nElems; e++)
        'T${e + 1}: ${model.sectionDimsForElem(e).formatSpec(model.sectionShapeForElem(e))} (L=${model.initialLength(e).toStringAsFixed(0)} mm)',
    ].join(' ; ');
    body.write(_docxParagraph('• Tiết diện & chiều dài các thanh: $secSummary.'));
    final supSummary = [
      for (int i = 0; i < model.nodeSupports.length; i++)
        'N${i + 1}: ${model.nodeSupports[i].shortLabel}',
    ].join(' | ');
    body.write(_docxParagraph(
        '• Liên kết gối tựa các nút: $supSummary${model.hasAnySpring ? " (k = ${model.springStiffnessKnMm.toStringAsFixed(1)} kN/mm)" : ""}'));
    body.write(_docxParagraph('• Hệ số tải trọng đang khảo sát: λ = ${loadFactor.toStringAsFixed(2)}  |  Lõi tính toán: ${nonlinear.engineSource}'));
    body.write(_docxParagraph('• Thuật toán phi tuyến: ${nonlinear.methodName} (Hội tụ: ${nonlinear.converged ? "ĐẠT" : "KHÔNG ĐẠT"}, ${nonlinear.totalIterations} vòng lặp).'));
    body.write(_docxParagraph('• Tài liệu & công thức áp dụng: CALFEM 3.4 bar2e/bar2g (calfem34.pdf tr. 5.3-2..5); Olsson & Dahlblom (2016) Chương 9 PT (9.35)-(9.38) tr. 259; Bài giảng NSA_4 Slides 6-12 & NSA_6 Mục 6.2-6.3; McGuire (2000) Chương 9 & 12.'));

    body.write(_docxParagraph('2. TÓM TẮT 7 CÔNG THỨC TOÁN HỌC ÁP DỤNG', bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    body.write(_docxParagraph('(1) Định lý Py-ta-go: l = √[(Δx₀ + Δuₓ)² + (Δy₀ + Δuᵧ)²].'));
    body.write(_docxParagraph('(2) Hiệu hai bình phương khử sai số làm tròn: l − L₀ = (l² − L₀²) / (l + L₀).'));
    body.write(_docxParagraph('(3) Lượng giác & Cosin chỉ phương: c = cos θ = (x₂ − x₁)/L ; s = sin θ = (y₂ − y₁)/L (c² + s² = 1).'));
    body.write(_docxParagraph('(4) Khai triển nhị thức Newton: (1 + d)^(1/2) ≈ 1 + d/2 → dẫn xuất biến dạng Green-Lagrange.'));
    body.write(_docxParagraph('(5) Đạo hàm, biến phân & tích phân xác định: δ(f²) = 2f·δf ; ∫₀ᴸ (1/L²) dx = 1/L.'));
    body.write(_docxParagraph('(6) Phương pháp tiếp tuyến Newton-Raphson: u^(k+1) = u^(k) + [K_t]⁻¹ · {P − f_int(u^(k))}.'));
    body.write(_docxParagraph('(7) Quy tắc đòn bẩy mô-men & Trị riêng mất ổn định: R₄ᵧ = −P·(L + u₂ₓ)/(2L + u₄ₓ) ; det(K_e + α_cr·K_g) = 0.'));

    body.write(_docxParagraph('3. BẢNG SO SÁNH CHUYỂN VỊ NÚT & PHẢN LỰC GỐI (TUYẾN TÍNH VS PHI TUYẾN)', bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    final nodeRows = <List<String>>[];
    for (int i = 0; i < model.nNodes; i++) {
      nodeRows.add([
        'Nút ${i + 1}',
        linear.uMm[2 * i].toStringAsFixed(6),
        linear.uMm[2 * i + 1].toStringAsFixed(6),
        nonlinear.uMm[2 * i].toStringAsFixed(6),
        nonlinear.uMm[2 * i + 1].toStringAsFixed(6),
        (nonlinear.reactionsN[2 * i] / 1000.0).toStringAsFixed(5),
        (nonlinear.reactionsN[2 * i + 1] / 1000.0).toStringAsFixed(5),
      ]);
    }
    body.write(_docxTable(
      ['Nút', 'ux TT (mm)', 'uy TT (mm)', 'ux PT (mm)', 'uy PT (mm)', 'Rx PT (kN)', 'Ry PT (kN)'],
      nodeRows,
      '1B365D',
    ));

    body.write(_docxParagraph('4. BẢNG NỘI LỰC, ỨNG SUẤT & BIẾN DẠNG CÁC THANH DÀN', bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    final memRows = <List<String>>[];
    for (int e = 0; e < model.nElems; e++) {
      final shE = model.sectionShapeForElem(e);
      memRows.add([
        '${e + 1} (${model.memberLabels[e]})',
        shE.shortLabel,
        model.initialLength(e).toStringAsFixed(1),
        model.areas[e].toStringAsFixed(1),
        (linear.nForcesN[e] / 1000.0).toStringAsFixed(4),
        (nonlinear.nForcesN[e] / 1000.0).toStringAsFixed(4),
        nonlinear.stressMpa[e].toStringAsFixed(3),
        (nonlinear.strain[e] * 1e6).toStringAsFixed(1),
      ]);
    }
    body.write(_docxTable(
      ['Thanh', 'Tiết diện', 'L₀ (mm)', 'A (mm²)', 'N TT (kN)', 'N PT (kN)', 'σ PT (MPa)', 'ε (με)'],
      memRows,
      '0F766E',
    ));

    final probeShape = model.sectionShapeForElem(probe.elemIndex);
    body.write(_docxParagraph('5. KẾT QUẢ KHẢO SÁT & PHẪU THUẬT MẶT CẮT TẠI ĐIỂM ĐANG CHỌN', bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    body.write(_docxParagraph(
      '• Vị trí phẫu thuật: Thanh ${probe.memberLabel} (L₀ = ${probe.l0Mm.toStringAsFixed(1)} mm) tại tọa độ chuẩn hóa ξ = ${probe.xi.toStringAsFixed(2)} (s = ${probe.sMm.toStringAsFixed(1)} mm), thớ (η = ${probe.etaNorm.toStringAsFixed(2)}, ζ = ${probe.zetaNorm.toStringAsFixed(2)}), tiết diện ${probeShape.label} (${probe.sectionDims.formatSpec(probeShape)}).',
    ));
    body.write(_docxParagraph(
      '• Ứng suất pháp σ_xx = ${probe.sigmaXxMpa.toStringAsFixed(4)} MPa (dọc trục ${probe.sigmaAxialMpa.toStringAsFixed(4)} + uốn P-δ ${probe.sigmaBendingMpa.toStringAsFixed(4)}) | von Mises = ${probe.sigmaVonMisesMpa.toStringAsFixed(4)} MPa | τ_max = ${probe.tauMaxMohrMpa.toStringAsFixed(4)} MPa.',
    ));
    body.write(_docxParagraph(
      '• Biến dạng dọc ε_xx = ${probe.epsXxMicro.toStringAsFixed(2)} με | Co/nở ngang Poisson ε_yy = ε_zz = ${probe.epsPoissonMicro.toStringAsFixed(2)} με | Góc xoay vật rắn Δθ = ${probe.rotationDeg.toStringAsFixed(5)}°.',
    ));

    body.write(_docxParagraph('6. KIỂM CHỨNG CÂN BẰNG CẤU HÌNH BIẾN DẠNG & NĂNG LƯỢNG', bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
    body.write(_docxParagraph(
      '• Kiểm tra cân bằng toàn hệ: ∑Fx = ${nonlinear.sumFxN.toStringAsExponential(3)} N | ∑Fy = ${nonlinear.sumFyN.toStringAsExponential(3)} N | ∑M_biến_dạng = ${nonlinear.sumMNmm.toStringAsExponential(3)} N·mm | Phần dư tự do max = ${nonlinear.maxFreeResidualN.toStringAsExponential(3)} N.',
    ));
    body.write(_docxParagraph(
      '• Năng lượng biến dạng tổng: Tuyến tính U_TT = ${(linear.totalEnergyNmm / 1000.0).toStringAsFixed(6)} J  |  Phi tuyến U_PT = ${(nonlinear.totalEnergyNmm / 1000.0).toStringAsFixed(6)} J.',
    ));

    if (connectionReports != null && connectionReports.isNotEmpty) {
      final firstP = connectionReports.first.params;
      body.write(_docxParagraph('7. TÍNH TOÁN & KIỂM TRA LIÊN KẾT CÁC NÚT (TCVN 5575 / EN 1993-1-8)', bold: true, sizeHalfPt: 24, colorHex: '0F3D6E'));
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
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    ${body.toString()}
    <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1250"/></w:sectPr>
  </w:body>
</w:document>''';

    const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    final archive = Archive();
    void addXml(String name, String content) {
      final data = utf8.encode(content);
      archive.addFile(ArchiveFile(name, data.length, data));
    }

    addXml('[Content_Types].xml', contentTypes);
    addXml('_rels/.rels', rels);
    addXml('word/document.xml', documentXml);

    final encoded = ZipEncoder().encode(archive);
    final bytes = Uint8List.fromList(encoded);
    const fileName = 'ThuyetMinh_CALFEM_PhiTuyen.docx';
    return saveBinaryFile(
      fileName,
      bytes,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
  }

  /// Xuất tệp Báo cáo PDF (.pdf) nhúng font Unicode tiếng Việt DejaVuSans
  static Future<String?> exportPdf({
    required TrussModelData model,
    required TrussAnalysisResult linear,
    required TrussAnalysisResult nonlinear,
    required ProbeInspection probe,
    required double loadFactor,
    List<NodeConnectionReport>? connectionReports,
  }) async {
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
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text('TRƯỜNG ĐẠI HỌC BÁCH KHOA – ĐHQG TP. HỒ CHÍ MINH',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: navy)),
                pw.SizedBox(height: 4),
                pw.Text('BÁO CÁO PHÂN TÍCH PHI TUYẾN HÌNH HỌC HỆ DÀN (CALFEM)',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.black),
                    textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 3),
                pw.Text('Giảng viên hướng dẫn: PGS. TS Ngô Hữu Cường | Học viên: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624) | Liên hệ: vothanhvang@gmail.com | Xuất: $ts',
                    style: pw.TextStyle(fontSize: 7.6, color: slate),
                    textAlign: pw.TextAlign.center),
              ],
            ),
          ),
          pw.Divider(color: navy, thickness: 1.2),
          pw.SizedBox(height: 6),
          pw.Text('1. Thông số đầu vào & thuật toán',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: navy)),
          pw.SizedBox(height: 3),
          pw.Text(
            '• Mô hình: ${model.name} — ${model.description}\n'
            '• Tiết diện & chiều dài thanh: ${[for (int e = 0; e < model.nElems; e++) "T${e + 1}: ${model.sectionShapeForElem(e).shortLabel} (L=${model.initialLength(e).toStringAsFixed(0)} mm, A=${model.areas[e].toStringAsFixed(0)} mm²)"].join(" | ")}\n'
            '• Liên kết nút: ${[for (int i = 0; i < model.nodeSupports.length; i++) "N${i + 1}: ${model.nodeSupports[i].shortLabel}"].join(" | ")}${model.hasAnySpring ? " (k = ${model.springStiffnessKnMm.toStringAsFixed(1)} kN/mm)" : ""}\n'
            '• Hệ số tải λ = ${loadFactor.toStringAsFixed(2)} | Phương pháp: ${nonlinear.methodName}\n'
            '• Lõi giải: ${nonlinear.engineSource} | Hội tụ: ${nonlinear.converged ? "ĐẠT" : "KHÔNG ĐẠT"} (${nonlinear.totalIterations} vòng lặp).',
            style: const pw.TextStyle(fontSize: 8.6, lineSpacing: 2.3),
          ),
          pw.SizedBox(height: 8),
          pw.Text('2. Tóm tắt 7 công thức Toán học áp dụng',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: navy)),
          pw.SizedBox(height: 2),
          pw.Text(
            '(1) Py-ta-go: l = √[(Δx₀+Δuₓ)²+(Δy₀+Δuᵧ)²]  |  (2) Hiệu bình phương: l−L₀ = (l²−L₀²)/(l+L₀)\n'
            '(3) Cosin chỉ phương: c = (x₂−x₁)/L, s = (y₂−y₁)/L  |  (4) Nhị thức Newton: (1+d)^(1/2) ≈ 1 + d/2\n'
            '(5) Biến phân & Tích phân: δ(f²)=2f·δf, ∫₀ᴸ(1/L²)dx=1/L  |  (6) Newton-Raphson: u^(k+1)=u^(k)+[K_t]⁻¹R\n'
            '(7) Đòn bẩy biến dạng & Trị riêng: R₄ᵧ = −P·(L+u₂ₓ)/(2L+u₄ₓ) ; det(K_e + α_cr·K_g) = 0.',
            style: const pw.TextStyle(fontSize: 8.2, lineSpacing: 2.2),
          ),
          pw.SizedBox(height: 8),
          pw.Text('3. Bảng chuyển vị nút & phản lực gối (Tuyến tính vs Phi tuyến)',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: navy)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headerDecoration: pw.BoxDecoration(color: navy),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
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
          pw.SizedBox(height: 10),
          pw.Text('4. Bảng nội lực, ứng suất & biến dạng các phần tử thanh',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: teal)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headerDecoration: pw.BoxDecoration(color: teal),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 7.6),
            cellStyle: const pw.TextStyle(fontSize: 7.6),
            oddRowDecoration: pw.BoxDecoration(color: lightRow),
            headers: ['Thanh', 'Tiết diện', 'L₀ (mm)', 'A (mm²)', 'N TT (kN)', 'N PT (kN)', 'σ PT (MPa)', 'ε (με)'],
            data: [
              for (int e = 0; e < model.nElems; e++)
                [
                  '${e + 1} (${model.memberLabels[e]})',
                  model.sectionShapeForElem(e).shortLabel,
                  model.initialLength(e).toStringAsFixed(1),
                  model.areas[e].toStringAsFixed(1),
                  (linear.nForcesN[e] / 1000).toStringAsFixed(4),
                  (nonlinear.nForcesN[e] / 1000).toStringAsFixed(4),
                  nonlinear.stressMpa[e].toStringAsFixed(3),
                  (nonlinear.strain[e] * 1e6).toStringAsFixed(1),
                ],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text('5. Khảo sát điểm & phẫu thuật mặt cắt đang chọn',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: navy)),
          pw.SizedBox(height: 3),
          pw.Text(
            '• Thanh ${probe.memberLabel} (L₀=${probe.l0Mm.toStringAsFixed(1)} mm) tại ξ = ${probe.xi.toStringAsFixed(2)} (s = ${probe.sMm.toStringAsFixed(1)} mm), thớ (η=${probe.etaNorm.toStringAsFixed(2)}, ζ=${probe.zetaNorm.toStringAsFixed(2)}), tiết diện ${model.sectionShapeForElem(probe.elemIndex).label} (${probe.sectionDims.formatSpec(model.sectionShapeForElem(probe.elemIndex))}):\n'
            '  - Ứng suất pháp σ_xx = ${probe.sigmaXxMpa.toStringAsFixed(4)} MPa | von Mises = ${probe.sigmaVonMisesMpa.toStringAsFixed(4)} MPa | τ_max = ${probe.tauMaxMohrMpa.toStringAsFixed(4)} MPa.\n'
            '  - Biến dạng dọc ε_xx = ${probe.epsXxMicro.toStringAsFixed(2)} με | Co/nở ngang Poisson = ${probe.epsPoissonMicro.toStringAsFixed(2)} με | Xoay Δθ = ${probe.rotationDeg.toStringAsFixed(5)}°.\n'
            '• Kiểm chứng cân bằng cấu hình biến dạng: ∑Fx = ${nonlinear.sumFxN.toStringAsExponential(2)} N, ∑Fy = ${nonlinear.sumFyN.toStringAsExponential(2)} N, ∑M = ${nonlinear.sumMNmm.toStringAsExponential(2)} N·mm.\n'
            '• Năng lượng biến dạng tổng: Tuyến tính = ${(linear.totalEnergyNmm / 1000).toStringAsFixed(6)} J | Phi tuyến = ${(nonlinear.totalEnergyNmm / 1000).toStringAsFixed(6)} J.',
            style: const pw.TextStyle(fontSize: 9, lineSpacing: 2.5),
          ),
          if (connectionReports != null && connectionReports.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text('6. Tính toán & kiểm tra liên kết các nút (TCVN 5575 / EN 1993-1-8)',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: navy)),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.2, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: teal),
              cellStyle: const pw.TextStyle(fontSize: 8.0),
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
}
