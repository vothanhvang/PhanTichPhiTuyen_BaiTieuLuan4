// ============================================================================
// KHUNG NHÌN 2D TƯƠNG TÁC CHO DẦM BÊ TÔNG CỐT THÉP PHI TUYẾN (PHƯƠNG PHÁP THỚ)
// ============================================================================
// Hiển thị đồng bộ trên một màn hình kỹ thuật trực quan:
//   1. Phần trên: Dầm BTCT biến dạng thực theo hàm dạng Hermite, bản đồ màu
//      nội lực/độ võng/ứng suất, vết nứt uốn thực tế từ mép dưới, thanh cốt thép
//      kéo/nén (đổi màu đỏ cam khi chảy dẻo), cốt cứng chữ I (nếu bật), đường
//      trục trung hòa biến thiên, gối tựa 2 đầu tùy chỉnh, tải 3 điểm / 4 điểm
//      với kích thước a (mm) & đường dao cắt phẫu thuật tương tác (chạm/kéo).
//   2. Phần dưới: Biểu đồ Mô-men uốn M(x) (kN·m) và Lực cắt V(x) (kN) căn thẳng
//      hàng theo trục dọc x ∈ [0, L] của dầm!
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/rc_beam_engine.dart';
import 'ansys_colorbar.dart';

class RcBeamViewport2D extends StatefulWidget {
  final RcBeamAnalysisResult result;
  final RcBeamAnalysisResult resultLinear;
  final RcBeamContourField field;
  final double deformScale;
  final double probeXNorm;
  final bool darkMode;
  final bool showColorBar;
  final ValueChanged<double> onProbeXChanged;
  final ValueChanged<bool>? onToggleColorBar;

  const RcBeamViewport2D({
    super.key,
    required this.result,
    required this.resultLinear,
    required this.field,
    required this.deformScale,
    required this.probeXNorm,
    required this.darkMode,
    this.showColorBar = true,
    required this.onProbeXChanged,
    this.onToggleColorBar,
  });

  @override
  State<RcBeamViewport2D> createState() => _RcBeamViewport2DState();
}

class _RcBeamViewport2DState extends State<RcBeamViewport2D> {
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  double _baseZoom = 1.0;
  Offset _lastFocal = Offset.zero;
  bool _panMode = false;
  bool _rightDrag = false;

  void _fitView() => setState(() {
        _zoom = 1.0;
        _pan = Offset.zero;
      });

  double _fieldValueForSection(RcSectionState sec, double vMm, double momentKnm) {
    switch (widget.field) {
      case RcBeamContourField.bendingMoment:
        return momentKnm;
      case RcBeamContourField.deflection:
        return vMm.abs();
      case RcBeamContourField.curvature:
        return sec.kappa * 1e6;
      case RcBeamContourField.concreteCompStress:
        return sec.sigmaTopConcMpa.abs();
      case RcBeamContourField.rebarStress:
        return sec.sigmaBotSteelMpa.abs();
      case RcBeamContourField.stiffnessRatio:
        return (100.0 * sec.eiEffNmm2 / math.max(1.0, widget.result.eiGrossNmm2)).clamp(0.0, 100.0);
    }
  }

  ({double minV, double maxV}) _computeRange() {
    double minV = double.infinity;
    double maxV = -double.infinity;
    for (final el in widget.result.elements) {
      for (int k = 0; k < 3; k++) {
        final gs = el.gaussSections[k];
        final xi = k == 0 ? 0.1127 : (k == 1 ? 0.5 : 0.8873);
        final v = (1.0 - xi) * el.dElem[1] + xi * el.dElem[4];
        final val = _fieldValueForSection(gs, v, gs.mForceNmm / 1e6);
        if (val < minV) minV = val;
        if (val > maxV) maxV = val;
      }
    }
    if (!minV.isFinite || !maxV.isFinite) return (minV: 0.0, maxV: 1.0);
    if ((maxV - minV).abs() < 1e-6) return (minV: minV - 1.0, maxV: maxV + 1.0);
    return (minV: minV, maxV: maxV);
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF06B6D4), size: 20),
            SizedBox(width: 8),
            Text('Hướng dẫn thao tác 2D — Dầm BTCT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          '• Chạm vào thân dầm hoặc biểu đồ M(x)/V(x): di chuyển mặt cắt phẫu thuật thớ dọc theo nhịp x/L.\n'
          '• Cuộn chuột / chụm 2 ngón: phóng to / thu nhỏ vùng nứt uốn.\n'
          '• Kéo chuột phải (hoặc bật Pan): dịch chuyển khung bản vẽ.\n'
          '• Đường nét đứt xanh lá trong dầm: quỹ đạo Trục trung hòa x_NA dịch chuyển lên trên tại vùng nứt.\n'
          '• Nét đỏ dọc đáy dầm: chiều sâu vết nứt uốn thực tế tính từ các thớ bê tông chịu kéo.',
          style: TextStyle(fontSize: 12.2, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Đã hiểu')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _computeRange();
    return LayoutBuilder(
      builder: (context, constraints) {
        final sz = Size(constraints.maxWidth, constraints.maxHeight);
        final padL = math.max(76.0, sz.width * 0.11);
        final padR = math.max(36.0, sz.width * 0.06);
        final usableW = math.max(120.0, (sz.width - padL - padR) * _zoom);
        final x0 = padL + _pan.dx + (sz.width - padL - padR - usableW) * 0.5;

        void updateProbeAt(Offset localPos) {
          final xNorm = ((localPos.dx - x0) / usableW).clamp(0.0, 1.0);
          widget.onProbeXChanged(xNorm);
        }

        return Stack(
          children: [
            Listener(
              onPointerDown: (e) => _rightDrag = (e.buttons & kSecondaryMouseButton) != 0,
              onPointerUp: (_) => _rightDrag = false,
              onPointerSignal: (s) {
                if (s is PointerScrollEvent) {
                  setState(() {
                    _zoom = (_zoom * (s.scrollDelta.dy < 0 ? 1.12 : 0.90)).clamp(0.6, 4.0);
                  });
                }
              },
              child: GestureDetector(
                onTapDown: (d) => updateProbeAt(d.localPosition),
                onScaleStart: (d) {
                  _baseZoom = _zoom;
                  _lastFocal = d.focalPoint;
                },
                onScaleUpdate: (d) {
                  final delta = d.focalPoint - _lastFocal;
                  _lastFocal = d.focalPoint;
                  if (_panMode || _rightDrag || d.pointerCount >= 2) {
                    setState(() {
                      if (d.scale != 1.0) _zoom = (_baseZoom * d.scale).clamp(0.6, 4.0);
                      _pan += delta;
                    });
                  } else {
                    updateProbeAt(d.localFocalPoint);
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: widget.darkMode
                          ? const [Color(0xFF0A1428), Color(0xFF060B16)]
                          : const [Color(0xFFF1F5F9), Color(0xFFFFFFFF)],
                    ),
                  ),
                  child: CustomPaint(
                    painter: _RcBeam2DPainter(
                      result: widget.result,
                      resultLinear: widget.resultLinear,
                      field: widget.field,
                      minVal: range.minV,
                      maxVal: range.maxV,
                      deformScale: widget.deformScale,
                      probeXNorm: widget.probeXNorm,
                      darkMode: widget.darkMode,
                      x0: x0,
                      beamPixelLen: usableW,
                      panY: _pan.dy,
                      zoom: _zoom,
                    ),
                  ),
                ),
              ),
            ),

            // Thang màu góc trên trái (có thể thu gọn)
            Positioned(
              left: 12,
              top: 12,
              child: widget.showColorBar
                  ? AnsysColorBar(
                      title: widget.field.label,
                      unit: widget.field.unit,
                      minVal: range.minV,
                      maxVal: range.maxV,
                      darkMode: widget.darkMode,
                      onHide: widget.onToggleColorBar != null ? () => widget.onToggleColorBar!(false) : null,
                    )
                  : ColorBarRestoreButton(
                      darkMode: widget.darkMode,
                      onShow: () => widget.onToggleColorBar?.call(true),
                    ),
            ),

            // Thanh điều khiển góc trên phải
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.darkMode ? const Color(0xD90F172A) : const Color(0xE6FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: widget.darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                ),
                child: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: Text(_panMode ? 'Pan' : 'Cắt thớ', style: const TextStyle(fontSize: 10.2)),
                      selected: _panMode,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) => setState(() => _panMode = v),
                    ),
                    InkWell(
                      onTap: _fitView,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: widget.darkMode ? 0.9 : 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Fit',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: widget.darkMode ? const Color(0xFF38BDF8) : const Color(0xFF0F3D6E),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Phóng to',
                      icon: const Icon(Icons.zoom_in, size: 17),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _zoom = (_zoom * 1.16).clamp(0.6, 4.0)),
                    ),
                    IconButton(
                      tooltip: 'Thu nhỏ',
                      icon: const Icon(Icons.zoom_out, size: 17),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _zoom = (_zoom / 1.16).clamp(0.6, 4.0)),
                    ),
                  ],
                ),
              ),
            ),

            // Nút trợ giúp nhỏ gọn góc dưới trái
            Positioned(
              left: 12,
              bottom: 10,
              child: InkWell(
                onTap: () => _showHelp(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: widget.darkMode ? const Color(0xCC0F172A) : const Color(0xE6FFFFFF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.55)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.help_outline, size: 14, color: Color(0xFF06B6D4)),
                      const SizedBox(width: 4),
                      Text(
                        'Thao tác 2D',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: widget.darkMode ? const Color(0xFFCBD5E1) : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RcBeam2DPainter extends CustomPainter {
  final RcBeamAnalysisResult result;
  final RcBeamAnalysisResult resultLinear;
  final RcBeamContourField field;
  final double minVal;
  final double maxVal;
  final double deformScale;
  final double probeXNorm;
  final bool darkMode;
  final double x0;
  final double beamPixelLen;
  final double panY;
  final double zoom;

  _RcBeam2DPainter({
    required this.result,
    required this.resultLinear,
    required this.field,
    required this.minVal,
    required this.maxVal,
    required this.deformScale,
    required this.probeXNorm,
    required this.darkMode,
    required this.x0,
    required this.beamPixelLen,
    required this.panY,
    required this.zoom,
  });

  double _valAt(RcSectionState sec, double vMm, double momentKnm) {
    switch (field) {
      case RcBeamContourField.bendingMoment:
        return momentKnm;
      case RcBeamContourField.deflection:
        return vMm.abs();
      case RcBeamContourField.curvature:
        return sec.kappa * 1e6;
      case RcBeamContourField.concreteCompStress:
        return sec.sigmaTopConcMpa.abs();
      case RcBeamContourField.rebarStress:
        return sec.sigmaBotSteelMpa.abs();
      case RcBeamContourField.stiffnessRatio:
        return (100.0 * sec.eiEffNmm2 / math.max(1.0, result.eiGrossNmm2)).clamp(0.0, 100.0);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cfg = result.config;
    final pxPerMm = beamPixelLen / math.max(100.0, cfg.spanMm);
    // Phóng đại chiều cao dầm nhẹ để nhìn rõ vết nứt & cốt thép nhưng vẫn giữ tỷ lệ L/h thực tế!
    final beamHPx = (cfg.heightMm * pxPerMm * 1.15).clamp(42.0, math.min(86.0, size.height * 0.16)).toDouble();
    final beamCenterY = size.height * 0.34 + panY;
    final splitY = size.height * 0.60;

    // 1. Lưới kỹ thuật mảnh
    final gridPaint = Paint()
      ..color = darkMode ? const Color(0xFF132238) : const Color(0xFFE2E8F0)
      ..strokeWidth = 0.7;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Đường phân cách giữa dầm biến dạng (trên) và biểu đồ M(x), V(x) (dưới)
    canvas.drawLine(
      Offset(0, splitY),
      Offset(size.width, splitY),
      Paint()
        ..color = darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)
        ..strokeWidth = 1.2,
    );

    double toSx(double xMm) => x0 + (xMm / cfg.spanMm) * beamPixelLen;
    // Độ võng hiển thị tỷ lệ (vMm âm là võng xuống -> y màn hình tăng)
    final maxRawPx = result.maxAbsDeflectionMm * deformScale * pxPerMm;
    final effectiveScale = maxRawPx > (size.height * 0.14)
        ? (size.height * 0.14) / math.max(1e-6, result.maxAbsDeflectionMm * pxPerMm)
        : deformScale;
    double deflPx(double vMm) => -vMm * effectiveScale * pxPerMm;

    // 2. Đường bao dầm ban đầu (chưa biến dạng, nét đứt mờ)
    final ghostRect = Rect.fromLTWH(x0, beamCenterY - 0.5 * beamHPx, beamPixelLen, beamHPx);
    canvas.drawRect(
      ghostRect,
      Paint()
        ..color = darkMode ? const Color(0x5564748B) : const Color(0x6664748B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    // 3. Lấy mẫu mịn dọc từng phần tử Hermite để vẽ dầm BTCT biến dạng có bản đồ màu liên tục
    final spanVal = (maxVal - minVal).abs() < 1e-9 ? 1.0 : (maxVal - minVal);
    final topPts = <Offset>[];
    final botPts = <Offset>[];
    final naPts = <Offset>[];
    final topBarPts = <Offset>[];
    final botBarPts = <Offset>[];
    final coreTopPts = <Offset>[];
    final coreBotPts = <Offset>[];
    final crackSegments = <(Offset, Offset)>[];
    final botBarYielded = <bool>[];
    final momentPts = <(double xMm, double mKnm)>[];
    final shearPts = <(double xMm, double vKn)>[];

    final coverBotFrac = (cfg.coverBotMm / cfg.heightMm).clamp(0.05, 0.35);
    final coverTopFrac = (cfg.coverTopMm / cfg.heightMm).clamp(0.05, 0.35);
    final coreHalfFrac = (0.5 * cfg.coreHMm / cfg.heightMm).clamp(0.08, 0.42);

    for (final el in result.elements) {
      const sub = 6;
      for (int s = 0; s < sub; s++) {
        final xi0 = s / sub;
        final xi1 = (s + 1) / sub;
        final xiM = 0.5 * (xi0 + xi1);
        final p0 = RcBeamFiberEngine.probeBeamAt(result, (el.x1Mm + xi0 * el.lengthMm) / cfg.spanMm);
        final p1 = RcBeamFiberEngine.probeBeamAt(result, (el.x1Mm + xi1 * el.lengthMm) / cfg.spanMm);
        final pM = RcBeamFiberEngine.probeBeamAt(result, (el.x1Mm + xiM * el.lengthMm) / cfg.spanMm);

        final sx0 = toSx(el.x1Mm + xi0 * el.lengthMm);
        final sx1 = toSx(el.x1Mm + xi1 * el.lengthMm);
        final cy0 = beamCenterY + deflPx(p0.vMm);
        final cy1 = beamCenterY + deflPx(p1.vMm);

        final tCol = ((_valAt(pM.section, pM.vMm, pM.momentKnm) - minVal) / spanVal).clamp(0.0, 1.0);
        final segCol = ansysRainbowColor(tCol);

        final quad = Path()
          ..moveTo(sx0, cy0 - 0.5 * beamHPx)
          ..lineTo(sx1, cy1 - 0.5 * beamHPx)
          ..lineTo(sx1, cy1 + 0.5 * beamHPx)
          ..lineTo(sx0, cy0 + 0.5 * beamHPx)
          ..close();
        canvas.drawPath(quad, Paint()..color = segCol.withValues(alpha: darkMode ? 0.72 : 0.65));

        if (topPts.isEmpty) {
          topPts.add(Offset(sx0, cy0 - 0.5 * beamHPx));
          botPts.add(Offset(sx0, cy0 + 0.5 * beamHPx));
          topBarPts.add(Offset(sx0, cy0 - 0.5 * beamHPx + coverTopFrac * beamHPx));
          botBarPts.add(Offset(sx0, cy0 + 0.5 * beamHPx - coverBotFrac * beamHPx));
          botBarYielded.add(p0.section.steelYielded);
          coreTopPts.add(Offset(sx0, cy0 - coreHalfFrac * beamHPx));
          coreBotPts.add(Offset(sx0, cy0 + coreHalfFrac * beamHPx));
          naPts.add(Offset(sx0, cy0 - 0.5 * beamHPx + (p0.section.xNeutralDepthMm / cfg.heightMm) * beamHPx));
        }
        topPts.add(Offset(sx1, cy1 - 0.5 * beamHPx));
        botPts.add(Offset(sx1, cy1 + 0.5 * beamHPx));
        topBarPts.add(Offset(sx1, cy1 - 0.5 * beamHPx + coverTopFrac * beamHPx));
        botBarPts.add(Offset(sx1, cy1 + 0.5 * beamHPx - coverBotFrac * beamHPx));
        botBarYielded.add(p1.section.steelYielded);
        coreTopPts.add(Offset(sx1, cy1 - coreHalfFrac * beamHPx));
        coreBotPts.add(Offset(sx1, cy1 + coreHalfFrac * beamHPx));
        naPts.add(Offset(sx1, cy1 - 0.5 * beamHPx + (p1.section.xNeutralDepthMm / cfg.heightMm) * beamHPx));

        // Vết nứt uốn bê tông thực tế tại tâm dải (vẽ từ mép dưới hướng lên đúng độ sâu vết nứt!)
        if (pM.section.hasCracked && pM.section.crackDepthMm > 5.0) {
          final sxM = 0.5 * (sx0 + sx1);
          final cyM = 0.5 * (cy0 + cy1);
          final crackPx = (pM.section.crackDepthMm / cfg.heightMm).clamp(0.0, 0.92).toDouble() * beamHPx;
          crackSegments.add((
            Offset(sxM, cyM + 0.5 * beamHPx),
            Offset(sxM, cyM + 0.5 * beamHPx - crackPx),
          ));
        }
      }
      momentPts.add((el.x1Mm, el.m1Knm));
      momentPts.add((el.x2Mm, el.m2Knm));
      shearPts.add((el.x1Mm, el.vShearKn));
      shearPts.add((el.x2Mm, el.vShearKn));
    }

    // Đường viền trên/dưới dầm BTCT
    final outlinePaint = Paint()
      ..color = darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9;
    void drawPolyline(List<Offset> pts, Paint p) {
      if (pts.length < 2) return;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, p);
    }

    drawPolyline(topPts, outlinePaint);
    drawPolyline(botPts, outlinePaint);
    if (topPts.isNotEmpty && botPts.isNotEmpty) {
      canvas.drawLine(topPts.first, botPts.first, outlinePaint);
      canvas.drawLine(topPts.last, botPts.last, outlinePaint);
    }

    // 4. Dầm cốt cứng thép hình chữ I (nếu bật)
    if (cfg.hasRigidCore && coreTopPts.length >= 2) {
      final coreFill = Path()..moveTo(coreTopPts.first.dx, coreTopPts.first.dy);
      for (int i = 1; i < coreTopPts.length; i++) {
        coreFill.lineTo(coreTopPts[i].dx, coreTopPts[i].dy);
      }
      for (int i = coreBotPts.length - 1; i >= 0; i--) {
        coreFill.lineTo(coreBotPts[i].dx, coreBotPts[i].dy);
      }
      coreFill.close();
      canvas.drawPath(coreFill, Paint()..color = const Color(0xFF60A5FA).withValues(alpha: 0.35));
      final coreFlange = Paint()
        ..color = const Color(0xFF93C5FD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6;
      drawPolyline(coreTopPts, coreFlange);
      drawPolyline(coreBotPts, coreFlange);
    }

    // 5. Thanh cốt thép dọc đỉnh (As') và đáy (As — sáng đỏ cam tại vùng chảy dẻo!)
    if (cfg.asTopMm2 > 0) {
      drawPolyline(
        topBarPts,
        Paint()
          ..color = const Color(0xFFCBD5E1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }
    if (cfg.asBotMm2 > 0 && botBarPts.length >= 2) {
      for (int i = 0; i < botBarPts.length - 1; i++) {
        final yld = botBarYielded[i] || botBarYielded[i + 1];
        canvas.drawLine(
          botBarPts[i],
          botBarPts[i + 1],
          Paint()
            ..color = yld ? const Color(0xFFFF3B30) : const Color(0xFFFACC15)
            ..strokeWidth = yld ? 4.0 : 3.0
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // 6. Vết nứt uốn thực tế từ mép dưới bê tông
    final crackPaint = Paint()
      ..color = darkMode ? const Color(0xFFFF4D6D) : const Color(0xFFB91C1C)
      ..strokeWidth = 1.5;
    for (final seg in crackSegments) {
      canvas.drawLine(seg.$1, seg.$2, crackPaint);
    }

    // 7. Quỹ đạo Trục trung hòa x_NA (nét đứt xanh lá sáng)
    if (naPts.length >= 2) {
      final naPaint = Paint()
        ..color = const Color(0xFF4ADE80)
        ..strokeWidth = 1.6;
      for (int i = 0; i < naPts.length - 1; i += 2) {
        canvas.drawLine(naPts[i], naPts[i + 1], naPaint);
      }
    }

    // 8. Nút lưới PTHH (N1..Nn) dọc trục dầm
    for (int i = 0; i < result.nNodes; i++) {
      final sx = toSx(result.xNodesMm[i]);
      final sy = beamCenterY + deflPx(result.dGlobal[3 * i + 1]);
      canvas.drawCircle(Offset(sx, sy), 3.3, Paint()..color = darkMode ? Colors.white : const Color(0xFF0F172A));
      if (result.nNodes <= 11 || i == 0 || i == result.nNodes - 1 || i == result.nNodes ~/ 2) {
        _drawText(
          canvas,
          Offset(sx - 8, sy - 0.5 * beamHPx - 16),
          'N${i + 1}',
          darkMode ? const Color(0xFF94A3B8) : const Color(0xFF334155),
          8.8,
        );
      }
    }

    // 9. Ký hiệu gối tựa 2 đầu tùy chỉnh + giá trị phản lực R_A, R_B
    final leftSupY = beamCenterY + deflPx(result.dGlobal[1]) + 0.5 * beamHPx;
    final rightSupY = beamCenterY + deflPx(result.dGlobal[3 * (result.nNodes - 1) + 1]) + 0.5 * beamHPx;
    _drawSupport(canvas, Offset(toSx(0), leftSupY), cfg.leftSupport, isLeft: true, reactionKn: result.rLeftKn);
    _drawSupport(canvas, Offset(toSx(cfg.spanMm), rightSupY), cfg.rightSupport, isLeft: false, reactionKn: result.rRightKn);

    // 10. Ngoại lực tập trung (3 điểm tại a hoặc 4 điểm tại a và L - a) + kích thước a (mm)
    final a = cfg.effectiveAMm;
    final loadXs = cfg.loadType == RcBeamLoadType.threePoint ? [a] : [a, cfg.spanMm - a];
    final loadMag = cfg.loadType == RcBeamLoadType.threePoint ? cfg.loadQKn : 0.5 * cfg.loadQKn;
    for (int k = 0; k < loadXs.length; k++) {
      final lx = loadXs[k];
      final pr = RcBeamFiberEngine.probeBeamAt(result, lx / cfg.spanMm);
      final sx = toSx(lx);
      final topY = beamCenterY + deflPx(pr.vMm) - 0.5 * beamHPx;
      _drawArrow(canvas, Offset(sx, topY - 46), Offset(sx, topY - 3), const Color(0xFFFF2E55), 3.0);
      final lbl = cfg.loadType == RcBeamLoadType.threePoint
          ? 'Q = ${loadMag.toStringAsFixed(1)} kN'
          : 'Q/2 = ${loadMag.toStringAsFixed(1)} kN';
      _drawText(canvas, Offset(sx - 34, topY - 62), lbl, const Color(0xFFFF4D6D), 10.2, bold: true);
    }

    // Đường kích thước khoảng cách a (mm) và nhịp L (mm)
    final dimY = beamCenterY - 0.5 * beamHPx - 28;
    _drawDimLine(canvas, toSx(0), toSx(a), dimY, 'a = ${a.toStringAsFixed(0)} mm');
    final spanDimY = beamCenterY + 0.5 * beamHPx + 42;
    _drawDimLine(
      canvas,
      toSx(0),
      toSx(cfg.spanMm),
      spanDimY,
      'L = ${cfg.spanMm.toStringAsFixed(0)} mm  (b×h = ${cfg.widthMm.toStringAsFixed(0)}×${cfg.heightMm.toStringAsFixed(0)}, L/h = ${cfg.spanToDepthRatio.toStringAsFixed(1)})',
    );

    // 11. BIỂU ĐỒ MÔ-MEN UỐN M(x) & LỰC CẮT V(x) BÊN DƯỚI (căn thẳng theo x ∈ [0, L])
    final diagTop = splitY + 10;
    final diagH = math.max(96.0, size.height - diagTop - 16);
    final mAxisY = diagTop + diagH * 0.12;
    final mAmpPx = diagH * 0.30;
    final vAxisY = diagTop + diagH * 0.78;
    final vAmpPx = diagH * 0.15;

    // Trục 0 của biểu đồ M(x)
    canvas.drawLine(
      Offset(x0, mAxisY),
      Offset(x0 + beamPixelLen, mAxisY),
      Paint()..color = darkMode ? const Color(0xFF475569) : const Color(0xFF64748B)..strokeWidth = 1.1,
    );
    _drawText(
      canvas,
      Offset(12, mAxisY - 12),
      'Biểu đồ M(x)\n(kN·m)',
      const Color(0xFFF59E0B),
      9.6,
      bold: true,
    );
    if (momentPts.length >= 2) {
      final mScale = math.max(1e-3, result.mMaxKnm);
      final mPath = Path()..moveTo(toSx(momentPts.first.$1), mAxisY);
      for (final pt in momentPts) {
        // Quy ước kết cấu: mô-men căng thớ dưới (dương) vẽ xuống dưới trục 0!
        mPath.lineTo(toSx(pt.$1), mAxisY + (pt.$2 / mScale) * mAmpPx);
      }
      mPath.lineTo(toSx(momentPts.last.$1), mAxisY);
      mPath.close();
      canvas.drawPath(mPath, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.25));
      canvas.drawPath(
        mPath,
        Paint()
          ..color = const Color(0xFFF59E0B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      _drawText(
        canvas,
        Offset(toSx(a) - 48, mAxisY + mAmpPx + 4),
        'M_max = ${result.mMaxKnm.toStringAsFixed(2)} kN·m (${cfg.loadType == RcBeamLoadType.threePoint && (a - 0.5 * cfg.spanMm).abs() < 1.0 ? "QL/4" : "PTHH"})',
        const Color(0xFFFBBF24),
        9.6,
        bold: true,
      );
    }

    // Trục 0 của biểu đồ Lực cắt V(x)
    canvas.drawLine(
      Offset(x0, vAxisY),
      Offset(x0 + beamPixelLen, vAxisY),
      Paint()..color = darkMode ? const Color(0xFF475569) : const Color(0xFF64748B)..strokeWidth = 1.1,
    );
    _drawText(
      canvas,
      Offset(12, vAxisY - 12),
      'Biểu đồ V(x)\n(kN)',
      const Color(0xFF38BDF8),
      9.6,
      bold: true,
    );
    if (shearPts.length >= 2) {
      final vScale = math.max(1e-3, result.vMaxKn);
      final vPath = Path()..moveTo(toSx(shearPts.first.$1), vAxisY);
      for (final pt in shearPts) {
        vPath.lineTo(toSx(pt.$1), vAxisY - (pt.$2 / vScale) * vAmpPx);
      }
      vPath.lineTo(toSx(shearPts.last.$1), vAxisY);
      vPath.close();
      canvas.drawPath(vPath, Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.22));
      canvas.drawPath(
        vPath,
        Paint()
          ..color = const Color(0xFF38BDF8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      _drawText(
        canvas,
        Offset(x0 + 6, vAxisY - vAmpPx - 13),
        '+${result.vMaxKn.toStringAsFixed(1)} kN',
        const Color(0xFF38BDF8),
        9.0,
        bold: true,
      );
    }

    // 12. Đường dao cắt phẫu thuật tương tác (cyan) xuyên suốt từ dầm xuống biểu đồ M(x), V(x)!
    final probe = RcBeamFiberEngine.probeBeamAt(result, probeXNorm);
    final probeSx = toSx(probeXNorm * cfg.spanMm);
    canvas.drawLine(
      Offset(probeSx, beamCenterY - 0.5 * beamHPx - 14),
      Offset(probeSx, size.height - 10),
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeWidth = 1.8,
    );
    final eiPct = 100.0 * probe.section.eiEffNmm2 / math.max(1.0, result.eiGrossNmm2);
    final badgeText =
        'Lát cắt x=${(probeXNorm * cfg.spanMm).toStringAsFixed(0)} mm | M=${probe.momentKnm.toStringAsFixed(1)} kN·m\n'
        'v=${probe.vMm.toStringAsFixed(2)} mm • x_NA=${probe.section.xNeutralDepthMm.toStringAsFixed(0)} mm • EI=${eiPct.toStringAsFixed(0)}%';
    final badgeTp = TextPainter(
      text: TextSpan(
        text: badgeText,
        style: TextStyle(
          color: darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
          fontSize: 8.6,
          fontWeight: FontWeight.bold,
          height: 1.28,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(180.0, size.width - 28.0));
    final boxW = badgeTp.width + 14.0;
    final boxH = badgeTp.height + 10.0;
    final badgeX = (probeSx + 8).clamp(12.0, math.max(12.0, size.width - boxW - 10.0)).toDouble();
    final boxY = splitY - boxH - 6.0;
    final infoRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeX, boxY, boxW, boxH),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      infoRect,
      Paint()..color = darkMode ? const Color(0xE60B1528) : const Color(0xF0FFFFFF),
    );
    canvas.drawRRect(
      infoRect,
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    badgeTp.paint(canvas, Offset(badgeX + 7.0, boxY + 5.0));
  }

  void _drawSupport(Canvas canvas, Offset p, BeamSupportType sup, {required bool isLeft, required double reactionKn}) {
    final stroke = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final fill = Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.25);

    if (sup == BeamSupportType.pin) {
      final tri = Path()
        ..moveTo(p.dx, p.dy)
        ..lineTo(p.dx - 11, p.dy + 16)
        ..lineTo(p.dx + 11, p.dy + 16)
        ..close();
      canvas.drawPath(tri, fill);
      canvas.drawPath(tri, stroke);
      canvas.drawLine(Offset(p.dx - 15, p.dy + 16), Offset(p.dx + 15, p.dy + 16), stroke);
    } else if (sup == BeamSupportType.roller) {
      final tri = Path()
        ..moveTo(p.dx, p.dy)
        ..lineTo(p.dx - 10, p.dy + 13)
        ..lineTo(p.dx + 10, p.dy + 13)
        ..close();
      canvas.drawPath(tri, fill);
      canvas.drawPath(tri, stroke);
      canvas.drawCircle(Offset(p.dx - 6, p.dy + 17), 3.3, stroke);
      canvas.drawCircle(Offset(p.dx + 6, p.dy + 17), 3.3, stroke);
      canvas.drawLine(Offset(p.dx - 15, p.dy + 21), Offset(p.dx + 15, p.dy + 21), stroke);
    } else if (sup == BeamSupportType.fixed) {
      final dxWall = isLeft ? -10.0 : 10.0;
      canvas.drawRect(
        Rect.fromLTRB(math.min(p.dx, p.dx + dxWall), p.dy - 36, math.max(p.dx, p.dx + dxWall), p.dy + 12),
        fill,
      );
      canvas.drawLine(Offset(p.dx, p.dy - 36), Offset(p.dx, p.dy + 12), stroke);
    } else if (sup == BeamSupportType.spring) {
      final sp = Path()..moveTo(p.dx, p.dy);
      for (int k = 1; k <= 5; k++) {
        sp.lineTo(p.dx + (k.isOdd ? -7 : 7), p.dy + k * 4.0);
      }
      sp.lineTo(p.dx, p.dy + 23);
      canvas.drawPath(sp, stroke..color = const Color(0xFFF59E0B));
      canvas.drawLine(Offset(p.dx - 12, p.dy + 23), Offset(p.dx + 12, p.dy + 23), stroke);
    }
    if (sup != BeamSupportType.free) {
      _drawText(
        canvas,
        Offset(p.dx - 26, p.dy + 24),
        'R${isLeft ? "A" : "B"}=${reactionKn.toStringAsFixed(1)} kN',
        const Color(0xFF10B981),
        9.2,
        bold: true,
      );
    }
  }

  void _drawDimLine(Canvas canvas, double xa, double xb, double y, String label) {
    final p = Paint()
      ..color = darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(xa, y), Offset(xb, y), p);
    canvas.drawLine(Offset(xa, y - 5), Offset(xa, y + 5), p);
    canvas.drawLine(Offset(xb, y - 5), Offset(xb, y + 5), p);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: darkMode ? const Color(0xFFCBD5E1) : const Color(0xFF1E293B),
          fontSize: 9.2,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(0.5 * (xa + xb) - 0.5 * tp.width, y - tp.height - 2));
  }

  void _drawArrow(Canvas canvas, Offset a, Offset b, Color col, double w) {
    final p = Paint()
      ..color = col
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, p);
    final dir = (b - a);
    final l = dir.distance;
    if (l < 1e-3) return;
    final u = dir / l;
    final n = Offset(-u.dy, u.dx);
    final head = Path()
      ..moveTo(b.dx, b.dy)
      ..lineTo(b.dx - u.dx * 10 + n.dx * 5, b.dy - u.dy * 10 + n.dy * 5)
      ..lineTo(b.dx - u.dx * 10 - n.dx * 5, b.dy - u.dy * 10 - n.dy * 5)
      ..close();
    canvas.drawPath(head, Paint()..color = col);
  }

  void _drawText(Canvas canvas, Offset pos, String text, Color col, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: col,
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _RcBeam2DPainter old) => true;
}
