// ============================================================================
// CỬA SỔ MÔ PHỎNG 2D KẾT CẤU DÀN PHẲNG (PAN, ZOOM, CHỌN NÚT & PHẪU THUẬT)
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
  final int? selectedNode;
  final double probeXi;
  final bool surgicalMode;
  final bool darkMode;
  final bool showColorBar;
  final ValueChanged<bool>? onToggleColorBar;
  final ConnectionDisplayMode connectionMode;
  final ConnectionDetailType connectionType;
  final List<MemberDesignCheck>? designChecks;
  final void Function(int elemIndex, double xi) onProbeChanged;
  final ValueChanged<int>? onNodeTapped;

  const AnsysViewport2D({
    super.key,
    required this.model,
    required this.result,
    required this.field,
    required this.deformScale,
    required this.playbackFraction,
    required this.selectedElem,
    this.selectedNode,
    required this.probeXi,
    required this.surgicalMode,
    required this.darkMode,
    this.showColorBar = true,
    this.onToggleColorBar,
    this.connectionMode = ConnectionDisplayMode.schematic,
    this.connectionType = ConnectionDetailType.boltedGusset,
    this.designChecks,
    required this.onProbeChanged,
    this.onNodeTapped,
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

  void _showControlsHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF06B6D4), size: 20),
            SizedBox(width: 8),
            Text('Hướng dẫn thao tác khung 2D & Phím tắt', style: TextStyle(fontSize: 14)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Chạm vào THANH: Đặt điểm khảo sát & cắt Phẫu thuật tại vị trí ξ', style: TextStyle(fontSize: 12.2)),
            SizedBox(height: 4),
            Text('• Chạm vào NÚT: Chọn nút & mở chi tiết Tab Liên kết', style: TextStyle(fontSize: 12.2)),
            SizedBox(height: 4),
            Text('• Kéo chuột / 1 ngón: Di chuyển khung nhìn (Pan)', style: TextStyle(fontSize: 12.2)),
            SizedBox(height: 4),
            Text('• Cuộn chuột / Chụm 2 ngón: Phóng to / Thu nhỏ (Zoom)', style: TextStyle(fontSize: 12.2)),
            Divider(height: 16),
            Text('Phím tắt nhanh:', style: TextStyle(fontSize: 12.2, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('• Space: Phát / Tạm dừng mô phỏng tăng tải', style: TextStyle(fontSize: 12)),
            Text('• 2 / 3: Chuyển nhanh khung nhìn 2D ↔ 3D', style: TextStyle(fontSize: 12)),
            Text('• Ctrl+Z / Ctrl+Y: Hoàn tác (Undo) / Làm lại (Redo)', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
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
      case ContourField.utilizationRatio:
        final checks = widget.designChecks ?? CalfemNonlinearEngine.checkMembers(widget.model, widget.result);
        return [
          for (int e = 0; e < ne; e++) (e < checks.length ? checks[e].utilizationPct : 0.0) * frac,
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

    // 1. Ưu tiên chọn NÚT trực tiếp nếu nhấn gần nút (bán kính 22 px)
    if (widget.onNodeTapped != null) {
      int bestNode = -1;
      double bestNodeDist = 22.0;
      for (int i = 0; i < widget.model.nNodes; i++) {
        final pn = tf.toScreen(
          widget.model.coords[i][0] + scaleDef * widget.result.uMm[2 * i],
          widget.model.coords[i][1] + scaleDef * widget.result.uMm[2 * i + 1],
        );
        final d = (pTap - pn).distance;
        if (d < bestNodeDist) {
          bestNodeDist = d;
          bestNode = i;
        }
      }
      if (bestNode >= 0) {
        widget.onNodeTapped!(bestNode);
        return;
      }
    }

    // 2. Chọn THANH & vị trí cắt phẫu thuật ξ
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
    final fullVals = _fieldValuesPerElem(1.0);
    double minV = fullVals.isEmpty ? 0.0 : fullVals.reduce(math.min);
    double maxV = fullVals.isEmpty ? 1.0 : fullVals.reduce(math.max);
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
    } else if (widget.field == ContourField.utilizationRatio) {
      minV = 0.0;
      maxV = math.max(100.0, maxV);
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
                      selectedNode: widget.selectedNode,
                      probeXi: widget.probeXi,
                      surgicalMode: widget.surgicalMode,
                      darkMode: widget.darkMode,
                      connectionMode: widget.connectionMode,
                      connectionType: widget.connectionType,
                    ),
                  ),
                ),
              ),
            ),
            // Bảng thang màu góc trên trái (có nút ẩn / hiện để không che khung 2D)
            Positioned(
              left: 12,
              top: 12,
              child: widget.showColorBar
                  ? AnsysColorBar(
                      title: widget.field.label,
                      unit: widget.field.unit,
                      minVal: minV,
                      maxVal: maxV,
                      darkMode: widget.darkMode,
                      onHide: widget.onToggleColorBar != null
                          ? () => widget.onToggleColorBar!(false)
                          : null,
                    )
                  : ColorBarRestoreButton(
                      darkMode: widget.darkMode,
                      onShow: () => widget.onToggleColorBar?.call(true),
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
            // Nút trợ giúp gọn nhẹ góc dưới trái
            Positioned(
              left: 12,
              bottom: 10,
              child: Tooltip(
                message: 'Hướng dẫn thao tác 2D & phím tắt',
                child: InkWell(
                  onTap: () => _showControlsHelp(context),
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
  final int? selectedNode;
  final double probeXi;
  final bool surgicalMode;
  final bool darkMode;
  final ConnectionDisplayMode connectionMode;
  final ConnectionDetailType connectionType;

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
    this.selectedNode,
    required this.probeXi,
    required this.surgicalMode,
    required this.darkMode,
    this.connectionMode = ConnectionDisplayMode.schematic,
    this.connectionType = ConnectionDetailType.boltedGusset,
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

      // Nhãn giá trị nổi giữa thanh (tự thu gọn khi dàn ≥ 8 thanh để không che hình)
      final mid = Offset(0.5 * (a.dx + b.dx), 0.5 * (a.dy + b.dy));
      final compact2d = model.nElems >= 8;
      _drawBadge(
        canvas,
        mid + Offset(0, e == 0 ? 22 : (e == 2 ? -22 : 0)),
        compact2d
            ? 'T${e + 1}: ${midVal.toStringAsFixed(1)}'
            : 'T${e + 1}(${model.memberLabels[e]}): ${field.symbol} = ${field.formatValue(midVal)}',
        barColor,
      );
    }

    // 4. Vẽ liên kết gối tựa (Sơ đồ tính hoặc Chi tiết gia công chế tạo) & ngoại lực P
    if (connectionMode == ConnectionDisplayMode.fabrication) {
      _drawFabricationNodes2D(canvas);
    }
    _drawSupportsAndLoads(canvas);

    // 5. Vẽ nút khớp 2D (tô màu & vòng sáng nút đang chọn)
    for (int i = 0; i < model.nNodes; i++) {
      final p = tf.toScreen(
        model.coords[i][0] + deformScale * result.uMm[2 * i],
        model.coords[i][1] + deformScale * result.uMm[2 * i + 1],
      );
      if (selectedNode == i) {
        canvas.drawCircle(p, 13.5, Paint()..color = const Color(0xFF06B6D4).withValues(alpha: 0.25));
        canvas.drawCircle(
          p,
          13.5,
          Paint()
            ..color = const Color(0xFF00E5FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }
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
        selectedNode == i
            ? const Color(0xFF00E5FF)
            : (darkMode ? Colors.white : const Color(0xFF0F172A)),
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

  /// Vẽ bản mã vát góc, bu-lông lục giác / đường hàn cam / chốt Clevis & bản đế móng trên 2D chế tạo
  void _drawFabricationNodes2D(Canvas canvas) {
    final gussetFill = Paint()..color = darkMode ? const Color(0xCC1D4ED8) : const Color(0xCC93C5FD);
    final gussetEdge = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final plateFill = Paint()..color = const Color(0xFF64748B);
    final concFill = Paint()..color = darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    final edgeStroke = Paint()
      ..color = darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    List<Offset> hull2D(List<Offset> pts) {
      if (pts.length <= 3) return pts;
      final s = List<Offset>.from(pts)
        ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
      double cr(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
      final lo = <Offset>[];
      for (final p in s) {
        while (lo.length >= 2 && cr(lo[lo.length - 2], lo.last, p) <= 0) {
          lo.removeLast();
        }
        lo.add(p);
      }
      final hi = <Offset>[];
      for (final p in s.reversed) {
        while (hi.length >= 2 && cr(hi[hi.length - 2], hi.last, p) <= 0) {
          hi.removeLast();
        }
        hi.add(p);
      }
      lo.removeLast();
      hi.removeLast();
      return [...lo, ...hi];
    }

    for (int i = 0; i < model.nNodes; i++) {
      final p = tf.toScreen(
        model.coords[i][0] + deformScale * result.uMm[2 * i],
        model.coords[i][1] + deformScale * result.uMm[2 * i + 1],
      );
      final sup = i < model.nodeSupports.length ? model.nodeSupports[i] : NodeSupportType.free;

      final pts = <Offset>[];
      final dirs = <Offset>[];
      for (int e = 0; e < model.nElems; e++) {
        final n1 = model.conn[e][0] - 1;
        final n2 = model.conn[e][1] - 1;
        if (n1 != i && n2 != i) continue;
        final other = n1 == i ? n2 : n1;
        final q = tf.toScreen(
          model.coords[other][0] + deformScale * result.uMm[2 * other],
          model.coords[other][1] + deformScale * result.uMm[2 * other + 1],
        );
        final v = q - p;
        final len = v.distance;
        if (len < 1e-3) continue;
        final u = v / len;
        final perp = Offset(-u.dy, u.dx);
        dirs.add(u);
        const reachPx = 38.0;
        const hw = 13.0;
        pts.add(p + u * reachPx + perp * hw);
        pts.add(p + u * reachPx - perp * hw);
        pts.add(p + perp * hw);
        pts.add(p - perp * hw);
      }
      final hull = hull2D(pts);
      if (hull.length >= 3) {
        final gp = Path()..moveTo(hull.first.dx, hull.first.dy);
        for (int k = 1; k < hull.length; k++) {
          gp.lineTo(hull[k].dx, hull[k].dy);
        }
        gp.close();
        canvas.drawPath(gp, gussetFill);
        canvas.drawPath(gp, gussetEdge);
      }
      // Vẽ bu-lông vàng / đường hàn cam / chốt Clevis trên mỗi đầu thanh 2D
      for (final u in dirs) {
        final perp = Offset(-u.dy, u.dx);
        if (connectionType == ConnectionDetailType.boltedGusset) {
          for (final d in [18.0, 30.0]) {
            for (final off in [-5.5, 5.5]) {
              final bp = p + u * d + perp * off;
              canvas.drawCircle(bp, 2.7, Paint()..color = const Color(0xFFFACC15));
              canvas.drawCircle(bp, 2.7, Paint()..color = const Color(0xFF0F172A)..style = PaintingStyle.stroke..strokeWidth = 0.8);
            }
          }
        } else if (connectionType == ConnectionDetailType.weldedGusset) {
          final wp = Paint()..color = const Color(0xFFF97316)..strokeWidth = 3.0..strokeCap = StrokeCap.round;
          canvas.drawLine(p + u * 10 + perp * 8.5, p + u * 35 + perp * 8.5, wp);
          canvas.drawLine(p + u * 10 - perp * 8.5, p + u * 35 - perp * 8.5, wp);
        }
      }
      if (connectionType == ConnectionDetailType.pinnedClevis) {
        canvas.drawCircle(p, 10.0, Paint()..color = const Color(0xFFF59E0B));
        canvas.drawCircle(p, 10.0, edgeStroke);
      }
      // Bệ bản đế + bu-lông neo + khối móng bê tông cho chế độ chi tiết chế tạo 2D (xoay đủ 4 hướng!)
      final dir = model.resolvedDirectionFor(i);
      final out2 = _dirOut2D(dir);
      final tang2 = Offset(-out2.dy, out2.dx);

      void drawOrientedRect(Offset centerPt, double alongLen, double acrossLen, Paint fill) {
        final ha = 0.5 * alongLen;
        final hw = 0.5 * acrossLen;
        final rectP = Path()
          ..moveTo((centerPt - out2 * ha - tang2 * hw).dx, (centerPt - out2 * ha - tang2 * hw).dy)
          ..lineTo((centerPt + out2 * ha - tang2 * hw).dx, (centerPt + out2 * ha - tang2 * hw).dy)
          ..lineTo((centerPt + out2 * ha + tang2 * hw).dx, (centerPt + out2 * ha + tang2 * hw).dy)
          ..lineTo((centerPt - out2 * ha + tang2 * hw).dx, (centerPt - out2 * ha + tang2 * hw).dy)
          ..close();
        canvas.drawPath(rectP, fill);
        canvas.drawPath(rectP, edgeStroke);
      }

      if (sup == NodeSupportType.pin) {
        drawOrientedRect(p + out2 * 34.0, 18.0, 56.0, concFill);
        drawOrientedRect(p + out2 * 22.0, 6.0, 42.0, plateFill);
        for (final off in [-14.0, 14.0]) {
          canvas.drawLine(
            p + out2 * 16.0 + tang2 * off,
            p + out2 * 36.0 + tang2 * off,
            Paint()..color = const Color(0xFFFACC15)..strokeWidth = 2.0,
          );
        }
      } else if (sup == NodeSupportType.rollerX || sup == NodeSupportType.rollerXSpringX || sup == NodeSupportType.rollerY) {
        drawOrientedRect(p + out2 * 39.0, 12.0, 52.0, concFill);
        drawOrientedRect(p + out2 * 18.0, 5.0, 36.0, plateFill);
        drawOrientedRect(p + out2 * 30.0, 5.0, 42.0, plateFill);
        canvas.drawCircle(p + out2 * 24.0 - tang2 * 8.0, 3.6, Paint()..color = const Color(0xFF38BDF8));
        canvas.drawCircle(p + out2 * 24.0 + tang2 * 8.0, 3.6, Paint()..color = const Color(0xFF38BDF8));
      }
    }
  }

  Offset _dirOut2D(SupportDirection dir) {
    switch (dir) {
      case SupportDirection.top:
        return const Offset(0, -1);
      case SupportDirection.left:
        return const Offset(-1, 0);
      case SupportDirection.right:
        return const Offset(1, 0);
      case SupportDirection.bottom:
      case SupportDirection.auto:
        return const Offset(0, 1);
    }
  }

  void _drawSupportsAndLoads(Canvas canvas) {
    final supPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final springPaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final c in model.coords) {
      minX = math.min(minX, c[0]);
      maxX = math.max(maxX, c[0]);
      minY = math.min(minY, c[1]);
      maxY = math.max(maxY, c[1]);
    }
    final midX = 0.5 * (minX + maxX);
    final midY = 0.5 * (minY + maxY);

    void drawGroundHatch(Offset a, Offset b, Offset dirOut) {
      canvas.drawLine(a, b, supPaint);
      final v = b - a;
      final len = v.distance;
      if (len < 1e-3) return;
      final tUnit = v / len;
      final nUnit = dirOut / dirOut.distance;
      for (double s = 3.0; s <= len - 2.0; s += 6.5) {
        final base = a + tUnit * s;
        canvas.drawLine(base, base + nUnit * 6.0 - tUnit * 4.0, supPaint..strokeWidth = 1.4);
      }
      supPaint.strokeWidth = 2.0;
    }

    void drawSpring2D(Offset pNode, Offset pAnchor, String tag) {
      final d = pAnchor - pNode;
      final len = d.distance;
      if (len < 6.0) return;
      final u = d / len;
      final n = Offset(-u.dy, u.dx);
      const lead = 7.0;
      const coils = 5;
      const amp = 6.0;
      final body = math.max(6.0, len - 2 * lead);
      final path = Path()
        ..moveTo(pNode.dx, pNode.dy)
        ..lineTo(pNode.dx + u.dx * lead, pNode.dy + u.dy * lead);
      for (int c = 0; c < coils; c++) {
        final s1 = lead + (c + 0.25) / coils * body;
        final s2 = lead + (c + 0.75) / coils * body;
        final q1 = pNode + u * s1 + n * amp;
        final q2 = pNode + u * s2 - n * amp;
        path.lineTo(q1.dx, q1.dy);
        path.lineTo(q2.dx, q2.dy);
      }
      path.lineTo(pAnchor.dx - u.dx * lead, pAnchor.dy - u.dy * lead);
      path.lineTo(pAnchor.dx, pAnchor.dy);
      canvas.drawPath(path, springPaint);
      drawGroundHatch(pAnchor - n * 13.0, pAnchor + n * 13.0, u);
      _drawText(canvas, pAnchor + n * 10.0 - const Offset(6, 6), tag, const Color(0xFFFBBF24), 9.5, bold: true);
    }

    for (int i = 0; i < model.nNodes; i++) {
      final sup = i < model.nodeSupports.length ? model.nodeSupports[i] : NodeSupportType.free;
      final p0 = tf.toScreen(model.coords[i][0], model.coords[i][1]);
      final p = tf.toScreen(
        model.coords[i][0] + deformScale * result.uMm[2 * i],
        model.coords[i][1] + deformScale * result.uMm[2 * i + 1],
      );
      final isTop = model.coords[i][1] > midY + 1e-3;
      final isRight = model.coords[i][0] > midX + 1e-3;

      final dir = model.resolvedDirectionFor(i);
      final out = _dirOut2D(dir);
      final tang = Offset(-out.dy, out.dx);

      if (connectionMode == ConnectionDisplayMode.schematic) {
        if (sup == NodeSupportType.pin) {
          final tri = Path()
            ..moveTo((p + out * 7.0).dx, (p + out * 7.0).dy)
            ..lineTo((p + out * 24.0 - tang * 13.0).dx, (p + out * 24.0 - tang * 13.0).dy)
            ..lineTo((p + out * 24.0 + tang * 13.0).dx, (p + out * 24.0 + tang * 13.0).dy)
            ..close();
          canvas.drawPath(tri, Paint()..color = const Color(0xFF334155));
          canvas.drawPath(tri, supPaint);
          drawGroundHatch(
            p + out * 25.0 - tang * 18.0,
            p + out * 25.0 + tang * 18.0,
            out,
          );
        } else if (sup == NodeSupportType.rollerX || sup == NodeSupportType.rollerXSpringX || sup == NodeSupportType.rollerY) {
          final tri = Path()
            ..moveTo((p + out * 7.0).dx, (p + out * 7.0).dy)
            ..lineTo((p + out * 22.0 - tang * 12.0).dx, (p + out * 22.0 - tang * 12.0).dy)
            ..lineTo((p + out * 22.0 + tang * 12.0).dx, (p + out * 22.0 + tang * 12.0).dy)
            ..close();
          canvas.drawPath(tri, Paint()..color = const Color(0xFF334155));
          canvas.drawPath(tri, supPaint);
          canvas.drawCircle(p + out * 26.0 - tang * 6.0, 3.5, supPaint);
          canvas.drawCircle(p + out * 26.0 + tang * 6.0, 3.5, supPaint);
          drawGroundHatch(
            p + out * 30.0 - tang * 18.0,
            p + out * 30.0 + tang * 18.0,
            out,
          );
        }
      }

      if (sup.hasSpringY) {
        final rawDir = i < model.supportDirections.length ? model.supportDirections[i] : SupportDirection.auto;
        final sgnY = (rawDir == SupportDirection.top)
            ? -1.0
            : (rawDir == SupportDirection.bottom ? 1.0 : (isTop ? -1.0 : 1.0));
        final anchorY = Offset(p.dx, p0.dy + sgnY * 42.0);
        drawSpring2D(Offset(p.dx, p.dy + sgnY * 7.0), anchorY, 'kᵧ');
      }
      if (sup.hasSpringX) {
        final rawDir = i < model.supportDirections.length ? model.supportDirections[i] : SupportDirection.auto;
        final sgnX = (rawDir == SupportDirection.right)
            ? 1.0
            : (rawDir == SupportDirection.left ? -1.0 : (isRight ? 1.0 : -1.0));
        final anchorX = Offset(p0.dx + sgnX * 44.0, p.dy);
        drawSpring2D(Offset(p.dx + sgnX * 7.0, p.dy), anchorX, 'kₓ');
      }

      // Vẽ mũi tên tải trọng ngoài (Fx, Fy) tại mọi nút có tải (tỷ lệ trực quan theo độ lớn lực)
      double maxNodeF = 1.0;
      for (int k = 0; k < model.nNodes; k++) {
        final mk = math.sqrt(model.fRef[2 * k] * model.fRef[2 * k] + model.fRef[2 * k + 1] * model.fRef[2 * k + 1]);
        if (mk > maxNodeF) maxNodeF = mk;
      }
      final loadX = model.fRef[2 * i];
      final loadY = model.fRef[2 * i + 1];
      if (loadX.abs() > 1e-3 || loadY.abs() > 1e-3) {
        final mag = math.sqrt(loadX * loadX + loadY * loadY);
        final dirScreen = Offset(loadX / mag, -loadY / mag);
        final arrowLen = (36.0 + 30.0 * (mag / maxNodeF)).clamp(36.0, 66.0);
        final start = p;
        final end = p + dirScreen * arrowLen;
        _drawArrow(canvas, start, end, const Color(0xFFFF3B5C), 3.1);
        final pShow = mag * playbackFraction / 1000.0;
        final lbl = (loadX.abs() > 1e-3 && loadY.abs() > 1e-3)
            ? 'P${i + 1}=${pShow.toStringAsFixed(1)} kN'
            : 'P = ${pShow.toStringAsFixed(1)} kN';
        _drawText(
          canvas,
          end + const Offset(-26, -18),
          lbl,
          const Color(0xFFFF5A79),
          10.5,
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
