// ============================================================================
// MÔ-ĐUN XUẤT THUYẾT MINH WORD (.DOCX), PDF (.PDF) & CSV EXCEL CHO DẦM BTCT
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

  static String _p(String txt, {bool bold = false, int sz = 22, String? color, String align = 'left'}) {
    final c = color != null ? '<w:color w:val="$color"/>' : '';
    final b = bold ? '<w:b/>' : '';
    return '<w:p><w:pPr><w:jc w:val="$align"/><w:spacing w:after="90"/></w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>$b$c<w:sz w:val="$sz"/></w:rPr>'
        '<w:t xml:space="preserve">${_xmlEsc(txt)}</w:t></w:r></w:p>';
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
        '${_p(cap, sz: 18, color: "475569", align: "center")}';
  }

  static String _tbl(List<String> hdrs, List<List<String>> rows, String fillHex) {
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
          '${_p(h, bold: true, sz: 18, color: "FFFFFF", align: "center")}</w:tc>');
    }
    buf.write('</w:tr>');
    for (int r = 0; r < rows.length; r++) {
      final f = r.isOdd ? 'F1F5F9' : 'FFFFFF';
      buf.write('<w:tr>');
      for (int c = 0; c < rows[r].length; c++) {
        buf.write('<w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="$f"/></w:tcPr>'
            '${_p(rows[r][c], sz: 17, align: c == 0 ? "left" : "right")}</w:tc>');
      }
      buf.write('</w:tr>');
    }
    buf.write('</w:tbl>');
    return buf.toString();
  }

  /// 1. Xuất Thuyết minh Microsoft Word (.docx) Dầm BTCT Phi tuyến Thớ
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
    final hasImg = viewportPngBytes != null && viewportPngBytes.isNotEmpty;
    final now = DateTime.now();
    final ts = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final body = StringBuffer();
    body.write(_p('TRƯỜNG ĐẠI HỌC BÁCH KHOA — ĐHQG TP.HCM', bold: true, sz: 22, color: '1B365D', align: 'center'));
    body.write(_p('THUYẾT MINH PHÂN TÍCH PHI TUYẾN VẬT LIỆU DẦM BÊ TÔNG CỐT THÉP', bold: true, sz: 28, color: '0F3D6E', align: 'center'));
    body.write(_p('PHƯƠNG PHÁP THỚ (FIBER SECTION) & RAYLEIGH-RITZ PTHH (CHUẨN CALFEM)', bold: true, sz: 21, color: '0F766E', align: 'center'));
    body.write(_p('Giảng viên hướng dẫn: PGS. TS Ngô Hữu Cường', bold: true, sz: 20, color: '1E293B', align: 'center'));
    body.write(_p('Học viên thực hiện: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)', bold: true, sz: 20, color: '1E293B', align: 'center'));
    body.write(_p('Liên hệ: vothanhvang@gmail.com  |  ĐT: 0973.993.494  |  Ngày xuất: $ts', sz: 18, color: '475569', align: 'center'));

    if (hasImg) {
      body.write(_img(pngWidthPx ?? 1200, pngHeightPx ?? 720,
          'Hình 1. Mô hình Dầm BTCT chịu uốn ${cfg.loadType.shortLabel}, bản đồ ứng suất/nứt & mặt cắt phẫu thuật thớ'));
    }

    body.write(_p('1. THÔNG SỐ MÔ HÌNH DẦM BÊ TÔNG CỐT THÉP & TẢI TRỌNG', bold: true, sz: 23, color: '0F3D6E'));
    body.write(_tbl(
      ['Thông số', 'Giá trị thiết kế', 'Ghi chú / Quy chuẩn'],
      [
        ['Kích thước dầm L × b × h', '${cfg.spanMm.toStringAsFixed(0)} × ${cfg.widthMm.toStringAsFixed(0)} × ${cfg.heightMm.toStringAsFixed(0)} mm', 'Tỷ lệ nhịp/chiều cao L/h = ${cfg.spanToDepthRatio.toStringAsFixed(2)}'],
        ['Cốt thép chịu kéo As / nén As\'', '${cfg.asBotMm2.toStringAsFixed(1)} mm² / ${cfg.asTopMm2.toStringAsFixed(1)} mm²', 'Hàm lượng μ = ${cfg.steelRatioPct.toStringAsFixed(2)}% (a_s = ${cfg.coverBotMm.toStringAsFixed(0)} mm)'],
        ['Dầm cốt cứng (Thép hình I)', cfg.hasRigidCore ? 'CÓ (${cfg.coreHMm.toStringAsFixed(0)}×${cfg.coreBMm.toStringAsFixed(0)}×${cfg.coreTwMm.toStringAsFixed(0)}×${cfg.coreTfMm.toStringAsFixed(0)} mm, fy=${cfg.coreFyMpa.toStringAsFixed(0)} MPa)' : 'Không sử dụng', 'Đặt đồng tâm lõi dầm'],
        ['Vật liệu Bê tông (Hognestad)', 'f\'c = ${cfg.fcMpa.toStringAsFixed(1)} MPa, Ec = ${cfg.ecMpa.toStringAsFixed(0)} MPa', 'fct = ${cfg.fctMpa.toStringAsFixed(2)} MPa, ε_cu = ${(cfg.epsCu * 1000).toStringAsFixed(2)}‰'],
        ['Vật liệu Cốt thép (Đàn-dẻo)', 'fy = ${cfg.fyMpa.toStringAsFixed(0)} MPa, Es = ${cfg.esMpa.toStringAsFixed(0)} MPa', 'Tỷ số tái bền ${(cfg.hardeningRatio * 100).toStringAsFixed(1)}%'],
        ['Liên kết hai đầu dầm', 'Trái: ${cfg.leftSupport.shortLabel}  |  Phải: ${cfg.rightSupport.shortLabel}', 'Mô hình 6 DOF/phần tử (u, v, θ)'],
        ['Sơ đồ chất tải', '${cfg.loadType.label}, Q = ${cfg.loadQKn.toStringAsFixed(1)} kN, a = ${cfg.effectiveAMm.toStringAsFixed(0)} mm', cfg.momentFormulaLabel],
        ['Rời rạc hóa PTHH & Thớ', '${active.nElems} phần tử (${active.nNodes} nút) • ${cfg.nFibers} thớ bê tông', 'Tích phân Gauss-Legendre 3 điểm'],
      ],
      '0F3D6E',
    ));

    body.write(_p('2. SO SÁNH KẾT QUẢ TUYẾN TÍNH (beam2e) VÀ PHI TUYẾN VẬT LIỆU THỚ', bold: true, sz: 23, color: '0F3D6E'));
    final ratioV = linear.vMidMm.abs() > 1e-6 ? active.vMidMm.abs() / linear.vMidMm.abs() : 1.0;
    body.write(_tbl(
      ['Đại lượng đánh giá', 'Đàn hồi Tuyến tính', active.methodName, 'Nhận xét'],
      [
        ['Độ võng giữa nhịp v_mid (mm)', linear.vMidMm.toStringAsFixed(3), active.vMidMm.toStringAsFixed(3), 'Tăng ${ratioV.toStringAsFixed(2)}× do nứt/dẻo'],
        ['Mô-men cực đại M_max (kN·m)', linear.mMaxKnm.toStringAsFixed(2), active.mMaxKnm.toStringAsFixed(2), 'Khớp giải tích ${cfg.simpleBeamMaxMomentKnm.toStringAsFixed(2)}'],
        ['Phản lực gối trái / phải (kN)', '${linear.rLeftKn.toStringAsFixed(2)} / ${linear.rRightKn.toStringAsFixed(2)}', '${active.rLeftKn.toStringAsFixed(2)} / ${active.rRightKn.toStringAsFixed(2)}', 'ΣFy = ${active.sumFyN.toStringAsExponential(1)} N'],
        ['Trục trung hòa x_NA tại x/L=${probeXNorm.toStringAsFixed(2)}', '${(0.5 * cfg.heightMm).toStringAsFixed(1)} mm', '${sec.xNeutralDepthMm.toStringAsFixed(1)} mm', 'Dịch lên vùng nén khi nứt'],
        ['Độ cứng uốn hiệu dụng EI_eff', '${(active.eiGrossNmm2 / 1e12).toStringAsFixed(2)}×10¹²', '${(sec.eiEffNmm2 / 1e12).toStringAsFixed(2)}×10¹²', 'Còn ${eiPct.toStringAsFixed(1)}% EI₀'],
        ['Ứng suất nén BT / thép kéo (MPa)', 'Đàn hồi', '${sec.sigmaTopConcMpa.toStringAsFixed(1)} / ${sec.sigmaBotSteelMpa.toStringAsFixed(1)}', active.hasYielding ? 'Thép đã chảy dẻo' : (active.hasCracking ? 'BT đã nứt kéo' : 'Đàn hồi')],
      ],
      '0F766E',
    ));

    body.write(_p('3. KHẢO SÁT HỘI TỤ LƯỚI PHẦN TỬ (CHIA HAI NỬA: 2 → 4 → 8 → 16 → 32 PHẦN TỬ)', bold: true, sz: 23, color: '0F3D6E'));
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

    body.write(_p('4. BẢNG NỘI LỰC HAI ĐẦU PHẦN TỬ & CHUYỂN VỊ NÚT', bold: true, sz: 23, color: '0F3D6E'));
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
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';
    final docRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
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
      'ThuyetMinh_DamBTCT_PhiTuyenTho_CALFEM.docx',
      bytes,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
  }

  /// 2. Xuất Báo cáo PDF (.pdf) Dầm BTCT Phi tuyến Thớ
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
    final fontReg = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: fontReg, bold: fontBold));

    final navy = PdfColor.fromHex('#0F3D6E');
    final teal = PdfColor.fromHex('#0F766E');
    final slate = PdfColor.fromHex('#334155');
    final lightRow = PdfColor.fromHex('#F1F5F9');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(26),
        build: (ctx) => [
          pw.Center(child: pw.Text('TRƯỜNG ĐẠI HỌC BÁCH KHOA — ĐHQG TP.HCM', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: navy))),
          pw.SizedBox(height: 3),
          pw.Center(child: pw.Text('BÁO CÁO PHÂN TÍCH PHI TUYẾN VẬT LIỆU DẦM BÊ TÔNG CỐT THÉP (PHƯƠNG PHÁP THỚ)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12.2, color: navy))),
          pw.SizedBox(height: 3),
          pw.Center(child: pw.Text('GVHD: PGS. TS Ngô Hữu Cường  •  HV: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)', style: pw.TextStyle(fontSize: 9.0, color: slate))),
          pw.Center(child: pw.Text('Liên hệ: vothanhvang@gmail.com  •  ĐT: 0973.993.494', style: pw.TextStyle(fontSize: 8.5, color: slate))),
          pw.Divider(color: navy, thickness: 1.2),
          if (viewportPngBytes != null && viewportPngBytes.isNotEmpty) ...[
            pw.Center(
              child: pw.Container(
                height: 205,
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#CBD5E1'))),
                child: pw.Image(pw.MemoryImage(viewportPngBytes), fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 6),
          ],
          pw.Text('1. Thông số Hình học, Cốt thép, Vật liệu & So sánh Tuyến tính — Phi tuyến', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: navy)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8.5),
            headerDecoration: pw.BoxDecoration(color: navy),
            cellStyle: const pw.TextStyle(fontSize: 8.2),
            oddRowDecoration: pw.BoxDecoration(color: lightRow),
            headers: ['Thông số', 'Giá trị / Tuyến tính', 'Phi tuyến Thớ / Ghi chú'],
            data: [
              ['Nhịp L × b × h (L/h)', '${cfg.spanMm.toStringAsFixed(0)} × ${cfg.widthMm.toStringAsFixed(0)} × ${cfg.heightMm.toStringAsFixed(0)} mm', 'L/h = ${cfg.spanToDepthRatio.toStringAsFixed(2)} • ${cfg.nFibers} thớ BT'],
              ['Cốt thép As / As\' / Cốt cứng', '${cfg.asBotMm2.toStringAsFixed(1)} / ${cfg.asTopMm2.toStringAsFixed(1)} mm²', cfg.hasRigidCore ? 'Cốt cứng I (${cfg.coreHMm.toStringAsFixed(0)}×${cfg.coreBMm.toStringAsFixed(0)})' : 'BTCT thường (μ=${cfg.steelRatioPct.toStringAsFixed(2)}%)'],
              ['Chất tải & Gối tựa', '${cfg.loadType.shortLabel}, Q=${cfg.loadQKn.toStringAsFixed(1)} kN, a=${cfg.effectiveAMm.toStringAsFixed(0)} mm', '${cfg.leftSupport.shortLabel} — ${cfg.rightSupport.shortLabel}'],
              ['Độ võng giữa nhịp v_mid (mm)', linear.vMidMm.toStringAsFixed(3), active.vMidMm.toStringAsFixed(3)],
              ['Mô-men cực đại M_max (kN·m)', linear.mMaxKnm.toStringAsFixed(2), '${active.mMaxKnm.toStringAsFixed(2)} (${cfg.momentFormulaLabel})'],
              ['Trục trung hòa x_NA & EI_eff', '${(0.5 * cfg.heightMm).toStringAsFixed(1)} mm (100%)', '${sec.xNeutralDepthMm.toStringAsFixed(1)} mm (${(100.0 * sec.eiEffNmm2 / math.max(1.0, active.eiGrossNmm2)).toStringAsFixed(1)}% EI₀)'],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text('2. Bảng Khảo sát Hội tụ Lưới Phần tử (Chia hai nửa đối xứng: 2 → 32 PT)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: teal)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8.5),
            headerDecoration: pw.BoxDecoration(color: teal),
            cellStyle: const pw.TextStyle(fontSize: 8.2),
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
        ],
      ),
    );
    final bytes = await pdf.save();
    return saveBinaryFile('BaoCao_DamBTCT_PhiTuyenTho_CALFEM.pdf', bytes, 'application/pdf');
  }

  /// 3. Xuất Bảng số liệu Excel CSV (UTF-8 BOM) cho Dầm BTCT
  static Future<String?> exportCsv({
    required RcBeamAnalysisResult active,
    required List<RcMeshConvergencePoint> meshConv,
  }) async {
    final buf = StringBuffer('\uFEFF');
    buf.writeln('=== THONG SO DAM BTCT PHI TUYEN THO (CALFEM) ===');
    buf.writeln('L_mm,b_mm,h_mm,L_h,As_mm2,AsTop_mm2,Q_kN,a_mm,Mmax_kNm,vMid_mm,Converged');
    final c = active.config;
    buf.writeln('${c.spanMm},${c.widthMm},${c.heightMm},${c.spanToDepthRatio.toStringAsFixed(2)},${c.asBotMm2},${c.asTopMm2},${c.loadQKn},${c.effectiveAMm},${active.mMaxKnm.toStringAsFixed(4)},${active.vMidMm.toStringAsFixed(4)},${active.converged}');
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
