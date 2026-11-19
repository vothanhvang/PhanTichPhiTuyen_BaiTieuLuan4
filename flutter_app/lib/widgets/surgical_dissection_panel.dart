// ============================================================================
// BẢNG "PHẪU THUẬT" MẶT CẮT NGANG & MỔ DỌC THANH (INTERACTIVE SURGICAL LAB)
// ============================================================================
// Cho phép người học:
//   1. Chọn bất kỳ thanh nào và trượt vị trí vết cắt ξ ∈ [0, 1] dọc thanh.
//   2. Chạm/kéo BẤT KỲ ĐIỂM THỚ (η, ζ) nào bên trong mặt cắt ngang (Chữ I,
//      Ống tròn rỗng, Hộp vuông, Thanh tròn đặc) để xem trực tiếp:
//        - Ứng suất pháp σ_xx, ứng suất tương đương von Mises, τ_max (Mohr)
//        - Biến dạng dọc ε_xx và co/nở ngang do hiệu ứng Poisson ε_yy = -ν·ε_xx
//        - Biến dạng tiết diện trước (nét đứt) vs sau hiệu ứng Poisson (nét liền)!
//   3. Kéo thanh "Độ lệch ban đầu e₀/L" để chứng kiến hiệu ứng khuếch đại bậc hai
//      P-δ (NSA_4 Slide 27) làm biến thiên ứng suất từ đều sang lệch hai mép!
//   4. Xem đồ thị "Mổ dọc thanh" (ứng suất trục trung hòa & hai mép dọc trục s).
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/calfem_engine.dart';
import 'ansys_colorbar.dart';

class SurgicalDissectionPanel extends StatelessWidget {
  final TrussModelData model;
  final TrussAnalysisResult resultNL;
  final TrussAnalysisResult resultLin;
  final ProbeInspection probe;
  final int selectedElem;
  final double probeXi;
  final double etaNorm;
  final double zetaNorm;
  final double imperfectionRatio;
  final bool darkMode;
  final ValueChanged<int> onElemChanged;
  final ValueChanged<double> onXiChanged;
  final void Function(double eta, double zeta) onFiberChanged;
  final ValueChanged<double> onImperfectionChanged;

  const SurgicalDissectionPanel({
    super.key,
    required this.model,
    required this.resultNL,
    required this.resultLin,
    required this.probe,
    required this.selectedElem,
    required this.probeXi,
    required this.etaNorm,
    required this.zetaNorm,
    required this.imperfectionRatio,
    required this.darkMode,
    required this.onElemChanged,
    required this.onXiChanged,
    required this.onFiberChanged,
    required this.onImperfectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final textSub = darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Thanh tiêu đề Phòng Phẫu thuật
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0E7490), Color(0xFF1D4ED8)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Icons.biotech, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PHẪU THUẬT MẶT CẮT & KHẢO SÁT NỘI BỘ',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    Text(
                      'Cắt mở từng thanh tại vị trí ξ bất kỳ — soi ứng suất, biến dạng & hiệu ứng Poisson bên trong',
                      style: TextStyle(color: Color(0xFFE0F2FE), fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Chọn thanh & trượt vị trí cắt ξ + Độ lệch ban đầu e0/L
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Chọn thanh:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      isDense: true,
                      value: selectedElem.clamp(0, model.nElems - 1),
                      items: [
                        for (int e = 0; e < model.nElems; e++)
                          DropdownMenuItem(
                            value: e,
                            child: Text(
                              'Thanh ${e + 1} (${model.memberLabels[e]}) — σ=${resultNL.stressMpa[e].toStringAsFixed(2)} MPa',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) onElemChanged(v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Vị trí lát cắt dọc thanh ξ = s/L₀:', style: TextStyle(fontSize: 11, color: textSub)),
                  Text(
                    '${probeXi.toStringAsFixed(2)}  (s = ${probe.sMm.toStringAsFixed(1)} mm)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                  ),
                ],
              ),
              Slider(
                value: probeXi,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                onChanged: onXiChanged,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Độ lệch ban đầu e₀/L (hiệu ứng P-δ NSA_4):', style: TextStyle(fontSize: 11, color: textSub)),
                  Text(
                    imperfectionRatio <= 0 ? '0 (Khớp lý tưởng)' : 'L/${(1.0 / imperfectionRatio).round()}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                  ),
                ],
              ),
              Slider(
                value: imperfectionRatio,
                min: 0.0,
                max: 0.005,
                divisions: 50,
                onChanged: onImperfectionChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Bản đồ mặt cắt ngang phẫu thuật (tương tác chạm chọn điểm thớ (η, ζ))
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mặt cắt ngang: ${model.sectionShape.label}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
              ),
              const SizedBox(height: 2),
              Text(
                'Chạm hoặc kéo trực tiếp vào tiết diện để soi thớ (η, ζ)',
                style: TextStyle(fontSize: 10, color: textSub),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 215,
                child: LayoutBuilder(
                  builder: (context, cons) {
                    void pick(Offset local) {
                      final cx = cons.maxWidth / 2;
                      final cy = cons.maxHeight / 2;
                      final half = math.min(cons.maxWidth, cons.maxHeight) * 0.38;
                      final zN = ((local.dx - cx) / half).clamp(-1.0, 1.0);
                      final eN = (-(local.dy - cy) / half).clamp(-1.0, 1.0);
                      onFiberChanged(eN, zN);
                    }

                    return GestureDetector(
                      onTapDown: (d) => pick(d.localPosition),
                      onPanUpdate: (d) => pick(d.localPosition),
                      child: CustomPaint(
                        size: Size(cons.maxWidth, cons.maxHeight),
                        painter: _CrossSectionSurgicalPainter(
                          model: model,
                          resultNL: resultNL,
                          resultLin: resultLin,
                          elemIndex: selectedElem,
                          xi: probeXi,
                          etaNorm: etaNorm,
                          zetaNorm: zetaNorm,
                          imperfectionRatio: imperfectionRatio,
                          darkMode: darkMode,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Bảng chỉ số chi tiết tại đúng điểm khảo sát (e, ξ, η, ζ)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Thông số cơ học tại điểm khảo sát (Probe Inspector)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(height: 6),
              _metricRow('Trạng thái làm việc', probe.stateLabel,
                  valColor: probe.nKn > 1e-4
                      ? const Color(0xFFF43F5E)
                      : (probe.nKn < -1e-4 ? const Color(0xFF38BDF8) : const Color(0xFF10B981))),
              _metricRow('Tọa độ biến dạng (x, y)', '(${probe.xCur.toStringAsFixed(3)}, ${probe.yCur.toStringAsFixed(3)}) mm'),
              _metricRow('Chuyển vị nội suy (ux, uy)', '(${probe.uxMm.toStringAsFixed(5)}, ${probe.uyMm.toStringAsFixed(5)}) mm'),
              _metricRow('Lực dọc N (Phi tuyến vs Tuyến tính)',
                  '${probe.nKn.toStringAsFixed(4)} vs ${probe.nLinearKn.toStringAsFixed(4)} kN'),
              _metricRow('Ứng suất pháp σ_xx tại thớ (η=${etaNorm.toStringAsFixed(2)})',
                  '${probe.sigmaXxMpa.toStringAsFixed(4)} MPa',
                  valColor: const Color(0xFFFBBF24)),
              _metricRow('  • Thành phần dọc trục N/A', '${probe.sigmaAxialMpa.toStringAsFixed(4)} MPa'),
              _metricRow('  • Thành phần uốn phụ P-δ', '${probe.sigmaBendingMpa.toStringAsFixed(4)} MPa (DAF=${probe.daf.toStringAsFixed(4)})'),
              _metricRow('Ứng suất von Mises / τ_max (Mohr)',
                  '${probe.sigmaVonMisesMpa.toStringAsFixed(3)} / ${probe.tauMaxMohrMpa.toStringAsFixed(3)} MPa'),
              _metricRow('Biến dạng dọc trục ε_xx', '${probe.epsXxMicro.toStringAsFixed(2)} με'),
              _metricRow('Co/nở ngang Poisson ε_yy = ε_zz', '${probe.epsPoissonMicro.toStringAsFixed(2)} με'),
              _metricRow('Mật độ năng lượng biến dạng u₀', '${probe.energyDensityKjM3.toStringAsFixed(3)} kJ/m³'),
              _metricRow('Góc xoay vật rắn thanh Δθ', '${probe.rotationDeg.toStringAsFixed(5)}°'),
              _metricRow('Tải oằn cục bộ Euler (tham khảo)', '${probe.pEulerLocalKn.toStringAsFixed(1)} kN'),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Biểu đồ Mổ dọc thanh (Longitudinal Cutaway)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mổ dọc thanh (Longitudinal Cutaway: s = 0 → L₀)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 145,
                child: CustomPaint(
                  size: const Size(double.infinity, 145),
                  painter: _LongitudinalCutPainter(
                    model: model,
                    resultNL: resultNL,
                    resultLin: resultLin,
                    elemIndex: selectedElem,
                    xi: probeXi,
                    imperfectionRatio: imperfectionRatio,
                    darkMode: darkMode,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricRow(String label, String val, {Color? valColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 10.6,
                    color: darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569))),
          ),
          Text(
            val,
            style: TextStyle(
              fontSize: 10.6,
              fontWeight: FontWeight.bold,
              fontFamily: 'DejaVuSansMono',
              color: valColor ?? (darkMode ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrossSectionSurgicalPainter extends CustomPainter {
  final TrussModelData model;
  final TrussAnalysisResult resultNL;
  final TrussAnalysisResult resultLin;
  final int elemIndex;
  final double xi;
  final double etaNorm;
  final double zetaNorm;
  final double imperfectionRatio;
  final bool darkMode;

  _CrossSectionSurgicalPainter({
    required this.model,
    required this.resultNL,
    required this.resultLin,
    required this.elemIndex,
    required this.xi,
    required this.etaNorm,
    required this.zetaNorm,
    required this.imperfectionRatio,
    required this.darkMode,
  });

  bool _inside(double eta, double zeta) {
    switch (model.sectionShape) {
      case SectionShape.solidRod:
        return eta * eta + zeta * zeta <= 1.0;
      case SectionShape.circTube:
        final r2 = eta * eta + zeta * zeta;
        return r2 >= 0.72 && r2 <= 1.0;
      case SectionShape.boxSection:
        return eta.abs() >= 0.76 || zeta.abs() >= 0.76;
      case SectionShape.iSection:
        return eta.abs() >= 0.76 || zeta.abs() <= 0.14;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final half = math.min(size.width, size.height) * 0.39;

    // Lưới trục tâm mặt cắt (y, z)
    final axisP = Paint()
      ..color = darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(14, cy), Offset(size.width - 14, cy), axisP);
    canvas.drawLine(Offset(cx, 12), Offset(cx, size.height - 12), axisP);

    // Tính phạm vi ứng suất trên mặt cắt để chuẩn hóa bản đồ màu nhiệt
    final pTop = CalfemNonlinearEngine.probeMember(
      model: model, resultNL: resultNL, resultLin: resultLin,
      elemIndex: elemIndex, xi: xi, etaNorm: 1.0, zetaNorm: 0.0, imperfectionRatio: imperfectionRatio,
    );
    final pBot = CalfemNonlinearEngine.probeMember(
      model: model, resultNL: resultNL, resultLin: resultLin,
      elemIndex: elemIndex, xi: xi, etaNorm: -1.0, zetaNorm: 0.0, imperfectionRatio: imperfectionRatio,
    );
    double sMin = math.min(pTop.sigmaXxMpa, pBot.sigmaXxMpa);
    double sMax = math.max(pTop.sigmaXxMpa, pBot.sigmaXxMpa);
    final isUniform = (sMax - sMin).abs() < 1e-6;
    if (isUniform) {
      sMin = -55.0;
      sMax = 55.0;
    }

    // Hệ số phóng đại biến dạng ngang Poisson trực quan (kéo -> thót lại; nén -> phình ra)
    final poissonVisual = 1.0 + (-model.nu * resultNL.strain[elemIndex]).clamp(-0.002, 0.002) * 350.0;

    // Vẽ lưới phần tử màu bên trong tiết diện (với biến dạng ngang Poisson)
    const nGrid = 22;
    final cellPx = (2.0 * half / nGrid) * poissonVisual;
    for (int iy = 0; iy < nGrid; iy++) {
      final eta = -1.0 + 2.0 * (iy + 0.5) / nGrid;
      for (int iz = 0; iz < nGrid; iz++) {
        final zeta = -1.0 + 2.0 * (iz + 0.5) / nGrid;
        if (!_inside(eta, zeta)) continue;
        final pCell = CalfemNonlinearEngine.probeMember(
          model: model, resultNL: resultNL, resultLin: resultLin,
          elemIndex: elemIndex, xi: xi, etaNorm: eta, zetaNorm: zeta, imperfectionRatio: imperfectionRatio,
        );
        final t = ((pCell.sigmaXxMpa - sMin) / math.max(1e-9, sMax - sMin)).clamp(0.0, 1.0);
        final px = cx + zeta * half * poissonVisual;
        final py = cy - eta * half * poissonVisual;
        canvas.drawRect(
          Rect.fromCenter(center: Offset(px, py), width: cellPx + 0.6, height: cellPx + 0.6),
          Paint()..color = ansysRainbowColor(t),
        );
      }
    }

    // Đường viền ban đầu (nét trắng mờ) so sánh hiệu ứng Poisson
    _drawSectionOutline(canvas, cx, cy, half, Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);

    // Đường viền sau biến dạng Poisson (sáng nét)
    _drawSectionOutline(canvas, cx, cy, half * poissonVisual, Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8);

    // Điểm khảo sát thớ đang chọn (η, ζ)
    final selX = cx + zetaNorm * half * poissonVisual;
    final selY = cy - etaNorm * half * poissonVisual;
    canvas.drawCircle(Offset(selX, selY), 8.0, Paint()..color = Colors.white.withValues(alpha: 0.3));
    canvas.drawCircle(Offset(selX, selY), 4.5, Paint()..color = const Color(0xFFFFEA00));
    canvas.drawCircle(
      Offset(selX, selY),
      4.5,
      Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1.4,
    );

    // Chú thích trực quan hiệu ứng Poisson
    final note = resultNL.nForcesN[elemIndex] > 1e-3
        ? 'Kéo → Tiết diện CO ngang (Poisson)'
        : (resultNL.nForcesN[elemIndex] < -1e-3 ? 'Nén → Tiết diện PHÌNH ngang (Poisson)' : 'Không lực');
    final tp = TextPainter(
      text: TextSpan(
        text: note,
        style: TextStyle(color: const Color(0xFF38BDF8), fontSize: 9.8, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(8, size.height - 16));
  }

  void _drawSectionOutline(Canvas canvas, double cx, double cy, double r, Paint p) {
    switch (model.sectionShape) {
      case SectionShape.solidRod:
        canvas.drawCircle(Offset(cx, cy), r, p);
        break;
      case SectionShape.circTube:
        canvas.drawCircle(Offset(cx, cy), r, p);
        canvas.drawCircle(Offset(cx, cy), r * 0.85, p);
        break;
      case SectionShape.boxSection:
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: 2 * r, height: 2 * r), p);
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: 1.52 * r, height: 1.52 * r), p);
        break;
      case SectionShape.iSection:
        final tf = 0.24 * r;
        final tw = 0.14 * r;
        final path = Path()
          ..moveTo(cx - r, cy - r)
          ..lineTo(cx + r, cy - r)
          ..lineTo(cx + r, cy - r + tf)
          ..lineTo(cx + tw, cy - r + tf)
          ..lineTo(cx + tw, cy + r - tf)
          ..lineTo(cx + r, cy + r - tf)
          ..lineTo(cx + r, cy + r)
          ..lineTo(cx - r, cy + r)
          ..lineTo(cx - r, cy + r - tf)
          ..lineTo(cx - tw, cy + r - tf)
          ..lineTo(cx - tw, cy - r + tf)
          ..lineTo(cx - r, cy - r + tf)
          ..close();
        canvas.drawPath(path, p);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _CrossSectionSurgicalPainter oldDelegate) => true;
}

class _LongitudinalCutPainter extends CustomPainter {
  final TrussModelData model;
  final TrussAnalysisResult resultNL;
  final TrussAnalysisResult resultLin;
  final int elemIndex;
  final double xi;
  final double imperfectionRatio;
  final bool darkMode;

  _LongitudinalCutPainter({
    required this.model,
    required this.resultNL,
    required this.resultLin,
    required this.elemIndex,
    required this.xi,
    required this.imperfectionRatio,
    required this.darkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 44.0, padR = 14.0, padT = 14.0, padB = 22.0;
    final plotW = size.width - padL - padR;
    final plotH = size.height - padT - padB;
    if (plotW <= 10 || plotH <= 10) return;

    const n = 25;
    final top = <double>[];
    final mid = <double>[];
    final bot = <double>[];
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      top.add(CalfemNonlinearEngine.probeMember(
        model: model, resultNL: resultNL, resultLin: resultLin,
        elemIndex: elemIndex, xi: t, etaNorm: 1.0, imperfectionRatio: imperfectionRatio,
      ).sigmaXxMpa);
      mid.add(CalfemNonlinearEngine.probeMember(
        model: model, resultNL: resultNL, resultLin: resultLin,
        elemIndex: elemIndex, xi: t, etaNorm: 0.0, imperfectionRatio: imperfectionRatio,
      ).sigmaXxMpa);
      bot.add(CalfemNonlinearEngine.probeMember(
        model: model, resultNL: resultNL, resultLin: resultLin,
        elemIndex: elemIndex, xi: t, etaNorm: -1.0, imperfectionRatio: imperfectionRatio,
      ).sigmaXxMpa);
    }

    final all = [...top, ...mid, ...bot];
    double yMin = all.reduce(math.min);
    double yMax = all.reduce(math.max);
    if ((yMax - yMin).abs() < 0.2) {
      yMin -= 1.0;
      yMax += 1.0;
    } else {
      final pad = (yMax - yMin) * 0.18;
      yMin -= pad;
      yMax += pad;
    }

    Offset toPt(int idx, double val) => Offset(
          padL + plotW * idx / (n - 1),
          padT + plotH * (1.0 - (val - yMin) / (yMax - yMin)),
        );

    // Khung trục
    final frameP = Paint()
      ..color = darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(padL, padT, plotW, plotH), frameP);

    void drawSeries(List<double> arr, Color col, double w) {
      final path = Path()..moveTo(toPt(0, arr[0]).dx, toPt(0, arr[0]).dy);
      for (int i = 1; i < arr.length; i++) {
        final p = toPt(i, arr[i]);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = w);
    }

    drawSeries(mid, const Color(0xFF38BDF8), 1.8);
    drawSeries(top, const Color(0xFFF43F5E), 2.2);
    drawSeries(bot, const Color(0xFF22C55E), 2.2);

    // Đường dao cắt dọc tại ξ
    final cutX = padL + plotW * xi;
    canvas.drawLine(
      Offset(cutX, padT),
      Offset(cutX, padT + plotH),
      Paint()..color = const Color(0xFFFFEA00)..strokeWidth = 1.6,
    );

    void txt(Offset o, String s) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(color: darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569), fontSize: 8.8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o);
    }

    txt(Offset(2, padT - 4), yMax.toStringAsFixed(1));
    txt(Offset(2, padT + plotH - 8), yMin.toStringAsFixed(1));
    txt(Offset(padL, padT + plotH + 4), 'ξ=0 (Đầu 1)');
    txt(Offset(padL + plotW - 56, padT + plotH + 4), 'ξ=1 (Đầu 2)');
  }

  @override
  bool shouldRepaint(covariant _LongitudinalCutPainter oldDelegate) => true;
}
