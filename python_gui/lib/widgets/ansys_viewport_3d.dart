// ============================================================================
// CỬA SỔ MÔ PHỎNG 3D CHUẨN ANSYS MECHANICAL (PHONG LIGHTING + PHẪU THUẬT 3D)
// ============================================================================
// Trình kết xuất 3D thuần Flutter Canvas siêu mượt 60-120 FPS (hoạt động hoàn hảo
// trên Windows .exe, Android Xiaomi Pad 8 Pro / 13T Pro, và GitHub Web):
//   • Dựng khối 3D thật cho từng thanh dàn theo đúng tiết diện đang chọn
//     (Thép chữ I, Ống tròn rỗng, Hộp vuông, Thanh tròn đặc) + khớp bản lề 3D.
//   • Chiếu sáng 3D Lambert + Blinn-Phong + sắp xếp chiều sâu Z-Buffer (Painter).
//   • Điều khiển y hệt ANSYS:
//       - Kéo trái / 1 ngón : Xoay tự do 360° (Orbit Rotate)
//       - Kéo phải / nút Pan: Di chuyển mặt phẳng nhìn (Pan)
//       - Cuộn chuột / Chụm : Phóng to / Thu nhỏ (Zoom)
//       - Nút góc nhìn chuẩn: ISO 3D | Mặt XY | Trên XZ | Cạnh YZ | Fit All
//   • CHẾ ĐỘ PHẪU THUẬT 3D (3D SECTION CUT):
//       - Hiển thị mặt phẳng dao cắt phát sáng màu xanh lơ xuyên đúng vị trí ξ.
//       - Cắt lìa phần sau thanh (làm trong suốt) để NHÌN TRỰC TIẾP VÀO BÊN TRONG
//         lõi tiết diện cùng mũi tên ứng suất pháp thớ bên trong!
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/calfem_engine.dart';
import 'ansys_colorbar.dart';

class AnsysViewport3D extends StatefulWidget {
  final TrussModelData model;
  final TrussAnalysisResult result;
  final ContourField field;
  final double deformScale;
  final double playbackFraction;
  final int selectedElem;
  final double probeXi;
  final bool surgicalMode;
  final bool darkMode;
  final bool showColorBar;
  final ValueChanged<bool>? onToggleColorBar;
  final ConnectionDisplayMode connectionMode;
  final ConnectionDetailType connectionType;
  final void Function(int elemIndex, double xi) onProbeChanged;

  const AnsysViewport3D({
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
    this.showColorBar = true,
    this.onToggleColorBar,
    this.connectionMode = ConnectionDisplayMode.schematic,
    this.connectionType = ConnectionDetailType.boltedGusset,
    required this.onProbeChanged,
  });

  @override
  State<AnsysViewport3D> createState() => _AnsysViewport3DState();
}

class _AnsysViewport3DState extends State<AnsysViewport3D> {
  double _yaw = -0.52;   // Góc xoay ngang mặc định kiểu ISO ANSYS
  double _pitch = 0.32;  // Góc nghiêng nhìn từ trên xuống
  double _zoom = 1.05;
  Offset _pan = Offset.zero;
  bool _panMode = false;
  double _baseZoom = 1.0;
  Offset _lastFocal = Offset.zero;
  bool _rightButtonDown = false;

  void _setCameraPreset(double yaw, double pitch) {
    setState(() {
      _yaw = yaw;
      _pitch = pitch;
      _pan = Offset.zero;
      _zoom = 1.05;
    });
  }

  List<double> _fieldValues(double frac) {
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

  @override
  Widget build(BuildContext context) {
    final vals = _fieldValues(widget.playbackFraction);
    // Khóa cố định thang đo [minV, maxV] theo trạng thái 100% tải (frac = 1.0)
    // để khi chạy mô phỏng video tăng tải (0% → 100%), dải màu Gradient 3D trên các thanh
    // biến đổi sóng cầu vồng liên tục theo đúng mức tải tức thời!
    final fullVals = _fieldValues(1.0);
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
        final cam = _Camera3D(
          yaw: _yaw,
          pitch: _pitch,
          zoom: _zoom,
          pan: _pan,
          model: widget.model,
          viewport: size,
        );

        return Stack(
          children: [
            Listener(
              onPointerDown: (e) {
                _rightButtonDown = (e.buttons & kSecondaryMouseButton) != 0 ||
                    (e.buttons & kMiddleMouseButton) != 0;
              },
              onPointerUp: (_) => _rightButtonDown = false,
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  setState(() {
                    _zoom = (_zoom * (event.scrollDelta.dy < 0 ? 1.12 : 0.89)).clamp(0.35, 4.5);
                  });
                }
              },
              child: GestureDetector(
                onTapDown: (details) {
                  // Chọn thanh & vị trí khảo sát ngay trong không gian 3D!
                  final scaleDef = widget.deformScale * widget.playbackFraction;
                  int bestElem = widget.selectedElem;
                  double bestXi = widget.probeXi;
                  double bestDist = 38.0;
                  for (int e = 0; e < widget.model.nElems; e++) {
                    final ni = widget.model.conn[e][0] - 1;
                    final nj = widget.model.conn[e][1] - 1;
                    final pa = cam.project(_Vec3(
                      widget.model.coords[ni][0] + scaleDef * widget.result.uMm[2 * ni],
                      widget.model.coords[ni][1] + scaleDef * widget.result.uMm[2 * ni + 1],
                      0,
                    ));
                    final pb = cam.project(_Vec3(
                      widget.model.coords[nj][0] + scaleDef * widget.result.uMm[2 * nj],
                      widget.model.coords[nj][1] + scaleDef * widget.result.uMm[2 * nj + 1],
                      0,
                    ));
                    final ab = pb.pt - pa.pt;
                    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
                    if (ab2 < 1e-6) continue;
                    final t = (((details.localPosition.dx - pa.pt.dx) * ab.dx +
                                (details.localPosition.dy - pa.pt.dy) * ab.dy) /
                            ab2)
                        .clamp(0.0, 1.0);
                    final proj = Offset(pa.pt.dx + t * ab.dx, pa.pt.dy + t * ab.dy);
                    final d = (details.localPosition - proj).distance;
                    if (d < bestDist) {
                      bestDist = d;
                      bestElem = e;
                      bestXi = t;
                    }
                  }
                  if (bestDist < 38.0) {
                    widget.onProbeChanged(bestElem, bestXi);
                  }
                },
                onScaleStart: (d) {
                  _baseZoom = _zoom;
                  _lastFocal = d.focalPoint;
                },
                onScaleUpdate: (d) {
                  final delta = d.focalPoint - _lastFocal;
                  _lastFocal = d.focalPoint;
                  setState(() {
                    if (d.scale != 1.0) {
                      _zoom = (_baseZoom * d.scale).clamp(0.35, 4.5);
                    }
                    if (_panMode || _rightButtonDown || d.pointerCount >= 2) {
                      _pan += delta;
                    } else {
                      _yaw += delta.dx * 0.0085;
                      _pitch = (_pitch + delta.dy * 0.0085).clamp(-1.45, 1.45);
                    }
                  });
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
                          : const [Color(0xFFE2E8F0), Color(0xFFF8FAFC)],
                    ),
                  ),
                  child: CustomPaint(
                    painter: _Ansys3DPainter(
                      model: widget.model,
                      result: widget.result,
                      field: widget.field,
                      values: vals,
                      minVal: minV,
                      maxVal: maxV,
                      cam: cam,
                      deformScale: widget.deformScale * widget.playbackFraction,
                      playbackFraction: widget.playbackFraction,
                      selectedElem: widget.selectedElem,
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

            // Bảng thang màu góc trên trái (có nút ẩn / hiện để không che khung 3D)
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

            // Thanh điều khiển góc nhìn 3D chuẩn ANSYS góc trên phải
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: BoxDecoration(
                  color: widget.darkMode ? const Color(0xD90F172A) : const Color(0xE6FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: widget.darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                ),
                child: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _camBtn('ISO', () => _setCameraPreset(-0.52, 0.32)),
                    _camBtn('XY', () => _setCameraPreset(0.0, 0.0)),
                    _camBtn('XZ', () => _setCameraPreset(0.0, 1.40)),
                    _camBtn('YZ', () => _setCameraPreset(1.57, 0.0)),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: Text(_panMode ? 'Pan' : 'Xoay 3D', style: const TextStyle(fontSize: 10.5)),
                      selected: _panMode,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) => setState(() => _panMode = v),
                    ),
                    IconButton(
                      tooltip: 'Phóng to',
                      icon: const Icon(Icons.zoom_in, size: 17),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _zoom = (_zoom * 1.18).clamp(0.35, 4.5)),
                    ),
                    IconButton(
                      tooltip: 'Thu nhỏ',
                      icon: const Icon(Icons.zoom_out, size: 17),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _zoom = (_zoom / 1.18).clamp(0.35, 4.5)),
                    ),
                  ],
                ),
              ),
            ),

            // Gợi ý điều khiển 3D góc dưới trái
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
                  'Kéo trái/1 ngón: Xoay 3D  •  Kéo phải/2 ngón: Pan  •  Cuộn/Chụm: Zoom  •  Chạm thanh: Khảo sát & Phẫu thuật 3D',
                  style: TextStyle(
                    fontSize: 10.2,
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

  Widget _camBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: widget.darkMode ? 0.9 : 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            color: widget.darkMode ? const Color(0xFF38BDF8) : const Color(0xFF0F3D6E),
          ),
        ),
      ),
    );
  }
}

class _Vec3 {
  final double x, y, z;
  const _Vec3(this.x, this.y, this.z);
  _Vec3 operator +(_Vec3 o) => _Vec3(x + o.x, y + o.y, z + o.z);
  _Vec3 operator -(_Vec3 o) => _Vec3(x - o.x, y - o.y, z - o.z);
  _Vec3 operator *(double s) => _Vec3(x * s, y * s, z * s);
  double dot(_Vec3 o) => x * o.x + y * o.y + z * o.z;
  _Vec3 cross(_Vec3 o) => _Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  _Vec3 normalized() {
    final l = length;
    return l > 1e-12 ? _Vec3(x / l, y / l, z / l) : const _Vec3(0, 0, 1);
  }
}

class _Projected {
  final Offset pt;
  final double depth;
  const _Projected(this.pt, this.depth);
}

class _Camera3D {
  final double yaw;
  final double pitch;
  final double zoom;
  final Offset pan;
  final Size viewport;
  late final _Vec3 center;
  late final double worldScale;

  _Camera3D({
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.pan,
    required TrussModelData model,
    required this.viewport,
  }) {
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final c in model.coords) {
      minX = math.min(minX, c[0]);
      maxX = math.max(maxX, c[0]);
      minY = math.min(minY, c[1]);
      maxY = math.max(maxY, c[1]);
    }
    center = _Vec3(0.5 * (minX + maxX), 0.5 * (minY + maxY), 0.0);
    final span = math.max(maxX - minX, maxY - minY).clamp(200.0, 20000.0);
    worldScale = (math.min(viewport.width, viewport.height) * 0.52 / span) * zoom;
  }

  _Vec3 toCameraSpace(_Vec3 p) {
    final d = p - center;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final x1 = d.x * cy + d.z * sy;
    final z1 = -d.x * sy + d.z * cy;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final y2 = d.y * cp - z1 * sp;
    final z2 = d.y * sp + z1 * cp;
    return _Vec3(x1, y2, z2);
  }

  _Projected project(_Vec3 p) {
    final c = toCameraSpace(p);
    // Phối cảnh mềm kiểu CAD/CAE (tránh méo hình kỹ thuật)
    final camDist = 6500.0;
    final persp = camDist / math.max(400.0, camDist - c.z);
    final sx = viewport.width * 0.52 + pan.dx + c.x * worldScale * persp;
    final sy = viewport.height * 0.54 + pan.dy - c.y * worldScale * persp;
    return _Projected(Offset(sx, sy), c.z);
  }
}

class _Face3D {
  final List<_Vec3> verts;
  final Color baseColor;
  final double alpha;
  final bool drawEdge;
  final Color edgeColor;
  final double depth;
  // Tùy chọn dải màu Gradient liên tục dọc trục thanh 3D (dùng cho Chuyển vị tổng ||u||)
  final _Vec3? gradStart;
  final _Vec3? gradEnd;
  final List<Color>? gradColors;

  const _Face3D({
    required this.verts,
    required this.baseColor,
    required this.depth,
    this.alpha = 1.0,
    this.drawEdge = true,
    this.edgeColor = const Color(0x550F172A),
    this.gradStart,
    this.gradEnd,
    this.gradColors,
  });
}

class _Ansys3DPainter extends CustomPainter {
  final TrussModelData model;
  final TrussAnalysisResult result;
  final ContourField field;
  final List<double> values;
  final double minVal;
  final double maxVal;
  final _Camera3D cam;
  final double deformScale;
  final double playbackFraction;
  final int selectedElem;
  final double probeXi;
  final bool surgicalMode;
  final bool darkMode;
  final ConnectionDisplayMode connectionMode;
  final ConnectionDetailType connectionType;

  _Ansys3DPainter({
    required this.model,
    required this.result,
    required this.field,
    required this.values,
    required this.minVal,
    required this.maxVal,
    required this.cam,
    required this.deformScale,
    required this.playbackFraction,
    required this.selectedElem,
    required this.probeXi,
    required this.surgicalMode,
    required this.darkMode,
    this.connectionMode = ConnectionDisplayMode.schematic,
    this.connectionType = ConnectionDetailType.boltedGusset,
  });

  /// Tạo đa giác tròn 2D (v, w) dùng cho chốt khớp, con lăn 3D
  List<Offset> _circleProfile(double diameter, {int nSeg = 12}) {
    final r = 0.5 * diameter * 0.95;
    return [
      for (int k = 0; k < nSeg; k++)
        Offset(r * math.cos(2 * math.pi * k / nSeg), r * math.sin(2 * math.pi * k / nSeg)),
    ];
  }

  /// Tạo danh sách đa giác viền 2D (v, w) của mặt cắt ngang 3D theo đúng kích thước thực (H, B, tf, tw, s)
  /// Trả về 2 đa giác tách rời (kèm khe hở bản mã) cho tiết diện ghép đôi 2L và 2C!
  List<List<Offset>> _crossSectionPolygons(SectionShape shape, SectionDimensions dims) {
    final maxDim = math.max(dims.height, dims.width);
    // Giữ nguyên tỷ lệ hình học thực (H:B:tf:tw:s), chỉ giới hạn trần hiển thị nếu nhập quá lớn so với nhịp dàn
    final visScale = maxDim > 260.0 ? (260.0 / maxDim) * 0.95 : 0.95;
    final polysMm = dims.outlinePolygonsMm(shape, includeInnerHole: false);
    return [
      for (final poly in polysMm)
        [
          for (final pt in poly) Offset(pt[1] * visScale, pt[0] * visScale),
        ],
    ];
  }

  void _addPrismFaces(
    List<_Face3D> faces,
    _Vec3 pStart,
    _Vec3 pEnd,
    List<Offset> profile,
    Color color, {
    double alpha = 1.0,
    bool highlightEndCap = false,
    List<Color>? gradientColors,
  }) {
    final axis = (pEnd - pStart).normalized();
    const zAxis = _Vec3(0, 0, 1);
    final vAxis = zAxis.cross(axis).normalized(); // vuông góc thanh trong mặt phẳng XY
    final wAxis = zAxis;                          // phương Z (độ dày 3D)

    final ringA = <_Vec3>[];
    final ringB = <_Vec3>[];
    for (final pt in profile) {
      final offset = vAxis * pt.dx + wAxis * pt.dy;
      ringA.add(pStart + offset);
      ringB.add(pEnd + offset);
    }

    final hasGrad = gradientColors != null && gradientColors.length >= 2;
    final startColor = hasGrad ? gradientColors.first : color;
    final endColor = hasGrad ? gradientColors.last : color;

    final n = profile.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final quad = [ringA[i], ringB[i], ringB[j], ringA[j]];
      final avgDepth = quad.map((v) => cam.toCameraSpace(v).z).reduce((a, b) => a + b) / 4.0;
      faces.add(_Face3D(
        verts: quad,
        baseColor: color,
        depth: avgDepth,
        alpha: alpha,
        gradStart: hasGrad ? (ringA[i] + ringA[j]) * 0.5 : null,
        gradEnd: hasGrad ? (ringB[i] + ringB[j]) * 0.5 : null,
        gradColors: hasGrad ? gradientColors : null,
      ));
    }
    // Mặt nắp đầu & cuối (nếu dùng Gradient -> lấy đúng màu tại nút đầu/mặt cắt cuối!)
    final depthA = ringA.map((v) => cam.toCameraSpace(v).z).reduce((a, b) => a + b) / n;
    final depthB = ringB.map((v) => cam.toCameraSpace(v).z).reduce((a, b) => a + b) / n;
    faces.add(_Face3D(verts: ringA.reversed.toList(), baseColor: startColor, depth: depthA, alpha: alpha));
    faces.add(_Face3D(
      verts: ringB,
      baseColor: highlightEndCap ? (hasGrad ? endColor : const Color(0xFFFFD600)) : endColor,
      depth: depthB + (highlightEndCap ? 2.0 : 0.0),
      alpha: highlightEndCap ? 0.98 : alpha,
      edgeColor: highlightEndCap ? const Color(0xFF00E5FF) : const Color(0x550F172A),
    ));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Lưới sàn tham chiếu 3D tự động thích ứng theo khoảng cách / kích thước dàn thực tế
    final floorPaint = Paint()
      ..color = darkMode ? const Color(0x331E293B) : const Color(0x4494A3B8)
      ..strokeWidth = 0.9;
    double gMinX = double.infinity, gMaxX = -double.infinity;
    double gMinY = double.infinity, gMaxY = -double.infinity;
    for (final c in model.coords) {
      gMinX = math.min(gMinX, c[0]);
      gMaxX = math.max(gMaxX, c[0]);
      gMinY = math.min(gMinY, c[1]);
      gMaxY = math.max(gMaxY, c[1]);
    }
    final gSpan = math.max(400.0, math.max(gMaxX - gMinX, gMaxY - gMinY));
    final gStep = (gSpan / 8.0).clamp(100.0, 2000.0);
    final padX = math.max(300.0, gSpan * 0.22);
    final padY = math.max(200.0, gSpan * 0.22);
    final xStart = ((gMinX - padX) / gStep).floor() * gStep;
    final xEnd = ((gMaxX + padX) / gStep).ceil() * gStep;
    final yStart = ((gMinY - padY) / gStep).floor() * gStep;
    final yEnd = ((gMaxY + padY) / gStep).ceil() * gStep;
    for (double x = xStart; x <= xEnd + 1e-6; x += gStep) {
      final a = cam.project(_Vec3(x, yStart, -180)).pt;
      final b = cam.project(_Vec3(x, yEnd, -180)).pt;
      canvas.drawLine(a, b, floorPaint);
    }
    for (double y = yStart; y <= yEnd + 1e-6; y += gStep) {
      final a = cam.project(_Vec3(xStart, y, -180)).pt;
      final b = cam.project(_Vec3(xEnd, y, -180)).pt;
      canvas.drawLine(a, b, floorPaint);
    }

    // 2. Dây khung cấu hình ban đầu (Undeformed 3D Ghost)
    final ghostPaint = Paint()
      ..color = darkMode ? const Color(0x6664748B) : const Color(0x8864748B)
      ..strokeWidth = 1.4;
    for (int e = 0; e < model.nElems; e++) {
      final ni = model.conn[e][0] - 1;
      final nj = model.conn[e][1] - 1;
      final a = cam.project(_Vec3(model.coords[ni][0], model.coords[ni][1], 0)).pt;
      final b = cam.project(_Vec3(model.coords[nj][0], model.coords[nj][1], 0)).pt;
      canvas.drawLine(a, b, ghostPaint);
    }

    // 3. Tạo toàn bộ lưới mặt phẳng 3D cho các thanh, khớp nối và mặt cắt phẫu thuật
    final faces = <_Face3D>[];
    final span = (maxVal - minVal).abs() < 1e-12 ? 1.0 : (maxVal - minVal);
    final nodePos3D = <_Vec3>[
      for (int i = 0; i < model.nNodes; i++)
        _Vec3(
          model.coords[i][0] + deformScale * result.uMm[2 * i],
          model.coords[i][1] + deformScale * result.uMm[2 * i + 1],
          0.0,
        ),
    ];

    // Hàm nội suy liên tục giá trị trường kết quả tại ξ ∈ [0, 1] dọc thanh e
    double valueAt3D(int e, double xi) {
      if (field == ContourField.displacement) {
        final ni = model.conn[e][0] - 1;
        final nj = model.conn[e][1] - 1;
        final ux = (1.0 - xi) * result.uMm[2 * ni] + xi * result.uMm[2 * nj];
        final uy = (1.0 - xi) * result.uMm[2 * ni + 1] + xi * result.uMm[2 * nj + 1];
        return math.sqrt(ux * ux + uy * uy) * playbackFraction;
      }
      return values[e];
    }

    List<Color>? buildGradColors(int e, double xiA, double xiB) {
      if (field != ContourField.displacement) return null;
      const nStops = 16;
      return [
        for (int s = 0; s < nStops; s++)
          ansysRainbowColor(
            ((valueAt3D(e, xiA + (xiB - xiA) * s / (nStops - 1)) - minVal) / span).clamp(0.0, 1.0),
          ),
      ];
    }

    for (int e = 0; e < model.nElems; e++) {
      final ni = model.conn[e][0] - 1;
      final nj = model.conn[e][1] - 1;
      final p1 = nodePos3D[ni];
      final p2 = nodePos3D[nj];
      final tVal = ((valueAt3D(e, 0.5) - minVal) / span).clamp(0.0, 1.0);
      final col = ansysRainbowColor(tVal);
      final shapeE = model.sectionShapeForElem(e);
      final dims = model.sectionDimsForElem(e);
      final profiles = _crossSectionPolygons(shapeE, dims);

      if (surgicalMode && e == selectedElem) {
        // PHẪU THUẬT 3D: Cắt thanh tại vị trí ξ!
        // Phần trước [0, ξ]: khối đặc có nắp phẫu thuật + Gradient liên tục
        // Phần sau [ξ, 1]: cắt rời làm mờ trong suốt + Gradient liên tục!
        final pCut = p1 + (p2 - p1) * probeXi;
        if (probeXi > 0.03) {
          for (final profile in profiles) {
            _addPrismFaces(
              faces,
              p1,
              pCut,
              profile,
              col,
              alpha: 1.0,
              highlightEndCap: true,
              gradientColors: buildGradColors(e, 0.0, probeXi),
            );
          }
        }
        if (probeXi < 0.97) {
          for (final profile in profiles) {
            _addPrismFaces(
              faces,
              pCut,
              p2,
              profile,
              col,
              alpha: 0.26,
              gradientColors: buildGradColors(e, probeXi, 1.0),
            );
          }
        }
        // Mặt phẳng dao cắt trong suốt màu xanh lơ vuông góc trục thanh
        final axis = (p2 - p1).normalized();
        final vAxis = const _Vec3(0, 0, 1).cross(axis).normalized();
        final wAxis = const _Vec3(0, 0, 1);
        final sz = math.min(280.0, math.max(dims.height, dims.width)) * 1.15;
        final planeVerts = [
          pCut - vAxis * sz - wAxis * sz,
          pCut + vAxis * sz - wAxis * sz,
          pCut + vAxis * sz + wAxis * sz,
          pCut - vAxis * sz + wAxis * sz,
        ];
        final dPlane = planeVerts.map((v) => cam.toCameraSpace(v).z).reduce((a, b) => a + b) / 4.0;
        faces.add(_Face3D(
          verts: planeVerts,
          baseColor: const Color(0xFF00E5FF),
          depth: dPlane + 1.0,
          alpha: 0.24,
          edgeColor: const Color(0xFF00E5FF),
        ));
      } else {
        for (final profile in profiles) {
          _addPrismFaces(
            faces,
            p1,
            p2,
            profile,
            col,
            alpha: 0.96,
            gradientColors: buildGradColors(e, 0.0, 1.0),
          );
        }
      }
    }

    // Khớp trụ 3D hoặc Chi tiết gia công chế tạo 3D tại từng nút!
    if (connectionMode == ConnectionDisplayMode.fabrication) {
      _addFabricationConnections3D(faces, nodePos3D);
    } else {
      final pinProfile = _circleProfile(68.0);
      for (int i = 0; i < model.nNodes; i++) {
        final p = nodePos3D[i];
        Color pinColor = const Color(0xFFCBD5E1);
        if (field == ContourField.displacement) {
          final uNode = math.sqrt(math.pow(result.uMm[2 * i], 2) + math.pow(result.uMm[2 * i + 1], 2)) * playbackFraction;
          pinColor = ansysRainbowColor(((uNode - minVal) / span).clamp(0.0, 1.0));
        }
        _addPrismFaces(
          faces,
          _Vec3(p.x, p.y, -75),
          _Vec3(p.x, p.y, 75),
          pinProfile,
          pinColor,
        );
      }
    }

    // 4. Sắp xếp Z-Buffer (từ xa tới gần) và đổ bóng Phong 3D + Gradient liên tục
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    final lightDir = const _Vec3(0.45, 0.65, 0.85).normalized();

    Color shadeColor(Color base, double shade, double spec, double alpha) {
      final r = ((base.r * 255 * shade + spec * 255).round()).clamp(0, 255);
      final g = ((base.g * 255 * shade + spec * 255).round()).clamp(0, 255);
      final b = ((base.b * 255 * shade + spec * 255).round()).clamp(0, 255);
      return Color.fromARGB((alpha * 255).round().clamp(0, 255), r, g, b);
    }

    for (final f in faces) {
      if (f.verts.length < 3) continue;
      final c0 = cam.toCameraSpace(f.verts[0]);
      final c1 = cam.toCameraSpace(f.verts[1]);
      final c2 = cam.toCameraSpace(f.verts[2]);
      final normal = (c1 - c0).cross(c2 - c0).normalized();
      // Đổ bóng Lambert hai mặt + điểm sáng Specular nhẹ
      final diff = normal.dot(lightDir).abs();
      final shade = (0.34 + 0.66 * diff).clamp(0.25, 1.08);
      final spec = math.pow(diff, 14) * 0.24;

      final path = Path();
      final first = cam.project(f.verts[0]).pt;
      path.moveTo(first.dx, first.dy);
      for (int k = 1; k < f.verts.length; k++) {
        final pt = cam.project(f.verts[k]).pt;
        path.lineTo(pt.dx, pt.dy);
      }
      path.close();

      final fillPaint = Paint()..style = PaintingStyle.fill;
      if (f.gradColors != null && f.gradStart != null && f.gradEnd != null) {
        final sA = cam.project(f.gradStart!).pt;
        final sB = cam.project(f.gradEnd!).pt;
        if ((sB - sA).distance > 1.0) {
          final nC = f.gradColors!.length;
          final shadedCols = [
            for (final c in f.gradColors!) shadeColor(c, shade, spec, f.alpha),
          ];
          final stops = [for (int s = 0; s < nC; s++) s / (nC - 1)];
          fillPaint.shader = ui.Gradient.linear(sA, sB, shadedCols, stops);
        } else {
          fillPaint.color = shadeColor(f.baseColor, shade, spec, f.alpha);
        }
      } else {
        fillPaint.color = shadeColor(f.baseColor, shade, spec, f.alpha);
      }
      canvas.drawPath(path, fillPaint);
      if (f.drawEdge) {
        canvas.drawPath(
          path,
          Paint()
            ..color = f.edgeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.85,
        );
      }
    }

    // 4b. Ký hiệu gối tựa 3D (Sơ đồ tính hoặc Chi tiết lò xo/neo bổ sung cho chế độ chi tiết chế tạo)
    if (connectionMode == ConnectionDisplayMode.schematic) {
      _drawSupports3D(canvas, nodePos3D);
    } else {
      _drawFabricationOverlays3D(canvas, nodePos3D);
    }

    // 5. Mũi tên lực ngoài P trong không gian 3D & mũi tên ứng suất nội tại mặt cắt phẫu thuật
    for (int i = 0; i < model.nNodes; i++) {
      final fx = model.fRef[2 * i], fy = model.fRef[2 * i + 1];
      if (fx.abs() > 1e-3 || fy.abs() > 1e-3) {
        final mag = math.sqrt(fx * fx + fy * fy);
        final p0 = nodePos3D[i];
        final pTip = p0 + _Vec3(fx / mag * 340.0, fy / mag * 340.0, 0);
        final s0 = cam.project(p0).pt;
        final s1 = cam.project(pTip).pt;
        _drawArrow(canvas, s0, s1, const Color(0xFFFF2E55), 3.6);
        _drawLabel(
          canvas,
          s1 + const Offset(8, -14),
          'P = ${(mag * playbackFraction / 1000).toStringAsFixed(1)} kN',
          const Color(0xFFFF5A79),
        );
      }
    }

    // 6. Khi ở chế độ Phẫu thuật: vẽ mũi tên ứng suất thớ phóng ra từ mặt cắt!
    if (surgicalMode) {
      final eSel = selectedElem.clamp(0, model.nElems - 1);
      final p1 = nodePos3D[model.conn[eSel][0] - 1];
      final p2 = nodePos3D[model.conn[eSel][1] - 1];
      final pCut = p1 + (p2 - p1) * probeXi;
      final axis = (p2 - p1).normalized();
      final isTension = result.nForcesN[eSel] >= 0;
      final arrowDir = isTension ? axis : axis * -1.0;
      final vAxis = const _Vec3(0, 0, 1).cross(axis).normalized();
      for (final off in [-42.0, 0.0, 42.0]) {
        final base = pCut + vAxis * off;
        final tip = base + arrowDir * 145.0;
        _drawArrow(
          canvas,
          cam.project(base).pt,
          cam.project(tip).pt,
          isTension ? const Color(0xFFFF5252) : const Color(0xFF00E5FF),
          2.4,
        );
      }
      final cutScreen = cam.project(pCut).pt;
      final cutVal = valueAt3D(eSel, probeXi);
      _drawLabel(
        canvas,
        cutScreen + const Offset(14, -24),
        'MẶT CẮT PHẪU THUẬT ξ=${probeXi.toStringAsFixed(2)}\n${field.symbol} = ${field.formatValue(cutVal)}',
        const Color(0xFF00E5FF),
      );
    }

    // 6b. Nhãn giá trị động trên từng thanh 3D (đồng bộ 100% với tùy chọn ContourField!)
    final span3d = (maxVal - minVal).abs() < 1e-12 ? 1.0 : (maxVal - minVal);
    for (int e = 0; e < model.nElems; e++) {
      if (surgicalMode && e == selectedElem.clamp(0, model.nElems - 1)) continue;
      final p1 = nodePos3D[model.conn[e][0] - 1];
      final p2 = nodePos3D[model.conn[e][1] - 1];
      final mid3 = (p1 + p2) * 0.5;
      final sp = cam.project(mid3).pt;
      final midV = valueAt3D(e, 0.5);
      final tCol = ((midV - minVal) / span3d).clamp(0.0, 1.0);
      _drawBadge3D(
        canvas,
        sp + Offset(0, e == 0 ? 16 : (e == 2 ? -16 : 0)),
        'T${e + 1}: ${field.formatValue(midV)}',
        ansysRainbowColor(tCol),
      );
    }

    // 7. Nhãn tên các nút 3D (kèm ||u|| khi đang chọn hiển thị chuyển vị)
    for (int i = 0; i < model.nNodes; i++) {
      final pt = cam.project(nodePos3D[i]).pt;
      final uNode = math.sqrt(math.pow(result.uMm[2 * i], 2) + math.pow(result.uMm[2 * i + 1], 2)) * playbackFraction;
      final nodeLbl = field == ContourField.displacement
          ? 'N${i + 1} (${uNode.toStringAsFixed(3)} mm)'
          : 'N${i + 1}';
      _drawLabel(canvas, pt + const Offset(10, -14), nodeLbl,
          darkMode ? Colors.white : const Color(0xFF0F172A));
    }

    // 8. Hệ trục tọa độ 3D Triad kiểu ANSYS ở góc dưới phải
    _drawCoordinateTriad(canvas, Offset(size.width - 56, size.height - 56));
  }

  /// Dựng khối hộp chữ nhật 3D theo trục toàn cục X, Y, Z (bản đế, sườn, móng bê tông)
  void _addBox3D(
    List<_Face3D> faces,
    _Vec3 center,
    double sx,
    double sy,
    double sz,
    Color color, {
    double alpha = 0.98,
    Color edgeColor = const Color(0x880F172A),
  }) {
    final hx = 0.5 * sx, hy = 0.5 * sy, hz = 0.5 * sz;
    final p000 = _Vec3(center.x - hx, center.y - hy, center.z - hz);
    final p100 = _Vec3(center.x + hx, center.y - hy, center.z - hz);
    final p110 = _Vec3(center.x + hx, center.y + hy, center.z - hz);
    final p010 = _Vec3(center.x - hx, center.y + hy, center.z - hz);
    final p001 = _Vec3(center.x - hx, center.y - hy, center.z + hz);
    final p101 = _Vec3(center.x + hx, center.y - hy, center.z + hz);
    final p111 = _Vec3(center.x + hx, center.y + hy, center.z + hz);
    final p011 = _Vec3(center.x - hx, center.y + hy, center.z + hz);
    final quads = [
      [p001, p101, p111, p011], // +Z
      [p100, p000, p010, p110], // -Z
      [p000, p100, p101, p001], // -Y
      [p110, p010, p011, p111], // +Y
      [p000, p001, p011, p010], // -X
      [p100, p110, p111, p101], // +X
    ];
    for (final q in quads) {
      final d = q.map((v) => cam.toCameraSpace(v).z).reduce((a, b) => a + b) / 4.0;
      faces.add(_Face3D(verts: q, baseColor: color, depth: d, alpha: alpha, edgeColor: edgeColor));
    }
  }

  /// Đùn đa giác XY (bản mã cắt vát) thành tấm thép 3D dày [zMin, zMax]
  void _addExtrudedPolyXY(
    List<_Face3D> faces,
    List<Offset> poly,
    double zMin,
    double zMax,
    Color color, {
    double alpha = 0.94,
    Color edgeColor = const Color(0xAA93C5FD),
  }) {
    if (poly.length < 3) return;
    final n = poly.length;
    final back = [for (final pt in poly) _Vec3(pt.dx, pt.dy, zMin)];
    final front = [for (final pt in poly) _Vec3(pt.dx, pt.dy, zMax)];
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final q = [back[i], front[i], front[j], back[j]];
      final d = q.map((v) => cam.toCameraSpace(v).z).reduce((a, b) => a + b) / 4.0;
      faces.add(_Face3D(verts: q, baseColor: color, depth: d, alpha: alpha, edgeColor: edgeColor));
    }
    final dBack = back.map((v) => cam.toCameraSpace(v).z).reduce((a, b) => a + b) / n;
    final dFront = front.map((v) => cam.toCameraSpace(v).z).reduce((a, b) => a + b) / n;
    faces.add(_Face3D(verts: back.reversed.toList(), baseColor: color, depth: dBack, alpha: alpha, edgeColor: edgeColor));
    faces.add(_Face3D(verts: front, baseColor: color, depth: dFront, alpha: alpha, edgeColor: edgeColor));
  }

  List<Offset> _convexHullXY(List<Offset> pts) {
    if (pts.length <= 3) return pts;
    final sorted = List<Offset>.from(pts)
      ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  /// Dựng toàn bộ chi tiết gia công chế tạo 3D tại các nút (bản mã, bu-lông/hàn/chốt & gối móng)
  void _addFabricationConnections3D(List<_Face3D> faces, List<_Vec3> nodePos3D) {
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
    final spanLen = math.max(maxX - minX, maxY - minY);
    final reach = (spanLen * 0.105).clamp(110.0, 220.0);

    // Mặt cắt lục giác bu-lông 3D (6 cạnh) & trục con lăn tròn 3D (10 cạnh)
    final hexBoltProfile = [
      for (int k = 0; k < 6; k++)
        Offset(13.0 * math.cos(k * math.pi / 3.0), 13.0 * math.sin(k * math.pi / 3.0)),
    ];
    final rollerProfile = _circleProfile(44.0);
    final clevisPinProfile = _circleProfile(64.0);

    for (int i = 0; i < model.nNodes; i++) {
      final p = nodePos3D[i];
      final sup = i < model.nodeSupports.length ? model.nodeSupports[i] : NodeSupportType.free;
      final isTop = model.coords[i][1] > midY + 1e-3;
      final isRight = model.coords[i][0] > midX + 1e-3;

      final hullPts = <Offset>[];
      double maxHalfW = 52.0;

      for (int e = 0; e < model.nElems; e++) {
        final n1 = model.conn[e][0] - 1;
        final n2 = model.conn[e][1] - 1;
        if (n1 != i && n2 != i) continue;
        final other = n1 == i ? n2 : n1;
        final dir3 = (nodePos3D[other] - p).normalized();
        final dir2 = Offset(dir3.x, dir3.y);
        final perp2 = Offset(-dir2.dy, dir2.dx);
        final dims = model.sectionDimsForElem(e);
        final hw = (dims.height * 0.55).clamp(45.0, 92.0);
        maxHalfW = math.max(maxHalfW, hw);

        final p2 = Offset(p.x, p.y);
        hullPts.add(p2 + dir2 * reach + perp2 * (hw + 14.0));
        hullPts.add(p2 + dir2 * reach - perp2 * (hw + 14.0));
        hullPts.add(p2 + perp2 * (hw + 10.0));
        hullPts.add(p2 - perp2 * (hw + 10.0));

        // Chi tiết liên kết đầu thanh: Bu-lông lục giác 3D / Đường hàn góc 3D / Chốt Clevis 3D
        if (connectionType == ConnectionDetailType.boltedGusset) {
          for (final dAlong in [reach * 0.44, reach * 0.78]) {
            for (final off in [-hw * 0.48, hw * 0.48]) {
              final bx = p.x + dir2.dx * dAlong + perp2.dx * off;
              final by = p.y + dir2.dy * dAlong + perp2.dy * off;
              // Dựng riêng mũ bu-lông mặt trước (+Z) và đai ốc mặt sau (-Z) nhô nổi trên bề mặt bản mã!
              _addPrismFaces(
                faces,
                _Vec3(bx, by, 60.0),
                _Vec3(bx, by, 78.0),
                hexBoltProfile,
                const Color(0xFFFACC15),
                alpha: 1.0,
              );
              _addPrismFaces(
                faces,
                _Vec3(bx, by, -78.0),
                _Vec3(bx, by, -60.0),
                hexBoltProfile,
                const Color(0xFFEAB308),
                alpha: 1.0,
              );
            }
          }
        } else if (connectionType == ConnectionDetailType.weldedGusset) {
          // 2 dải đường hàn góc 3D màu cam sáng nổi trên hai mặt tiếp giáp bản mã
          final weldProfile = [
            const Offset(-8, -8),
            const Offset(8, -8),
            const Offset(8, 8),
            const Offset(-8, 8),
          ];
          for (final sgn in [-1.0, 1.0]) {
            final wa = _Vec3(
              p.x + dir2.dx * (reach * 0.22) + perp2.dx * (hw * sgn),
              p.y + dir2.dy * (reach * 0.22) + perp2.dy * (hw * sgn),
              64.0,
            );
            final wb = _Vec3(
              p.x + dir2.dx * (reach * 0.94) + perp2.dx * (hw * sgn),
              p.y + dir2.dy * (reach * 0.94) + perp2.dy * (hw * sgn),
              64.0,
            );
            _addPrismFaces(faces, wa, wb, weldProfile, const Color(0xFFF97316));
            _addPrismFaces(
              faces,
              _Vec3(wa.x, wa.y, -64.0),
              _Vec3(wb.x, wb.y, -64.0),
              weldProfile,
              const Color(0xFFF97316),
            );
          }
        }
      }

      // Kéo dài tai bản mã nối tới bản đế theo đúng hướng nút đã chọn (↓ / ↑ / ← / →)
      final dir = model.resolvedDirectionFor(i);
      final out3 = _dirOut3D(dir);
      final tang3 = _Vec3(-out3.y, out3.x, 0.0);
      if (sup != NodeSupportType.free) {
        final cExt = Offset(p.x + out3.x * 95.0, p.y + out3.y * 95.0);
        hullPts.add(cExt - Offset(tang3.x * 80.0, tang3.y * 80.0));
        hullPts.add(cExt + Offset(tang3.x * 80.0, tang3.y * 80.0));
      }

      // Đùn 2 tấm bản mã kẹp 3D màu xanh công nghiệp ở mặt trước & mặt sau nút
      final hull = _convexHullXY(hullPts);
      _addExtrudedPolyXY(faces, hull, 44.0, 60.0, const Color(0xFF1D4ED8), alpha: 0.90);
      _addExtrudedPolyXY(faces, hull, -60.0, -44.0, const Color(0xFF1E40AF), alpha: 0.90);

      // Chốt bản lề Clevis 3D Ø60 nếu chọn kiểu Tai chốt
      if (connectionType == ConnectionDetailType.pinnedClevis) {
        _addPrismFaces(
          faces,
          _Vec3(p.x, p.y, -88.0),
          _Vec3(p.x, p.y, 88.0),
          clevisPinProfile,
          const Color(0xFFF59E0B),
        );
      }

      // CHI TIẾT GỐI TỰA CHẾ TẠO 3D XOAY ĐỦ 4 HƯỚNG (BẢN ĐẾ, SƯỜN, BU-LÔNG NEO, MÓNG / CON LĂN / LÒ XO)
      const steelCol = Color(0xFF64748B);
      const concreteCol = Color(0xFF475569);
      const anchorCol = Color(0xFFFACC15);
      final isHorizDir = dir == SupportDirection.left || dir == SupportDirection.right;

      void addOrientedBox(_Vec3 c, double alongOut, double acrossTang, double dz, Color col) {
        _addBox3D(
          faces,
          c,
          isHorizDir ? alongOut : acrossTang,
          isHorizDir ? acrossTang : alongOut,
          dz,
          col,
        );
      }

      if (sup == NodeSupportType.pin) {
        final bpCenter = p + out3 * 108.0;
        addOrientedBox(bpCenter, 26, 270, 180, steelCol);
        addOrientedBox(bpCenter - out3 * 42.0 - tang3 * 75.0, 62, 16, 130, const Color(0xFF475569));
        addOrientedBox(bpCenter - out3 * 42.0 + tang3 * 75.0, 62, 16, 130, const Color(0xFF475569));
        addOrientedBox(bpCenter + out3 * 52.0, 78, 350, 240, concreteCol);
        for (final off in [-105.0, 105.0]) {
          for (final az in [-62.0, 62.0]) {
            addOrientedBox(bpCenter - out3 * 12.0 + tang3 * off + _Vec3(0, 0, az), 52, 18, 18, anchorCol);
          }
        }
      } else if (sup == NodeSupportType.rollerX || sup == NodeSupportType.rollerXSpringX || sup == NodeSupportType.rollerY) {
        addOrientedBox(p + out3 * 102.0, 22, 230, 165, steelCol);
        for (final off in [-58.0, 58.0]) {
          final rc = p + out3 * 136.0 + tang3 * off;
          _addPrismFaces(
            faces,
            _Vec3(rc.x, rc.y, -78.0),
            _Vec3(rc.x, rc.y, 78.0),
            rollerProfile,
            const Color(0xFF38BDF8),
          );
        }
        addOrientedBox(p + out3 * 170.0, 24, 270, 185, steelCol);
        addOrientedBox(p + out3 * 212.0, 60, 330, 230, concreteCol);
      }

      if (sup.hasSpringY) {
        final rawDir = i < model.supportDirections.length ? model.supportDirections[i] : SupportDirection.auto;
        final sgn = rawDir == SupportDirection.top
            ? 1.0
            : (rawDir == SupportDirection.bottom ? -1.0 : (isTop ? 1.0 : -1.0));
        final p0y = model.coords[i][1];
        _addBox3D(faces, _Vec3(p.x, p.y + sgn * 96.0, 0), 210, 20, 155, steelCol);
        _addBox3D(faces, _Vec3(p.x, p0y + sgn * 195.0, 0), 245, 22, 180, steelCol);
        _addBox3D(faces, _Vec3(p.x, p0y + sgn * 234.0, 0), 300, 56, 220, concreteCol);
      }
      if (sup.hasSpringX) {
        final rawDir = i < model.supportDirections.length ? model.supportDirections[i] : SupportDirection.auto;
        final sgn = rawDir == SupportDirection.right
            ? 1.0
            : (rawDir == SupportDirection.left ? -1.0 : (isRight ? 1.0 : -1.0));
        final p0x = model.coords[i][0];
        _addBox3D(faces, _Vec3(p.x + sgn * 96.0, p.y, 0), 20, 210, 155, steelCol);
        _addBox3D(faces, _Vec3(p0x + sgn * 195.0, p.y, 0), 22, 245, 180, steelCol);
        _addBox3D(faces, _Vec3(p0x + sgn * 234.0, p.y, 0), 56, 300, 220, concreteCol);
      }
    }
  }

  /// Vẽ cuộn lò xo thép công nghiệp 3D (nối giữa tấm ép và bản đế) cho chế độ chi tiết chế tạo
  void _drawFabricationOverlays3D(Canvas canvas, List<_Vec3> nodePos3D) {
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
    final sprPaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round;

    void drawCoil3D(_Vec3 a, _Vec3 b, _Vec3 perp) {
      final path = Path();
      final s0 = cam.project(a).pt;
      path.moveTo(s0.dx, s0.dy);
      for (int c = 0; c < 5; c++) {
        final t1 = (c + 0.25) / 5.0;
        final t2 = (c + 0.75) / 5.0;
        final q1 = cam.project(a + (b - a) * t1 + perp * 22.0).pt;
        final q2 = cam.project(a + (b - a) * t2 - perp * 22.0).pt;
        path.lineTo(q1.dx, q1.dy);
        path.lineTo(q2.dx, q2.dy);
      }
      final s1 = cam.project(b).pt;
      path.lineTo(s1.dx, s1.dy);
      canvas.drawPath(path, sprPaint);
    }

    for (int i = 0; i < model.nNodes; i++) {
      final sup = i < model.nodeSupports.length ? model.nodeSupports[i] : NodeSupportType.free;
      if (!sup.hasSpring) continue;
      final p = nodePos3D[i];
      final isTop = model.coords[i][1] > midY + 1e-3;
      final isRight = model.coords[i][0] > midX + 1e-3;
      if (sup.hasSpringY) {
        final rawDir = i < model.supportDirections.length ? model.supportDirections[i] : SupportDirection.auto;
        final sgn = rawDir == SupportDirection.top
            ? 1.0
            : (rawDir == SupportDirection.bottom ? -1.0 : (isTop ? 1.0 : -1.0));
        final p0y = model.coords[i][1];
        for (final off in [-48.0, 48.0]) {
          drawCoil3D(
            _Vec3(p.x + off, p.y + sgn * 106.0, 0),
            _Vec3(p.x + off, p0y + sgn * 184.0, 0),
            const _Vec3(1, 0, 0),
          );
        }
      }
      if (sup.hasSpringX) {
        final rawDir = i < model.supportDirections.length ? model.supportDirections[i] : SupportDirection.auto;
        final sgn = rawDir == SupportDirection.right
            ? 1.0
            : (rawDir == SupportDirection.left ? -1.0 : (isRight ? 1.0 : -1.0));
        final p0x = model.coords[i][0];
        for (final off in [-48.0, 48.0]) {
          drawCoil3D(
            _Vec3(p.x + sgn * 106.0, p.y + off, 0),
            _Vec3(p0x + sgn * 184.0, p.y + off, 0),
            const _Vec3(0, 1, 0),
          );
        }
      }
    }
  }

  _Vec3 _dirOut3D(SupportDirection dir) {
    switch (dir) {
      case SupportDirection.top:
        return const _Vec3(0, 1, 0);
      case SupportDirection.left:
        return const _Vec3(-1, 0, 0);
      case SupportDirection.right:
        return const _Vec3(1, 0, 0);
      case SupportDirection.bottom:
      case SupportDirection.auto:
        return const _Vec3(0, -1, 0);
    }
  }

  void _drawSupports3D(Canvas canvas, List<_Vec3> nodePos3D) {
    final supStroke = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final supFill = Paint()..color = const Color(0xCC1E293B);
    final springStroke = Paint()
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
    final unit = (math.max(maxX - minX, maxY - minY) * 0.085).clamp(55.0, 140.0);

    void drawSpring3D(_Vec3 a3, _Vec3 b3, _Vec3 perp3, String tag) {
      final path = Path();
      final s0 = cam.project(a3).pt;
      path.moveTo(s0.dx, s0.dy);
      const coils = 5;
      final lead = 0.14;
      final amp = unit * 0.28;
      final pLeadA = cam.project(a3 + (b3 - a3) * lead).pt;
      path.lineTo(pLeadA.dx, pLeadA.dy);
      for (int c = 0; c < coils; c++) {
        final t1 = lead + (1.0 - 2 * lead) * (c + 0.25) / coils;
        final t2 = lead + (1.0 - 2 * lead) * (c + 0.75) / coils;
        final q1 = cam.project(a3 + (b3 - a3) * t1 + perp3 * amp).pt;
        final q2 = cam.project(a3 + (b3 - a3) * t2 - perp3 * amp).pt;
        path.lineTo(q1.dx, q1.dy);
        path.lineTo(q2.dx, q2.dy);
      }
      final pLeadB = cam.project(a3 + (b3 - a3) * (1.0 - lead)).pt;
      final sEnd = cam.project(b3).pt;
      path.lineTo(pLeadB.dx, pLeadB.dy);
      path.lineTo(sEnd.dx, sEnd.dy);
      canvas.drawPath(path, springStroke);
      final g1 = cam.project(b3 - perp3 * (unit * 0.65)).pt;
      final g2 = cam.project(b3 + perp3 * (unit * 0.65)).pt;
      canvas.drawLine(g1, g2, supStroke);
      _drawLabel(canvas, sEnd + const Offset(6, -6), tag, const Color(0xFFFBBF24));
    }

    for (int i = 0; i < model.nNodes; i++) {
      final sup = i < model.nodeSupports.length ? model.nodeSupports[i] : NodeSupportType.free;
      if (sup == NodeSupportType.free) continue;
      final p = nodePos3D[i];
      final p0 = _Vec3(model.coords[i][0], model.coords[i][1], 0.0);
      final isTop = model.coords[i][1] > midY + 1e-3;
      final isRight = model.coords[i][0] > midX + 1e-3;

      final dir = model.resolvedDirectionFor(i);
      final out3 = _dirOut3D(dir);
      final tang3 = _Vec3(-out3.y, out3.x, 0.0);

      if (sup == NodeSupportType.pin) {
        final a = cam.project(p + out3 * (unit * 0.25)).pt;
        final b = cam.project(p + out3 * (unit * 1.15) - tang3 * (unit * 0.65)).pt;
        final c = cam.project(p + out3 * (unit * 1.15) + tang3 * (unit * 0.65)).pt;
        final tri = Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..lineTo(c.dx, c.dy)..close();
        canvas.drawPath(tri, supFill);
        canvas.drawPath(tri, supStroke);
        final g1 = cam.project(p + out3 * (unit * 1.2) - tang3 * (unit * 0.9)).pt;
        final g2 = cam.project(p + out3 * (unit * 1.2) + tang3 * (unit * 0.9)).pt;
        canvas.drawLine(g1, g2, supStroke);
      } else if (sup == NodeSupportType.rollerX || sup == NodeSupportType.rollerXSpringX || sup == NodeSupportType.rollerY) {
        final a = cam.project(p + out3 * (unit * 0.25)).pt;
        final b = cam.project(p + out3 * (unit * 1.05) - tang3 * (unit * 0.6)).pt;
        final c = cam.project(p + out3 * (unit * 1.05) + tang3 * (unit * 0.6)).pt;
        final tri = Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..lineTo(c.dx, c.dy)..close();
        canvas.drawPath(tri, supFill);
        canvas.drawPath(tri, supStroke);
        final w1 = cam.project(p + out3 * (unit * 1.28) - tang3 * (unit * 0.3)).pt;
        final w2 = cam.project(p + out3 * (unit * 1.28) + tang3 * (unit * 0.3)).pt;
        canvas.drawCircle(w1, 3.8, Paint()..color = const Color(0xFF38BDF8));
        canvas.drawCircle(w2, 3.8, Paint()..color = const Color(0xFF38BDF8));
        final g1 = cam.project(p + out3 * (unit * 1.5) - tang3 * (unit * 0.85)).pt;
        final g2 = cam.project(p + out3 * (unit * 1.5) + tang3 * (unit * 0.85)).pt;
        canvas.drawLine(g1, g2, supStroke);
      }

      if (sup.hasSpringY) {
        final rawDir = i < model.supportDirections.length ? model.supportDirections[i] : SupportDirection.auto;
        final sgn = rawDir == SupportDirection.top
            ? 1.0
            : (rawDir == SupportDirection.bottom ? -1.0 : (isTop ? 1.0 : -1.0));
        final anchorY = _Vec3(p.x, p0.y + sgn * unit * 1.8, 0.0);
        drawSpring3D(p + _Vec3(0, sgn * unit * 0.25, 0), anchorY, const _Vec3(1, 0, 0), 'kᵧ');
      }
      if (sup.hasSpringX) {
        final rawDir = i < model.supportDirections.length ? model.supportDirections[i] : SupportDirection.auto;
        final sgn = rawDir == SupportDirection.right
            ? 1.0
            : (rawDir == SupportDirection.left ? -1.0 : (isRight ? 1.0 : -1.0));
        final anchorX = _Vec3(p0.x + sgn * unit * 1.8, p.y, 0.0);
        drawSpring3D(p + _Vec3(sgn * unit * 0.25, 0, 0), anchorX, const _Vec3(0, 1, 0), 'kₓ');
      }
    }
  }

  void _drawCoordinateTriad(Canvas canvas, Offset origin) {
    final axes = [
      (const _Vec3(1, 0, 0), const Color(0xFFFF5252), 'X'),
      (const _Vec3(0, 1, 0), const Color(0xFF22C55E), 'Y'),
      (const _Vec3(0, 0, 1), const Color(0xFF38BDF8), 'Z'),
    ];
    for (final (v, col, lbl) in axes) {
      final rot = cam.toCameraSpace(cam.center + v * 100.0);
      final end = origin + Offset(rot.x * 0.36, -rot.y * 0.36);
      _drawArrow(canvas, origin, end, col, 2.2);
      _drawLabel(canvas, end + const Offset(3, -6), lbl, col);
    }
  }

  void _drawArrow(Canvas canvas, Offset a, Offset b, Color col, double w) {
    canvas.drawLine(a, b, Paint()..color = col..strokeWidth = w..strokeCap = StrokeCap.round);
    final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
    const h = 10.0;
    final p1 = Offset(b.dx - h * math.cos(ang - 0.45), b.dy - h * math.sin(ang - 0.45));
    final p2 = Offset(b.dx - h * math.cos(ang + 0.45), b.dy - h * math.sin(ang + 0.45));
    canvas.drawPath(
      Path()..moveTo(b.dx, b.dy)..lineTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..close(),
      Paint()..color = col,
    );
  }

  void _drawBadge3D(Canvas canvas, Offset center, String text, Color borderColor) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: darkMode ? Colors.white : const Color(0xFF0F172A),
          fontSize: 9.2,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(center: center, width: tp.width + 10, height: tp.height + 5);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(rrect, Paint()..color = darkMode ? const Color(0xBF0B1220) : const Color(0xD9FFFFFF));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawLabel(Canvas canvas, Offset pos, String text, Color col) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: col,
          fontSize: 10.2,
          fontWeight: FontWeight.bold,
          fontFamily: 'DejaVuSans',
          shadows: [
            Shadow(color: darkMode ? Colors.black : Colors.white, blurRadius: 3),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _Ansys3DPainter oldDelegate) => true;
}
