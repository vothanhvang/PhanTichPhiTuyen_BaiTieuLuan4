// ============================================================================
// BẢNG TRA CỨU LÝ THUYẾT, CÔNG THỨC CẤP 3 & MÃ NGUỒN PYTHON / DART
// ============================================================================
// Hiển thị công thức toán học chuẩn sách giáo khoa: dấu căn bậc hai ĐẦY ĐỦ
// có gạch ngang phủ trọn biểu thức bên trong (vinculum) và phân số xếp tầng!
// ============================================================================

import 'package:flutter/material.dart';

class TheoryAndCodePanel extends StatelessWidget {
  final bool darkMode;
  const TheoryAndCodePanel({super.key, required this.darkMode});

  @override
  Widget build(BuildContext context) {
    final cardBg = darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final codeBg = darkMode ? const Color(0xFF070D19) : const Color(0xFFF8FAFC);
    final textColor = darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
    final mathColor = darkMode ? const Color(0xFF7DD3FC) : const Color(0xFF0F3D6E);
    final formulaBg = darkMode ? const Color(0xFF0A1426) : const Color(0xFFF1F5F9);

    TextStyle bodyStyle() => TextStyle(fontSize: 11, height: 1.48, color: textColor);
    TextStyle mathStyle({bool bold = false}) => TextStyle(
          fontSize: 11.5,
          fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          color: mathColor,
          height: 1.2,
        );

    Widget formulaBox(Widget formulaWidget) {
      return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 8, left: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: formulaBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: mathColor.withValues(alpha: 0.25)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: formulaWidget,
        ),
      );
    }

    Widget cardWrapper(String title, Widget content) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF38BDF8))),
            const SizedBox(height: 6),
            content,
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // MỤC 1: TÓM TẮT 7 CÔNG THỨC TOÁN HỌC VỚI DẤU CĂN ĐẦY ĐỦ & PHÂN SỐ CHUẨN
        cardWrapper(
          '1. Tóm tắt 7 công thức Toán học',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1) Định lý Py-ta-go — Chiều dài thực thanh sau biến dạng:', style: bodyStyle()),
              formulaBox(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('l = ', style: mathStyle(bold: true)),
                    _MathSqrt(
                      color: mathColor,
                      child: Text('(Δx₀ + Δuₓ)² + (Δy₀ + Δuᵧ)²', style: mathStyle()),
                    ),
                  ],
                ),
              ),
              Text('2) Hằng đẳng thức hiệu hai bình phương — Khử sai số làm tròn máy tính:', style: bodyStyle()),
              formulaBox(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('l − L₀ = ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('l² − L₀²', style: mathStyle()),
                      denominator: Text('l + L₀', style: mathStyle()),
                      color: mathColor,
                    ),
                  ],
                ),
              ),
              Text('3) Lượng giác & Cosin chỉ phương (c² + s² = 1):', style: bodyStyle()),
              formulaBox(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('c = cos θ = ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('x₂ − x₁', style: mathStyle()),
                      denominator: Text('L', style: mathStyle()),
                      color: mathColor,
                    ),
                    Text('   ;   s = sin θ = ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('y₂ − y₁', style: mathStyle()),
                      denominator: Text('L', style: mathStyle()),
                      color: mathColor,
                    ),
                  ],
                ),
              ),
              Text('4) Khai triển nhị thức Newton → dẫn xuất biến dạng Green-Lagrange:', style: bodyStyle()),
              formulaBox(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _MathSqrt(
                      color: mathColor,
                      child: Text('1 + d', style: mathStyle()),
                    ),
                    Text('  ≈  1 + ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('d', style: mathStyle()),
                      denominator: Text('2', style: mathStyle()),
                      color: mathColor,
                    ),
                  ],
                ),
              ),
              Text('5) Đạo hàm, biến phân bình phương & Tích phân xác định:', style: bodyStyle()),
              formulaBox(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('δ(f²) = 2f · δf   ;   ∫₀ᴸ ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('1', style: mathStyle()),
                      denominator: Text('L²', style: mathStyle()),
                      color: mathColor,
                    ),
                    Text(' dx = ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('1', style: mathStyle()),
                      denominator: Text('L', style: mathStyle()),
                      color: mathColor,
                    ),
                  ],
                ),
              ),
              Text('6) Phương pháp tiếp tuyến Newton-Raphson giải hệ phi tuyến:', style: bodyStyle()),
              formulaBox(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('u_mới = u_cũ + ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('R(u_cũ)', style: mathStyle()),
                      denominator: Text('K_t(u_cũ)', style: mathStyle()),
                      color: mathColor,
                    ),
                  ],
                ),
              ),
              Text('7) Quy tắc đòn bẩy mô-men biến dạng & Bài toán trị riêng mất ổn định:', style: bodyStyle()),
              formulaBox(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('R₄ᵧ = −P · ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('L + u₂ₓ', style: mathStyle()),
                      denominator: Text('2L + u₄ₓ', style: mathStyle()),
                      color: mathColor,
                    ),
                    Text('   ;   det(K_e + α_cr·K_g) = 0', style: mathStyle(bold: true)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // MỤC 2: BA CẤP ĐỘ PHÂN TÍCH PHI TUYẾN HÌNH HỌC
        cardWrapper(
          '2. Ba cấp độ Phân tích Phi tuyến Hình học (Dẫn nguồn Giáo trình)',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• Cấp 1 – Tuyến tính Bậc 1 (CALFEM bar2e – calfem34.pdf tr. 5.3-2 / PDF tr. 60): cân bằng trên hình dạng chưa biến dạng.\n'
                '• Cấp 2 – Bậc 2 CALFEM gốc (bar2g – Dahlblom 2016 PT 9.35–9.38 tr. 259 / PDF tr. 273): cộng ma trận độ cứng hình học ngang (N/L)·K_eσ, lặp cập nhật lực dọc N.\n'
                '• Cấp 3a – Đồng chuyển động Corotational UL (Jeffers 2026 Mục 8.3 tr. 186; Yang 2025 Chương 4 tr. 119): đánh giá bar2g tại tọa độ biến dạng hiện tại x = X + u:',
                style: bodyStyle(),
              ),
              formulaBox(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('ε_eng = ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('l − L₀', style: mathStyle()),
                      denominator: Text('L₀', style: mathStyle()),
                      color: mathColor,
                    ),
                    Text('   ;   K_t = ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('EA', style: mathStyle()),
                      denominator: Text('L₀', style: mathStyle()),
                      color: mathColor,
                    ),
                    Text('(n·nᵀ) + ', style: mathStyle()),
                    _MathFrac(
                      numerator: Text('N', style: mathStyle()),
                      denominator: Text('l', style: mathStyle()),
                      color: mathColor,
                    ),
                    Text('(I − n·nᵀ)', style: mathStyle()),
                  ],
                ),
              ),
              Text(
                '• Cấp 3b – Total Lagrangian (Bài giảng NSA_4 Slides 6–12 / PDF tr. 2–3; McGuire 2000 PT 9.1–9.9 tr. 243–245): dùng biến dạng Green-Lagrange:',
                style: bodyStyle(),
              ),
              formulaBox(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('ε_GL = ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('l² − L₀²', style: mathStyle()),
                      denominator: Text('2L₀²', style: mathStyle()),
                      color: mathColor,
                    ),
                    Text('   ;   [k_g] = ', style: mathStyle(bold: true)),
                    _MathFrac(
                      numerator: Text('F_x2', style: mathStyle()),
                      denominator: Text('L₀', style: mathStyle()),
                      color: mathColor,
                    ),
                    Text('·[[I, −I], [−I, I]]', style: mathStyle()),
                  ],
                ),
              ),
            ],
          ),
        ),

        // MỤC 3: BẢN CHẤT VẬT LÝ
        cardWrapper(
          '3. Bản chất Vật lý Đáng chú ý của Hệ Dàn 5 thanh Đề bài',
          Text(
            '• Thanh 1–2 "hồi sinh": Trong tuyến tính N₁₂ = 0 (thanh không lực), nhưng trong phi tuyến hình học khi Nút 2 dịch chuyển lên trên, theo định lý Py-ta-go thanh 1–2 bị kéo giãn và phát sinh lực kéo N₁₂ = +13.55 N (tại 1P) → +180.4 kN (tại 100P)!\n'
            '• Bất đối xứng Mềm hóa vs Cứng hóa: Lực +P hướng lên làm 2 thanh chéo bị NÉN và dẹt dần → kết cấu MỀM đi (u₂ᵧ tăng +0.072% tại 1P, +27.8% tại 250P) và bật nhảy Snap-Through tại P_lim = 78.45 MN! Ngược lại nếu đảo chiều −P hướng xuống, 2 thanh chéo chịu KÉO → kết cấu CỨNG lên!\n'
            '• Bất đối xứng phản lực gối: Vì gối con lăn Nút 4 trượt sang phải (u₄ₓ > 0), nhịp giữa 2 gối mở rộng thành 2L + u₄ₓ làm |R₁ᵧ| = 104.020 kN > |R₄ᵧ| = 103.980 kN!',
            style: bodyStyle(),
          ),
        ),

        // MỤC 4: MÃ LÕI PYTHON CALFEM
        cardWrapper(
          '4. Trích đoạn Mã Lõi Python CALFEM (python_core/calfem_elements.py)',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cấu trúc mô-đun rõ ràng, giữ nguyên quy ước hàm CALFEM 3.4 và chú thích tiếng Việt đầy đủ:',
                style: bodyStyle(),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: codeBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: SelectableText(
                  '''def bar2g(ex, ey, ep, N):
    """Ma trận độ cứng thanh dàn 2D phi tuyến hình học chuẩn CALFEM 3.4"""
    E, A = float(ep[0]), float(ep[1])
    dx, dy = ex[1] - ex[0], ey[1] - ey[0]
    L = np.hypot(dx, dy)
    c, s = dx / L, dy / L
    G = np.array([[ c, s, 0, 0], [-s, c, 0, 0],
                  [ 0, 0, c, s], [ 0, 0,-s, c]])
    Kle = (E*A/L)*np.array([[1,0,-1,0],[0,0,0,0],[-1,0,1,0],[0,0,0,0]]) \\
        + (N/L)  *np.array([[0,0,0,0],[0,1,0,-1],[0,0,0,0],[0,-1,0,1]])
    return G.T @ Kle @ G

def bar2g_corotational(ex0, ey0, ep, ed):
    """Đồng chuyển động Corotational UL – khử mất chữ số bằng a-b=(a²-b²)/(a+b)"""
    dx0, dy0 = ex0[1] - ex0[0], ey0[1] - ey0[0]
    L0 = np.hypot(dx0, dy0)
    dux, duy = ed[2] - ed[0], ed[3] - ed[1]
    dxc, dyc = dx0 + dux, dy0 + duy
    l_cur = np.hypot(dxc, dyc)
    dl = (dux*(2*dx0 + dux) + duy*(2*dy0 + duy)) / (l_cur + L0)
    N = ep[0] * ep[1] * (dl / L0)
    n = np.array([dxc / l_cur, dyc / l_cur])
    f_int = N * np.array([-n[0], -n[1], n[0], n[1]])
    k2 = (ep[0]*ep[1]/L0)*np.outer(n, n) + (N/l_cur)*(np.eye(2) - np.outer(n, n))
    Kt = np.block([[k2, -k2], [-k2, k2]])
    return f_int, Kt, N''',
                  style: TextStyle(
                    fontFamily: 'DejaVuSansMono',
                    fontSize: 9.8,
                    height: 1.4,
                    color: darkMode ? const Color(0xFFA5F3FC) : const Color(0xFF0F3D6E),
                  ),
                ),
              ),
            ],
          ),
        ),
        // MỤC 5: THÔNG TIN NHÓM THỰC HIỆN & LIÊN HỆ
        cardWrapper(
          '5. Thông tin Nhóm thực hiện & Liên hệ',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• Trường Đại học Bách Khoa – ĐHQG TP. Hồ Chí Minh (Khoa Kỹ thuật Xây dựng)\n'
                '• Giảng viên hướng dẫn: PGS. TS Ngô Hữu Cường\n'
                '• Học viên thực hiện: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)',
                style: bodyStyle(),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: formulaBg,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.45)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.email_outlined, size: 15, color: Color(0xFF10B981)),
                    SizedBox(width: 7),
                    Expanded(
                      child: SelectableText(
                        'Liên hệ: vothanhvang@gmail.com',
                        style: TextStyle(fontSize: 11.2, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Widget vẽ dấu căn bậc hai ĐẦY ĐỦ chuẩn sách giáo khoa (có thanh ngang
/// vinculum phủ trọn 100% chiều rộng biểu thức bên trong dấu căn).
class _MathSqrt extends StatelessWidget {
  final Widget child;
  final Color color;
  const _MathSqrt({required this.child, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RadicalPainter(color: color),
      child: Padding(
        padding: const EdgeInsets.only(left: 14, top: 4, right: 4, bottom: 1),
        child: child,
      ),
    );
  }
}

class _RadicalPainter extends CustomPainter {
  final Color color;
  const _RadicalPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.45
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final topY = 1.5;
    final botY = size.height - 1.5;
    final midY = size.height * 0.56;

    final path = Path()
      ..moveTo(0.8, midY + 1.0) // móc ngang ngắn bên trái
      ..lineTo(3.2, midY - 0.5)
      ..lineTo(6.4, botY) // đi xuống đáy dấu căn
      ..lineTo(11.5, topY) // kéo chéo lên đỉnh
      ..lineTo(size.width - 1.2, topY) // thanh gạch ngang phủ trọn biểu thức (vinculum)
      ..lineTo(size.width - 1.2, topY + 2.6); // móc xuống nhỏ cuối thanh căn chuẩn SGK
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RadicalPainter oldDelegate) => oldDelegate.color != color;
}

/// Widget phân số xếp tầng chuẩn Toán học (tử số / gạch phân số / mẫu số)
class _MathFrac extends StatelessWidget {
  final Widget numerator;
  final Widget denominator;
  final Color color;

  const _MathFrac({
    required this.numerator,
    required this.denominator,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: numerator,
          ),
          Container(
            height: 1.3,
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            color: color,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: denominator,
          ),
        ],
      ),
    );
  }
}
