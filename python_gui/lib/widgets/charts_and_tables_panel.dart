// ============================================================================
// BẢNG BIỂU ĐỒ KỸ THUẬT & ĐỐI CHIẾU SỐ LIỆU (TUYẾN TÍNH VS PHI TUYẾN)
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/calfem_engine.dart';

class ChartsAndTablesPanel extends StatelessWidget {
  final TrussModelData model;
  final TrussAnalysisResult resLinear;
  final TrussAnalysisResult resActive;
  final TrussAnalysisResult resBar2g;
  final TrussAnalysisResult resCorot;
  final TrussAnalysisResult resTL;
  final List<EquilibriumPoint> snapCurve;
  final bool darkMode;

  const ChartsAndTablesPanel({
    super.key,
    required this.model,
    required this.resLinear,
    required this.resActive,
    required this.resBar2g,
    required this.resCorot,
    required this.resTL,
    required this.snapCurve,
    required this.darkMode,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. Đồ thị đường cong cân bằng chuyển vị lớn (Snap-Through / Limit Point)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Đường cong Cân bằng Toàn phần P–u (Bật nhảy Snap-Through)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(height: 3),
              Text(
                'Màu xanh: Nhánh ổn định (det Kt > 0)  •  Màu đỏ: Nhánh mất ổn định Snap-Through (det Kt < 0)  •  Nét đứt: Tuyến tính (bar2e)',
                style: TextStyle(fontSize: 10, color: darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: CustomPaint(
                  size: const Size(double.infinity, 220),
                  painter: _SnapThroughChartPainter(
                    curve: snapCurve,
                    darkMode: darkMode,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. Bảng đối chiếu Chuyển vị nút (Tuyến tính vs bar2g vs Corotational UL vs Total Lagrangian)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bảng 1. So sánh Chuyển vị Nút & Phản lực Gối (4 Mô hình CALFEM)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 32,
                  dataRowMinHeight: 28,
                  dataRowMaxHeight: 32,
                  columnSpacing: 14,
                  headingRowColor: WidgetStatePropertyAll(
                    darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  ),
                  columns: const [
                    DataColumn(label: Text('DOF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5))),
                    DataColumn(label: Text('Tuyến tính\n(mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                    DataColumn(label: Text('CALFEM bar2g\n(mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                    DataColumn(label: Text('Corotational UL\n(mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                    DataColumn(label: Text('Total Lagr.\n(mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                    DataColumn(label: Text('Phản lực PT\n(kN)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                  ],
                  rows: [
                    for (int k = 0; k < model.nDofs; k++)
                      DataRow(cells: [
                        DataCell(Text('${k.isEven ? "ux" : "uy"}${k ~/ 2 + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5))),
                        DataCell(Text(resLinear.uMm[k].toStringAsFixed(6),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10))),
                        DataCell(Text(resBar2g.uMm[k].toStringAsFixed(6),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10))),
                        DataCell(Text(resCorot.uMm[k].toStringAsFixed(6),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10, color: Color(0xFF38BDF8)))),
                        DataCell(Text(resTL.uMm[k].toStringAsFixed(6),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10))),
                        DataCell(Text((resCorot.reactionsN[k] / 1000.0).toStringAsFixed(5),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10, color: Color(0xFFFBBF24)))),
                      ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. Bảng đối chiếu Nội lực & Ứng suất các thanh
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bảng 2. So sánh Lực dọc N, Ứng suất σ & Chênh lệch Phi tuyến ΔN',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 32,
                  dataRowMinHeight: 28,
                  dataRowMaxHeight: 32,
                  columnSpacing: 14,
                  headingRowColor: WidgetStatePropertyAll(
                    darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  ),
                  columns: const [
                    DataColumn(label: Text('Thanh', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5))),
                    DataColumn(label: Text('A (mm²)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                    DataColumn(label: Text('N TT (kN)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                    DataColumn(label: Text('N PT (kN)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                    DataColumn(label: Text('ΔN (N)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                    DataColumn(label: Text('σ PT (MPa)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                    DataColumn(label: Text('ε (με)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)), numeric: true),
                  ],
                  rows: [
                    for (int e = 0; e < model.nElems; e++)
                      DataRow(cells: [
                        DataCell(Text('T${e + 1} (${model.memberLabels[e]})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5))),
                        DataCell(Text(model.areas[e].toStringAsFixed(1),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10))),
                        DataCell(Text((resLinear.nForcesN[e] / 1000.0).toStringAsFixed(4),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10))),
                        DataCell(Text((resActive.nForcesN[e] / 1000.0).toStringAsFixed(4),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10, color: Color(0xFF38BDF8)))),
                        DataCell(Text((resActive.nForcesN[e] - resLinear.nForcesN[e]).toStringAsFixed(2),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10, color: Color(0xFFF43F5E)))),
                        DataCell(Text(resActive.stressMpa[e].toStringAsFixed(3),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10))),
                        DataCell(Text((resActive.strain[e] * 1e6).toStringAsFixed(1),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 10))),
                      ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 4. Hộp Kiểm chứng Cân bằng & Năng lượng
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kiểm chứng Cơ học trên Cấu hình Biến dạng (Equilibrium & Energy)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 6),
              Text(
                '• ∑Fx = ${resActive.sumFxN.toStringAsExponential(2)} N  |  ∑Fy = ${resActive.sumFyN.toStringAsExponential(2)} N  |  ∑M_biến_dạng = ${resActive.sumMNmm.toStringAsExponential(2)} N·mm\n'
                '• Phần dư tự do max ||Rf||∞ = ${resActive.maxFreeResidualN.toStringAsExponential(2)} N  |  Số vòng lặp: ${resActive.totalIterations}\n'
                '• Năng lượng biến dạng: U_TT = ${(resLinear.totalEnergyNmm / 1000).toStringAsFixed(6)} J  vs  U_PT = ${(resActive.totalEnergyNmm / 1000).toStringAsFixed(6)} J',
                style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'DejaVuSansMono',
                  height: 1.45,
                  color: darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SnapThroughChartPainter extends CustomPainter {
  final List<EquilibriumPoint> curve;
  final bool darkMode;
  const _SnapThroughChartPainter({required this.curve, required this.darkMode});

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.length < 3) return;
    const padL = 54.0, padR = 16.0, padT = 16.0, padB = 28.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;

    final maxU = curve.map((p) => p.uMainMm).reduce(math.max);
    final minP = math.min(0.0, curve.map((p) => p.pKn).reduce(math.min));
    final maxP = math.max(1.0, curve.map((p) => p.pKn).reduce(math.max)) * 1.12;

    Offset toPx(double u, double p) => Offset(
          padL + w * (u / math.max(1e-6, maxU)),
          padT + h * (1.0 - (p - minP) / math.max(1e-6, maxP - minP)),
        );

    // Lưới & khung
    final gridP = Paint()
      ..color = darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)
      ..strokeWidth = 0.9;
    for (int i = 0; i <= 4; i++) {
      final y = padT + h * i / 4.0;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridP);
      final x = padL + w * i / 4.0;
      canvas.drawLine(Offset(x, padT), Offset(x, padT + h), gridP);
    }

    // Trục P = 0
    final zeroY = toPx(0, 0).dy;
    canvas.drawLine(Offset(padL, zeroY), Offset(padL + w, zeroY),
        Paint()..color = const Color(0xFF64748B)..strokeWidth = 1.2);

    // Đường tiếp tuyến tuyến tính ban đầu
    if (curve.length > 1 && curve[1].uMainMm > 1e-6) {
      final slope = curve[1].pKn / curve[1].uMainMm;
      final uLinEnd = math.min(maxU, maxP / math.max(1e-6, slope));
      canvas.drawLine(
        toPx(0, 0),
        toPx(uLinEnd, uLinEnd * slope),
        Paint()..color = const Color(0xFF94A3B8)..strokeWidth = 1.4,
      );
    }

    // Vẽ từng đoạn đường cong (xanh ổn định / đỏ mất ổn định Snap-Through)
    for (int i = 0; i < curve.length - 1; i++) {
      final a = toPx(curve[i].uMainMm, curve[i].pKn);
      final b = toPx(curve[i + 1].uMainMm, curve[i + 1].pKn);
      final isUnst = curve[i].isUnstable || curve[i + 1].isUnstable;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = isUnst ? const Color(0xFFFF3B5C) : const Color(0xFF06B6D4)
          ..strokeWidth = isUnst ? 3.2 : 2.6
          ..strokeCap = StrokeCap.round,
      );
    }

    // Tìm & đánh dấu điểm giới hạn đầu tiên (Limit Point A)
    int peakIdx = 1;
    for (int i = 1; i < curve.length - 1; i++) {
      if (curve[i].pKn > curve[i - 1].pKn && curve[i].pKn >= curve[i + 1].pKn) {
        peakIdx = i;
        break;
      }
    }
    final pk = curve[peakIdx];
    final pkPt = toPx(pk.uMainMm, pk.pKn);
    canvas.drawCircle(pkPt, 5.5, Paint()..color = const Color(0xFFFF3B5C));
    canvas.drawCircle(pkPt, 5.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);

    void drawTxt(Offset o, String s, {Color? col}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: col ?? (darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
            fontSize: 9.2,
            fontWeight: col != null ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o);
    }

    drawTxt(
      pkPt + const Offset(8, -16),
      'Limit Point: ${(pk.pKn / 1000).toStringAsFixed(2)} MN (u=${pk.uMainMm.toStringAsFixed(0)} mm)',
      col: const Color(0xFFFF6B81),
    );
    drawTxt(Offset(4, padT - 4), '${(maxP / 1000).toStringAsFixed(1)} MN');
    drawTxt(Offset(4, padT + h - 8), '${(minP / 1000).toStringAsFixed(1)} MN');
    drawTxt(Offset(padL, padT + h + 6), 'u = 0 mm');
    drawTxt(Offset(padL + w - 74, padT + h + 6), 'u = ${maxU.toStringAsFixed(0)} mm');
  }

  @override
  bool shouldRepaint(covariant _SnapThroughChartPainter oldDelegate) => true;
}
