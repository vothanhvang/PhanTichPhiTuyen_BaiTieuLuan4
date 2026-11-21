// ============================================================================
// MÔ-ĐUN XUẤT BẢN VẼ CẤU TẠO LIÊN KẾT DẠNG AUTOCAD (.DXF) VÀ BẢN VẼ KỸ THUẬT PDF
// ============================================================================
// Xuất bản vẽ gia công chi tiết tại nút liên kết tỷ lệ 1:1 (đơn vị mm):
//   1. AutoCAD (.dxf) chuẩn R12/R2000 đa lớp (LAYER):
//        TIM_TRUC, BAN_MA, THANH_THEP, BU_LONG, DUONG_HAN, BAN_DE_MONG,
//        KICH_THUOC, KHUNG_TEN, GHI_CHU — mở trực tiếp trong AutoCAD / BricsCAD / ZWCAD!
//   2. Bản vẽ kỹ thuật vector PDF (.pdf) khổ A4 ngang kèm khung tên, bản vẽ
//      cấu tạo cắt ngắn đầu thanh thực tế, kích thước mm & bảng kiểm tra TCVN 5575 / EC3.
// ============================================================================

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'calfem_engine.dart';
import 'connection_calculator.dart';
import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';

class _Pt {
  final double x, y;
  const _Pt(this.x, this.y);
  _Pt operator +(_Pt o) => _Pt(x + o.x, y + o.y);
  _Pt operator -(_Pt o) => _Pt(x - o.x, y - o.y);
  _Pt operator *(double s) => _Pt(x * s, y * s);
}

class _NodeShopGeometry {
  final NodeConnectionReport report;
  final SupportDirection dir;
  final List<_Pt> gussetPoly;
  final List<({
    ConnectedMemberInfo member,
    String specLabel,
    _Pt uDir,
    _Pt perp,
    double halfH,
    double setbackMm,
    double overlapEndMm,
    double drawEndMm,
    List<_Pt> bolts,
    List<(_Pt, _Pt)> welds,
  })> members;
  final double reachMm;
  final _Pt outVec;
  final _Pt tangVec;
  final double minX, maxX, minY, maxY;

  const _NodeShopGeometry({
    required this.report,
    required this.dir,
    required this.gussetPoly,
    required this.members,
    required this.reachMm,
    required this.outVec,
    required this.tangVec,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });
}

class ConnectionDrawingExporter {
  static _Pt _dirOut(SupportDirection d) {
    switch (d) {
      case SupportDirection.top:
        return const _Pt(0, 1);
      case SupportDirection.left:
        return const _Pt(-1, 0);
      case SupportDirection.right:
        return const _Pt(1, 0);
      case SupportDirection.bottom:
      case SupportDirection.auto:
        return const _Pt(0, -1);
    }
  }

  static List<_Pt> _convexHull(List<_Pt> pts) {
    if (pts.length <= 3) return pts;
    final sorted = List<_Pt>.from(pts)
      ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    double cr(_Pt o, _Pt a, _Pt b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    final lo = <_Pt>[];
    for (final p in sorted) {
      while (lo.length >= 2 && cr(lo[lo.length - 2], lo.last, p) <= 0) {
        lo.removeLast();
      }
      lo.add(p);
    }
    final hi = <_Pt>[];
    for (final p in sorted.reversed) {
      while (hi.length >= 2 && cr(hi[hi.length - 2], hi.last, p) <= 0) {
        hi.removeLast();
      }
      hi.add(p);
    }
    lo.removeLast();
    hi.removeLast();
    return [...lo, ...hi];
  }

  /// Dựng tọa độ hình học gia công thực tế 1:1 (mm) quanh tâm nút (0, 0)
  static _NodeShopGeometry _buildGeometry(TrussModelData model, NodeConnectionReport rep) {
    final p = rep.params;
    final dir = model.resolvedDirectionFor(rep.nodeIndex);
    final outV = _dirOut(dir);
    final tangV = _Pt(-outV.y, outV.x);

    final double e1 = math.max(30.0, 1.5 * p.boltSpec.d0Mm);
    final double pitch = math.max(60.0, 3.0 * p.boltSpec.d0Mm);
    final int nRows = math.max(1, (p.boltsPerMember / 2).ceil());
    final double overlapLen = p.detailType == ConnectionDetailType.weldedGusset
        ? math.max(140.0, p.weldLengthMm)
        : (2.0 * e1 + math.max(0, nRows - 1) * pitch);
    final double setbackBase = 75.0; // Khe hở cắt đầu thanh thực tế cách tâm nút (mm)
    final double reach = setbackBase + overlapLen + 20.0;

    final hullPts = <_Pt>[];
    final memInfos = <({
      ConnectedMemberInfo member,
      String specLabel,
      _Pt uDir,
      _Pt perp,
      double halfH,
      double setbackMm,
      double overlapEndMm,
      double drawEndMm,
      List<_Pt> bolts,
      List<(_Pt, _Pt)> welds,
    })>[];

    for (final m in rep.members) {
      final u = _Pt(math.cos(m.angleRad), math.sin(m.angleRad));
      final perp = _Pt(-u.y, u.x);
      final shapeE = model.sectionShapeForElem(m.elemIndex);
      final dims = model.sectionDimsForElem(m.elemIndex);
      final bnd = dims.rotatedBounds(shapeE);
      final halfH = (0.5 * bnd.height).clamp(32.0, 130.0);
      final sb = math.max(setbackBase, halfH * 0.95);
      final ovEnd = sb + overlapLen;
      final drawEnd = ovEnd + 165.0;

      hullPts.add(u * (ovEnd + 15.0) + perp * (halfH + 22.0));
      hullPts.add(u * (ovEnd + 15.0) - perp * (halfH + 22.0));
      hullPts.add(perp * (halfH + 18.0));
      hullPts.add(perp * -(halfH + 18.0));

      final bolts = <_Pt>[];
      final welds = <(_Pt, _Pt)>[];
      if (p.detailType == ConnectionDetailType.boltedGusset) {
        final gauge = (halfH * 0.52).clamp(24.0, 75.0);
        for (int r = 0; r < nRows; r++) {
          final dist = sb + e1 + r * pitch;
          if (p.boltsPerMember == 1) {
            bolts.add(u * dist);
          } else {
            bolts.add(u * dist + perp * gauge);
            bolts.add(u * dist - perp * gauge);
          }
        }
      } else if (p.detailType == ConnectionDetailType.weldedGusset) {
        final wA = sb + 10.0;
        final wB = sb + math.max(80.0, p.weldLengthMm);
        welds.add((u * wA + perp * halfH, u * wB + perp * halfH));
        welds.add((u * wA - perp * halfH, u * wB - perp * halfH));
      }

      memInfos.add((
        member: m,
        specLabel: dims.formatSpec(shapeE),
        uDir: u,
        perp: perp,
        halfH: halfH,
        setbackMm: sb,
        overlapEndMm: ovEnd,
        drawEndMm: drawEnd,
        bolts: bolts,
        welds: welds,
      ));
    }

    if (rep.supportType != NodeSupportType.free) {
      final bpDist = 145.0;
      hullPts.add(outV * bpDist + tangV * (0.45 * p.basePlateWidthMm));
      hullPts.add(outV * bpDist - tangV * (0.45 * p.basePlateWidthMm));
    }

    final hull = _convexHull(hullPts);
    double minX = -260, maxX = 260, minY = -260, maxY = 260;
    void ext(_Pt q) {
      minX = math.min(minX, q.x);
      maxX = math.max(maxX, q.x);
      minY = math.min(minY, q.y);
      maxY = math.max(maxY, q.y);
    }

    for (final q in hull) {
      ext(q);
    }
    for (final m in memInfos) {
      ext(m.uDir * m.drawEndMm + m.perp * m.halfH);
      ext(m.uDir * m.drawEndMm - m.perp * m.halfH);
    }
    if (rep.supportType != NodeSupportType.free) {
      ext(outV * 310.0 + tangV * (0.65 * p.basePlateWidthMm));
      ext(outV * 310.0 - tangV * (0.65 * p.basePlateWidthMm));
    }

    return _NodeShopGeometry(
      report: rep,
      dir: dir,
      gussetPoly: hull,
      members: memInfos,
      reachMm: reach,
      outVec: outV,
      tangVec: tangV,
      minX: minX - 80.0,
      maxX: maxX + 80.0,
      minY: minY - 80.0,
      maxY: maxY + 80.0,
    );
  }

  /// Loại bỏ dấu tiếng Việt cho chuỗi DXF R12 ASCII thuần (AutoCAD đọc không bao giờ bị vỡ ký tự!)
  static String _asciiDxf(String s) {
    const map = {
      'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
      'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
      'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
      'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
      'đ': 'd', 'Đ': 'D',
      'À': 'A', 'Á': 'A', 'Ả': 'A', 'Ã': 'A', 'Ạ': 'A',
      'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ẳ': 'A', 'Ẵ': 'A', 'Ặ': 'A',
      'Â': 'A', 'Ầ': 'A', 'Ấ': 'A', 'Ẩ': 'A', 'Ẫ': 'A', 'Ậ': 'A',
      'È': 'E', 'É': 'E', 'Ẻ': 'E', 'Ẽ': 'E', 'Ẹ': 'E',
      'Ê': 'E', 'Ề': 'E', 'Ế': 'E', 'Ể': 'E', 'Ễ': 'E', 'Ệ': 'E',
      'Ì': 'I', 'Í': 'I', 'Ỉ': 'I', 'Ĩ': 'I', 'Ị': 'I',
      'Ò': 'O', 'Ó': 'O', 'Ỏ': 'O', 'Õ': 'O', 'Ọ': 'O',
      'Ô': 'O', 'Ồ': 'O', 'Ố': 'O', 'Ổ': 'O', 'Ỗ': 'O', 'Ộ': 'O',
      'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ở': 'O', 'Ỡ': 'O', 'Ợ': 'O',
      'Ù': 'U', 'Ú': 'U', 'Ủ': 'U', 'Ũ': 'U', 'Ụ': 'U',
      'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ử': 'U', 'Ữ': 'U', 'Ự': 'U',
      'Ỳ': 'Y', 'Ý': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y', 'Ỵ': 'Y',
      '×': 'x', 'Ø': 'D', '°': ' deg', '–': '-', '—': '-', '•': '|', '↻': 'Rot ',
      'σ': 'sigma', 'λ': 'lambda', '≥': '>=', '≤': '<=',
    };
    final out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      out.write(map[ch] ?? (ch.codeUnitAt(0) < 128 ? ch : ' '));
    }
    return out.toString();
  }

  /// Tạo nội dung chuỗi AutoCAD DXF (AC1009 / R12 chuẩn mở 100% mọi phiên bản AutoCAD)
  static String buildDxfString({
    required TrussModelData model,
    required NodeConnectionReport report,
  }) {
    final g = _buildGeometry(model, report);
    final p = report.params;
    final buf = StringBuffer();

    void addPair(int code, String val) {
      buf.writeln('  $code');
      buf.writeln(val);
    }

    void addLayer(String name, int color, String ltype) {
      addPair(0, 'LAYER');
      addPair(2, name);
      addPair(70, '0');
      addPair(62, '$color');
      addPair(6, ltype);
    }

    void addLine(String layer, double x1, double y1, double x2, double y2) {
      addPair(0, 'LINE');
      addPair(8, layer);
      addPair(10, x1.toStringAsFixed(3));
      addPair(20, y1.toStringAsFixed(3));
      addPair(30, '0.0');
      addPair(11, x2.toStringAsFixed(3));
      addPair(21, y2.toStringAsFixed(3));
      addPair(31, '0.0');
    }

    void addCircle(String layer, double cx, double cy, double r) {
      addPair(0, 'CIRCLE');
      addPair(8, layer);
      addPair(10, cx.toStringAsFixed(3));
      addPair(20, cy.toStringAsFixed(3));
      addPair(30, '0.0');
      addPair(40, r.toStringAsFixed(3));
    }

    void addText(String layer, double x, double y, double h, String txt, {double rotDeg = 0.0}) {
      addPair(0, 'TEXT');
      addPair(8, layer);
      addPair(10, x.toStringAsFixed(3));
      addPair(20, y.toStringAsFixed(3));
      addPair(30, '0.0');
      addPair(40, h.toStringAsFixed(2));
      addPair(1, _asciiDxf(txt));
      if (rotDeg.abs() > 1e-3) addPair(50, rotDeg.toStringAsFixed(2));
    }

    void addPoly(String layer, List<_Pt> pts, {bool closed = true}) {
      if (pts.length < 2) return;
      for (int i = 0; i < pts.length - 1; i++) {
        addLine(layer, pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y);
      }
      if (closed && pts.length >= 3) {
        addLine(layer, pts.last.x, pts.last.y, pts.first.x, pts.first.y);
      }
    }

    void addRect(_Pt center, _Pt alongDir, _Pt acrossDir, double alongLen, double acrossLen, String layer) {
      final ha = 0.5 * alongLen;
      final hw = 0.5 * acrossLen;
      addPoly(layer, [
        center - alongDir * ha - acrossDir * hw,
        center + alongDir * ha - acrossDir * hw,
        center + alongDir * ha + acrossDir * hw,
        center - alongDir * ha + acrossDir * hw,
      ]);
    }

    // HEADER
    addPair(0, 'SECTION');
    addPair(2, 'HEADER');
    addPair(9, r'$ACADVER');
    addPair(1, 'AC1009');
    addPair(9, r'$INSUNITS');
    addPair(70, '4'); // Millimeters
    addPair(0, 'ENDSEC');

    // TABLES (LTYPE + LAYER)
    addPair(0, 'SECTION');
    addPair(2, 'TABLES');
    addPair(0, 'TABLE');
    addPair(2, 'LTYPE');
    addPair(70, '2');
    addPair(0, 'LTYPE');
    addPair(2, 'CONTINUOUS');
    addPair(70, '0');
    addPair(3, 'Solid line');
    addPair(72, '65');
    addPair(73, '0');
    addPair(40, '0.0');
    addPair(0, 'LTYPE');
    addPair(2, 'CENTER');
    addPair(70, '0');
    addPair(3, 'Center ____ _ ____');
    addPair(72, '65');
    addPair(73, '4');
    addPair(40, '40.0');
    addPair(49, '24.0');
    addPair(49, '-6.0');
    addPair(49, '4.0');
    addPair(49, '-6.0');
    addPair(0, 'ENDTAB');

    addPair(0, 'TABLE');
    addPair(2, 'LAYER');
    addPair(70, '9');
    addLayer('TIM_TRUC', 8, 'CENTER');
    addLayer('BAN_MA', 5, 'CONTINUOUS');
    addLayer('THANH_THEP', 4, 'CONTINUOUS');
    addLayer('BU_LONG', 2, 'CONTINUOUS');
    addLayer('DUONG_HAN', 30, 'CONTINUOUS');
    addLayer('BAN_DE_MONG', 7, 'CONTINUOUS');
    addLayer('KICH_THUOC', 3, 'CONTINUOUS');
    addLayer('KHUNG_TEN', 7, 'CONTINUOUS');
    addLayer('GHI_CHU', 7, 'CONTINUOUS');
    addPair(0, 'ENDTAB');
    addPair(0, 'ENDSEC');

    // ENTITIES
    addPair(0, 'SECTION');
    addPair(2, 'ENTITIES');

    // 1. Đường tim trục tâm nút & trục các thanh
    addLine('TIM_TRUC', g.minX + 30, 0, g.maxX - 30, 0);
    addLine('TIM_TRUC', 0, g.minY + 30, 0, g.maxY - 30);

    // 2. Đường bao bản mã nút (BAN_MA)
    addPoly('BAN_MA', g.gussetPoly, closed: true);

    // 3. Các thanh thép cắt ngắn đầu thanh thực tế (setback cách tâm nút, lộ phần ngoài bản mã)
    for (final m in g.members) {
      final p0 = m.uDir * m.setbackMm;
      final pOut = m.uDir * m.drawEndMm;
      // Tim thanh
      addLine('TIM_TRUC', 0, 0, pOut.x, pOut.y);
      // Bao thanh thép đã cắt ngắn đầu thanh đúng cấu tạo gia công thực tế
      addPoly('THANH_THEP', [
        p0 + m.perp * m.halfH,
        pOut + m.perp * m.halfH,
        pOut - m.perp * m.halfH,
        p0 - m.perp * m.halfH,
      ]);
      // Đường cắt vát nhận diện đầu thanh ngoài
      addLine(
        'THANH_THEP',
        (pOut + m.perp * (m.halfH + 10)).x,
        (pOut + m.perp * (m.halfH + 10)).y,
        (pOut - m.perp * (m.halfH + 10)).x,
        (pOut - m.perp * (m.halfH + 10)).y,
      );
      // Nhãn thanh + tiết diện + nội lực
      final lblPos = m.uDir * (m.overlapEndMm + 45.0) + m.perp * (m.halfH + 16.0);
      addText(
        'GHI_CHU',
        lblPos.x,
        lblPos.y,
        14.0,
        'T${m.member.elemIndex + 1} (${m.specLabel}) N=${m.member.forceKn.toStringAsFixed(1)} kN',
      );
      // Bu-lông (vòng lỗ d0 + chữ thập tâm)
      for (final b in m.bolts) {
        final r = 0.5 * p.boltSpec.d0Mm;
        addCircle('BU_LONG', b.x, b.y, r);
        addLine('BU_LONG', b.x - r * 1.4, b.y, b.x + r * 1.4, b.y);
        addLine('BU_LONG', b.x, b.y - r * 1.4, b.x, b.y + r * 1.4);
      }
      // Đường hàn góc
      for (final (wa, wb) in m.welds) {
        addLine('DUONG_HAN', wa.x, wa.y, wb.x, wb.y);
        addLine('DUONG_HAN', (wa + m.perp * 4).x, (wa + m.perp * 4).y, (wb + m.perp * 4).x, (wb + m.perp * 4).y);
      }
    }

    // Chốt bản lề Clevis
    if (p.detailType == ConnectionDetailType.pinnedClevis) {
      addCircle('BU_LONG', 0, 0, 0.5 * p.pinDiameterMm);
      addCircle('BU_LONG', 0, 0, 0.5 * p.pinDiameterMm + 16.0);
    }

    // 4. Chi tiết bản đế, sườn, bu-lông neo, móng bê tông / con lăn / lò xo theo hướng gối thực tế
    if (report.supportType == NodeSupportType.pin) {
      final bpC = g.outVec * 158.0;
      addRect(bpC, g.outVec, g.tangVec, p.basePlateThickMm, p.basePlateWidthMm, 'BAN_DE_MONG');
      addRect(bpC + g.outVec * (0.5 * p.basePlateThickMm + 50.0), g.outVec, g.tangVec, 100.0,
          p.basePlateWidthMm + 120.0, 'BAN_DE_MONG');
      for (final sgn in [-1.0, 1.0]) {
        final aBase = bpC + g.tangVec * (sgn * p.basePlateWidthMm * 0.36);
        final aTop = aBase - g.outVec * 38.0;
        final aBot = aBase + g.outVec * 115.0;
        addLine('BU_LONG', aTop.x, aTop.y, aBot.x, aBot.y);
        addCircle('BU_LONG', aTop.x, aTop.y, 10.0);
      }
    } else if (report.supportType == NodeSupportType.rollerX ||
        report.supportType == NodeSupportType.rollerXSpringX ||
        report.supportType == NodeSupportType.rollerY) {
      addRect(g.outVec * 150.0, g.outVec, g.tangVec, 22.0, p.basePlateWidthMm * 0.85, 'BAN_DE_MONG');
      addRect(g.outVec * 218.0, g.outVec, g.tangVec, 24.0, p.basePlateWidthMm, 'BAN_DE_MONG');
      addRect(g.outVec * 270.0, g.outVec, g.tangVec, 80.0, p.basePlateWidthMm + 100.0, 'BAN_DE_MONG');
      for (final off in [-55.0, 55.0]) {
        final rc = g.outVec * 184.0 + g.tangVec * off;
        addCircle('BU_LONG', rc.x, rc.y, 22.0);
      }
    }

    // 5. Đường kích thước phủ bì bản mã (KICH_THUOC)
    double gMinX = double.infinity, gMaxX = -double.infinity;
    double gMinY = double.infinity, gMaxY = -double.infinity;
    for (final q in g.gussetPoly) {
      gMinX = math.min(gMinX, q.x);
      gMaxX = math.max(gMaxX, q.x);
      gMinY = math.min(gMinY, q.y);
      gMaxY = math.max(gMaxY, q.y);
    }
    if (gMinX.isFinite) {
      final dyDim = gMaxY + 42.0;
      addLine('KICH_THUOC', gMinX, gMaxY + 6, gMinX, dyDim + 12);
      addLine('KICH_THUOC', gMaxX, gMaxY + 6, gMaxX, dyDim + 12);
      addLine('KICH_THUOC', gMinX, dyDim, gMaxX, dyDim);
      addText('KICH_THUOC', 0.5 * (gMinX + gMaxX) - 55, dyDim + 8, 15.0,
          'W_bm = ${(gMaxX - gMinX).toStringAsFixed(0)} mm');

      final dxDim = gMaxX + 42.0;
      addLine('KICH_THUOC', gMaxX + 6, gMinY, dxDim + 12, gMinY);
      addLine('KICH_THUOC', gMaxX + 6, gMaxY, dxDim + 12, gMaxY);
      addLine('KICH_THUOC', dxDim, gMinY, dxDim, gMaxY);
      addText('KICH_THUOC', dxDim + 12, 0.5 * (gMinY + gMaxY), 15.0,
          'H_bm = ${(gMaxY - gMinY).toStringAsFixed(0)} mm');
    }

    // 6. Khung bản vẽ & Khung tên kỹ thuật (KHUNG_TEN)
    final bx1 = g.minX - 60.0;
    final bx2 = g.maxX + 260.0;
    final by1 = g.minY - 140.0;
    final by2 = g.maxY + 110.0;
    addPoly('KHUNG_TEN', [_Pt(bx1, by1), _Pt(bx2, by1), _Pt(bx2, by2), _Pt(bx1, by2)]);
    addLine('KHUNG_TEN', bx1, by1 + 110.0, bx2, by1 + 110.0);
    addText(
      'GHI_CHU',
      bx1 + 20,
      by1 + 80,
      18.0,
      'BAN VE CAU TAO LIEN KET NUT N${report.nodeIndex + 1} (${report.supportType.shortLabel}) - TY LE 1:1 (mm)',
    );
    addText(
      'GHI_CHU',
      bx1 + 20,
      by1 + 52,
      13.5,
      'Ban ma: PL${p.gussetThicknessMm.toStringAsFixed(0)} (${report.gussetWidthMm.toStringAsFixed(0)}x${report.gussetHeightMm.toStringAsFixed(0)} mm) Thep ${p.steelGrade.code} | ${p.detailType.shortLabel} (${p.boltSpec.code}) | U_max = ${report.maxUtilizationPct.toStringAsFixed(1)}% (${report.allPassed ? "DAT" : "VUOT"})',
    );
    addText(
      'GHI_CHU',
      bx1 + 20,
      by1 + 24,
      12.0,
      'DH Bach Khoa TP.HCM | GVHD: PGS. TS Ngo Huu Cuong | HV: Lam Phuc Tam (2670621) - Vo Thanh Vang (2670624)',
    );

    addPair(0, 'ENDSEC');
    addPair(0, 'EOF');
    return buf.toString();
  }

  /// Xuất bản vẽ AutoCAD (.dxf) tỷ lệ 1:1 (mm) cho nút đang chọn
  static Future<String?> exportNodeDxf({
    required TrussModelData model,
    required NodeConnectionReport report,
  }) async {
    final dxf = buildDxfString(model: model, report: report);
    final bytes = Uint8List.fromList(utf8.encode(dxf));
    final fileName = 'BanVe_LienKet_Nut${report.nodeIndex + 1}_AutoCAD.dxf';
    return saveBinaryFile(fileName, bytes, 'application/dxf');
  }

  /// Xuất bản vẽ kỹ thuật cấu tạo liên kết dạng PDF vector (khổ A4 ngang chuẩn bản vẽ xưởng)
  static Future<String?> exportNodeBlueprintPdf({
    required TrussModelData model,
    required NodeConnectionReport report,
  }) async {
    final g = _buildGeometry(model, report);
    final p = report.params;
    final fontReg = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: fontReg, bold: fontBold));

    final navy = PdfColor.fromHex('#0F3D6E');
    final teal = PdfColor.fromHex('#0F766E');
    final slate = PdfColor.fromHex('#334155');
    final lightRow = PdfColor.fromHex('#F1F5F9');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (ctx) => pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: navy, width: 1.5)),
          padding: const pw.EdgeInsets.all(10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Tiêu đề bản vẽ kỹ thuật
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'BẢN VẼ CẤU TẠO CHI TIẾT LIÊN KẾT NÚT N${report.nodeIndex + 1} (${report.supportType.label})',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12.5, color: navy),
                      ),
                      pw.Text(
                        'Mô hình: ${model.name}  •  Gia công: ${p.detailType.label}  •  Thép ${p.steelGrade.code} (fy=${p.steelGrade.fyMpa.toStringAsFixed(0)} MPa)',
                        style: pw.TextStyle(fontSize: 8.5, color: slate),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: report.allPassed ? PdfColor.fromHex('#DCFCE7') : PdfColor.fromHex('#FEE2E2'),
                      border: pw.Border.all(
                        color: report.allPassed ? PdfColor.fromHex('#15803D') : PdfColor.fromHex('#B91C1C'),
                      ),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      '${report.allPassed ? "ĐẠT" : "VƯỢT"} — U_max = ${report.maxUtilizationPct.toStringAsFixed(1)}%',
                      style: pw.TextStyle(
                        fontSize: 9.0,
                        fontWeight: pw.FontWeight.bold,
                        color: report.allPassed ? PdfColor.fromHex('#15803D') : PdfColor.fromHex('#B91C1C'),
                      ),
                    ),
                  ),
                ],
              ),
              pw.Divider(color: navy, thickness: 1.0),
              // Phần chính: Bản vẽ vector CAD bên trái + Bảng kiểm tra & thông số bên phải
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Expanded(
                      flex: 6,
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('#F8FAFC'),
                          border: pw.Border.all(color: PdfColor.fromHex('#CBD5E1'), width: 0.8),
                        ),
                        child: pw.CustomPaint(
                          painter: (canvas, size) {
                            _paintPdfBlueprint(canvas, size, g);
                          },
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('THÔNG SỐ GIA CÔNG CHẾ TẠO',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.2, color: navy)),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            '• Bản mã: PL${p.gussetThicknessMm.toStringAsFixed(0)} (${report.gussetWidthMm.toStringAsFixed(0)} × ${report.gussetHeightMm.toStringAsFixed(0)} mm), thép ${p.steelGrade.code}\n'
                            '• Đầu thanh: ${p.detailType.shortLabel} (${p.detailType == ConnectionDetailType.boltedGusset ? "${p.boltsPerMember} × ${p.boltSpec.code}" : (p.detailType == ConnectionDetailType.weldedGusset ? "hf=${p.weldLegMm.toStringAsFixed(0)} mm, lw=${p.weldLengthMm.toStringAsFixed(0)} mm" : "Chốt Ø${p.pinDiameterMm.toStringAsFixed(0)} mm")})\n'
                            '• Bản đế gối: ${p.basePlateWidthMm.toStringAsFixed(0)}×${p.basePlateLengthMm.toStringAsFixed(0)}×${p.basePlateThickMm.toStringAsFixed(0)} mm (Hướng: ${g.dir.label})\n'
                            '• Phản lực nút: Rx=${report.rxKn.toStringAsFixed(2)} kN | Ry=${report.ryKn.toStringAsFixed(2)} kN',
                            style: const pw.TextStyle(fontSize: 7.8, lineSpacing: 2.0),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text('CÁC THANH QUY TỤ VÀO NÚT',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.0, color: teal)),
                          pw.SizedBox(height: 2),
                          pw.TableHelper.fromTextArray(
                            headerDecoration: pw.BoxDecoration(color: teal),
                            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 7.0),
                            cellStyle: const pw.TextStyle(fontSize: 6.9),
                            oddRowDecoration: pw.BoxDecoration(color: lightRow),
                            headers: ['Thanh', 'Tiết diện', 'N (kN)', 'U (%)'],
                            data: [
                              for (final m in g.members)
                                [
                                  'T${m.member.elemIndex + 1} (${m.member.label})',
                                  m.specLabel,
                                  m.member.forceKn.toStringAsFixed(1),
                                  '${m.member.activeUtilPct(p.detailType).toStringAsFixed(1)}%',
                                ],
                            ],
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text('KIỂM TRA CHỊU LỰC (TCVN 5575 / EN 1993-1-8)',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.0, color: navy)),
                          pw.SizedBox(height: 2),
                          pw.TableHelper.fromTextArray(
                            headerDecoration: pw.BoxDecoration(color: navy),
                            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 6.8),
                            cellStyle: const pw.TextStyle(fontSize: 6.6),
                            oddRowDecoration: pw.BoxDecoration(color: lightRow),
                            headers: ['Hạng mục', 'Tác dụng / Khả năng', 'U%', 'KQ'],
                            data: [
                              for (final c in report.checks.take(7))
                                [
                                  c.category,
                                  '${c.demandLabel} / ${c.capacityLabel}',
                                  '${c.utilizationPct.toStringAsFixed(1)}%',
                                  c.passed ? 'ĐẠT' : 'VƯỢT',
                                ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              // Khung tên bản vẽ dưới đáy
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#EFF6FF'),
                  border: pw.Border.all(color: navy, width: 0.9),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TRƯỜNG ĐH BÁCH KHOA – ĐHQG TP.HCM  |  GVHD: PGS. TS Ngô Hữu Cường',
                      style: pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold, color: navy),
                    ),
                    pw.Text(
                      'HV: Lâm Phúc Tâm (2670621) – Võ Thanh Vang (2670624)  |  vothanhvang@gmail.com  •  0973.993.494',
                      style: pw.TextStyle(fontSize: 7.6, color: slate),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final bytes = await pdf.save();
    final fileName = 'BanVe_LienKet_Nut${report.nodeIndex + 1}.pdf';
    return saveBinaryFile(fileName, bytes, 'application/pdf');
  }

  /// Vẽ bản vẽ CAD vector trực tiếp lên PdfGraphics (đầu thanh cắt ngắn thực tế, bản mã che khuất hoàn toàn!)
  static void _paintPdfBlueprint(PdfGraphics canvas, PdfPoint size, _NodeShopGeometry g) {
    final wMm = math.max(100.0, g.maxX - g.minX);
    final hMm = math.max(100.0, g.maxY - g.minY);
    final scale = math.min((size.x * 0.84) / wMm, (size.y * 0.84) / hMm);
    final cxMm = 0.5 * (g.minX + g.maxX);
    final cyMm = 0.5 * (g.minY + g.maxY);

    double px(double x) => 0.5 * size.x + (x - cxMm) * scale;
    double py(double y) => 0.5 * size.y + (y - cyMm) * scale;

    void drawPoly(List<_Pt> pts, {PdfColor? fill, PdfColor? stroke, double lw = 1.0}) {
      if (pts.length < 3) return;
      canvas.moveTo(px(pts.first.x), py(pts.first.y));
      for (int i = 1; i < pts.length; i++) {
        canvas.lineTo(px(pts[i].x), py(pts[i].y));
      }
      canvas.closePath();
      if (fill != null && stroke != null) {
        canvas.setFillColor(fill);
        canvas.setStrokeColor(stroke);
        canvas.setLineWidth(lw);
        canvas.fillAndStrokePath();
      } else if (fill != null) {
        canvas.setFillColor(fill);
        canvas.fillPath();
      } else if (stroke != null) {
        canvas.setStrokeColor(stroke);
        canvas.setLineWidth(lw);
        canvas.strokePath();
      }
    }

    void drawRect(_Pt c, _Pt aDir, _Pt wDir, double aLen, double wLen, PdfColor fill, PdfColor stroke) {
      final ha = 0.5 * aLen;
      final hw = 0.5 * wLen;
      drawPoly([
        c - aDir * ha - wDir * hw,
        c + aDir * ha - wDir * hw,
        c + aDir * ha + wDir * hw,
        c - aDir * ha + wDir * hw,
      ], fill: fill, stroke: stroke, lw: 0.9);
    }

    // 1. Lưới mờ & đường tim trục
    canvas.setStrokeColor(PdfColor.fromHex('#CBD5E1'));
    canvas.setLineWidth(0.5);
    canvas.drawLine(px(g.minX), py(0), px(g.maxX), py(0));
    canvas.drawLine(px(0), py(g.minY), px(0), py(g.maxY));
    canvas.strokePath();

    // 2. Vẽ các thanh thép đã cắt ngắn đầu thanh thực tế (TRƯỚC bản mã -> phần nằm sau bản mã bị che khuất hoàn toàn!)
    for (final m in g.members) {
      final p0 = m.uDir * m.setbackMm;
      final pOut = m.uDir * m.drawEndMm;
      final barFill = m.member.forceKn > 0.1
          ? PdfColor.fromHex('#FECACA')
          : (m.member.forceKn < -0.1 ? PdfColor.fromHex('#BAE6FD') : PdfColor.fromHex('#E2E8F0'));
      final barStroke = m.member.forceKn > 0.1
          ? PdfColor.fromHex('#DC2626')
          : (m.member.forceKn < -0.1 ? PdfColor.fromHex('#0284C7') : PdfColor.fromHex('#475569'));
      drawPoly([
        p0 + m.perp * m.halfH,
        pOut + m.perp * m.halfH,
        pOut - m.perp * m.halfH,
        p0 - m.perp * m.halfH,
      ], fill: barFill, stroke: barStroke, lw: 1.1);
    }

    // 3. Bản mã ĐẶC 100% vẽ đè lên vùng chồng lấn đầu thanh (che hoàn toàn nét khuất phía sau!)
    drawPoly(
      g.gussetPoly,
      fill: PdfColor.fromHex('#DBEAFE'),
      stroke: PdfColor.fromHex('#1D4ED8'),
      lw: 1.4,
    );

    // 4. Bu-lông / Đường hàn / Chốt Clevis nổi trên mặt bản mã
    final p = g.report.params;
    for (final m in g.members) {
      for (final b in m.bolts) {
        final r = math.max(2.2, 0.5 * p.boltSpec.d0Mm * scale);
        canvas.drawEllipse(px(b.x), py(b.y), r, r);
        canvas.setFillColor(PdfColor.fromHex('#FACC15'));
        canvas.setStrokeColor(PdfColor.fromHex('#1E293B'));
        canvas.setLineWidth(0.7);
        canvas.fillAndStrokePath();
      }
      for (final (wa, wb) in m.welds) {
        canvas.setStrokeColor(PdfColor.fromHex('#EA580C'));
        canvas.setLineWidth(2.6);
        canvas.drawLine(px(wa.x), py(wa.y), px(wb.x), py(wb.y));
        canvas.strokePath();
      }
    }
    if (p.detailType == ConnectionDetailType.pinnedClevis) {
      final rp = math.max(4.0, 0.5 * p.pinDiameterMm * scale);
      canvas.drawEllipse(px(0), py(0), rp, rp);
      canvas.setFillColor(PdfColor.fromHex('#F59E0B'));
      canvas.setStrokeColor(PdfColor.fromHex('#0F172A'));
      canvas.setLineWidth(1.0);
      canvas.fillAndStrokePath();
    }

    // 5. Bản đế, bu-lông neo, móng bê tông / gối con lăn đúng hướng gối
    if (g.report.supportType == NodeSupportType.pin) {
      final bpC = g.outVec * 158.0;
      drawRect(bpC + g.outVec * (0.5 * p.basePlateThickMm + 50.0), g.outVec, g.tangVec, 100.0,
          p.basePlateWidthMm + 120.0, PdfColor.fromHex('#CBD5E1'), PdfColor.fromHex('#475569'));
      drawRect(bpC, g.outVec, g.tangVec, p.basePlateThickMm, p.basePlateWidthMm,
          PdfColor.fromHex('#64748B'), PdfColor.fromHex('#0F172A'));
      for (final sgn in [-1.0, 1.0]) {
        final aBase = bpC + g.tangVec * (sgn * p.basePlateWidthMm * 0.36);
        final aTop = aBase - g.outVec * 38.0;
        final aBot = aBase + g.outVec * 115.0;
        canvas.setStrokeColor(PdfColor.fromHex('#CA8A04'));
        canvas.setLineWidth(1.8);
        canvas.drawLine(px(aTop.x), py(aTop.y), px(aBot.x), py(aBot.y));
        canvas.strokePath();
      }
    } else if (g.report.supportType == NodeSupportType.rollerX ||
        g.report.supportType == NodeSupportType.rollerXSpringX ||
        g.report.supportType == NodeSupportType.rollerY) {
      drawRect(g.outVec * 270.0, g.outVec, g.tangVec, 80.0, p.basePlateWidthMm + 100.0,
          PdfColor.fromHex('#CBD5E1'), PdfColor.fromHex('#475569'));
      drawRect(g.outVec * 150.0, g.outVec, g.tangVec, 22.0, p.basePlateWidthMm * 0.85,
          PdfColor.fromHex('#64748B'), PdfColor.fromHex('#0F172A'));
      drawRect(g.outVec * 218.0, g.outVec, g.tangVec, 24.0, p.basePlateWidthMm,
          PdfColor.fromHex('#64748B'), PdfColor.fromHex('#0F172A'));
      for (final off in [-55.0, 55.0]) {
        final rc = g.outVec * 184.0 + g.tangVec * off;
        final rr = math.max(3.5, 22.0 * scale);
        canvas.drawEllipse(px(rc.x), py(rc.y), rr, rr);
        canvas.setFillColor(PdfColor.fromHex('#38BDF8'));
        canvas.setStrokeColor(PdfColor.fromHex('#0F172A'));
        canvas.setLineWidth(0.9);
        canvas.fillAndStrokePath();
      }
    }

    // Dấu tim nút chuẩn
    canvas.setStrokeColor(PdfColor.fromHex('#0F3D6E'));
    canvas.setLineWidth(0.9);
    canvas.drawLine(px(-14), py(0), px(14), py(0));
    canvas.drawLine(px(0), py(-14), px(0), py(14));
    canvas.strokePath();
  }
}
