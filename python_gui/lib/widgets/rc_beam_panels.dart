// ============================================================================
// CÁC BẢNG PHÂN TÍCH CHUYÊN SÂU CHO DẦM BTCT PHI TUYẾN (PHƯƠNG PHÁP THỚ)
// ============================================================================
// Gồm 4 tab chuyên biệt bên phải khung Studio:
//   1. RcBeamSurgicalPanel : Phẫu thuật mặt cắt thớ (Mặt cắt b×h, ε(y), σ(y),
//                            trục trung hòa x_NA, EA/ES/EI tiếp tuyến, độ sâu nứt).
//   2. RcBeamFemMatrixPanel: Ma trận độ cứng 6×6 [Kt^e], ma trận mặt cắt [Dt],
//                            quan hệ nội lực - chuyển vị {f^e} ↔ {d^e}, bảng nút.
//   3. RcBeamChartsPanel   : Biểu đồ P-Δ (Tuyến tính vs Thớ phi tuyến), M-κ,
//                            Khảo sát hội tụ lưới (2, 4, 8, 16, 32 phần tử) & NR.
//   4. RcBeamTheoryPanel   : Cơ sở lý thuyết Rayleigh-Ritz (Π=U-W → δΠ=0),
//                            PTHH 6-DOF Hermite, Gauss 3 điểm & mã nguồn Python.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/rc_beam_engine.dart';

// ============================================================================
// 1. TAB PHẪU THUẬT MẶT CẮT THỚ (SURGICAL FIBER DISSECTION)
// ============================================================================
class RcBeamSurgicalPanel extends StatelessWidget {
  final RcBeamAnalysisResult result;
  final RcBeamAnalysisResult resultLinear;
  final double probeXNorm;
  final bool darkMode;
  final ValueChanged<double> onProbeXChanged;

  const RcBeamSurgicalPanel({
    super.key,
    required this.result,
    required this.resultLinear,
    required this.probeXNorm,
    required this.darkMode,
    required this.onProbeXChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final textSub = darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    final cfg = result.config;
    final probe = RcBeamFiberEngine.probeBeamAt(result, probeXNorm);
    final sec = probe.section;
    final eiPct = (100.0 * sec.eiEffNmm2 / math.max(1.0, result.eiGrossNmm2)).clamp(0.0, 100.0);
    final xMm = probeXNorm * cfg.spanMm;

    String stateLabel = 'Nguyên vẹn đàn hồi';
    Color stateColor = const Color(0xFF22C55E);
    if (sec.concreteCrushed) {
      stateLabel = 'Bê tông vỡ ép vùng nén!';
      stateColor = const Color(0xFF9333EA);
    } else if (sec.steelYielded) {
      stateLabel = 'Cốt thép kéo đã CHẢY DẺO';
      stateColor = const Color(0xFFEF4444);
    } else if (sec.hasCracked) {
      stateLabel = 'Bê tông vùng kéo ĐÃ NỨT (mềm hóa)';
      stateColor = const Color(0xFFF59E0B);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Thanh tiêu đề Phẫu thuật mặt cắt thớ
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0E7490), Color(0xFF1D4ED8)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.layers, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PHẪU THUẬT MẶT CẮT THỚ BTCT',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.4),
                    ),
                    Text(
                      'Chia ${cfg.nFibers} thớ bê tông + cốt thép tại trọng tâm${cfg.hasRigidCore ? " + Cốt cứng chữ I" : ""}',
                      style: const TextStyle(color: Color(0xFFE0F2FE), fontSize: 9.6),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: stateColor, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'EI=${eiPct.toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Thanh trượt chọn vị trí lát cắt x/L dọc nhịp dầm
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mặt cắt x = ${xMm.toStringAsFixed(0)} mm (${(probeXNorm * 100).toStringAsFixed(1)}% L)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('PT E${probe.element.elemIndex + 1}', style: TextStyle(fontSize: 9.8, color: textSub)),
                ],
              ),
              Slider(
                value: probeXNorm.clamp(0.0, 1.0),
                min: 0.0,
                max: 1.0,
                onChanged: onProbeXChanged,
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _jumpChip('Gối trái (0)', 0.02, onProbeXChanged),
                  _jumpChip('Điểm lực a', (cfg.effectiveAMm / cfg.spanMm).clamp(0.02, 0.98), onProbeXChanged),
                  _jumpChip('Giữa nhịp (L/2)', 0.50, onProbeXChanged),
                  _jumpChip('1/4 nhịp', 0.25, onProbeXChanged),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: stateColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'Trạng thái mặt cắt: $stateLabel',
                  style: TextStyle(fontSize: 10.2, fontWeight: FontWeight.bold, color: stateColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Bản vẽ 3 cột: Mặt cắt thớ b×h | Biến dạng tuyến tính ε(y) | Ứng suất phi tuyến σ(y)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Phân bố Thớ — Biến dạng ε(y) — Ứng suất σ(y) & Trục trung hòa x_NA',
                style: TextStyle(fontSize: 10.8, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(height: 6),
              Container(
                height: 245,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: darkMode ? const Color(0xFF07101E) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    painter: _FiberSectionPainter(cfg: cfg, section: sec, darkMode: darkMode),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  _legendDot(const Color(0xFF2563EB), 'BT nén'),
                  _legendDot(const Color(0xFFF59E0B), 'BT kéo chưa nứt'),
                  _legendDot(const Color(0xFFEF4444), 'BT nứt kéo'),
                  _legendDot(const Color(0xFFFACC15), 'Cốt thép'),
                  _legendDot(const Color(0xFF4ADE80), 'Trục trung hòa x_NA'),
                  if (cfg.hasRigidCore) _legendDot(const Color(0xFF38BDF8), 'Cốt cứng chữ I'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Bảng thông số độ cứng mặt cắt EA, ES, EI, Trục trung hòa & Ứng suất
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Đặc trưng Độ cứng Tiếp tuyến & Trạng thái Ứng suất tại Lát cắt',
                style: TextStyle(fontSize: 10.8, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 6),
              _metricRow('Mô-men uốn M(x) / Lực cắt V(x)', '${probe.momentKnm.toStringAsFixed(2)} kN·m  |  ${probe.shearKn.toStringAsFixed(2)} kN', textSub),
              _metricRow('Độ võng v(x) / Góc xoay θ(x)', '${probe.vMm.toStringAsFixed(3)} mm  |  ${(probe.thetaRad * 1000).toStringAsFixed(3)} mrad', textSub),
              _metricRow('Biến dạng trục ε₀ / Độ cong κ', '${(sec.eps0 * 1e3).toStringAsFixed(4)} ‰  |  ${(sec.kappa * 1e6).toStringAsFixed(2)}×10⁻⁶ /mm', textSub),
              _metricRow('Trục trung hòa từ mép trên x_NA', '${sec.xNeutralDepthMm.toStringAsFixed(1)} mm (y_NA = ${sec.yNeutralMm.toStringAsFixed(1)} mm)', textSub),
              _metricRow('Chiều sâu vết nứt từ mép dưới', '${sec.crackDepthMm.toStringAsFixed(1)} mm / ${cfg.heightMm.toStringAsFixed(0)} mm', textSub),
              const Divider(height: 12),
              _metricRow('Độ cứng kéo-nén tiếp tuyến EA_t', '${(sec.eaTangentN / 1e6).toStringAsFixed(2)} MN', textSub),
              _metricRow('Mô-men tĩnh tiếp tuyến ES_t', '${(sec.esTangentNmm / 1e9).toStringAsFixed(3)} GN·mm', textSub),
              _metricRow('Độ cứng uốn tiếp tuyến EI_t', '${(sec.eiTangentNmm2 / 1e12).toStringAsFixed(3)} ×10¹² N·mm²', textSub),
              _metricRow('Độ cứng uốn hiệu dụng EI_eff', '${(sec.eiEffNmm2 / 1e12).toStringAsFixed(3)} ×10¹² N·mm² (${eiPct.toStringAsFixed(1)}% EI₀)', textSub),
              const Divider(height: 12),
              _metricRow('Ứng suất nén BT mép trên σ_c', '${sec.sigmaTopConcMpa.toStringAsFixed(2)} MPa (f\'c = -${cfg.fcMpa.toStringAsFixed(1)})', textSub),
              _metricRow('Ứng suất cốt thép kéo đáy σ_s', '${sec.sigmaBotSteelMpa.toStringAsFixed(2)} MPa (fy = ${cfg.fyMpa.toStringAsFixed(0)})', textSub),
              _metricRow('Ứng suất cốt thép nén đỉnh σ_s\'', '${sec.sigmaTopSteelMpa.toStringAsFixed(2)} MPa', textSub),
            ],
          ),
        ),
      ],
    );
  }

  Widget _jumpChip(String lbl, double xN, ValueChanged<double> onTap) => ActionChip(
        label: Text(lbl, style: const TextStyle(fontSize: 9.8)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: () => onTap(xN),
      );

  Widget _legendDot(Color c, String lbl) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(lbl, style: const TextStyle(fontSize: 9.5)),
        ],
      );

  Widget _metricRow(String k, String v, Color textSub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(k, style: TextStyle(fontSize: 10.0, color: textSub))),
            const SizedBox(width: 6),
            Text(v, style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.bold, fontFamily: 'DejaVuSansMono')),
          ],
        ),
      );
}

class _FiberSectionPainter extends CustomPainter {
  final RcBeamConfig cfg;
  final RcSectionState section;
  final bool darkMode;

  _FiberSectionPainter({required this.cfg, required this.section, required this.darkMode});

  @override
  void paint(Canvas canvas, Size size) {
    final topPad = 24.0;
    final botPad = 20.0;
    final secH = size.height - topPad - botPad;
    final secW = (secH * (cfg.widthMm / cfg.heightMm)).clamp(48.0, size.width * 0.28);
    final xSecLeft = 18.0;
    final xSecRight = xSecLeft + secW;
    final h = cfg.heightMm;

    double yToPx(double yMm) => topPad + ((0.5 * h - yMm) / h) * secH;

    // 1. CỘT 1: MẶT CẮT NGANG THỚ (b × h)
    _txt(canvas, Offset(xSecLeft, 5), 'Mặt cắt ${cfg.widthMm.toStringAsFixed(0)}×${h.toStringAsFixed(0)}', const Color(0xFF38BDF8), 9.3, bold: true);
    for (final f in section.fibers) {
      if (f.spec.kind != 'concrete') continue;
      final yTop = yToPx(f.spec.yMm + 0.5 * f.spec.heightMm);
      final yBot = yToPx(f.spec.yMm - 0.5 * f.spec.heightMm);
      Color c;
      if (f.isCrushed) {
        c = const Color(0xFF9333EA);
      } else if (f.isCracked) {
        c = const Color(0xFFEF4444).withValues(alpha: 0.35);
      } else if (f.stressMpa < 0) {
        final t = (f.stressMpa.abs() / math.max(1.0, cfg.fcMpa)).clamp(0.05, 1.0);
        c = Color.lerp(const Color(0xFF38BDF8), const Color(0xFF1D4ED8), t)!;
      } else {
        c = const Color(0xFFF59E0B).withValues(alpha: 0.55);
      }
      final r = Rect.fromLTRB(xSecLeft, yTop, xSecRight, yBot);
      canvas.drawRect(r, Paint()..color = c);
      canvas.drawRect(
        r,
        Paint()
          ..color = darkMode ? const Color(0x330F172A) : const Color(0x33334155)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.4,
      );
      if (f.isCracked) {
        canvas.drawLine(Offset(xSecLeft + 3, 0.5 * (yTop + yBot)), Offset(xSecRight - 3, 0.5 * (yTop + yBot)),
            Paint()..color = const Color(0xFFEF4444)..strokeWidth = 0.8);
      }
    }
    // Viền ngoài mặt cắt
    canvas.drawRect(
      Rect.fromLTRB(xSecLeft, topPad, xSecRight, topPad + secH),
      Paint()
        ..color = darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // Vẽ cốt cứng chữ I (nếu có)
    if (cfg.hasRigidCore) {
      final cx = 0.5 * (xSecLeft + xSecRight);
      final scaleX = secW / cfg.widthMm;
      final bwPx = cfg.coreBMm * scaleX;
      final twPx = math.max(3.0, cfg.coreTwMm * scaleX);
      final tfPx = math.max(3.0, (cfg.coreTfMm / h) * secH);
      final yCoreTop = yToPx(0.5 * cfg.coreHMm);
      final yCoreBot = yToPx(-0.5 * cfg.coreHMm);
      final coreP = Paint()..color = const Color(0xFF38BDF8);
      canvas.drawRect(Rect.fromLTRB(cx - 0.5 * bwPx, yCoreTop, cx + 0.5 * bwPx, yCoreTop + tfPx), coreP);
      canvas.drawRect(Rect.fromLTRB(cx - 0.5 * bwPx, yCoreBot - tfPx, cx + 0.5 * bwPx, yCoreBot), coreP);
      canvas.drawRect(Rect.fromLTRB(cx - 0.5 * twPx, yCoreTop + tfPx, cx + 0.5 * twPx, yCoreBot - tfPx), coreP);
    }

    // Vẽ chấm tròn cốt thép tại đúng trọng tâm As, As'
    for (final f in section.fibers) {
      if (f.spec.kind != 'rebar_bot' && f.spec.kind != 'rebar_top') continue;
      final yPx = yToPx(f.spec.yMm);
      final nDots = f.spec.kind == 'rebar_bot' ? (cfg.asBotMm2 > 1400 ? 4 : 3) : 2;
      final col = f.isYielded ? const Color(0xFFFF3B30) : const Color(0xFFFACC15);
      for (int k = 0; k < nDots; k++) {
        final dx = nDots == 1 ? 0.5 : (0.18 + 0.64 * k / (nDots - 1));
        final cx = xSecLeft + dx * secW;
        canvas.drawCircle(Offset(cx, yPx), 4.2, Paint()..color = col);
        canvas.drawCircle(
          Offset(cx, yPx),
          4.2,
          Paint()
            ..color = const Color(0xFF0F172A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      }
    }

    // Đường trục trung hòa x_NA chạy ngang suốt cả 3 biểu đồ!
    final yNaPx = yToPx(section.yNeutralMm);
    final naPaint = Paint()..color = const Color(0xFF4ADE80)..strokeWidth = 1.5;
    for (double x = xSecLeft - 6; x < size.width - 10; x += 8) {
      canvas.drawLine(Offset(x, yNaPx), Offset(math.min(x + 4.5, size.width - 10), yNaPx), naPaint);
    }
    _txt(canvas, Offset(xSecLeft, size.height - 15), 'x_NA = ${section.xNeutralDepthMm.toStringAsFixed(0)} mm', const Color(0xFF4ADE80), 8.8, bold: true);

    // 2. CỘT 2: BIỂU ĐỒ BIẾN DẠNG TUYẾN TÍNH ε(y) (‰)
    final col2X = xSecRight + (size.width - xSecRight) * 0.25;
    final col2Half = (size.width - xSecRight) * 0.19;
    _txt(canvas, Offset(col2X - 30, 5), 'Biến dạng ε (‰)', const Color(0xFF38BDF8), 9.2, bold: true);
    canvas.drawLine(
      Offset(col2X, topPad),
      Offset(col2X, topPad + secH),
      Paint()..color = darkMode ? const Color(0xFF475569) : const Color(0xFF64748B)..strokeWidth = 1.0,
    );
    final epsTop = section.eps0 - (0.5 * h) * section.kappa;
    final epsBot = section.eps0 - (-0.5 * h) * section.kappa;
    final maxEps = math.max(1e-5, math.max(epsTop.abs(), epsBot.abs()));
    final pEpsTop = Offset(col2X + (epsTop / maxEps) * col2Half, topPad);
    final pEpsBot = Offset(col2X + (epsBot / maxEps) * col2Half, topPad + secH);
    final epsPoly = Path()
      ..moveTo(col2X, topPad)
      ..lineTo(pEpsTop.dx, pEpsTop.dy)
      ..lineTo(pEpsBot.dx, pEpsBot.dy)
      ..lineTo(col2X, topPad + secH)
      ..close();
    canvas.drawPath(epsPoly, Paint()..color = const Color(0xFF06B6D4).withValues(alpha: 0.22));
    canvas.drawLine(pEpsTop, pEpsBot, Paint()..color = const Color(0xFF06B6D4)..strokeWidth = 2.0);
    _txt(canvas, Offset(col2X - col2Half, topPad + 2), '${(epsTop * 1000).toStringAsFixed(2)}‰', const Color(0xFF60A5FA), 8.3);
    _txt(canvas, Offset(col2X + 4, topPad + secH - 13), '+${(epsBot * 1000).toStringAsFixed(2)}‰', const Color(0xFFFBBF24), 8.3);

    // 3. CỘT 3: BIỂU ĐỒ ỨNG SUẤT PHI TUYẾN σ(y) (Bê tông Parabol + Mũi tên lực cốt thép!)
    final col3X = xSecRight + (size.width - xSecRight) * 0.70;
    final col3Half = (size.width - xSecRight) * 0.21;
    _txt(canvas, Offset(col3X - 30, 5), 'Ứng suất σ (MPa)', const Color(0xFFF59E0B), 8.8, bold: true, maxX: size.width);
    canvas.drawLine(
      Offset(col3X, topPad),
      Offset(col3X, topPad + secH),
      Paint()..color = darkMode ? const Color(0xFF475569) : const Color(0xFF64748B)..strokeWidth = 1.0,
    );
    final maxConcSig = math.max(cfg.fctMpa, section.fibers.where((f) => f.spec.kind == 'concrete').fold(0.0, (m, f) => math.max(m, f.stressMpa.abs())));
    final concList = section.fibers.where((f) => f.spec.kind == 'concrete').toList();
    if (concList.length >= 2) {
      final sp = Path()..moveTo(col3X, yToPx(concList.first.spec.yMm));
      for (final f in concList) {
        final sx = col3X + (f.stressMpa / maxConcSig) * col3Half;
        sp.lineTo(sx, yToPx(f.spec.yMm));
      }
      sp.lineTo(col3X, yToPx(concList.last.spec.yMm));
      sp.close();
      canvas.drawPath(sp, Paint()..color = const Color(0xFF3B82F6).withValues(alpha: 0.30));
      canvas.drawPath(sp, Paint()..color = const Color(0xFF60A5FA)..style = PaintingStyle.stroke..strokeWidth = 1.8);
    }
    // Mũi tên lực cốt thép kéo đáy (As) & nén đỉnh (As')
    for (final f in section.fibers) {
      if (f.spec.kind != 'rebar_bot' && f.spec.kind != 'rebar_top') continue;
      final yPx = yToPx(f.spec.yMm);
      final dir = f.stressMpa >= 0 ? 1.0 : -1.0;
      final len = (f.stressMpa.abs() / math.max(1.0, cfg.fyMpa)).clamp(0.15, 1.0) * col3Half;
      final col = f.isYielded ? const Color(0xFFFF3B30) : const Color(0xFFFACC15);
      canvas.drawLine(Offset(col3X, yPx), Offset(col3X + dir * len, yPx), Paint()..color = col..strokeWidth = 3.2);
      _txt(
        canvas,
        Offset(col3X + (dir > 0 ? 4 : -col3Half), yPx - 12),
        '${f.stressMpa.toStringAsFixed(0)} MPa',
        col,
        8.2,
        bold: true,
      );
    }
  }

  void _txt(Canvas canvas, Offset pos, String t, Color col, double sz, {bool bold = false, double? maxX}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: col, fontSize: sz, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = maxX != null ? math.min(pos.dx, math.max(4.0, maxX - tp.width - 6.0)) : pos.dx;
    tp.paint(canvas, Offset(x, pos.dy));
  }

  @override
  bool shouldRepaint(covariant _FiberSectionPainter old) => true;
}

// ============================================================================
// 2. TAB MA TRẬN ĐỘ CỨNG PTHH & QUAN HỆ LỰC – CHUYỂN VỊ PHẦN TỬ
// ============================================================================
class RcBeamFemMatrixPanel extends StatefulWidget {
  final RcBeamAnalysisResult result;
  final bool darkMode;

  const RcBeamFemMatrixPanel({
    super.key,
    required this.result,
    required this.darkMode,
  });

  @override
  State<RcBeamFemMatrixPanel> createState() => _RcBeamFemMatrixPanelState();
}

class _RcBeamFemMatrixPanelState extends State<RcBeamFemMatrixPanel> {
  int _selectedElem = 0;

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = widget.darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final textSub = widget.darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    final elems = widget.result.elements;
    if (elems.isEmpty) return const SizedBox.shrink();
    final eIdx = _selectedElem.clamp(0, elems.length - 1);
    final el = elems[eIdx];
    const dofNames = ['u₁', 'v₁', 'θ₁', 'u₂', 'v₂', 'θ₂'];
    const fNames = ['N₁ (kN)', 'V₁ (kN)', 'M₁ (kN·m)', 'N₂ (kN)', 'V₂ (kN)', 'M₂ (kN·m)'];
    final fVals = [
      el.fEndElem[0] / 1e3,
      el.fEndElem[1] / 1e3,
      el.fEndElem[2] / 1e6,
      el.fEndElem[3] / 1e3,
      el.fEndElem[4] / 1e3,
      el.fEndElem[5] / 1e6,
    ];
    final dLabels = [
      '${el.dElem[0].toStringAsFixed(4)} mm',
      '${el.dElem[1].toStringAsFixed(4)} mm',
      '${(el.dElem[2] * 1000).toStringAsFixed(3)} mrad',
      '${el.dElem[3].toStringAsFixed(4)} mm',
      '${el.dElem[4].toStringAsFixed(4)} mm',
      '${(el.dElem[5] * 1000).toStringAsFixed(3)} mrad',
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Chọn phần tử khảo sát
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chọn Phần tử Dầm 2 nút (6 bậc tự do) để soi Ma trận [K_t^e]:',
                style: TextStyle(fontSize: 10.8, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (int i = 0; i < elems.length; i++)
                    ChoiceChip(
                      label: Text('E${i + 1}', style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.bold)),
                      selected: i == eIdx,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _selectedElem = i),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Phần tử E${eIdx + 1}: x ∈ [${el.x1Mm.toStringAsFixed(0)}, ${el.x2Mm.toStringAsFixed(0)}] mm  •  L_e = ${el.lengthMm.toStringAsFixed(0)} mm  •  M_trái = ${el.m1Knm.toStringAsFixed(2)}, M_phải = ${el.m2Knm.toStringAsFixed(2)} kN·m',
                style: TextStyle(fontSize: 9.8, color: textSub),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 1. Quan hệ Véc-tơ Nội lực {f^e} ↔ Véc-tơ Chuyển vị {d^e} hai đầu phần tử
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quan hệ Véc-tơ Nội lực {f^e} ↔ Chuyển vị {d^e} Hai đầu Phần tử',
                style: TextStyle(fontSize: 10.8, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 6),
              Table(
                border: TableBorder.all(color: border, width: 0.7),
                columnWidths: const {0: FlexColumnWidth(0.9), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.5)},
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: widget.darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                    children: const [
                      _Cell('DOF', bold: true),
                      _Cell('Chuyển vị {d^e}', bold: true),
                      _Cell('Lực đầu thanh {f^e}', bold: true),
                    ],
                  ),
                  for (int i = 0; i < 6; i++)
                    TableRow(
                      children: [
                        _Cell(dofNames[i], bold: true, color: const Color(0xFF38BDF8)),
                        _Cell(dLabels[i], mono: true),
                        _Cell('${fNames[i]}: ${fVals[i].toStringAsFixed(2)}', mono: true),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2. Ma trận độ cứng mặt cắt 2×2 [Dt] tại 3 điểm Gauss-Legendre
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tích phân Gauss-Legendre 3 điểm — Ma trận Mặt cắt [D_t] & Trục trung hòa',
                style: TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
              ),
              const SizedBox(height: 6),
              Table(
                border: TableBorder.all(color: border, width: 0.7),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: widget.darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                    children: const [
                      _Cell('Điểm GP', bold: true),
                      _Cell('EA_t (MN)', bold: true),
                      _Cell('EI_eff (10¹²)', bold: true),
                      _Cell('x_NA (mm)', bold: true),
                    ],
                  ),
                  for (int g = 0; g < el.gaussSections.length; g++)
                    TableRow(
                      children: [
                        _Cell('GP${g + 1} (${g == 0 ? "0.11" : (g == 1 ? "0.50" : "0.89")})', mono: true),
                        _Cell((el.gaussSections[g].eaTangentN / 1e6).toStringAsFixed(1), mono: true),
                        _Cell((el.gaussSections[g].eiEffNmm2 / 1e12).toStringAsFixed(3), mono: true),
                        _Cell(el.gaussSections[g].xNeutralDepthMm.toStringAsFixed(1), mono: true),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 3. Ma trận độ cứng tiếp tuyến phần tử 6×6 [Kt^e] (N, mm)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ma trận Độ cứng Tiếp tuyến Phần tử [K_t^e] (6×6) = ∫ [B]ᵀ[D_t][B] dx',
                style: TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(72),
                  border: TableBorder.all(color: border, width: 0.6),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: widget.darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                      children: [
                        const _Cell('K_t^e', bold: true),
                        for (final n in dofNames) _Cell(n, bold: true, color: const Color(0xFF38BDF8)),
                      ],
                    ),
                    for (int r = 0; r < 6; r++)
                      TableRow(
                        children: [
                          _Cell(dofNames[r], bold: true, color: const Color(0xFF38BDF8)),
                          for (int c = 0; c < 6; c++)
                            _Cell(
                              el.kt6x6[r][c].abs() < 1e-4 ? '0' : el.kt6x6[r][c].toStringAsExponential(2),
                              mono: true,
                              color: r == c ? const Color(0xFFFBBF24) : null,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 4. Bảng chuyển vị & phản lực tại toàn bộ các nút lưới
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bảng Chuyển vị Nút & Phản lực Gối (${widget.result.nNodes} nút, ΣFy = ${widget.result.sumFyN.toStringAsExponential(1)} N)',
                style: const TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 6),
              Table(
                border: TableBorder.all(color: border, width: 0.6),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: widget.darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                    children: const [
                      _Cell('Nút', bold: true),
                      _Cell('x (mm)', bold: true),
                      _Cell('v (mm)', bold: true),
                      _Cell('θ (mrad)', bold: true),
                      _Cell('Ry (kN)', bold: true),
                    ],
                  ),
                  for (int i = 0; i < widget.result.nNodes; i++)
                    TableRow(
                      children: [
                        _Cell('N${i + 1}', bold: true),
                        _Cell(widget.result.xNodesMm[i].toStringAsFixed(0), mono: true),
                        _Cell(widget.result.dGlobal[3 * i + 1].toStringAsFixed(3), mono: true),
                        _Cell((widget.result.dGlobal[3 * i + 2] * 1000).toStringAsFixed(2), mono: true),
                        _Cell(
                          widget.result.reactions[3 * i + 1].abs() > 1.0
                              ? (widget.result.reactions[3 * i + 1] / 1000.0).toStringAsFixed(2)
                              : '—',
                          mono: true,
                          color: widget.result.reactions[3 * i + 1].abs() > 1.0 ? const Color(0xFF10B981) : null,
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final bool bold;
  final bool mono;
  final Color? color;
  const _Cell(this.text, {this.bold = false, this.mono = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9.2,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFamily: mono ? 'DejaVuSansMono' : null,
          color: color,
        ),
      ),
    );
  }
}

// ============================================================================
// 3. TAB BIỂU ĐỒ P-Δ, M-κ, KHẢO SÁT HỘI TỤ LƯỚI (2..32) & HỘI TỤ NR
// ============================================================================
class RcBeamChartsPanel extends StatelessWidget {
  final RcBeamAnalysisResult resultActive;
  final RcBeamAnalysisResult resultLinear;
  final List<RcLoadDeflectionPoint> pushover;
  final List<RcMomentCurvaturePoint> momentCurvature;
  final List<RcMeshConvergencePoint> meshConvergence;
  final bool darkMode;

  const RcBeamChartsPanel({
    super.key,
    required this.resultActive,
    required this.resultLinear,
    required this.pushover,
    required this.momentCurvature,
    required this.meshConvergence,
    required this.darkMode,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final textSub = darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    // Xác định điểm nứt P_cr, chảy P_y, cực đại P_u trên đường P-Δ
    final pCrPt = pushover.cast<RcLoadDeflectionPoint?>().firstWhere((p) => p!.cracked, orElse: () => null);
    final pYPt = pushover.cast<RcLoadDeflectionPoint?>().firstWhere((p) => p!.yielded, orElse: () => null);
    final pMax = pushover.fold(0.0, (m, p) => math.max(m, p.loadQKn));

    // Xác định điểm nứt M_cr, chảy M_y, cực đại M_u trên đường M-κ
    final mCrPt = momentCurvature.cast<RcMomentCurvaturePoint?>().firstWhere((p) => p!.cracked, orElse: () => null);
    final mYPt = momentCurvature.cast<RcMomentCurvaturePoint?>().firstWhere((p) => p!.yielded, orElse: () => null);
    final mMax = momentCurvature.fold(0.0, (m, p) => math.max(m, p.momentKnm));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. Đường cong Tải trọng – Độ võng P-Δ (Pushover Tuyến tính vs Phi tuyến Thớ)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. Đường cong Ứng xử Tải – Độ võng (P – Δ)',
                style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(height: 4),
              Text(
                'P_cr = ${pCrPt != null ? "${pCrPt.loadQKn.toStringAsFixed(1)} kN" : "—"}  •  '
                'P_y = ${pYPt != null ? "${pYPt.loadQKn.toStringAsFixed(1)} kN" : "—"}  •  '
                'P_u = ${pMax.toStringAsFixed(1)} kN',
                style: TextStyle(fontSize: 9.8, color: textSub),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 195,
                width: double.infinity,
                child: CustomPaint(
                  painter: _PushoverChartPainter(
                    pushover: pushover,
                    activeQKn: resultActive.config.loadQKn,
                    activeDispMm: resultActive.vMidMm.abs(),
                    linearDispAtActiveQ: resultLinear.vMidMm.abs(),
                    darkMode: darkMode,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2. Đường cong Mô-men – Độ cong mặt cắt (M – κ)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '2. Đường cong Mô-men – Độ cong Mặt cắt Thớ (M – κ)',
                style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
              ),
              const SizedBox(height: 4),
              Text(
                'M_cr = ${mCrPt != null ? "${mCrPt.momentKnm.toStringAsFixed(1)} kN·m" : "—"}  •  '
                'M_y = ${mYPt != null ? "${mYPt.momentKnm.toStringAsFixed(1)} kN·m" : "—"}  •  '
                'M_u = ${mMax.toStringAsFixed(1)} kN·m',
                style: TextStyle(fontSize: 9.8, color: textSub),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  painter: _MomentCurvaturePainter(points: momentCurvature, darkMode: darkMode),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 3. Khảo sát bài toán hội tụ lưới phần tử (chia hai nửa: 2, 4, 8, 16, 32 phần tử)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '3. Khảo sát Hội tụ Lưới Phần tử (Chia hai nửa đối xứng: 2 → 32 PT)',
                style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: _MeshConvergencePainter(points: meshConvergence, darkMode: darkMode),
                ),
              ),
              const SizedBox(height: 8),
              Table(
                border: TableBorder.all(color: border, width: 0.6),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                    children: const [
                      _Cell('Số PT', bold: true),
                      _Cell('|v_mid| (mm)', bold: true),
                      _Cell('M_max', bold: true),
                      _Cell('x_NA', bold: true),
                      _Cell('Sai số %', bold: true),
                    ],
                  ),
                  for (final m in meshConvergence)
                    TableRow(
                      children: [
                        _Cell('${m.nElems} (${m.nElems ~/ 2}+${m.nElems ~/ 2})', bold: true),
                        _Cell(m.vMidMm.toStringAsFixed(3), mono: true),
                        _Cell(m.mMaxKnm.toStringAsFixed(1), mono: true),
                        _Cell('${m.xNeutralMm.toStringAsFixed(0)} mm', mono: true),
                        _Cell(
                          '${m.relErrorPct.toStringAsFixed(2)}%',
                          mono: true,
                          color: m.relErrorPct < 1.0 ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 4. Tốc độ hội tụ lặp Newton-Raphson bước cuối
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '4. Hội tụ Lặp Newton-Raphson (${resultActive.totalIterations} vòng tổng • ${resultActive.converged ? "Hội tụ đạt chuẩn" : "Chưa hội tụ"})',
                style: const TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 120,
                width: double.infinity,
                child: CustomPaint(
                  painter: _NrResidualPainter(residuals: resultActive.iterResidualsN, darkMode: darkMode),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PushoverChartPainter extends CustomPainter {
  final List<RcLoadDeflectionPoint> pushover;
  final double activeQKn;
  final double activeDispMm;
  final double linearDispAtActiveQ;
  final bool darkMode;

  _PushoverChartPainter({
    required this.pushover,
    required this.activeQKn,
    required this.activeDispMm,
    required this.linearDispAtActiveQ,
    required this.darkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 44.0, padR = 14.0, padT = 14.0, padB = 26.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    final bg = darkMode ? const Color(0xFF07101E) : const Color(0xFFF8FAFC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(padL, padT, w, h), const Radius.circular(6)),
      Paint()..color = bg,
    );
    final axisCol = darkMode ? const Color(0xFF475569) : const Color(0xFF64748B);
    canvas.drawLine(Offset(padL, padT), Offset(padL, padT + h), Paint()..color = axisCol);
    canvas.drawLine(Offset(padL, padT + h), Offset(padL + w, padT + h), Paint()..color = axisCol);

    if (pushover.length < 2) return;
    final maxX = math.max(activeDispMm * 1.15, pushover.fold(1.0, (m, p) => math.max(m, p.deflectionMidMm))) * 1.06;
    final maxY = math.max(activeQKn * 1.15, pushover.fold(10.0, (m, p) => math.max(m, p.loadQKn))) * 1.08;

    Offset map(double dx, double qy) => Offset(padL + (dx / maxX) * w, padT + h - (qy / maxY) * h);

    // Lưới & nhãn trục
    final gridP = Paint()..color = axisCol.withValues(alpha: 0.25)..strokeWidth = 0.7;
    for (int i = 1; i <= 4; i++) {
      final y = padT + h * (1.0 - i / 4.0);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridP);
      _drawLbl(canvas, Offset(2, y - 6), (maxY * i / 4.0).toStringAsFixed(0), axisCol, 8.4);
      final x = padL + w * (i / 4.0);
      canvas.drawLine(Offset(x, padT), Offset(x, padT + h), gridP);
      _drawLbl(canvas, Offset(x - 10, padT + h + 5), (maxX * i / 4.0).toStringAsFixed(1), axisCol, 8.4);
    }
    _drawLbl(canvas, Offset(padL + w * 0.36, size.height - 12), 'Độ võng giữa nhịp |v| (mm)', axisCol, 8.5);
    _drawLbl(canvas, Offset(4, 1), 'Q (kN)', axisCol, 8.5);

    // Đường Tuyến tính đàn hồi (nét đứt xám-cyan)
    if (linearDispAtActiveQ > 1e-6 && activeQKn > 1e-3) {
      final slope = activeQKn / linearDispAtActiveQ;
      final qEdge = math.min(maxY, slope * maxX);
      final dEdge = qEdge / slope;
      canvas.drawLine(
        map(0, 0),
        map(dEdge, qEdge),
        Paint()..color = const Color(0xFF94A3B8)..strokeWidth = 1.4,
      );
      _drawLbl(canvas, map(dEdge * 0.72, qEdge * 0.72) + const Offset(-34, -12), 'Tuyến tính', const Color(0xFF94A3B8), 8.2);
    }

    // Đường cong Phi tuyến Thớ (cam đỏ đậm)
    final path = Path()..moveTo(map(pushover.first.deflectionMidMm, pushover.first.loadQKn).dx, map(pushover.first.deflectionMidMm, pushover.first.loadQKn).dy);
    for (int i = 1; i < pushover.length; i++) {
      final pt = map(pushover[i].deflectionMidMm, pushover[i].loadQKn);
      path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFF97316)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );

    // Đánh dấu P_cr, P_y và Điểm làm việc hiện tại
    final pCr = pushover.cast<RcLoadDeflectionPoint?>().firstWhere((p) => p!.cracked, orElse: () => null);
    if (pCr != null) {
      final c = map(pCr.deflectionMidMm, pCr.loadQKn);
      canvas.drawCircle(c, 4.0, Paint()..color = const Color(0xFFFBBF24));
      _drawLbl(canvas, c + const Offset(5, -10), 'P_cr', const Color(0xFFFBBF24), 8.4, bold: true);
    }
    final pY = pushover.cast<RcLoadDeflectionPoint?>().firstWhere((p) => p!.yielded, orElse: () => null);
    if (pY != null) {
      final c = map(pY.deflectionMidMm, pY.loadQKn);
      canvas.drawCircle(c, 4.3, Paint()..color = const Color(0xFFEF4444));
      _drawLbl(canvas, c + const Offset(5, -12), 'P_y', const Color(0xFFEF4444), 8.4, bold: true);
    }

    final op = map(activeDispMm, activeQKn);
    canvas.drawCircle(op, 5.2, Paint()..color = const Color(0xFF22C55E));
    canvas.drawCircle(op, 5.2, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    _drawLbl(
      canvas,
      Offset((op.dx + 6).clamp(padL + 4, padL + w - 76), (op.dy - 14).clamp(padT + 2, padT + h - 14)),
      'Q=${activeQKn.toStringAsFixed(0)} kN',
      const Color(0xFF22C55E),
      8.6,
      bold: true,
    );
  }

  void _drawLbl(Canvas c, Offset p, String t, Color col, double sz, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: col, fontSize: sz, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p);
  }

  @override
  bool shouldRepaint(covariant _PushoverChartPainter old) => true;
}

class _MomentCurvaturePainter extends CustomPainter {
  final List<RcMomentCurvaturePoint> points;
  final bool darkMode;
  _MomentCurvaturePainter({required this.points, required this.darkMode});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 44.0, padR = 14.0, padT = 14.0, padB = 26.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(padL, padT, w, h), const Radius.circular(6)),
      Paint()..color = darkMode ? const Color(0xFF07101E) : const Color(0xFFF8FAFC),
    );
    final axisCol = darkMode ? const Color(0xFF475569) : const Color(0xFF64748B);
    canvas.drawLine(Offset(padL, padT), Offset(padL, padT + h), Paint()..color = axisCol);
    canvas.drawLine(Offset(padL, padT + h), Offset(padL + w, padT + h), Paint()..color = axisCol);
    if (points.length < 2) return;

    final maxK = points.fold(1e-6, (m, p) => math.max(m, p.kappaPerMm * 1e6)) * 1.05;
    final maxM = points.fold(10.0, (m, p) => math.max(m, p.momentKnm)) * 1.08;
    Offset map(double k6, double m) => Offset(padL + (k6 / maxK) * w, padT + h - (m / maxM) * h);

    final gridP = Paint()..color = axisCol.withValues(alpha: 0.25)..strokeWidth = 0.7;
    for (int i = 1; i <= 4; i++) {
      final y = padT + h * (1.0 - i / 4.0);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridP);
      _lbl(canvas, Offset(2, y - 6), (maxM * i / 4.0).toStringAsFixed(0), axisCol, 8.4);
      final x = padL + w * (i / 4.0);
      canvas.drawLine(Offset(x, padT), Offset(x, padT + h), gridP);
      _lbl(canvas, Offset(x - 10, padT + h + 5), (maxK * i / 4.0).toStringAsFixed(1), axisCol, 8.2);
    }
    _lbl(canvas, Offset(padL + w * 0.34, size.height - 12), 'Độ cong κ (10⁻⁶ /mm)', axisCol, 8.4);
    _lbl(canvas, Offset(2, 1), 'M (kN·m)', axisCol, 8.4);

    final path = Path()..moveTo(map(points.first.kappaPerMm * 1e6, points.first.momentKnm).dx, map(points.first.kappaPerMm * 1e6, points.first.momentKnm).dy);
    for (int i = 1; i < points.length; i++) {
      final pt = map(points[i].kappaPerMm * 1e6, points[i].momentKnm);
      path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFFF59E0B)..style = PaintingStyle.stroke..strokeWidth = 2.4);

    final mY = points.cast<RcMomentCurvaturePoint?>().firstWhere((p) => p!.yielded, orElse: () => null);
    if (mY != null) {
      final pt = map(mY.kappaPerMm * 1e6, mY.momentKnm);
      canvas.drawCircle(pt, 4.2, Paint()..color = const Color(0xFFEF4444));
      _lbl(canvas, pt + const Offset(5, -12), 'M_y=${mY.momentKnm.toStringAsFixed(0)}', const Color(0xFFEF4444), 8.4, bold: true);
    }
  }

  void _lbl(Canvas c, Offset p, String t, Color col, double sz, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: col, fontSize: sz, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p);
  }

  @override
  bool shouldRepaint(covariant _MomentCurvaturePainter old) => true;
}

class _MeshConvergencePainter extends CustomPainter {
  final List<RcMeshConvergencePoint> points;
  final bool darkMode;
  _MeshConvergencePainter({required this.points, required this.darkMode});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 44.0, padR = 16.0, padT = 14.0, padB = 24.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(padL, padT, w, h), const Radius.circular(6)),
      Paint()..color = darkMode ? const Color(0xFF07101E) : const Color(0xFFF8FAFC),
    );
    final axisCol = darkMode ? const Color(0xFF475569) : const Color(0xFF64748B);
    canvas.drawLine(Offset(padL, padT), Offset(padL, padT + h), Paint()..color = axisCol);
    canvas.drawLine(Offset(padL, padT + h), Offset(padL + w, padT + h), Paint()..color = axisCol);
    if (points.isEmpty) return;

    double minV = points.fold(double.infinity, (m, p) => math.min(m, p.vMidMm));
    double maxV = points.fold(-double.infinity, (m, p) => math.max(m, p.vMidMm));
    final spanV = math.max(0.1, maxV - minV);
    minV = math.max(0.0, minV - spanV * 0.25);
    maxV = maxV + spanV * 0.25;

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final px = padL + (points.length == 1 ? 0.5 : i / (points.length - 1)) * w;
      final py = padT + h - ((points[i].vMidMm - minV) / math.max(1e-6, maxV - minV)) * h;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
      canvas.drawCircle(Offset(px, py), 4.2, Paint()..color = const Color(0xFF10B981));
      _lbl(canvas, Offset(px - 10, padT + h + 4), '${points[i].nElems}PT', axisCol, 8.4, bold: true);
      _lbl(canvas, Offset(px - 14, py - 14), points[i].vMidMm.toStringAsFixed(2), const Color(0xFF10B981), 8.2, bold: true);
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFF10B981)..style = PaintingStyle.stroke..strokeWidth = 2.0);
    _lbl(canvas, Offset(2, 1), '|v| mm', axisCol, 8.3);
  }

  void _lbl(Canvas c, Offset p, String t, Color col, double sz, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: col, fontSize: sz, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p);
  }

  @override
  bool shouldRepaint(covariant _MeshConvergencePainter old) => true;
}

class _NrResidualPainter extends CustomPainter {
  final List<double> residuals;
  final bool darkMode;
  _NrResidualPainter({required this.residuals, required this.darkMode});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 40.0, padR = 12.0, padT = 10.0, padB = 20.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(padL, padT, w, h), const Radius.circular(6)),
      Paint()..color = darkMode ? const Color(0xFF07101E) : const Color(0xFFF8FAFC),
    );
    final axisCol = darkMode ? const Color(0xFF475569) : const Color(0xFF64748B);
    canvas.drawLine(Offset(padL, padT), Offset(padL, padT + h), Paint()..color = axisCol);
    canvas.drawLine(Offset(padL, padT + h), Offset(padL + w, padT + h), Paint()..color = axisCol);
    if (residuals.isEmpty) return;

    final logs = [for (final r in residuals) math.log(math.max(1e-12, r)) / math.ln10];
    const minL = -6.0, maxL = 6.0;
    final path = Path();
    for (int i = 0; i < logs.length; i++) {
      final px = padL + (logs.length == 1 ? 0.5 : i / (logs.length - 1)) * w;
      final py = padT + h - (((logs[i].clamp(minL, maxL)) - minL) / (maxL - minL)) * h;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
      canvas.drawCircle(Offset(px, py), 3.4, Paint()..color = const Color(0xFF38BDF8));
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFF38BDF8)..style = PaintingStyle.stroke..strokeWidth = 2.0);
    final tp = TextPainter(
      text: TextSpan(text: 'log₁₀‖R‖ (bước cuối)', style: TextStyle(color: axisCol, fontSize: 8.3)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(padL + 6, padT + 3));
  }

  @override
  bool shouldRepaint(covariant _NrResidualPainter old) => true;
}

// ============================================================================
// 4. TAB LÝ THUYẾT RAYLEIGH-RITZ, PHƯƠNG PHÁP THỚ & MÃ NGUỒN PYTHON
// ============================================================================
class RcBeamTheoryPanel extends StatelessWidget {
  final RcBeamAnalysisResult result;
  final bool darkMode;

  const RcBeamTheoryPanel({super.key, required this.result, required this.darkMode});

  static const String _pythonSnippet = r'''# Giải Dầm BTCT Phi tuyến Vật liệu — Phương pháp Thớ & Rayleigh-Ritz (CALFEM)
# File nguồn đầy đủ: python_core/rc_beam_fiber.py
for xi, wi in zip([0.11270167, 0.5, 0.88729833], [5/18, 8/18, 5/18]):
    Bu = np.array([-1/Le, 0, 0, 1/Le, 0, 0])
    Bk = np.array([0, (-6+12*xi)/Le**2, (-4+6*xi)/Le,
                   0, (6-12*xi)/Le**2,  (-2+6*xi)/Le])
    B = np.vstack([Bu, Bk])                  # Ma trận biến dạng 2×6
    eps0, kappa = Bu @ de, Bk @ de           # ε(y) = ε0 - y·κ
    # Tích phân qua các thớ bê tông + cốt thép + cốt cứng I:
    N = sum(sig_i * A_i);      M = -sum(sig_i * y_i * A_i)
    EA = sum(Et_i * A_i);      ES = -sum(Et_i * y_i * A_i)
    EI = sum(Et_i * y_i**2 * A_i)            # y_NA = eps0 / kappa
    Dt = np.array([[EA, ES], [ES, EI]])      # Ma trận độ cứng mặt cắt 2×2
    fe += (B.T @ np.array([N, M])) * (wi*Le) # {f_int^e} từ δΠ = 0
    Ke += (B.T @ Dt @ B) * (wi*Le)           # [K_t^e] (6×6): [K_t]{Δd} = {ΔF}''';

  @override
  Widget build(BuildContext context) {
    final cardBg = darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final textSub = darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionCard(
          cardBg,
          border,
          '1. Mô hình Dầm BTCT & Phương pháp Thớ (Fiber Section)',
          '• Dầm bê tông cốt thép đơn giản nhịp L (tỷ lệ L/h = 5 ÷ 10), chịu uốn 3 điểm (M = QL/4 khi a = L/2) hoặc 4 điểm (M = Q·a/2). Hai đầu gối tùy biến (Khớp cố định, Gối di động, Ngàm, Lò xo, Tự do).\n'
          '• Chia chiều cao tiết diện h thành n_fib dải thớ bê tông mỏng dy = h/n_fib. Cốt thép chịu kéo As, chịu nén As\' và tùy chọn Cốt cứng thép hình chữ I đặt chính xác tại trọng tâm y_k tính từ trục hình học.\n'
          '• Giả thiết tiết diện phẳng Euler-Bernoulli: ε(x, y) = ε₀(x) − y · κ(x), với ε₀ = du/dx và độ cong κ = d²v/dx².',
          textSub,
        ),
        const SizedBox(height: 8),
        _sectionCard(
          cardBg,
          border,
          '2. Thiết lập Độ cứng Mặt cắt (EA, ES, EI) & Trục trung hòa',
          '• Bê tông nén theo Parabol Hognestad σ_c = −f\'c[2(ε/ε₀) − (ε/ε₀)²]; bê tông kéo mềm hóa nứt hàm mũ (Tension Stiffening) có mô-đun tiếp tuyến nhất quán.\n'
          '• Cốt thép & cốt cứng theo luật đàn-dẻo song tuyến tính có tái bền.\n'
          '• Nội lực mặt cắt:  N = ∑ σ_i·A_i  ;   M = −∑ σ_i·y_i·A_i\n'
          '• Ma trận tiếp tuyến 2×2 [D_t]:\n'
          '    EA_t = ∑ E_t,i·A_i  ;   ES_t = −∑ E_t,i·y_i·A_i  ;   EI_t = ∑ E_t,i·y_i²·A_i\n'
          '• Độ cứng uốn hiệu dụng quanh trục trung hòa:  EI_eff = EI_t − ES_t² / EA_t\n'
          '• Vị trí Trục trung hòa tức thời:  y_NA = ε₀ / κ   ⇒   x_NA = h/2 − y_NA (tính từ mép nén trên).',
          textSub,
        ),
        const SizedBox(height: 8),
        _sectionCard(
          cardBg,
          border,
          '3. Phương pháp Rayleigh-Ritz (Hàm dừng thế năng → [K_t]{Δd} = {ΔF})',
          '• Xấp xỉ trường chuyển vị phần tử 2 nút 6 bậc tự do {d^e} = [u₁, v₁, θ₁, u₂, v₂, θ₂]ᵀ bằng đa thức tuyến tính cho u(x) và đa thức bậc 3 Hermite cho v(x).\n'
          '• Thế năng toàn phần của hệ:  Π(d) = U(d) − W(d) = ∫_V (∫ σ dε) dV − {d}ᵀ{F_ext}.\n'
          '• Áp dụng nguyên lý hàm dừng δΠ = 0 (Rayleigh-Ritz) thu được phương trình cân bằng phi tuyến:\n'
          '    {R(d)} = {F_ext} − {F_int(d)} = 0 ,  với  {f_int^e} = ∫₀^Le [B(x)]ᵀ {N, M}ᵀ dx.\n'
          '• Tuyến tính hóa véc-tơ lực gia tăng theo véc-tơ chuyển vị gia tăng:\n'
          '    [K_t^e] = ∂{f_int^e}/∂{d^e} = ∫₀^Le [B(x)]ᵀ [D_t(x)] [B(x)] dx   (Gauss-Legendre 3 điểm)\n'
          '    ⇒  [K_t] {Δd} = {ΔF}  (giải lặp Full Newton-Raphson kèm Backtracking Line Search).',
          textSub,
        ),
        const SizedBox(height: 8),
        // Khối mã Python chuẩn có nút sao chép
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '4. Mã nguồn Python Chuẩn (python_core/rc_beam_fiber.py)',
                    style: TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: _pythonSnippet));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã sao chép mã nguồn Python Dầm BTCT!')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 13),
                    label: const Text('Sao chép', style: TextStyle(fontSize: 10)),
                  ),
                ],
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: darkMode ? const Color(0xFF060C18) : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    _pythonSnippet,
                    style: TextStyle(
                      fontFamily: 'DejaVuSansMono',
                      fontSize: 9.2,
                      color: Color(0xFF7DD3FC),
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCard(Color bg, Color border, String title, String body, Color textSub) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 10.8, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
          const SizedBox(height: 5),
          Text(body, style: TextStyle(fontSize: 10.0, height: 1.48, color: textSub)),
        ],
      ),
    );
  }
}
