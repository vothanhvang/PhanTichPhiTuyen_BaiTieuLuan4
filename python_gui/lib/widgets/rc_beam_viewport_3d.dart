// ============================================================================
// KHUNG NHÌN 3D TƯƠNG TÁC CHO DẦM BÊ TÔNG CỐT THÉP PHI TUYẾN (PHƯƠNG PHÁP THỚ)
// ============================================================================
// Hiển thị mô hình 3D dầm BTCT với:
//   • Khối bê tông 3D phân đoạn theo lưới PTHH (bán trong suốt để nhìn thấu
//     bộ khung cốt thép dọc As, As' và cốt cứng thép hình chữ I bên trong!).
//   • Bản đồ màu trường ứng suất / mô-men / độ võng / tỷ lệ độ cứng EI_eff/EI0%.
//   • Mặt cắt phẫu thuật thớ 3D tại x/L chẻ ngang thân dầm, hiển thị trực tiếp
//     từng dải thớ bê tông nén/kéo/nứt và đường trục trung hòa ngay trong 3D!
//   • Gối tựa 3D hai đầu tùy chỉnh + Mũi tên ngoại lực 3 điểm / 4 điểm tại a.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/rc_beam_engine.dart';
import 'ansys_colorbar.dart';

class RcBeamViewport3D extends StatefulWidget {
  final RcBeamAnalysisResult result;
  final RcBeamContourField field;
  final double deformScale;
  final double probeXNorm;
  final bool darkMode;
  final bool showColorBar;
  final ValueChanged<double> onProbeXChanged;
  final ValueChanged<bool>? onToggleColorBar;

  const RcBeamViewport3D({
    super.key,
    required this.result,
    required this.field,
    required this.deformScale,
    required this.probeXNorm,
    required this.darkMode,
    this.showColorBar = true,
    required this.onProbeXChanged,
    this.onToggleColorBar,
  });

  @override
  State<RcBeamViewport3D> createState() => _RcBeamViewport3DState();
}

class _RcBeamViewport3DState extends State<RcBeamViewport3D> {
  double _yaw = -0.48;
  double _pitch = 0.28;
  double _zoom = 1.05;
  Offset _pan = Offset.zero;
  double _baseZoom = 1.05;
  Offset _lastFocal = Offset.zero;
  bool _panMode = false;
  bool _rightButtonDown = false;
  bool _translucentConcrete = true;

  void _setPreset(double yaw, double pitch) => setState(() {
        _yaw = yaw;
        _pitch = pitch;
      });

  void _fitView() => setState(() {
        _yaw = -0.48;
        _pitch = 0.28;
        _zoom = 1.05;
        _pan = Offset.zero;
      });

  double _valAt(RcSectionState sec, double vMm, double momentKnm) {
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
    double minV = double.infinity, maxV = -double.infinity;
    for (final el in widget.result.elements) {
      for (int k = 0; k < 3; k++) {
        final gs = el.gaussSections[k];
        final xi = k == 0 ? 0.1127 : (k == 1 ? 0.5 : 0.8873);
        final v = (1.0 - xi) * el.dElem[1] + xi * el.dElem[4];
        final val = _valAt(gs, v, gs.mForceNmm / 1e6);
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
            Text('Hướng dẫn thao tác 3D — Dầm BTCT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          '• Kéo chuột trái: xoay tự do mô hình Dầm BTCT 360°.\n'
          '• Chạm vào thân dầm: đặt mặt cắt phẫu thuật thớ 3D tại tọa độ x/L bất kỳ.\n'
          '• Nút "X-Quang": bật/tắt bê tông bán trong suốt để soi rõ cốt thép dọc & cốt cứng I bên trong.\n'
          '• Cuộn chuột / chụm 2 ngón: phóng to / thu nhỏ.\n'
          '• Kéo chuột phải (hoặc bật Pan): dịch chuyển khung hình.',
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
        final cam = _BeamCam3D(
          yaw: _yaw,
          pitch: _pitch,
          zoom: _zoom,
          pan: _pan,
          spanMm: widget.result.config.spanMm,
          viewport: sz,
        );

        return Stack(
          children: [
            Listener(
              onPointerDown: (e) => _rightButtonDown = (e.buttons & kSecondaryMouseButton) != 0,
              onPointerUp: (_) => _rightButtonDown = false,
              onPointerSignal: (s) {
                if (s is PointerScrollEvent) {
                  setState(() {
                    _zoom = (_zoom * (s.scrollDelta.dy < 0 ? 1.12 : 0.89)).clamp(0.45, 4.0);
                  });
                }
              },
              child: GestureDetector(
                onTapUp: (d) {
                  final pA = cam.project(const _V3(0, 0, 0)).pt;
                  final pB = cam.project(_V3(widget.result.config.spanMm, 0, 0)).pt;
                  final ab = pB - pA;
                  final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
                  if (ab2 > 1e-4) {
                    final t = (((d.localPosition.dx - pA.dx) * ab.dx + (d.localPosition.dy - pA.dy) * ab.dy) / ab2)
                        .clamp(0.0, 1.0);
                    widget.onProbeXChanged(t);
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
                    if (d.scale != 1.0) _zoom = (_baseZoom * d.scale).clamp(0.45, 4.0);
                    if (_panMode || _rightButtonDown || d.pointerCount >= 2) {
                      _pan += delta;
                    } else {
                      _yaw += delta.dx * 0.0085;
                      _pitch = (_pitch + delta.dy * 0.0085).clamp(-1.42, 1.42);
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
                    painter: _RcBeam3DPainter(
                      result: widget.result,
                      field: widget.field,
                      minVal: range.minV,
                      maxVal: range.maxV,
                      cam: cam,
                      deformScale: widget.deformScale,
                      probeXNorm: widget.probeXNorm,
                      darkMode: widget.darkMode,
                      translucentConcrete: _translucentConcrete,
                    ),
                  ),
                ),
              ),
            ),

            // Thang màu góc trên trái
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

            // Thanh góc nhìn 3D + nút X-Quang cốt thép
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
                    _btn('ISO', () => _setPreset(-0.48, 0.28)),
                    _btn('XY', () => _setPreset(0.0, 0.0)),
                    _btn('XZ', () => _setPreset(0.0, 1.38)),
                    _btn('Fit', _fitView),
                    FilterChip(
                      label: const Text('X-Quang', style: TextStyle(fontSize: 10.0)),
                      selected: _translucentConcrete,
                      visualDensity: VisualDensity.compact,
                      selectedColor: const Color(0xFF06B6D4).withValues(alpha: 0.35),
                      onSelected: (v) => setState(() => _translucentConcrete = v),
                    ),
                    ChoiceChip(
                      label: Text(_panMode ? 'Pan' : 'Xoay 3D', style: const TextStyle(fontSize: 10.0)),
                      selected: _panMode,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) => setState(() => _panMode = v),
                    ),
                  ],
                ),
              ),
            ),

            // Nút trợ giúp nhỏ góc dưới trái
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
                        'Thao tác 3D',
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

  Widget _btn(String lbl, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: widget.darkMode ? 0.9 : 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            lbl,
            style: TextStyle(
              fontSize: 10.3,
              fontWeight: FontWeight.bold,
              color: widget.darkMode ? const Color(0xFF38BDF8) : const Color(0xFF0F3D6E),
            ),
          ),
        ),
      );
}

class _V3 {
  final double x, y, z;
  const _V3(this.x, this.y, this.z);
  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  _V3 operator *(double s) => _V3(x * s, y * s, z * s);
  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) => _V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  _V3 normalized() {
    final l = math.sqrt(x * x + y * y + z * z);
    return l > 1e-12 ? _V3(x / l, y / l, z / l) : const _V3(0, 0, 1);
  }
}

class _BeamCam3D {
  final double yaw, pitch, zoom;
  final Offset pan;
  final double spanMm;
  final Size viewport;
  late final _V3 center;
  late final double scale;

  _BeamCam3D({
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.pan,
    required this.spanMm,
    required this.viewport,
  }) {
    center = _V3(0.5 * spanMm, 0, 0);
    scale = (math.min(viewport.width, viewport.height) * 0.64 / math.max(1000.0, spanMm)) * zoom;
  }

  _V3 toCam(_V3 p) {
    final d = p - center;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final x1 = d.x * cy + d.z * sy;
    final z1 = -d.x * sy + d.z * cy;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final y2 = d.y * cp - z1 * sp;
    final z2 = d.y * sp + z1 * cp;
    return _V3(x1, y2, z2);
  }

  ({Offset pt, double depth}) project(_V3 p) {
    final c = toCam(p);
    const camDist = 7500.0;
    final persp = camDist / math.max(600.0, camDist - c.z);
    final sx = viewport.width * 0.52 + pan.dx + c.x * scale * persp;
    final sy = viewport.height * 0.52 + pan.dy - c.y * scale * persp;
    return (pt: Offset(sx, sy), depth: c.z);
  }
}

class _Quad3D {
  final List<_V3> verts;
  final Color color;
  final double alpha;
  final Color edge;
  final double depth;
  const _Quad3D({
    required this.verts,
    required this.color,
    required this.depth,
    this.alpha = 1.0,
    this.edge = const Color(0x550F172A),
  });
}

class _RcBeam3DPainter extends CustomPainter {
  final RcBeamAnalysisResult result;
  final RcBeamContourField field;
  final double minVal, maxVal;
  final _BeamCam3D cam;
  final double deformScale;
  final double probeXNorm;
  final bool darkMode;
  final bool translucentConcrete;

  _RcBeam3DPainter({
    required this.result,
    required this.field,
    required this.minVal,
    required this.maxVal,
    required this.cam,
    required this.deformScale,
    required this.probeXNorm,
    required this.darkMode,
    required this.translucentConcrete,
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

  void _addBox(List<_Quad3D> quads, _V3 a, _V3 b, double hy, double hz, Color col, {double alpha = 1.0, Color? edge}) {
    final p000 = _V3(a.x, a.y - hy, a.z - hz);
    final p010 = _V3(a.x, a.y + hy, a.z - hz);
    final p011 = _V3(a.x, a.y + hy, a.z + hz);
    final p001 = _V3(a.x, a.y - hy, a.z + hz);
    final p100 = _V3(b.x, b.y - hy, b.z - hz);
    final p110 = _V3(b.x, b.y + hy, b.z - hz);
    final p111 = _V3(b.x, b.y + hy, b.z + hz);
    final p101 = _V3(b.x, b.y - hy, b.z + hz);
    final ec = edge ?? const Color(0x550F172A);
    final list = [
      [p001, p101, p111, p011],
      [p100, p000, p010, p110],
      [p010, p011, p111, p110],
      [p000, p100, p101, p001],
      [p000, p001, p011, p010],
      [p100, p110, p111, p101],
    ];
    for (final q in list) {
      final d = q.map((v) => cam.toCam(v).z).reduce((u, v) => u + v) / 4.0;
      quads.add(_Quad3D(verts: q, color: col, depth: d, alpha: alpha, edge: ec));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cfg = result.config;
    final L = cfg.spanMm;
    final h = cfg.heightMm;
    final b = cfg.widthMm;
    final hy = 0.5 * h;
    final hz = 0.5 * b;

    // 1. Lưới sàn 3D
    final floorPaint = Paint()
      ..color = darkMode ? const Color(0x331E293B) : const Color(0x4494A3B8)
      ..strokeWidth = 0.9;
    final floorY = -hy - 220.0;
    final step = L / 8.0;
    for (int i = 0; i <= 8; i++) {
      final x = i * step;
      canvas.drawLine(cam.project(_V3(x, floorY, -450)).pt, cam.project(_V3(x, floorY, 450)).pt, floorPaint);
    }
    for (double z = -450; z <= 450; z += 150) {
      canvas.drawLine(cam.project(_V3(0, floorY, z)).pt, cam.project(_V3(L, floorY, z)).pt, floorPaint);
    }

    // Hệ số phóng đại độ võng an toàn trong 3D
    final maxRaw = result.maxAbsDeflectionMm * deformScale;
    final effScale = maxRaw > (L * 0.14) ? (L * 0.14) / math.max(1e-6, result.maxAbsDeflectionMm) : deformScale;
    final quads = <_Quad3D>[];
    final spanVal = (maxVal - minVal).abs() < 1e-9 ? 1.0 : (maxVal - minVal);

    // 2. Dựng khối bê tông 3D phân đoạn + cốt thép dọc 3D + cốt cứng chữ I 3D!
    final nBarsBot = cfg.asBotMm2 > 1400 ? 4 : (cfg.asBotMm2 > 500 ? 3 : 2);
    final nBarsTop = cfg.asTopMm2 > 600 ? 3 : 2;
    final yBotBar = -hy + cfg.coverBotMm;
    final yTopBar = hy - cfg.coverTopMm;
    final concreteAlpha = translucentConcrete ? 0.34 : 0.92;

    for (final el in result.elements) {
      const sub = 3;
      for (int s = 0; s < sub; s++) {
        final xi0 = s / sub;
        final xi1 = (s + 1) / sub;
        final xiM = 0.5 * (xi0 + xi1);
        final xa = el.x1Mm + xi0 * el.lengthMm;
        final xb = el.x1Mm + xi1 * el.lengthMm;
        final p0 = RcBeamFiberEngine.probeBeamAt(result, xa / L);
        final p1 = RcBeamFiberEngine.probeBeamAt(result, xb / L);
        final pM = RcBeamFiberEngine.probeBeamAt(result, (el.x1Mm + xiM * el.lengthMm) / L);

        final ya = p0.vMm * effScale;
        final yb = p1.vMm * effScale;
        final tCol = ((_valAt(pM.section, pM.vMm, pM.momentKnm) - minVal) / spanVal).clamp(0.0, 1.0);
        final cCol = ansysRainbowColor(tCol);

        // Thanh cốt thép kéo đáy (As)
        if (cfg.asBotMm2 > 0) {
          final rCol = pM.section.steelYielded ? const Color(0xFFFF3B30) : const Color(0xFFFACC15);
          for (int k = 0; k < nBarsBot; k++) {
            final zk = nBarsBot == 1 ? 0.0 : (-hz + 36.0) + (2.0 * hz - 72.0) * k / (nBarsBot - 1);
            _addBox(quads, _V3(xa, ya + yBotBar, zk), _V3(xb, yb + yBotBar, zk), 12.0, 12.0, rCol);
          }
        }
        // Thanh cốt thép nén đỉnh (As')
        if (cfg.asTopMm2 > 0) {
          for (int k = 0; k < nBarsTop; k++) {
            final zk = nBarsTop == 1 ? 0.0 : (-hz + 38.0) + (2.0 * hz - 76.0) * k / (nBarsTop - 1);
            _addBox(quads, _V3(xa, ya + yTopBar, zk), _V3(xb, yb + yTopBar, zk), 9.0, 9.0, const Color(0xFFCBD5E1));
          }
        }
        // Dầm cốt cứng chữ I 3D (nếu bật!)
        if (cfg.hasRigidCore) {
          final ch = 0.5 * cfg.coreHMm;
          final cb = 0.5 * cfg.coreBMm;
          final tf = cfg.coreTfMm;
          final tw = 0.5 * cfg.coreTwMm;
          const coreCol = Color(0xFF38BDF8);
          _addBox(quads, _V3(xa, ya + ch - 0.5 * tf, 0), _V3(xb, yb + ch - 0.5 * tf, 0), 0.5 * tf, cb, coreCol);
          _addBox(quads, _V3(xa, ya - ch + 0.5 * tf, 0), _V3(xb, yb - ch + 0.5 * tf, 0), 0.5 * tf, cb, coreCol);
          _addBox(quads, _V3(xa, ya, 0), _V3(xb, yb, 0), ch - tf, tw, const Color(0xFF0284C7));
        }

        // Vỏ bê tông 3D phân đoạn theo phần tử
        _addBox(
          quads,
          _V3(xa, ya, 0),
          _V3(xb, yb, 0),
          hy,
          hz,
          cCol,
          alpha: concreteAlpha,
          edge: darkMode ? const Color(0x7794A3B8) : const Color(0x771E293B),
        );
      }
    }

    // 3. Mặt cắt phẫu thuật thớ 3D ngay tại probeXNorm (hiển thị từng dải thớ nén/kéo/nứt!)
    final probe = RcBeamFiberEngine.probeBeamAt(result, probeXNorm);
    final cutX = probeXNorm * L;
    final cutY = probe.vMm * effScale;
    final concFibers = probe.section.fibers.where((f) => f.spec.kind == 'concrete').toList();
    for (final f in concFibers) {
      Color fc;
      if (f.isCrushed) {
        fc = const Color(0xFF9333EA);
      } else if (f.isCracked) {
        fc = const Color(0xFFEF4444);
      } else if (f.stressMpa < 0) {
        final t = (f.stressMpa.abs() / math.max(1.0, cfg.fcMpa)).clamp(0.0, 1.0);
        fc = Color.lerp(const Color(0xFF38BDF8), const Color(0xFF1D4ED8), t)!;
      } else {
        fc = const Color(0xFFF59E0B);
      }
      final y0 = cutY + f.spec.yMm - 0.5 * f.spec.heightMm;
      final y1 = cutY + f.spec.yMm + 0.5 * f.spec.heightMm;
      final verts = [
        _V3(cutX, y0, -hz - 10),
        _V3(cutX, y0, hz + 10),
        _V3(cutX, y1, hz + 10),
        _V3(cutX, y1, -hz - 10),
      ];
      final d = verts.map((v) => cam.toCam(v).z).reduce((u, v) => u + v) / 4.0;
      quads.add(_Quad3D(verts: verts, color: fc, depth: d + 12.0, alpha: 0.92, edge: const Color(0xAA00E5FF)));
    }

    // 4. Khối gối tựa 3D hai đầu
    final vLeft = result.dGlobal[1] * effScale;
    final vRight = result.dGlobal[3 * (result.nNodes - 1) + 1] * effScale;
    if (cfg.leftSupport != BeamSupportType.free) {
      _addBox(quads, _V3(-75, vLeft - hy - 60, 0), _V3(75, vLeft - hy - 60, 0), 60, hz + 35, const Color(0xFF475569));
    }
    if (cfg.rightSupport != BeamSupportType.free) {
      _addBox(quads, _V3(L - 75, vRight - hy - 60, 0), _V3(L + 75, vRight - hy - 60, 0), 60, hz + 35, const Color(0xFF475569));
    }

    // 5. Sắp xếp Z-Buffer & Đổ bóng Lambert 3D
    quads.sort((a, b) => a.depth.compareTo(b.depth));
    final light = const _V3(0.45, 0.65, 0.85).normalized();

    for (final q in quads) {
      final c0 = cam.toCam(q.verts[0]);
      final c1 = cam.toCam(q.verts[1]);
      final c2 = cam.toCam(q.verts[2]);
      final n = (c1 - c0).cross(c2 - c0).normalized();
      final diff = n.dot(light).abs();
      final shade = (0.42 + 0.58 * diff).clamp(0.30, 1.05);
      final col = Color.fromARGB(
        (q.alpha * 255).round().clamp(0, 255),
        (q.color.r * 255 * shade).round().clamp(0, 255),
        (q.color.g * 255 * shade).round().clamp(0, 255),
        (q.color.b * 255 * shade).round().clamp(0, 255),
      );
      final path = Path();
      final p0 = cam.project(q.verts[0]).pt;
      path.moveTo(p0.dx, p0.dy);
      for (int i = 1; i < q.verts.length; i++) {
        final pi = cam.project(q.verts[i]).pt;
        path.lineTo(pi.dx, pi.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = col);
      canvas.drawPath(
        path,
        Paint()
          ..color = q.edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75,
      );
    }

    // 6. Mũi tên tải trọng 3D (3 điểm hoặc 4 điểm)
    final a = cfg.effectiveAMm;
    final loadXs = cfg.loadType == RcBeamLoadType.threePoint ? [a] : [a, L - a];
    final qEach = cfg.loadType == RcBeamLoadType.threePoint ? cfg.loadQKn : 0.5 * cfg.loadQKn;
    for (final lx in loadXs) {
      final pr = RcBeamFiberEngine.probeBeamAt(result, lx / L);
      final topY = pr.vMm * effScale + hy;
      final sTop = cam.project(_V3(lx, topY + 380, 0)).pt;
      final sTip = cam.project(_V3(lx, topY + 12, 0)).pt;
      _drawArrow(canvas, sTop, sTip, const Color(0xFFFF2E55), 3.4);
      _drawText(
        canvas,
        sTop + const Offset(-28, -18),
        cfg.loadType == RcBeamLoadType.threePoint
            ? 'Q = ${qEach.toStringAsFixed(1)} kN'
            : 'Q/2 = ${qEach.toStringAsFixed(1)} kN',
        const Color(0xFFFF5A79),
        10.5,
        bold: true,
      );
    }

    // 7. Nhãn lát cắt phẫu thuật thớ 3D (tự căn lề trong khung hình, không bao giờ tràn mép phải!)
    final cutPt = cam.project(_V3(cutX, cutY + hy + 40, hz)).pt;
    final eiPct = 100.0 * probe.section.eiEffNmm2 / math.max(1.0, result.eiGrossNmm2);
    final cutTp = TextPainter(
      text: TextSpan(
        text: 'LÁT CẮT THỚ x=${cutX.toStringAsFixed(0)} mm\n'
            'M=${probe.momentKnm.toStringAsFixed(1)} kN·m | x_NA=${probe.section.xNeutralDepthMm.toStringAsFixed(0)} mm | EI=${eiPct.toStringAsFixed(0)}%',
        style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 9.1, fontWeight: FontWeight.bold, height: 1.28),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(160.0, size.width - 28.0));
    final bx = (cutPt.dx + 10).clamp(12.0, math.max(12.0, size.width - cutTp.width - 22.0)).toDouble();
    final by = (cutPt.dy - cutTp.height - 16).clamp(62.0, math.max(62.0, size.height - cutTp.height - 20.0)).toDouble();
    final bgR = RRect.fromRectAndRadius(Rect.fromLTWH(bx - 6, by - 4, cutTp.width + 12, cutTp.height + 8), const Radius.circular(6));
    canvas.drawRRect(bgR, Paint()..color = darkMode ? const Color(0xD90B1528) : const Color(0xE6FFFFFF));
    canvas.drawRRect(bgR, Paint()..color = const Color(0xFF00E5FF)..style = PaintingStyle.stroke..strokeWidth = 1.0);
    cutTp.paint(canvas, Offset(bx, by));
  }

  void _drawArrow(Canvas canvas, Offset a, Offset b, Color col, double w) {
    canvas.drawLine(a, b, Paint()..color = col..strokeWidth = w..strokeCap = StrokeCap.round);
    final d = b - a;
    final l = d.distance;
    if (l < 1e-3) return;
    final u = d / l;
    final n = Offset(-u.dy, u.dx);
    final head = Path()
      ..moveTo(b.dx, b.dy)
      ..lineTo(b.dx - u.dx * 11 + n.dx * 5.5, b.dy - u.dy * 11 + n.dy * 5.5)
      ..lineTo(b.dx - u.dx * 11 - n.dx * 5.5, b.dy - u.dy * 11 - n.dy * 5.5)
      ..close();
    canvas.drawPath(head, Paint()..color = col);
  }

  void _drawText(Canvas canvas, Offset pos, String txt, Color col, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: txt,
        style: TextStyle(color: col, fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.w500, height: 1.25),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _RcBeam3DPainter old) => true;
}
