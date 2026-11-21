// ============================================================================
// BẢNG "PHẪU THUẬT" MẶT CẮT NGANG & MỔ DỌC THANH (INTERACTIVE SURGICAL LAB)
// ============================================================================
// Cho phép người học:
//   1. Chọn bất kỳ thanh nào và trượt mượt vị trí vết cắt ξ ∈ [0, 1] dọc thanh.
//   2. Quan sát hình ảnh mặt cắt ngang THAY ĐỔI TỨC THỜI & NHẠY CAO theo ξ:
//        - Thang màu nhiệt cố định theo biên độ cực đại tại giữa thanh (ξ=0.5)
//          nên tại hai đầu khớp (ξ=0, 1) tiết diện xanh đồng đều (uốn = 0),
//          càng trượt vào giữa thanh (ξ→0.5) trường màu đỏ-xanh càng bùng nở!
//        - Độ võng ngang P-δ: tiết diện dịch lệch khỏi trục gốc theo sin(πξ).
//        - Biến dạng ngang Poisson cục bộ từng thớ (hiệu ứng yên ngựa anticlastic).
//        - Biểu đồ phân bố ứng suất σ(η) bên cạnh biến thiên từ hình chữ nhật
//          (ở đầu thanh) sang hình thang nghiêng dốc (ở giữa thanh)!
//   3. Chạm/kéo BẤT KỲ ĐIỂM THỚ (η, ζ) nào bên trong mặt cắt ngang để soi
//      σ_xx, von Mises, τ_max (Mohr), ε_xx và co/nở ngang Poisson.
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
                      'Cắt mở từng thanh tại vị trí ξ bất kỳ — soi ứng suất, võng P-δ & Poisson tức thời',
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
                              'Thanh ${e + 1} (${model.memberLabels[e]}) [${model.sectionShapeForElem(e).shortLabel}] — σ=${resultNL.stressMpa[e].toStringAsFixed(2)} MPa',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.2),
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
                  Expanded(
                    child: Text(
                      'Vị trí lát cắt dọc thanh ξ = s/L₀:',
                      style: TextStyle(fontSize: 11, color: textSub),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${probeXi.toStringAsFixed(2)}  (s = ${probe.sMm.toStringAsFixed(1)} mm)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                  ),
                ],
              ),
              Slider(
                value: probeXi.clamp(0.0, 1.0),
                min: 0.0,
                max: 1.0,
                onChanged: onXiChanged,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Độ lệch ban đầu e₀/L (hiệu ứng P-δ NSA_4):',
                      style: TextStyle(fontSize: 11, color: textSub),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    imperfectionRatio <= 1e-6 ? '0 (Khớp lý tưởng)' : 'L/${(1.0 / imperfectionRatio).round()}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                  ),
                ],
              ),
              Slider(
                value: imperfectionRatio.clamp(0.0, 0.010),
                min: 0.0,
                max: 0.010,
                divisions: 100,
                onChanged: onImperfectionChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Bản đồ mặt cắt ngang phẫu thuật (tương tác chạm chọn điểm thớ (η, ζ) + biểu đồ ứng suất σ(η))
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Mặt cắt T${selectedElem + 1} (${model.memberLabels[selectedElem.clamp(0, model.nElems - 1)]}): ${model.sectionShapeForElem(selectedElem).label}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.3),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      'sin(πξ) = ${(math.sin(math.pi * probeXi) * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Builder(builder: (_) {
                final shapeE = model.sectionShapeForElem(selectedElem);
                final d = model.sectionDimsForElem(selectedElem);
                final l0 = model.initialLength(selectedElem.clamp(0, model.nElems - 1));
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: darkMode ? const Color(0xFF0A1426) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    '${d.formatSpec(shapeE)}  •  L₀=${l0.toStringAsFixed(1)} mm\n'
                    'A=${d.areaMm2.toStringAsFixed(0)} mm²  •  Ix=${(d.ix / 1e4).toStringAsFixed(1)}  •  Iy=${(d.iy / 1e4).toStringAsFixed(1)} cm⁴  •  i=${d.rGyrationMin.toStringAsFixed(1)} mm',
                    style: TextStyle(
                      fontSize: 9.7,
                      height: 1.35,
                      fontFamily: 'DejaVuSansMono',
                      color: darkMode ? const Color(0xFFBAE6FD) : const Color(0xFF0F3D6E),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
              Text(
                'Kéo thanh ξ ở trên để thấy ứng suất & độ võng P-δ thay đổi trực tiếp; chạm tiết diện để soi thớ (η, ζ)',
                style: TextStyle(fontSize: 9.8, color: textSub),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 238,
                child: LayoutBuilder(
                  builder: (context, cons) {
                    final d = model.sectionDimsForElem(selectedElem);
                    void pick(Offset local) {
                      final cx = cons.maxWidth * 0.36;
                      final cy = cons.maxHeight * 0.48;
                      final halfMax = math.min(cons.maxWidth * 0.58, cons.maxHeight) * 0.34;
                      final maxDim = math.max(1e-3, math.max(d.height, d.width));
                      final halfX = math.max(halfMax * 0.24, halfMax * (d.width / maxDim));
                      final halfY = math.max(halfMax * 0.24, halfMax * (d.height / maxDim));
                      final zN = ((local.dx - cx) / halfX).clamp(-1.0, 1.0);
                      final eN = (-(local.dy - cy) / halfY).clamp(-1.0, 1.0);
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

  bool _inside(double eta, double zeta, SectionDimensions dims) {
    final xMm = zeta * 0.5 * dims.width;
    final yMm = eta * 0.5 * dims.height;
    return dims.containsLocalPoint(model.sectionShapeForElem(elemIndex), xMm, yMm);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Bố trí mặt cắt bên trái (0..68%) theo ĐÚNG tỷ lệ thực H:B và biểu đồ σ(η) động bên phải (70..98%)
    final dims = model.sectionDimsForElem(elemIndex);
    final cx0 = size.width * 0.36;
    final cy0 = size.height * 0.48;
    final halfMax = math.min(size.width * 0.58, size.height) * 0.34;
    final maxDim = math.max(1e-3, math.max(dims.height, dims.width));
    final halfX = math.max(halfMax * 0.24, halfMax * (dims.width / maxDim));
    final halfY = math.max(halfMax * 0.24, halfMax * (dims.height / maxDim));

    // 1. Tính biên độ ứng suất CỐ ĐỊNH TOÀN THANH tại giữa nhịp (ξ = 0.50)
    //    (Không chuẩn hóa cục bộ theo ξ -> khi kéo ξ từ 0 → 0.5 → 1, màu nhiệt
    //    thay đổi rõ rệt từ đồng đều xanh lá ở hai đầu khớp sang đỏ-xanh rực rỡ ở giữa thanh!)
    final pMidTop = CalfemNonlinearEngine.probeMember(
      model: model, resultNL: resultNL, resultLin: resultLin,
      elemIndex: elemIndex, xi: 0.5, etaNorm: 1.0, zetaNorm: 0.0, imperfectionRatio: imperfectionRatio,
    );
    final pMidBot = CalfemNonlinearEngine.probeMember(
      model: model, resultNL: resultNL, resultLin: resultLin,
      elemIndex: elemIndex, xi: 0.5, etaNorm: -1.0, zetaNorm: 0.0, imperfectionRatio: imperfectionRatio,
    );
    final pCurTop = CalfemNonlinearEngine.probeMember(
      model: model, resultNL: resultNL, resultLin: resultLin,
      elemIndex: elemIndex, xi: xi, etaNorm: 1.0, zetaNorm: 0.0, imperfectionRatio: imperfectionRatio,
    );
    final pCurMid = CalfemNonlinearEngine.probeMember(
      model: model, resultNL: resultNL, resultLin: resultLin,
      elemIndex: elemIndex, xi: xi, etaNorm: 0.0, zetaNorm: 0.0, imperfectionRatio: imperfectionRatio,
    );
    final pCurBot = CalfemNonlinearEngine.probeMember(
      model: model, resultNL: resultNL, resultLin: resultLin,
      elemIndex: elemIndex, xi: xi, etaNorm: -1.0, zetaNorm: 0.0, imperfectionRatio: imperfectionRatio,
    );

    double sMin = math.min(pMidTop.sigmaXxMpa, pMidBot.sigmaXxMpa);
    double sMax = math.max(pMidTop.sigmaXxMpa, pMidBot.sigmaXxMpa);
    final hasBendingRange = (sMax - sMin).abs() >= 1e-6;
    if (!hasBendingRange) {
      final allS = resultNL.stressMpa;
      sMin = allS.reduce(math.min) - 1.0;
      sMax = allS.reduce(math.max) + 1.0;
    }

    // 2. Độ nhạy hình học động theo vị trí cắt ξ:
    //    - Độ võng ngang P-δ: δ(ξ) = e₀ · DAF · sin(πξ) (dịch chuyển tâm mặt cắt khỏi trục gốc!)
    //    - Biến dạng ngang Poisson cục bộ từng thớ (hiệu ứng uốn yên ngựa anticlastic)
    final sinXi = math.sin(math.pi * xi);
    final nForce = resultNL.nForcesN[elemIndex];
    final impStrength = (imperfectionRatio / 0.002).clamp(0.0, 3.0);
    final dafBoost = pCurMid.daf.clamp(0.6, 2.5);
    final bowSign = nForce < 0 ? 1.0 : -1.0;
    final shiftY = (nForce.abs() > 1e-3 && imperfectionRatio > 1e-6)
        ? bowSign * sinXi * (6.5 + 4.5 * impStrength) * math.min(1.6, dafBoost)
        : 0.0;
    final shiftYClamped = shiftY.clamp(-16.0, 16.0);
    final cy = cy0 + shiftYClamped;

    final eps0 = resultNL.strain[elemIndex];
    final basePoisson = 1.0 + (-model.nu * eps0).clamp(-0.0025, 0.0025) * 420.0;
    final anticlasticAmp = (hasBendingRange ? 0.085 * sinXi * (nForce < 0 ? 1.0 : -1.0) * math.min(1.6, impStrength) : 0.0)
        .clamp(-0.14, 0.14);

    // Lưới trục tâm BAN ĐẦU (trục chuẩn cố định trước khi võng P-δ)
    final axisP = Paint()
      ..color = darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(10, cy0), Offset(size.width * 0.67, cy0), axisP);
    canvas.drawLine(Offset(cx0, 12), Offset(cx0, size.height - 20), axisP);

    // Đường viền mặt cắt BAN ĐẦU tại vị trí gốc (trước võng & trước Poisson)
    _drawSectionOutline(
      canvas,
      cx0,
      cy0,
      halfX,
      halfY,
      dims,
      Paint()
        ..color = (darkMode ? Colors.white : const Color(0xFF475569)).withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    // 3. Vẽ lưới phần tử màu nhiệt độ phân giải cao (44×44) theo đúng hình học thực
    const nGrid = 44;
    final baseCellW = 2.0 * halfX / nGrid;
    final baseCellH = 2.0 * halfY / nGrid;
    final sigmaMid = pCurMid.sigmaXxMpa;
    final sigmaSlope = pCurTop.sigmaXxMpa - sigmaMid;
    final sSpan = math.max(1e-9, sMax - sMin);
    for (int iy = 0; iy < nGrid; iy++) {
      final eta = -1.0 + 2.0 * (iy + 0.5) / nGrid;
      final rowScaleX = (basePoisson + anticlasticAmp * eta).clamp(0.78, 1.24);
      final cellW = baseCellW * rowScaleX + 0.7;
      final cellH = baseCellH * basePoisson + 0.7;
      final sigRow = sigmaMid + eta * sigmaSlope;
      final t = ((sigRow - sMin) / sSpan).clamp(0.0, 1.0);
      final cellPaint = Paint()..color = ansysRainbowColor(t);
      final py = cy - eta * halfY * basePoisson;
      for (int iz = 0; iz < nGrid; iz++) {
        final zeta = -1.0 + 2.0 * (iz + 0.5) / nGrid;
        if (!_inside(eta, zeta, dims)) continue;
        final px = cx0 + zeta * halfX * rowScaleX;
        canvas.drawRect(
          Rect.fromCenter(center: Offset(px, py), width: cellW, height: cellH),
          cellPaint,
        );
      }
    }

    // Đường viền mặt cắt HIỆN TẠI (đã dịch theo võng P-δ và co/phình ngang Poisson theo ξ)
    _drawDeformedOutline(
      canvas,
      cx0,
      cy,
      halfX,
      halfY,
      dims,
      basePoisson,
      anticlasticAmp,
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // Nhãn kích thước phủ bì H & W ngay trên hình cắt (tách khỏi mũi tên δ(ξ) bên trái)
    final dimTextCol = darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    _paintText(
      canvas,
      'H=${dims.height.toStringAsFixed(0)}',
      Offset(cx0 + halfX * basePoisson + 5, cy - 6),
      dimTextCol,
      8.2,
    );
    _paintText(
      canvas,
      'W=${dims.width.toStringAsFixed(0)} mm',
      Offset(cx0 - 22, math.min(size.height - 29, cy + halfY * basePoisson + 3)),
      dimTextCol,
      8.2,
    );

    // Mũi tên chỉ rõ độ võng δ(ξ) giữa tâm ban đầu và tâm sau võng P-δ
    if (shiftYClamped.abs() > 2.5) {
      final arrowP = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 1.8;
      final ax = math.max(14.0, cx0 - halfX - 10);
      canvas.drawLine(Offset(ax, cy0), Offset(ax, cy), arrowP);
      canvas.drawCircle(Offset(ax, cy), 3.0, Paint()..color = const Color(0xFFF59E0B));
      _paintText(
        canvas,
        'δ(ξ)',
        Offset(math.max(2.0, ax - 18), (cy0 + cy) * 0.5 - 6),
        const Color(0xFFF59E0B),
        8.4,
        bold: true,
      );
    }

    // Điểm khảo sát thớ đang chọn (η, ζ)
    final selScaleX = (basePoisson + anticlasticAmp * etaNorm).clamp(0.78, 1.24);
    final selX = cx0 + zetaNorm * halfX * selScaleX;
    final selY = cy - etaNorm * halfY * basePoisson;
    canvas.drawCircle(Offset(selX, selY), 8.0, Paint()..color = Colors.white.withValues(alpha: 0.3));
    canvas.drawCircle(Offset(selX, selY), 4.5, Paint()..color = const Color(0xFFFFEA00));
    canvas.drawCircle(
      Offset(selX, selY),
      4.5,
      Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1.4,
    );

    // 4. BIỂU ĐỒ PHÂN BỐ ỨNG SUẤT ĐỘNG σ(η) BÊN PHẢI (Trapezoid ↔ Rectangle khi kéo ξ!)
    final profLeft = size.width * 0.72;
    final profRight = size.width - 10;
    final profW = math.max(36.0, profRight - profLeft);
    final topY = cy - halfY * basePoisson;
    final botY = cy + halfY * basePoisson;

    final baseLineX = profLeft + profW * 0.45;
    canvas.drawLine(
      Offset(baseLineX, topY - 4),
      Offset(baseLineX, botY + 4),
      Paint()..color = (darkMode ? Colors.white : Colors.black).withValues(alpha: 0.25)..strokeWidth = 1.0,
    );

    final maxDelta = math.max(1e-6, (sMax - sMin) * 0.5);
    double xForSigma(double sig) {
      final normDev = ((sig - pCurMid.sigmaXxMpa) / maxDelta).clamp(-1.0, 1.0);
      return baseLineX + normDev * (profW * 0.44);
    }

    final xTop = xForSigma(pCurTop.sigmaXxMpa);
    final xBot = xForSigma(pCurBot.sigmaXxMpa);
    final trap = Path()
      ..moveTo(baseLineX, topY)
      ..lineTo(xTop, topY)
      ..lineTo(xBot, botY)
      ..lineTo(baseLineX, botY)
      ..close();
    canvas.drawPath(
      trap,
      Paint()..color = const Color(0xFF06B6D4).withValues(alpha: 0.24),
    );
    canvas.drawPath(
      trap,
      Paint()..color = const Color(0xFF38BDF8)..style = PaintingStyle.stroke..strokeWidth = 1.6,
    );

    for (int k = 0; k <= 6; k++) {
      final frac = k / 6.0;
      final yy = topY + (botY - topY) * frac;
      final xx = xTop + (xBot - xTop) * frac;
      final sigK = pCurTop.sigmaXxMpa + (pCurBot.sigmaXxMpa - pCurTop.sigmaXxMpa) * frac;
      final tk = ((sigK - sMin) / math.max(1e-9, sMax - sMin)).clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(baseLineX, yy),
        Offset(xx, yy),
        Paint()..color = ansysRainbowColor(tk)..strokeWidth = 2.0,
      );
      canvas.drawCircle(Offset(xx, yy), 2.2, Paint()..color = ansysRainbowColor(tk));
    }

    _paintText(canvas, 'Biểu đồ σ(η)', Offset(profLeft - 2, 4), const Color(0xFF94A3B8), 8.6, bold: true);
    _paintText(
      canvas,
      'Trên: ${pCurTop.sigmaXxMpa.toStringAsFixed(2)}',
      Offset(profLeft - 6, math.max(16, topY - 14)),
      const Color(0xFFF43F5E),
      8.4,
      bold: true,
    );
    _paintText(
      canvas,
      'Dưới: ${pCurBot.sigmaXxMpa.toStringAsFixed(2)}',
      Offset(profLeft - 6, math.min(size.height - 28, botY + 4)),
      const Color(0xFF38BDF8),
      8.4,
      bold: true,
    );

    final deltaBending = (pCurTop.sigmaXxMpa - pCurMid.sigmaXxMpa).abs();
    final stateTxt = nForce > 1e-3
        ? 'Kéo (CO ngang)'
        : (nForce < -1e-3 ? 'Nén (PHÌNH ngang)' : 'Không lực');
    final note = 'ξ=${xi.toStringAsFixed(2)} • $stateTxt • Δσ_uốn = ±${deltaBending.toStringAsFixed(3)} MPa';
    _paintText(canvas, note, Offset(6, size.height - 15), const Color(0xFF38BDF8), 9.2, bold: true);
  }

  void _paintText(Canvas canvas, String text, Offset pos, Color color, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  void _drawDeformedOutline(
    Canvas canvas,
    double cx,
    double cy,
    double halfX,
    double halfY,
    SectionDimensions dims,
    double baseScale,
    double antiAmp,
    Paint p,
  ) {
    Offset pt(double zeta, double eta) {
      final sx = (baseScale + antiAmp * eta).clamp(0.78, 1.24);
      return Offset(cx + zeta * halfX * sx, cy - eta * halfY * baseScale);
    }

    final shapeE = model.sectionShapeForElem(elemIndex);
    if (shapeE == SectionShape.solidRod) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: 2 * halfX * baseScale, height: 2 * halfY * baseScale),
        p,
      );
      return;
    }
    if (shapeE == SectionShape.circTube) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: 2 * halfX * baseScale, height: 2 * halfY * baseScale),
        p,
      );
      final ratio = dims.radiusOut > 1e-6 ? (dims.radiusIn / dims.radiusOut).clamp(0.05, 0.96) : 0.85;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: 2 * halfX * ratio * baseScale,
          height: 2 * halfY * ratio * baseScale,
        ),
        p,
      );
      return;
    }

    final hwMm = math.max(1e-6, 0.5 * dims.width);
    final hhMm = math.max(1e-6, 0.5 * dims.height);
    final polys = dims.outlinePolygonsMm(shapeE, includeInnerHole: true);
    for (final poly in polys) {
      if (poly.length < 3) continue;
      final path = Path();
      for (int i = 0; i < poly.length; i++) {
        final o = pt(poly[i][0] / hwMm, poly[i][1] / hhMm);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      path.close();
      canvas.drawPath(path, p);
    }
  }

  void _drawSectionOutline(
    Canvas canvas,
    double cx,
    double cy,
    double halfX,
    double halfY,
    SectionDimensions dims,
    Paint p,
  ) {
    _drawDeformedOutline(canvas, cx, cy, halfX, halfY, dims, 1.0, 0.0, p);
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

    // Đường dao cắt dọc tại ξ kèm chấm sáng trên 3 đường cong
    final cutX = padL + plotW * xi;
    canvas.drawLine(
      Offset(cutX, padT),
      Offset(cutX, padT + plotH),
      Paint()..color = const Color(0xFFFFEA00)..strokeWidth = 1.8,
    );
    final pTopXi = CalfemNonlinearEngine.probeMember(
      model: model, resultNL: resultNL, resultLin: resultLin,
      elemIndex: elemIndex, xi: xi, etaNorm: 1.0, imperfectionRatio: imperfectionRatio,
    ).sigmaXxMpa;
    final pBotXi = CalfemNonlinearEngine.probeMember(
      model: model, resultNL: resultNL, resultLin: resultLin,
      elemIndex: elemIndex, xi: xi, etaNorm: -1.0, imperfectionRatio: imperfectionRatio,
    ).sigmaXxMpa;
    final yTopDot = padT + plotH * (1.0 - (pTopXi - yMin) / (yMax - yMin));
    final yBotDot = padT + plotH * (1.0 - (pBotXi - yMin) / (yMax - yMin));
    canvas.drawCircle(Offset(cutX, yTopDot), 3.5, Paint()..color = const Color(0xFFF43F5E));
    canvas.drawCircle(Offset(cutX, yBotDot), 3.5, Paint()..color = const Color(0xFF22C55E));

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
