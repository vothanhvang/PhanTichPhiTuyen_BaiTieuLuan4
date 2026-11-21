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

/// Thang màu đứng chú giải trường kết quả nổi bên góc màn hình mô phỏng
class AnsysColorBar extends StatelessWidget {
  final String title;
  final String unit;
  final double minVal;
  final double maxVal;
  final bool darkMode;
  final VoidCallback? onHide;

  const AnsysColorBar({
    super.key,
    required this.title,
    required this.unit,
    required this.minVal,
    required this.maxVal,
    this.darkMode = true,
    this.onHide,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (onHide != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Ẩn thang màu để nhìn thoáng mô hình 2D/3D',
                  child: InkWell(
                    onTap: onHide,
                    borderRadius: BorderRadius.circular(5),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.visibility_off_outlined,
                        size: 14,
                        color: textColor.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ),
              ],
            ],
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

/// Nút siêu gọn ở góc trên trái để mở lại bảng thang màu khi đang ẩn
class ColorBarRestoreButton extends StatelessWidget {
  final bool darkMode;
  final VoidCallback onShow;

  const ColorBarRestoreButton({
    super.key,
    required this.darkMode,
    required this.onShow,
  });

  @override
  Widget build(BuildContext context) {
    final bg = darkMode ? const Color(0xB30F172A) : const Color(0xD9FFFFFF);
    final border = darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    return Tooltip(
      message: 'Hiện bảng thang màu chú giải',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onShow,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFFF1744),
                        Color(0xFFFFEA00),
                        Color(0xFF00E676),
                        Color(0xFF0026FF),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  Icons.visibility_outlined,
                  size: 14,
                  color: darkMode ? const Color(0xFF38BDF8) : const Color(0xFF0F3D6E),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
