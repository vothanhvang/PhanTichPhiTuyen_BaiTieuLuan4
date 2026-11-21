// ============================================================================
// BẢNG BIỂU ĐỒ KỸ THUẬT, HỘI TỤ NEWTON-RAPHSON, MẤT ỔN ĐỊNH TRỊ RIÊNG & SỐ LIỆU
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/calfem_engine.dart';

class ChartsAndTablesPanel extends StatefulWidget {
  final TrussModelData model;
  final TrussAnalysisResult resLinear;
  final TrussAnalysisResult resActive;
  final TrussAnalysisResult resBar2g;
  final TrussAnalysisResult resCorot;
  final TrussAnalysisResult resTL;
  final List<EquilibriumPoint> snapCurve;
  final List<MemberDesignCheck>? designChecks;
  final BucklingAnalysisResult? buckling;
  final double loadFactor;
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
    this.designChecks,
    this.buckling,
    this.loadFactor = 1.0,
    required this.darkMode,
  });

  @override
  State<ChartsAndTablesPanel> createState() => _ChartsAndTablesPanelState();
}

class _ChartsAndTablesPanelState extends State<ChartsAndTablesPanel> {
  double? _hoverNormX;

  /// Tìm chuyển vị tại bậc tự do mang tải lớn nhất để đánh dấu điểm làm việc hiện tại trên đường cong P-u
  ({double uMm, double pKn}) _currentOperatingPoint() {
    int qGlobal = 0;
    double maxF = 0.0;
    for (int i = 0; i < widget.model.fRef.length; i++) {
      if (widget.model.fRef[i].abs() > maxF) {
        maxF = widget.model.fRef[i].abs();
        qGlobal = i;
      }
    }
    final uCur = qGlobal < widget.resActive.uMm.length ? widget.resActive.uMm[qGlobal].abs() : 0.0;
    final pCur = widget.loadFactor * maxF / 1000.0;
    return (uMm: uCur, pKn: pCur);
  }

  @override
  Widget build(BuildContext context) {
    final darkMode = widget.darkMode;
    final cardBg = darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final subTxt = darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final checks = widget.designChecks ?? CalfemNonlinearEngine.checkMembers(widget.model, widget.resActive);
    final buckling = widget.buckling ?? CalfemNonlinearEngine.solveElasticBuckling(widget.model, widget.resLinear);
    final curOp = _currentOperatingPoint();
    final passCount = checks.where((c) => c.passed).length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. Đồ thị đường cong cân bằng chuyển vị lớn (Snap-Through / Limit Point) có tương tác chạm & điểm làm việc
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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '1. Đường cong Cân bằng Toàn phần P–u (Snap-Through)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.2, color: Color(0xFF38BDF8)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.55)),
                    ),
                    child: Text(
                      'Điểm hiện tại: λ=${widget.loadFactor.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Xanh: Ổn định (det Kt > 0)  •  Đỏ: Mất ổn định (det Kt < 0)  •  Chấm lục: Trạng thái hiện tại  •  Rê chuột/Chạm để soi tọa độ',
                style: TextStyle(fontSize: 9.6, color: subTxt),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 224,
                child: LayoutBuilder(
                  builder: (context, cons) {
                    void updateHover(Offset local) {
                      const padL = 54.0, padR = 16.0;
                      final w = math.max(1.0, cons.maxWidth - padL - padR);
                      final norm = ((local.dx - padL) / w).clamp(0.0, 1.0);
                      setState(() => _hoverNormX = norm);
                    }

                    return MouseRegion(
                      onHover: (e) => updateHover(e.localPosition),
                      onExit: (_) => setState(() => _hoverNormX = null),
                      child: GestureDetector(
                        onTapDown: (d) => updateHover(d.localPosition),
                        onHorizontalDragUpdate: (d) => updateHover(d.localPosition),
                        onDoubleTap: () => setState(() => _hoverNormX = null),
                        child: CustomPaint(
                          size: Size(cons.maxWidth, 224),
                          painter: _SnapThroughChartPainter(
                            curve: widget.snapCurve,
                            currentU: curOp.uMm,
                            currentP: curOp.pKn,
                            hoverNormX: _hoverNormX,
                            darkMode: darkMode,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. Đồ thị Hội tụ Newton-Raphson (log10 ||R||∞ theo vòng lặp)
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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '2. Hội tụ Newton-Raphson bậc 2 (log₁₀ ||R||∞)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0, color: Color(0xFFA855F7)),
                    ),
                  ),
                  Text(
                    'Tổng: ${widget.resActive.totalIterations} vòng lặp',
                    style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w600, color: subTxt),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                widget.resActive.iterResidualsN.length >= 2
                    ? 'Lực dư ||R||∞ tại bước gia tải cuối giảm theo tốc độ hội tụ bậc 2 xuống dưới ngưỡng tol = 10⁻⁷ N'
                    : 'Chọn Full Newton-Raphson (Corotational UL hoặc Total Lagrangian) để xem biểu đồ hội tụ bậc 2 chi tiết',
                style: TextStyle(fontSize: 9.6, color: subTxt),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 148,
                child: CustomPaint(
                  size: const Size(double.infinity, 148),
                  painter: _ConvergenceChartPainter(
                    residuals: widget.resActive.iterResidualsN.isNotEmpty
                        ? widget.resActive.iterResidualsN
                        : [for (final h in widget.resActive.history) h.residualInfN],
                    darkMode: darkMode,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. Phân tích Mất ổn định Trị riêng Đàn hồi det(Ke + α_cr · Kg) = 0 + Mode 1
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '3. Mất ổn định Trị riêng Đàn hồi — Mode 1',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0, color: Color(0xFFF59E0B)),
                    ),
                  ),
                  if (buckling.hasBucklingMode)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (buckling.alphaCr > widget.loadFactor ? const Color(0xFF10B981) : const Color(0xFFF43F5E))
                            .withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: buckling.alphaCr > widget.loadFactor
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF43F5E),
                        ),
                      ),
                      child: Text(
                        'α_cr = ${buckling.alphaCr.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 10.2,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'DejaVuSansMono',
                          color: buckling.alphaCr > widget.loadFactor
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF43F5E),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                buckling.hasBucklingMode
                    ? 'Bài toán trị riêng det(Kₑ + α_cr·K_g) = 0  •  Tải tới hạn P_cr = ${buckling.pCrKn.toStringAsFixed(1)} kN (${(buckling.pCrKn / 1000).toStringAsFixed(2)} MN)  •  Hệ số dự trữ ổn định α_cr / λ = ${(buckling.alphaCr / math.max(1e-6, widget.loadFactor)).toStringAsFixed(1)}×'
                    : 'Hệ kết cấu hiện tại không có thanh chịu nén đáng kể hoặc không xuất hiện dạng mất ổn định dương.',
                style: TextStyle(fontSize: 9.8, color: subTxt),
              ),
              if (buckling.hasBucklingMode) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 158,
                  child: CustomPaint(
                    size: const Size(double.infinity, 158),
                    painter: _BucklingModePainter(
                      model: widget.model,
                      buckling: buckling,
                      darkMode: darkMode,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 4. Bảng 1: Đối chiếu Chuyển vị nút & Phản lực gối (đã đồng bộ phản lực đúng theo resActive!)
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
              const SizedBox(height: 2),
              Text(
                'Cột Phản lực (kN) đồng bộ đúng theo thuật toán đang chọn: ${widget.resActive.methodName}',
                style: TextStyle(fontSize: 9.6, color: subTxt),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 32,
                  dataRowMinHeight: 28,
                  dataRowMaxHeight: 32,
                  columnSpacing: 13,
                  headingRowColor: WidgetStatePropertyAll(
                    darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  ),
                  columns: const [
                    DataColumn(label: Text('DOF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.2))),
                    DataColumn(label: Text('Tuyến tính\n(mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                    DataColumn(label: Text('CALFEM bar2g\n(mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                    DataColumn(label: Text('Corotational UL\n(mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                    DataColumn(label: Text('Total Lagr.\n(mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                    DataColumn(label: Text('Phản lực\n(kN)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                  ],
                  rows: [
                    for (int k = 0; k < widget.model.nDofs; k++)
                      DataRow(cells: [
                        DataCell(Text('${k.isEven ? "ux" : "uy"}${k ~/ 2 + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.2))),
                        DataCell(Text(widget.resLinear.uMm[k].toStringAsFixed(6),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.8))),
                        DataCell(Text(widget.resBar2g.uMm[k].toStringAsFixed(6),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.8))),
                        DataCell(Text(widget.resCorot.uMm[k].toStringAsFixed(6),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.8, color: Color(0xFF38BDF8)))),
                        DataCell(Text(widget.resTL.uMm[k].toStringAsFixed(6),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.8))),
                        DataCell(Text((widget.resActive.reactionsN[k] / 1000.0).toStringAsFixed(5),
                            style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.8, color: Color(0xFFFBBF24)))),
                      ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 5. Bảng 2: Nội lực, Ứng suất & Kiểm tra Bền – Ổn định tổng thể thanh (TCVN 5575 / EN 1993-1-1)
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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Bảng 2. Nội lực, Tiết diện & Kiểm tra Bền – Ổn định (TCVN 5575 / EC3)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.8, color: Color(0xFF10B981)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: (passCount == checks.length ? const Color(0xFF10B981) : const Color(0xFFF43F5E))
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '$passCount/${checks.length} ĐẠT',
                      style: TextStyle(
                        fontSize: 9.8,
                        fontWeight: FontWeight.bold,
                        color: passCount == checks.length ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 32,
                  dataRowMinHeight: 28,
                  dataRowMaxHeight: 34,
                  columnSpacing: 11,
                  headingRowColor: WidgetStatePropertyAll(
                    darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  ),
                  columns: const [
                    DataColumn(label: Text('Thanh', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0))),
                    DataColumn(label: Text('Tiết diện', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0))),
                    DataColumn(label: Text('L₀\n(mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                    DataColumn(label: Text('N PT\n(kN)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                    DataColumn(label: Text('ΔN\n(N)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                    DataColumn(label: Text('σ PT\n(MPa)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                    DataColumn(label: Text('λ mảnh', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                    DataColumn(label: Text('U (%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0)), numeric: true),
                    DataColumn(label: Text('Kết luận', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0))),
                  ],
                  rows: [
                    for (int e = 0; e < widget.model.nElems; e++)
                      () {
                        final shE = widget.model.sectionShapeForElem(e);
                        final dimsE = widget.model.sectionDimsForElem(e);
                        final chk = e < checks.length ? checks[e] : null;
                        final uColor = chk == null
                            ? subTxt
                            : (chk.passed
                                ? (chk.utilizationPct > 80.0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981))
                                : const Color(0xFFF43F5E));
                        return DataRow(cells: [
                          DataCell(Text('T${e + 1} (${widget.model.memberLabels[e]})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.0))),
                          DataCell(Text(dimsE.formatSpec(shE),
                              style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.4))),
                          DataCell(Text(widget.model.initialLength(e).toStringAsFixed(0),
                              style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.6))),
                          DataCell(Text((widget.resActive.nForcesN[e] / 1000.0).toStringAsFixed(3),
                              style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.6, color: Color(0xFF38BDF8)))),
                          DataCell(Text((widget.resActive.nForcesN[e] - widget.resLinear.nForcesN[e]).toStringAsFixed(1),
                              style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.6, color: Color(0xFFF43F5E)))),
                          DataCell(Text(widget.resActive.stressMpa[e].toStringAsFixed(2),
                              style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.6))),
                          DataCell(Text(chk != null ? chk.slenderness.toStringAsFixed(1) : '-',
                              style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.6))),
                          DataCell(Text(
                            chk != null ? '${chk.utilizationPct.toStringAsFixed(1)}%' : '-',
                            style: TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 9.8, fontWeight: FontWeight.bold, color: uColor),
                          )),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: uColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                chk == null ? '-' : (chk.isYielded ? 'CHẢY DẺO' : (chk.passed ? 'ĐẠT' : 'VƯỢT')),
                                style: TextStyle(fontSize: 9.2, fontWeight: FontWeight.bold, color: uColor),
                              ),
                            ),
                          ),
                        ]);
                      }(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 6. Hộp Kiểm chứng Cân bằng & Năng lượng
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
                '• ∑Fx = ${widget.resActive.sumFxN.toStringAsExponential(2)} N  |  ∑Fy = ${widget.resActive.sumFyN.toStringAsExponential(2)} N  |  ∑M_biến_dạng = ${widget.resActive.sumMNmm.toStringAsExponential(2)} N·mm\n'
                '• Phần dư tự do max ||Rf||∞ = ${widget.resActive.maxFreeResidualN.toStringAsExponential(2)} N  |  Số vòng lặp: ${widget.resActive.totalIterations}\n'
                '• Năng lượng biến dạng: U_TT = ${(widget.resLinear.totalEnergyNmm / 1000).toStringAsFixed(6)} J  vs  U_PT = ${(widget.resActive.totalEnergyNmm / 1000).toStringAsFixed(6)} J'
                '${widget.model.materialNonlinear ? "\n• Chế độ GMNIA Đàn-Dẻo (fy=${widget.model.fyRef.toStringAsFixed(0)} MPa, Et/E=${(widget.model.hardeningRatio * 100).toStringAsFixed(1)}%): ${widget.resActive.yieldedElems.where((y) => y).length}/${widget.model.nElems} thanh đã chảy dẻo" : ""}',
                style: TextStyle(
                  fontSize: 10.2,
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
  final double currentU;
  final double currentP;
  final double? hoverNormX;
  final bool darkMode;

  const _SnapThroughChartPainter({
    required this.curve,
    required this.currentU,
    required this.currentP,
    required this.hoverNormX,
    required this.darkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.length < 3) return;
    const padL = 54.0, padR = 16.0, padT = 18.0, padB = 28.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    if (w <= 10 || h <= 10) return;

    final maxU = math.max(1e-3, math.max(currentU * 1.05, curve.map((p) => p.uMainMm).reduce(math.max)));
    final minP = math.min(0.0, math.min(currentP, curve.map((p) => p.pKn).reduce(math.min)));
    final maxP = math.max(1.0, math.max(currentP * 1.1, curve.map((p) => p.pKn).reduce(math.max))) * 1.12;

    Offset toPx(double u, double p) => Offset(
          padL + w * (u / math.max(1e-6, maxU)),
          padT + h * (1.0 - (p - minP) / math.max(1e-6, maxP - minP)),
        );

    final gridP = Paint()
      ..color = darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)
      ..strokeWidth = 0.9;
    for (int i = 0; i <= 4; i++) {
      final y = padT + h * i / 4.0;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridP);
      final x = padL + w * i / 4.0;
      canvas.drawLine(Offset(x, padT), Offset(x, padT + h), gridP);
    }

    final zeroY = toPx(0, 0).dy;
    canvas.drawLine(
      Offset(padL, zeroY),
      Offset(padL + w, zeroY),
      Paint()..color = const Color(0xFF64748B)..strokeWidth = 1.2,
    );

    if (curve.length > 1 && curve[1].uMainMm > 1e-6) {
      final slope = curve[1].pKn / curve[1].uMainMm;
      final uLinEnd = math.min(maxU, maxP / math.max(1e-6, slope));
      canvas.drawLine(
        toPx(0, 0),
        toPx(uLinEnd, uLinEnd * slope),
        Paint()..color = const Color(0xFF94A3B8)..strokeWidth = 1.3,
      );
    }

    for (int i = 0; i < curve.length - 1; i++) {
      final a = toPx(curve[i].uMainMm, curve[i].pKn);
      final b = toPx(curve[i + 1].uMainMm, curve[i + 1].pKn);
      final isUnst = curve[i].isUnstable || curve[i + 1].isUnstable;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = isUnst ? const Color(0xFFFF3B5C) : const Color(0xFF06B6D4)
          ..strokeWidth = isUnst ? 3.1 : 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Đánh dấu Limit Point
    int peakIdx = 1;
    for (int i = 1; i < curve.length - 1; i++) {
      if (curve[i].pKn > curve[i - 1].pKn && curve[i].pKn >= curve[i + 1].pKn) {
        peakIdx = i;
        break;
      }
    }
    final pk = curve[peakIdx];
    final pkPt = toPx(pk.uMainMm, pk.pKn);
    canvas.drawCircle(pkPt, 5.2, Paint()..color = const Color(0xFFFF3B5C));
    canvas.drawCircle(pkPt, 5.2, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.4);

    // Đánh dấu Điểm làm việc hiện tại (u_cur, P_cur)
    final opPt = toPx(currentU, currentP);
    canvas.drawCircle(opPt, 8.5, Paint()..color = const Color(0xFF10B981).withValues(alpha: 0.28));
    canvas.drawCircle(opPt, 4.8, Paint()..color = const Color(0xFF10B981));
    canvas.drawCircle(opPt, 4.8, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);

    void drawTxt(Offset o, String s, {Color? col}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: col ?? (darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
            fontSize: 9.0,
            fontWeight: col != null ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o);
    }

    // Tooltip tương tác khi rê chuột / chạm
    if (hoverNormX != null) {
      final targetU = hoverNormX! * maxU;
      EquilibriumPoint best = curve.first;
      double bestD = double.infinity;
      for (final pt in curve) {
        final d = (pt.uMainMm - targetU).abs();
        if (d < bestD) {
          bestD = d;
          best = pt;
        }
      }
      final hp = toPx(best.uMainMm, best.pKn);
      final crossP = Paint()
        ..color = const Color(0xFFFBBF24).withValues(alpha: 0.7)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(hp.dx, padT), Offset(hp.dx, padT + h), crossP);
      canvas.drawLine(Offset(padL, hp.dy), Offset(padL + w, hp.dy), crossP);
      canvas.drawCircle(hp, 5.0, Paint()..color = const Color(0xFFFBBF24));

      final tipText =
          'u=${best.uMainMm.toStringAsFixed(1)} mm | P=${(best.pKn / 1000).toStringAsFixed(3)} MN | λ=${best.lambda.toStringAsFixed(1)} (${best.isUnstable ? "Mất ổn định" : "Ổn định"})';
      final tp = TextPainter(
        text: TextSpan(
          text: tipText,
          style: TextStyle(
            color: darkMode ? Colors.white : const Color(0xFF0F172A),
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final boxW = tp.width + 12;
      final bx = (hp.dx + 8 + boxW > size.width - 4) ? math.max(padL + 2, hp.dx - boxW - 8) : hp.dx + 8;
      final by = math.max(padT + 2, math.min(padT + h - 24, hp.dy - 24));
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, boxW, tp.height + 8), const Radius.circular(5));
      canvas.drawRRect(rect, Paint()..color = darkMode ? const Color(0xE60F172A) : const Color(0xF0FFFFFF));
      canvas.drawRRect(rect, Paint()..color = const Color(0xFFFBBF24)..style = PaintingStyle.stroke..strokeWidth = 1.0);
      tp.paint(canvas, Offset(bx + 6, by + 4));
    }

    final pkText = 'Limit: ${(pk.pKn / 1000).toStringAsFixed(2)} MN (u=${pk.uMainMm.toStringAsFixed(0)} mm)';
    final pkTp = TextPainter(
      text: TextSpan(
        text: pkText,
        style: const TextStyle(color: Color(0xFFFF6B81), fontSize: 8.8, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pkLabelX = (pkPt.dx + 8 + pkTp.width > size.width - 4)
        ? math.max(padL + 2, size.width - pkTp.width - 4)
        : pkPt.dx + 8;
    pkTp.paint(canvas, Offset(pkLabelX, math.max(4, pkPt.dy - 15)));
    drawTxt(Offset(4, padT - 4), '${(maxP / 1000).toStringAsFixed(1)} MN');
    drawTxt(Offset(4, padT + h - 8), '${(minP / 1000).toStringAsFixed(1)} MN');
    drawTxt(Offset(padL, padT + h + 6), 'u = 0 mm');
    final uEndTp = TextPainter(
      text: TextSpan(
        text: 'u = ${maxU.toStringAsFixed(0)} mm',
        style: TextStyle(color: darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569), fontSize: 9.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    uEndTp.paint(canvas, Offset(math.max(padL + 40, padL + w - uEndTp.width), padT + h + 6));
  }

  @override
  bool shouldRepaint(covariant _SnapThroughChartPainter oldDelegate) => true;
}

class _ConvergenceChartPainter extends CustomPainter {
  final List<double> residuals;
  final bool darkMode;
  const _ConvergenceChartPainter({required this.residuals, required this.darkMode});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 46.0, padR = 14.0, padT = 14.0, padB = 24.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    if (w <= 10 || h <= 10) return;

    final gridP = Paint()
      ..color = darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)
      ..strokeWidth = 0.9;
    for (int i = 0; i <= 4; i++) {
      final y = padT + h * i / 4.0;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridP);
    }

    void drawTxt(Offset o, String s, {Color? col}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: col ?? (darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
            fontSize: 8.8,
            fontWeight: col != null ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o);
    }

    if (residuals.isEmpty) {
      drawTxt(Offset(padL + 12, padT + h * 0.45), 'Không có dữ liệu lặp phi tuyến.', col: const Color(0xFF94A3B8));
      return;
    }

    final logs = [
      for (final r in residuals) (math.log(math.max(1e-16, r.abs())) / math.ln10).clamp(-16.0, 8.0),
    ];
    final maxLog = math.max(1.0, logs.reduce(math.max) + 1.0);
    final minLog = math.min(-8.0, logs.reduce(math.min) - 1.0);
    final logSpan = math.max(1.0, maxLog - minLog);

    Offset ptAt(int idx) {
      final fx = logs.length <= 1 ? 0.5 : idx / (logs.length - 1);
      final fy = 1.0 - (logs[idx] - minLog) / logSpan;
      return Offset(padL + fx * w, padT + fy * h);
    }

    // Đường ngưỡng dung sai tol = 10^-7 N
    final tolY = padT + (1.0 - (-7.0 - minLog) / logSpan) * h;
    if (tolY >= padT && tolY <= padT + h) {
      canvas.drawLine(
        Offset(padL, tolY),
        Offset(padL + w, tolY),
        Paint()..color = const Color(0xFF10B981).withValues(alpha: 0.7)..strokeWidth = 1.2,
      );
      final tolTp = TextPainter(
        text: const TextSpan(
          text: 'tol = 10⁻⁷ N',
          style: TextStyle(color: Color(0xFF10B981), fontSize: 8.8, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tolTp.paint(canvas, Offset(math.max(padL + 4, padL + w - tolTp.width - 2), math.max(padT + 2, tolY - 13)));
    }

    final lineP = Paint()
      ..color = const Color(0xFFA855F7)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < logs.length; i++) {
      final p = ptAt(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, lineP);

    for (int i = 0; i < logs.length; i++) {
      final p = ptAt(i);
      canvas.drawCircle(p, 3.8, Paint()..color = const Color(0xFFC084FC));
      canvas.drawCircle(p, 3.8, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.1);
      if (logs.length <= 10 || i == 0 || i == logs.length - 1) {
        drawTxt(Offset(p.dx - 4, padT + h + 5), '$i');
      }
    }

    drawTxt(Offset(4, padT - 4), '10^${maxLog.round()}');
    drawTxt(Offset(4, padT + h - 8), '10^${minLog.round()}');
    drawTxt(Offset(padL + w * 0.35, padT + h + 6), 'Vòng lặp Newton-Raphson (k)');
  }

  @override
  bool shouldRepaint(covariant _ConvergenceChartPainter oldDelegate) => true;
}

class _BucklingModePainter extends CustomPainter {
  final TrussModelData model;
  final BucklingAnalysisResult buckling;
  final bool darkMode;
  const _BucklingModePainter({required this.model, required this.buckling, required this.darkMode});

  @override
  void paint(Canvas canvas, Size size) {
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final c in model.coords) {
      minX = math.min(minX, c[0]);
      maxX = math.max(maxX, c[0]);
      minY = math.min(minY, c[1]);
      maxY = math.max(maxY, c[1]);
    }
    final spanX = math.max(100.0, maxX - minX);
    final spanY = math.max(100.0, maxY - minY);
    final scale = math.min((size.width * 0.72) / spanX, (size.height * 0.66) / spanY);
    final cx = 0.5 * (minX + maxX);
    final cy = 0.5 * (minY + maxY);
    final scCenter = Offset(size.width * 0.5, size.height * 0.52);

    Offset toPx(double x, double y) => Offset(
          scCenter.dx + (x - cx) * scale,
          scCenter.dy - (y - cy) * scale,
        );

    final amp = math.max(spanX, spanY) * 0.14;

    // 1. Dàn gốc nét mờ
    final baseP = Paint()
      ..color = darkMode ? const Color(0xFF475569) : const Color(0xFF94A3B8)
      ..strokeWidth = 1.6;
    for (int e = 0; e < model.nElems; e++) {
      final ni = model.conn[e][0] - 1;
      final nj = model.conn[e][1] - 1;
      canvas.drawLine(
        toPx(model.coords[ni][0], model.coords[ni][1]),
        toPx(model.coords[nj][0], model.coords[nj][1]),
        baseP,
      );
    }

    // 2. Dạng mất ổn định Mode 1 màu cam/vàng nổi bật
    final modeGlow = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.25)
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round;
    final modeP = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    for (int e = 0; e < model.nElems; e++) {
      final ni = model.conn[e][0] - 1;
      final nj = model.conn[e][1] - 1;
      final a = toPx(
        model.coords[ni][0] + amp * buckling.modeShape[2 * ni],
        model.coords[ni][1] + amp * buckling.modeShape[2 * ni + 1],
      );
      final b = toPx(
        model.coords[nj][0] + amp * buckling.modeShape[2 * nj],
        model.coords[nj][1] + amp * buckling.modeShape[2 * nj + 1],
      );
      canvas.drawLine(a, b, modeGlow);
      canvas.drawLine(a, b, modeP);
    }

    for (int i = 0; i < model.nNodes; i++) {
      final p = toPx(
        model.coords[i][0] + amp * buckling.modeShape[2 * i],
        model.coords[i][1] + amp * buckling.modeShape[2 * i + 1],
      );
      canvas.drawCircle(p, 4.0, Paint()..color = const Color(0xFFFDE047));
      canvas.drawCircle(p, 4.0, Paint()..color = const Color(0xFF0F172A)..style = PaintingStyle.stroke..strokeWidth = 1.2);
    }
  }

  @override
  bool shouldRepaint(covariant _BucklingModePainter oldDelegate) => true;
}
