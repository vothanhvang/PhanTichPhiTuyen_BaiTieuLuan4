// ============================================================================
// CỬA SỔ MÔ PHỎNG 2D CHUẨN ANSYS MECHANICAL (PAN, ZOOM, KHẢO SÁT CHẠM, CẮT)
// ============================================================================
// Tính năng:
//   - Hiển thị cấu hình ban đầu (nét đứt) và cấu hình biến dạng phóng đại.
//   - Tô màu trường kết quả theo bảng màu cầu vồng ANSYS (Ứng suất σ, Biến dạng ε,
//     Lực dọc N, Chuyển vị ||u||, Mật độ năng lượng u₀).
//   - Kéo để Pan, cuộn chuột / chụm tay để Zoom.
//   - NHẤN VÀO BẤT KỲ VỊ TRÍ NÀO TRÊN BẤT KỲ THANH NÀO để đặt đầu dò khảo sát
//     (Probe Marker) và lưỡi cắt phẫu thuật tại đúng vị trí ξ ∈ [0, 1]!
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/calfem_engine.dart';
import 'ansys_colorbar.dart';

class AnsysViewport2D extends StatefulWidget {
  final TrussModelData model;
  final TrussAnalysisResult result;
  final ContourField field;
  final double deformScale;
  final double playbackFraction;
  final int selectedElem;
  final double probeXi;
  final bool surgicalMode;
  final bool darkMode;
  final void Function(int elemIndex, double xi) onProbeChanged;

  const AnsysViewport2D({
    super.key,
    required this.model,
    required this.result,
    required this.field,
    required this.deformScale,
    required this.playbackFraction,
    required this.selectedElem,
    required this.probeXi,
    required this.surgicalMode,
    required this.darkMode,
    required this.onProbeChanged,
  });

  @override
  State<AnsysViewport2D> createState() => _AnsysViewport2DState();
}

class _AnsysViewport2DState extends State<AnsysViewport2D> {
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  double _baseZoom = 1.0;
  Offset _lastFocal = Offset.zero;

  void _resetView() {
    setState(() {
      _zoom = 1.0;
      _pan = Offset.zero;
    });
  }

  List<double> _fieldValuesPerElem(double frac) {
    final ne = widget.model.nElems;
    switch (widget.field) {
      case ContourField.axialStress:
        return [for (int e = 0; e < ne; e++) widget.result.stressMpa[e] * frac];
      case ContourField.axialStrain:
        return [for (int e = 0; e < ne; e++) widget.result.strain[e] * 1e6 * frac];
      case ContourField.axialForce:
        return [for (int e = 0; e < ne; e++) widget.result.nForcesN[e] / 1000.0 * frac];
      case ContourField.displacement:
        return [
          for (int e = 0; e < ne; e++)
            () {
              final ni = widget.model.conn[e][0] - 1;
              final nj = widget.model.conn[e][1] - 1;
              final u1 = math.sqrt(math.pow(widget.result.uMm[2 * ni], 2) +
                  math.pow(widget.result.uMm[2 * ni + 1], 2));
              final u2 = math.sqrt(math.pow(widget.result.uMm[2 * nj], 2) +
                  math.pow(widget.result.uMm[2 * nj + 1], 2));
              return 0.5 * (u1 + u2) * frac;
            }()
        ];
      case ContourField.strainEnergyDensity:
        return [
          for (int e = 0; e < ne; e++)
            0.5 * widget.result.stressMpa[e] * widget.result.strain[e] * 1000.0 * frac * frac
        ];
    }
  }

  _Transform2D _computeTransform(Size size) {
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final c in widget.model.coords) {
      minX = math.min(minX, c[0]);
      maxX = math.max(maxX, c[0]);
      minY = math.min(minY, c[1]);
      maxY = math.max(maxY, c[1]);
    }
    final w = math.max(100.0, maxX - minX);
    final h = math.max(100.0, maxY - minY);
    final padW = size.width * 0.66;
    final padH = size.height * 0.64;
    final baseScale = math.min(padW / w, padH / h) * _zoom;
    final cx = 0.5 * (minX + maxX);
    final cy = 0.5 * (minY + maxY);
    return _Transform2D(
      scale: baseScale,
      cx: cx,
      cy: cy,
      screenCenter: Offset(size.width * 0.52, size.height * 0.54) + _pan,
    );
  }

  void _handleTapDown(TapDownDetails details, Size size) {
    final tf = _computeTransform(size);
    final pTap = details.localPosition;
    final scaleDef = widget.deformScale * widget.playbackFraction;

    int bestElem = widget.selectedElem;
    double bestXi = widget.probeXi;
    double bestDist = 42.0;

    for (int e = 0; e < widget.model.nElems; e++) {
      final ni = widget.model.conn[e][0] - 1;
      final nj = widget.model.conn[e][1] - 1;
      final a = tf.toScreen(
        widget.model.coords[ni][0] + scaleDef * widget.result.uMm[2 * ni],
        widget.model.coords[ni][1] + scaleDef * widget.result.uMm[2 * ni + 1],
      );
      final b = tf.toScreen(
        widget.model.coords[nj][0] + scaleDef * widget.result.uMm[2 * nj],
        widget.model.coords[nj][1] + scaleDef * widget.result.uMm[2 * nj + 1],
      );
      final ab = b - a;
      final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
      if (ab2 < 1e-6) continue;
      final t = (((pTap.dx - a.dx) * ab.dx + (pTap.dy - a.dy) * ab.dy) / ab2).clamp(0.0, 1.0);
      final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
      final d = (pTap - proj).distance;
      if (d < bestDist) {
        bestDist = d;
        bestElem = e;
        bestXi = t;
      }
    }
    if (bestDist < 42.0) {
      widget.onProbeChanged(bestElem, bestXi);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vals = _fieldValuesPerElem(widget.playbackFraction);
    // Khóa cố định thang đo [minV, maxV] theo trạng thái 100% tải (frac = 1.0)
    // để khi chạy mô phỏng video tăng tải (0% → 100%), dải màu Gradient trên từng thanh
    // biến đổi liên tục theo thời gian thực từ xanh dương đậm → lơ → lá → vàng → cam → đỏ!
    final fullVals = _fieldValuesPerElem(1.0);
    double minV = fullVals.reduce(math.min);
    double maxV = fullVals.reduce(math.max);
    if (widget.field == ContourField.displacement) {
      minV = 0.0;
      maxV = 0.0;
      for (int i = 0; i < widget.model.nNodes; i++) {
        final uMag = math.sqrt(
          math.pow(widget.result.uMm[2 * i], 2) +
              math.pow(widget.result.uMm[2 * i + 1], 2),
        );
        if (uMag > maxV) maxV = uMag;
      }
    } else if (widget.field == ContourField.strainEnergyDensity) {
      minV = 0.0;
    } else {
      minV = math.min(0.0, minV);
      maxV = math.max(0.0, maxV);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final tf = _computeTransform(size);
        return Stack(
          children: [
            Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  setState(() {
                    final factor = event.scrollDelta.dy < 0 ? 1.12 : 0.89;
                    _zoom = (_zoom * factor).clamp(0.4, 5.0);
                  });
                }
              },
              child: GestureDetector(
                onTapDown: (d) => _handleTapDown(d, size),
                onScaleStart: (d) {
                  _baseZoom = _zoom;
                  _lastFocal = d.focalPoint;
                },
                onScaleUpdate: (d) {
                  setState(() {
                    if (d.scale != 1.0) {
                      _zoom = (_baseZoom * d.scale).clamp(0.4, 5.0);
                    }
                    _pan += (d.focalPoint - _lastFocal);
                    _lastFocal = d.focalPoint;
                  });
                },
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: widget.darkMode ? const Color(0xFF090F1D) : const Color(0xFFF1F5F9),
                  child: CustomPaint(
                    painter: _Ansys2DPainter(
                      model: widget.model,
                      result: widget.result,
                      field: widget.field,
                      values: vals,
                      minVal: minV,
                      maxVal: maxV,
                      tf: tf,
                      deformScale: widget.deformScale * widget.playbackFraction,
                      playbackFraction: widget.playbackFraction,
                      selectedElem: widget.selectedElem,
                      probeXi: widget.probeXi,
                      surgicalMode: widget.surgicalMode,
                      darkMode: widget.darkMode,
                    ),
                  ),
                ),
              ),
            ),
            // Thang màu ANSYS góc trên trái
            Positioned(
              left: 12,
              top: 12,
              child: AnsysColorBar(
                title: widget.field.label,
                unit: widget.field.unit,
                minVal: minV,
                maxVal: maxV,
                darkMode: widget.darkMode,
              ),
            ),
            // Thanh công cụ Zoom / Reset góc trên phải
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.darkMode ? const Color(0xCC0F172A) : const Color(0xE6FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: widget.darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Phóng to (+)',
                      icon: const Icon(Icons.zoom_in, size: 18),
                      onPressed: () => setState(() => _zoom = (_zoom * 1.2).clamp(0.4, 5.0)),
                    ),
                    IconButton(
                      tooltip: 'Thu nhỏ (-)',
                      icon: const Icon(Icons.zoom_out, size: 18),
                      onPressed: () => setState(() => _zoom = (_zoom / 1.2).clamp(0.4, 5.0)),
                    ),
                    IconButton(
                      tooltip: 'Vừa khung hình (Fit)',
                      icon: const Icon(Icons.fit_screen, size: 18),
                      onPressed: _resetView,
                    ),
                  ],
                ),
              ),
            ),
            // Gợi ý tương tác góc dưới trái
            Positioned(
              left: 12,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: widget.darkMode ? const Color(0xCC0F172A) : const Color(0xE6FFFFFF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.4)),
                ),
                child: Text(
                  'Chạm vào bất kỳ điểm nào trên thanh để khảo sát & đặt vết cắt phẫu thuật  •  Kéo: Pan  •  Cuộn/Chụm: Zoom',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: widget.darkMode ? const Color(0xFF94A3B8) : const Color(0xFF334155),
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

class _Transform2D {
  final double scale;
  final double cx;
  final double cy;
  final Offset screenCenter;
  const _Transform2D({
    required this.scale,
    required this.cx,
    required this.cy,
    required this.screenCenter,
  });

  Offset toScreen(double x, double y) => Offset(
        screenCenter.dx + (x - cx) * scale,
        screenCenter.dy - (y - cy) * scale,
      );
}

class _Ansys2DPainter extends CustomPainter {
  final TrussModelData model;
  final TrussAnalysisResult result;
  final ContourField field;
  final List<double> values;
  final double minVal;
  final double maxVal;
  final _Transform2D tf;
  final double deformScale;
  final double playbackFraction;
  final int selectedElem;
  final double probeXi;
  final bool surgicalMode;
  final bool darkMode;

  _Ansys2DPainter({
    required this.model,
    required this.result,
    required this.field,
    required this.values,
    required this.minVal,
    required this.maxVal,
    required this.tf,
    required this.deformScale,
    required this.playbackFraction,
    required this.selectedElem,
    required this.probeXi,
    required this.surgicalMode,
    required this.darkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Lưới kỹ thuật CAE
    final gridPaint = Paint()
      ..color = darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)
      ..strokeWidth = 0.8;
    const stepPx = 40.0;
    for (double x = tf.screenCenter.dx % stepPx; x < size.width; x += stepPx) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = tf.screenCenter.dy % stepPx; y < size.height; y += stepPx) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. Cấu hình ban đầu nét đứt
    final ghostPaint = Paint()
      ..color = darkMode ? const Color(0xFF475569) : const Color(0xFF94A3B8)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (int e = 0; e < model.nElems; e++) {
      final ni = model.conn[e][0] - 1;
      final nj = model.conn[e][1] - 1;
      final a = tf.toScreen(model.coords[ni][0], model.coords[ni][1]);
      final b = tf.toScreen(model.coords[nj][0], model.coords[nj][1]);
      _drawDashedLine(canvas, a, b, ghostPaint);
    }

    final span = (maxVal - minVal).abs() < 1e-12 ? 1.0 : (maxVal - minVal);

    // Hàm nội suy giá trị trường kết quả liên tục dọc thanh tại tọa độ ξ ∈ [0, 1]
    double valueAt(int e, double xi) {
      if (field == ContourField.displacement) {
        final ni = model.conn[e][0] - 1;
        final nj = model.conn[e][1] - 1;
        final ux = (1.0 - xi) * result.uMm[2 * ni] + xi * result.uMm[2 * nj];
        final uy = (1.0 - xi) * result.uMm[2 * ni + 1] + xi * result.uMm[2 * nj + 1];
        return math.sqrt(ux * ux + uy * uy) * playbackFraction;
      }
      return values[e];
    }

    ui.Shader? barGradientShader(int e, Offset pA, Offset pB, double xiA, double xiB, double alpha) {
      if (field != ContourField.displacement) return null;
      if ((pB - pA).distance < 1e-3) return null;
      const nStops = 16;
      final cols = <Color>[];
      final stops = <double>[];
      for (int s = 0; s < nStops; s++) {
        final f = s / (nStops - 1);
        final xi = xiA + f * (xiB - xiA);
        final t = ((valueAt(e, xi) - minVal) / span).clamp(0.0, 1.0);
        cols.add(ansysRainbowColor(t).withValues(alpha: alpha));
        stops.add(f);
      }
      return ui.Gradient.linear(pA, pB, cols, stops);
    }

    // 3. Các thanh biến dạng tô màu cầu vồng liên tục (Gradient mượt khi xem chuyển vị ||u||)
    for (int e = 0; e < model.nElems; e++) {
      final ni = model.conn[e][0] - 1;
      final nj = model.conn[e][1] - 1;
      final a = tf.toScreen(
        model.coords[ni][0] + deformScale * result.uMm[2 * ni],
        model.coords[ni][1] + deformScale * result.uMm[2 * ni + 1],
      );
      final b = tf.toScreen(
        model.coords[nj][0] + deformScale * result.uMm[2 * nj],
        model.coords[nj][1] + deformScale * result.uMm[2 * nj + 1],
      );
      final midVal = valueAt(e, 0.5);
      final tColor = ((midVal - minVal) / span).clamp(0.0, 1.0);
      final barColor = ansysRainbowColor(tColor);
      final isSel = e == selectedElem;
      final thick = (model.areas[e] > model.baseA * 1.5 ? 11.5 : 7.5) + (isSel ? 2.5 : 0.0);

      // Viền phát sáng nhẹ khi đang được chọn
      if (isSel) {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFF38BDF8).withValues(alpha: 0.35)
            ..strokeWidth = thick + 8
            ..strokeCap = StrokeCap.round,
        );
      }

      if (surgicalMode && isSel) {
        // Khi ở chế độ Phẫu thuật: nửa sau vết cắt ξ hiện mờ để thấy rõ mặt cắt mổ!
        final cutPt = Offset(a.dx + probeXi * (b.dx - a.dx), a.dy + probeXi * (b.dy - a.dy));
        if (probeXi > 0.01) {
          final pFront = Paint()
            ..color = barColor
            ..strokeWidth = thick
            ..strokeCap = StrokeCap.butt;
          final shFront = barGradientShader(e, a, cutPt, 0.0, probeXi, 1.0);
          if (shFront != null) pFront.shader = shFront;
          canvas.drawLine(a, cutPt, pFront);
        }

        if (probeXi < 0.99) {
          final pBack = Paint()
            ..color = barColor.withValues(alpha: 0.25)
            ..strokeWidth = thick * 0.75
            ..strokeCap = StrokeCap.round;
          final shBack = barGradientShader(e, cutPt, b, probeXi, 1.0, 0.28);
          if (shBack != null) pBack.shader = shBack;
          canvas.drawLine(cutPt, b, pBack);
        }

        // Đường dao cắt phẫu thuật vuông góc trục thanh
        final dir = b - a;
        final len = dir.distance;
        if (len > 1) {
          final perp = Offset(-dir.dy / len, dir.dx / len) * 26.0;
          canvas.drawLine(
            cutPt - perp,
            cutPt + perp,
            Paint()
              ..color = const Color(0xFF00E5FF)
              ..strokeWidth = 2.6,
          );
        }
      } else {
        final pBar = Paint()
          ..color = barColor
          ..strokeWidth = thick
          ..strokeCap = StrokeCap.round;
        final sh = barGradientShader(e, a, b, 0.0, 1.0, 1.0);
        if (sh != null) pBar.shader = sh;
        canvas.drawLine(a, b, pBar);
      }

      // Nhãn giá trị nổi giữa thanh — đồng bộ 100% với trường hiển thị đang chọn
      final mid = Offset(0.5 * (a.dx + b.dx), 0.5 * (a.dy + b.dy));
      _drawBadge(
        canvas,
        mid + Offset(0, e == 0 ? 22 : (e == 2 ? -22 : 0)),
        'T${e + 1}(${model.memberLabels[e]}): ${field.symbol} = ${field.formatValue(midVal)}',
        barColor,
      );
    }

    // 4. Vẽ gối tựa & mũi tên ngoại lực P
    _drawSupportsAndLoads(canvas);

    // 5. Vẽ nút khớp 2D (tô màu & ghi chuyển vị nút thật khi đang xem Chuyển vị tổng ||u||)
    for (int i = 0; i < model.nNodes; i++) {
      final p = tf.toScreen(
        model.coords[i][0] + deformScale * result.uMm[2 * i],
        model.coords[i][1] + deformScale * result.uMm[2 * i + 1],
      );
      final uNode = math.sqrt(math.pow(result.uMm[2 * i], 2) + math.pow(result.uMm[2 * i + 1], 2)) * playbackFraction;
      final nodeAccent = field == ContourField.displacement
          ? ansysRainbowColor(((uNode - minVal) / span).clamp(0.0, 1.0))
          : const Color(0xFF38BDF8);
      canvas.drawCircle(
        p,
        7.5,
        Paint()
          ..color = field == ContourField.displacement
              ? nodeAccent
              : (darkMode ? const Color(0xFF0F172A) : Colors.white),
      );
      canvas.drawCircle(
        p,
        7.5,
        Paint()
          ..color = field == ContourField.displacement
              ? (darkMode ? Colors.white : const Color(0xFF0F172A))
              : nodeAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
      final nodeLabel = field == ContourField.displacement
          ? 'N${i + 1} (${uNode.toStringAsFixed(3)} mm)'
          : 'N${i + 1}';
      _drawText(
        canvas,
        p + const Offset(10, -16),
        nodeLabel,
        darkMode ? Colors.white : const Color(0xFF0F172A),
        11,
        bold: true,
      );
    }

    // 6. Con trỏ khảo sát (Probe Cursor) trên thanh đang chọn
    final eSel = selectedElem.clamp(0, model.nElems - 1);
    final ni = model.conn[eSel][0] - 1;
    final nj = model.conn[eSel][1] - 1;
    final aSel = tf.toScreen(
      model.coords[ni][0] + deformScale * result.uMm[2 * ni],
      model.coords[ni][1] + deformScale * result.uMm[2 * ni + 1],
    );
    final bSel = tf.toScreen(
      model.coords[nj][0] + deformScale * result.uMm[2 * nj],
      model.coords[nj][1] + deformScale * result.uMm[2 * nj + 1],
    );
    final probePt = Offset(
      aSel.dx + probeXi * (bSel.dx - aSel.dx),
      aSel.dy + probeXi * (bSel.dy - aSel.dy),
    );
    canvas.drawCircle(
      probePt,
      11,
      Paint()..color = const Color(0xFF00E5FF).withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      probePt,
      5.5,
      Paint()..color = const Color(0xFF00E5FF),
    );
    canvas.drawCircle(
      probePt,
      5.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  void _drawSupportsAndLoads(Canvas canvas) {
    final fixed = model.fixedDofs0.toSet();
    final supPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < model.nNodes; i++) {
      final fxLock = fixed.contains(2 * i);
      final fyLock = fixed.contains(2 * i + 1);
      final p = tf.toScreen(
        model.coords[i][0] + deformScale * result.uMm[2 * i],
        model.coords[i][1] + deformScale * result.uMm[2 * i + 1],
      );
      if (fxLock && fyLock) {
        final tri = Path()
          ..moveTo(p.dx, p.dy + 7)
          ..lineTo(p.dx - 13, p.dy + 24)
          ..lineTo(p.dx + 13, p.dy + 24)
          ..close();
        canvas.drawPath(tri, Paint()..color = const Color(0xFF334155));
        canvas.drawPath(tri, supPaint);
        canvas.drawLine(Offset(p.dx - 18, p.dy + 25), Offset(p.dx + 18, p.dy + 25), supPaint);
      } else if (fyLock) {
        // Con lăn phía trên (như Nút 4 trong đề bài)
        final tri = Path()
          ..moveTo(p.dx, p.dy - 7)
          ..lineTo(p.dx - 12, p.dy - 22)
          ..lineTo(p.dx + 12, p.dy - 22)
          ..close();
        canvas.drawPath(tri, Paint()..color = const Color(0xFF334155));
        canvas.drawPath(tri, supPaint);
        canvas.drawCircle(Offset(p.dx - 6, p.dy - 26), 3.5, supPaint);
        canvas.drawCircle(Offset(p.dx + 6, p.dy - 26), 3.5, supPaint);
        canvas.drawLine(Offset(p.dx - 18, p.dy - 30), Offset(p.dx + 18, p.dy - 30), supPaint);
      }

      // Vẽ mũi tên tải trọng ngoài P
      final loadX = model.fRef[2 * i];
      final loadY = model.fRef[2 * i + 1];
      if (loadX.abs() > 1e-3 || loadY.abs() > 1e-3) {
        final mag = math.sqrt(loadX * loadX + loadY * loadY);
        final dirScreen = Offset(loadX / mag, -loadY / mag);
        final start = p;
        final end = p + dirScreen * 58.0;
        _drawArrow(canvas, start, end, const Color(0xFFFF3B5C), 3.2);
        _drawText(
          canvas,
          end + const Offset(-26, -18),
          'P = ${(mag * playbackFraction / 1000.0).toStringAsFixed(1)} kN',
          const Color(0xFFFF5A79),
          11,
          bold: true,
        );
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Color color, double width) {
    final p = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, p);
    final ang = math.atan2(end.dy - start.dy, end.dx - start.dx);
    const head = 12.0;
    final p1 = Offset(end.dx - head * math.cos(ang - 0.45), end.dy - head * math.sin(ang - 0.45));
    final p2 = Offset(end.dx - head * math.cos(ang + 0.45), end.dy - head * math.sin(ang + 0.45));
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final d = (b - a).distance;
    const dash = 7.0, gap = 5.0;
    for (double t = 0; t < d; t += dash + gap) {
      final t1 = (t / d).clamp(0.0, 1.0);
      final t2 = ((t + dash) / d).clamp(0.0, 1.0);
      canvas.drawLine(Offset.lerp(a, b, t1)!, Offset.lerp(a, b, t2)!, paint);
    }
  }

  void _drawBadge(Canvas canvas, Offset center, String text, Color accent) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: darkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
          fontSize: 9.8,
          fontWeight: FontWeight.w600,
          fontFamily: 'DejaVuSans',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(center: center, width: tp.width + 10, height: tp.height + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = darkMode ? const Color(0xD90F172A) : const Color(0xE6FFFFFF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()
        ..color = accent.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    tp.paint(canvas, Offset(rect.left + 5, rect.top + 3));
  }

  void _drawText(Canvas canvas, Offset pos, String text, Color color, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFamily: 'DejaVuSans',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _Ansys2DPainter oldDelegate) => true;
}
