// ============================================================================
// BẢNG MÀU CẦU VỒNG CHUẨN ANSYS MECHANICAL & THANG ĐO CHÚ GIẢI (COLORBAR)
// ============================================================================

import 'package:flutter/material.dart';

/// Chuyển giá trị chuẩn hóa t ∈ [0, 1] sang bảng màu cầu vồng chuẩn ANSYS
/// (Xanh lam đậm → Lục lam → Xanh lá → Vàng → Đỏ rực)
Color ansysRainbowColor(double t) {
  final v = t.clamp(0.0, 1.0);
  const stops = [
    Color(0xFF0026FF), // 0.00 - Nén mạnh / Cực tiểu
    Color(0xFF00B4FF), // 0.25 - Xanh dương sáng
    Color(0xFF00E676), // 0.50 - Xanh lá (trung tính)
    Color(0xFFFFEA00), // 0.75 - Vàng
    Color(0xFFFF1744), // 1.00 - Kéo mạnh / Cực đại
  ];
  final scaled = v * (stops.length - 1);
  final idx = scaled.floor().clamp(0, stops.length - 2);
  final frac = scaled - idx;
  return Color.lerp(stops[idx], stops[idx + 1], frac)!;
}

/// Thang màu đứng kiểu ANSYS nổi bên trái/phải màn hình mô phỏng
class AnsysColorBar extends StatelessWidget {
  final String title;
  final String unit;
  final double minVal;
  final double maxVal;
  final bool darkMode;

  const AnsysColorBar({
    super.key,
    required this.title,
    required this.unit,
    required this.minVal,
    required this.maxVal,
    this.darkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final bg = darkMode
        ? const Color(0xCC0F172A)
        : const Color(0xE6FFFFFF);
    final border = darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    final span = (maxVal - minVal).abs() < 1e-12 ? 1.0 : (maxVal - minVal);
    final ticks = List.generate(5, (i) => maxVal - span * i / 4.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: const Color(0xFF38BDF8),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Đơn vị: $unit',
            style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 9.5),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 156,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: border),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFFF1744),
                        Color(0xFFFFEA00),
                        Color(0xFF00E676),
                        Color(0xFF00B4FF),
                        Color(0xFF0026FF),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final v in ticks)
                      Text(
                        v.abs() >= 1000
                            ? v.toStringAsFixed(0)
                            : (v.abs() >= 10 ? v.toStringAsFixed(2) : v.toStringAsFixed(3)),
                        style: TextStyle(
                          color: textColor,
                          fontFamily: 'DejaVuSansMono',
                          fontSize: 9.5,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
