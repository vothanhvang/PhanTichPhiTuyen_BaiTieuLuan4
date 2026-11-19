// ============================================================================
// BẢNG TRA CỨU LÝ THUYẾT, CÔNG THỨC CẤP 3 & MÃ NGUỒN PYTHON / DART
// ============================================================================
// Giúp thầy hướng dẫn và các bạn trong lớp xem ngay công thức, dẫn nguồn số
// trang tài liệu và đoạn mã lõi có chú thích tiếng Việt ngay trong phần mềm!
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

    Widget sectionCard(String title, String body, {String? code}) {
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
            Text(
              body,
              style: TextStyle(
                fontSize: 11,
                height: 1.48,
                color: darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
              ),
            ),
            if (code != null) ...[
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
                  code,
                  style: TextStyle(
                    fontFamily: 'DejaVuSansMono',
                    fontSize: 9.8,
                    height: 1.4,
                    color: darkMode ? const Color(0xFFA5F3FC) : const Color(0xFF0F3D6E),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        sectionCard(
          '1. Tóm tắt Kiến thức Toán Phổ thông Cấp 3 dùng trong Bài toán',
          '• Định lý Py-ta-go (Lớp 7): Chiều dài thực thanh biến dạng l = √[(Δx₀ + Δuₓ)² + (Δy₀ + Δuᵧ)²].\n'
          '• Hằng đẳng thức hiệu hai bình phương (Lớp 8): l − L₀ = (l² − L₀²)/(l + L₀) giúp khử sai số làm tròn máy tính!\n'
          '• Khai triển nhị thức Newton (Lớp 11): √(1 + d) ≈ 1 + d/2 → suy ra biến dạng hữu hạn Green-Lagrange.\n'
          '• Phương pháp tiếp tuyến Newton-Raphson (Lớp 11-12): u_mới = u_cũ + R(u_cũ) / K_t(u_cũ) để giải hệ phi tuyến.\n'
          '• Quy tắc đòn bẩy / Mô-men lực (Vật lý 10): R₄ᵧ·(2L + u₄ₓ) = −P·(L + u₂ₓ) giải thích vì sao R₁ᵧ ≠ R₄ᵧ!',
        ),
        sectionCard(
          '2. Ba cấp độ Phân tích Phi tuyến Hình học (Dẫn nguồn Giáo trình)',
          '• Cấp 1 – Tuyến tính Bậc 1 (CALFEM bar2e – calfem34.pdf tr. 5.3-2 / PDF tr. 60): cân bằng trên hình dạng chưa biến dạng.\n'
          '• Cấp 2 – Bậc 2 CALFEM gốc (bar2g – Dahlblom 2016 PT 9.35–9.38 tr. 259 / PDF tr. 273): cộng ma trận độ cứng hình học ngang (N/L)·K_eσ, lặp cập nhật lực dọc N.\n'
          '• Cấp 3a – Đồng chuyển động Corotational UL (Jeffers 2026 Mục 8.3 tr. 186; Yang 2025 Chương 4 tr. 119): đánh giá bar2g tại tọa độ biến dạng hiện tại x = X + u với biến dạng kỹ thuật ε = (l − L₀)/L₀.\n'
          '• Cấp 3b – Total Lagrangian (Bài giảng NSA_4 Slides 6–12 / PDF tr. 2–3; McGuire 2000 PT 9.1–9.9 tr. 243–245): dùng biến dạng Green-Lagrange ε_GL = (l² − L₀²)/(2L₀²) và [k_g] = (F_x2/L₀)·[[I, -I], [-I, I]].',
        ),
        sectionCard(
          '3. Bản chất Vật lý Đáng chú ý của Hệ Dàn 5 thanh Đề bài',
          '• Thanh 1–2 "hồi sinh": Trong tuyến tính N₁₂ = 0 (thanh không lực), nhưng trong phi tuyến hình học khi Nút 2 dịch chuyển lên trên, theo định lý Py-ta-go thanh 1–2 bị kéo giãn và phát sinh lực kéo N₁₂ = +13.55 N (tại 1P) → +180.4 kN (tại 100P)!\n'
          '• Bất đối xứng Mềm hóa vs Cứng hóa: Lực +P hướng lên làm 2 thanh chéo bị NÉN và dẹt dần → kết cấu MỀM đi (u₂ᵧ tăng +0.072% tại 1P, +27.8% tại 250P) và bật nhảy Snap-Through tại P_lim = 78.45 MN! Ngược lại nếu đảo chiều −P hướng xuống, 2 thanh chéo chịu KÉO → kết cấu CỨNG lên!\n'
          '• Bất đối xứng phản lực gối: Vì gối con lăn Nút 4 trượt sang phải (u₄ₓ > 0), nhịp giữa 2 gối mở rộng thành 2L + u₄ₓ làm |R₁ᵧ| = 104.020 kN > |R₄ᵧ| = 103.980 kN!',
        ),
        sectionCard(
          '4. Trích đoạn Mã Lõi Python CALFEM (`python_core/calfem_elements.py`)',
          'Cấu trúc mô-đun rõ ràng, giữ nguyên quy ước hàm CALFEM 3.4 và chú thích tiếng Việt đầy đủ:',
          code: '''def bar2g(ex, ey, ep, N):
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
        ),
      ],
    );
  }
}
