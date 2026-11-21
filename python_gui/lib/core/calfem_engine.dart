// ============================================================================
// LÕI TÍNH TOÁN CALFEM PHI TUYẾN HÌNH HỌC (BẢN DART SONG SONG 100% VỚI PYTHON)
// ============================================================================
// Mục đích:
//   1. Cung cấp đầy đủ các hàm phần tử chuẩn CALFEM 3.4 (bar2e, bar2g, bar2s)
//      và mở rộng phi tuyến hình học chuyển vị lớn (Corotational UL, Total
//      Lagrangian Green-Lagrange theo Bài giảng NSA_4 & McGuire Ch. 9).
//   2. Cài đặt đủ 6 thuật toán giải phi tuyến trong Bài giảng NSA_6:
//      Linear, CALFEM bar2g bậc 2, Full Newton-Raphson, Modified NR, Euler,
//      Runge-Kutta bậc 2 (RK2) và Điều khiển chuyển vị (Displacement Control)
//      để truy vết toàn bộ đường cong bật nhảy Snap-Through!
//   3. Cho phép ứng dụng chạy OFFLINE siêu mượt 120Hz trên Android (Xiaomi Pad
//      8 Pro & Xiaomi 13T Pro) và chạy trực tiếp trên trình duyệt GitHub Pages,
//      đồng thời khớp tuyệt đối với lõi Python trên Windows!
// ============================================================================

import 'dart:math' as math;

/// Kiểu mặt cắt ngang 3D của thanh dàn / khung (đủ 12 tiết diện frame tiêu chuẩn)
enum SectionShape {
  iSection('Thép chữ I / H (I / H-Beam)', 'I_SECTION'),
  boxSection('Thép hộp rỗng (RHS / SHS)', 'BOX_SECTION'),
  circTube('Ống thép tròn rỗng (CHS)', 'CIRC_TUBE'),
  solidRect('Chữ nhật / Vuông đặc (B×H)', 'SOLID_RECT'),
  solidRod('Thanh tròn đặc (Circular Rod)', 'SOLID_ROD'),
  channelC('Thép chữ C / U (Channel)', 'CHANNEL_C'),
  angleL('Thép góc chữ L (Angle)', 'ANGLE_L'),
  doubleAngle('Thép góc đôi 2L (Double Angle)', 'DOUBLE_ANGLE'),
  doubleChannel('Thép chữ C đôi 2C (Double Channel)', 'DOUBLE_CHANNEL'),
  teeSection('Thép chữ T (Structural Tee)', 'TEE_SECTION'),
  zeeSection('Thép chữ Z / Xà gồ Z (Z-Section)', 'ZEE_SECTION'),
  cruciform('Thép chữ thập (+) (Cruciform)', 'CRUCIFORM');

  final String label;
  final String code;
  const SectionShape(this.label, this.code);
}

/// Phương pháp phân tích / thuật toán giải phi tuyến
enum SolverMethod {
  corotationalNR('Phi tuyến CALFEM-UL (Full NR)', 'corotational_nr'),
  bar2gSecondOrder('CALFEM bar2g (Bậc 2 gốc – Dahlblom)', 'bar2g'),
  totalLagrangian('Total Lagrangian (Green-Lagrange – NSA_4)', 'total_lagrangian'),
  modifiedNR('Modified Newton-Raphson (NSA_6 6.3.4)', 'modified_nr'),
  rk2Midpoint('Runge-Kutta bậc 2 RK2 (NSA_6 6.2)', 'rk2'),
  eulerSingleStep('Euler bước đơn (NSA_6 6.2)', 'euler'),
  linearFirstOrder('Đàn hồi Tuyến tính Bậc 1 (bar2e)', 'linear');

  final String label;
  final String code;
  const SolverMethod(this.label, this.code);
}

/// Bài toán mẫu có sẵn (Đề bài chính + Các bài toán kiểm chứng sách gốc)
enum TrussPreset {
  assignment5Bar('Đề bài chính: Dàn 4 nút – 5 thanh (1.jpg)', 'assignment_5bar'),
  dahlblomEx91('Benchmark: Dahlblom Example 9.1 (bar2g)', 'dahlblom_ex9_1'),
  calfemExs3('Benchmark: CALFEM 3.4 exs3.m', 'calfem_exs3'),
  vonMisesArch('Minh họa bật nhảy: Vòm 2 thanh Von Mises', 'von_mises');

  final String label;
  final String code;
  const TrussPreset(this.label, this.code);
}

/// Các loại liên kết gối tựa tại từng nút của hệ dàn phẳng 2D/3D
enum NodeSupportType {
  free('Tự do (Không liên kết)', 'Tự do', 'FREE'),
  pin('Gối cố định — Khớp bản lề (Khóa X, Y)', 'Gối cố định', 'PIN'),
  rollerX('Gối di động ngang — Con lăn X (Khóa Y)', 'Con lăn X', 'ROLLER_X'),
  rollerY('Gối di động đứng — Con lăn Y (Khóa X)', 'Con lăn Y', 'ROLLER_Y'),
  springY('Gối đàn hồi đứng — Lò xo kᵧ', 'Lò xo kᵧ', 'SPRING_Y'),
  springX('Gối đàn hồi ngang — Lò xo kₓ', 'Lò xo kₓ', 'SPRING_X'),
  springXY('Gối đàn hồi 2 phương — Lò xo kₓ, kᵧ', 'Lò xo XY', 'SPRING_XY'),
  rollerXSpringX('Gối trượt ngang + Lò xo kháng X (Khóa Y, kₓ)', 'Con lăn X + kₓ', 'ROLLER_X_SPRING_X');

  final String label;
  final String shortLabel;
  final String code;
  const NodeSupportType(this.label, this.shortLabel, this.code);

  bool get locksX => this == pin || this == rollerY;
  bool get locksY => this == pin || this == rollerX || this == rollerXSpringX;
  bool get hasSpringX => this == springX || this == springXY || this == rollerXSpringX;
  bool get hasSpringY => this == springY || this == springXY;
  bool get hasSpring => hasSpringX || hasSpringY;
  int get restraintCount => (locksX || hasSpringX ? 1 : 0) + (locksY || hasSpringY ? 1 : 0);
}

/// Hướng bố trí hình học của liên kết gối tựa tại nút (Sơ đồ tính & Chi tiết chế tạo 2D/3D)
enum SupportDirection {
  auto('Tự động', 'Auto', 'AUTO'),
  bottom('Dưới (↓)', '↓', 'BOTTOM'),
  top('Trên (↑)', '↑', 'TOP'),
  left('Trái (←)', '←', 'LEFT'),
  right('Phải (→)', '→', 'RIGHT');

  final String label;
  final String shortIcon;
  final String code;
  const SupportDirection(this.label, this.shortIcon, this.code);
}

/// Chế độ hiển thị liên kết nút: Sơ đồ tính cơ học ↔ Chi tiết gia công chế tạo
enum ConnectionDisplayMode {
  schematic('Sơ đồ tính', 'SCHEMATIC'),
  fabrication('Chi tiết chế tạo', 'FABRICATION');

  final String label;
  final String code;
  const ConnectionDisplayMode(this.label, this.code);
}

/// Kiểu cấu tạo liên kết gia công chế tạo đầu thanh dàn tại nút thép
enum ConnectionDetailType {
  boltedGusset('Bản mã + Bu-lông M20-8.8', 'Bu-lông M20', 'BOLTED_GUSSET'),
  weldedGusset('Bản mã + Đường hàn góc hf=8', 'Hàn góc hf=8', 'WELDED_GUSSET'),
  pinnedClevis('Tai chốt bản lề cơ khí Ø60', 'Chốt Ø60', 'PINNED_CLEVIS');

  final String label;
  final String shortLabel;
  final String code;
  const ConnectionDetailType(this.label, this.shortLabel, this.code);
}

/// Trường kết quả hiển thị bản đồ màu kiểu ANSYS
enum ContourField {
  axialStress('Ứng suất pháp σ (MPa)', 'MPa', 'σ'),
  axialStrain('Biến dạng dọc ε (με)', 'με', 'ε'),
  axialForce('Lực dọc trục N (kN)', 'kN', 'N'),
  displacement('Chuyển vị tổng ||u|| (mm)', 'mm', '||u||'),
  strainEnergyDensity('Mật độ năng lượng u₀ (kJ/m³)', 'kJ/m³', 'u₀');

  final String label;
  final String unit;
  final String symbol;
  const ContourField(this.label, this.unit, this.symbol);

  String formatValue(double v) {
    switch (this) {
      case ContourField.axialStress:
        return '${v.toStringAsFixed(2)} $unit';
      case ContourField.axialStrain:
        return '${v.toStringAsFixed(2)} $unit';
      case ContourField.axialForce:
        return '${v.abs() < 1.0 ? v.toStringAsFixed(4) : v.toStringAsFixed(2)} $unit';
      case ContourField.displacement:
        return '${v.toStringAsFixed(4)} $unit';
      case ContourField.strainEnergyDensity:
        return '${v.toStringAsFixed(3)} $unit';
    }
  }
}

/// Hình chữ nhật con trong hệ tọa độ tâm khung bao tiết diện (x: ngang, y: đứng, mm)
class _RectPart {
  final double x0, x1, y0, y1;
  const _RectPart(this.x0, this.x1, this.y0, this.y1);

  bool contains(double x, double y) => x >= x0 && x <= x1 && y >= y0 && y <= y1;
}

class _InertiaResult {
  final double area;
  final double ix;
  final double iy;
  final double iMajor;
  final double iMinor;
  const _InertiaResult(this.area, this.ix, this.iy, this.iMajor, this.iMinor);

  static _InertiaResult fromRects(List<_RectPart> rects) {
    double sumA = 0.0, sumAx = 0.0, sumAy = 0.0;
    for (final r in rects) {
      final w = math.max(0.0, r.x1 - r.x0);
      final h = math.max(0.0, r.y1 - r.y0);
      final a = w * h;
      sumA += a;
      sumAx += a * 0.5 * (r.x0 + r.x1);
      sumAy += a * 0.5 * (r.y0 + r.y1);
    }
    if (sumA <= 1e-9) {
      return const _InertiaResult(1.0, 1.0, 1.0, 1.0, 1.0);
    }
    final xc = sumAx / sumA;
    final yc = sumAy / sumA;
    double ix = 0.0, iy = 0.0, ixy = 0.0;
    for (final r in rects) {
      final w = math.max(0.0, r.x1 - r.x0);
      final h = math.max(0.0, r.y1 - r.y0);
      final a = w * h;
      final dx = 0.5 * (r.x0 + r.x1) - xc;
      final dy = 0.5 * (r.y0 + r.y1) - yc;
      ix += w * h * h * h / 12.0 + a * dy * dy;
      iy += h * w * w * w / 12.0 + a * dx * dx;
      ixy += a * dx * dy;
    }
    final avg = 0.5 * (ix + iy);
    final rad = math.sqrt(math.pow(0.5 * (ix - iy), 2) + ixy * ixy);
    final i1 = math.max(1e-6, avg + rad);
    final i2 = math.max(1e-6, avg - rad);
    return _InertiaResult(sumA, math.max(1e-6, ix), math.max(1e-6, iy), i1, i2);
  }
}

/// Thông số hình học mặt cắt ngang 3D do người dùng nhập trực tiếp từ giao diện (mm)
class CustomSectionGeometry {
  final double heightMm; // Chiều cao H hoặc Đường kính ngoài D (ống / tròn đặc)
  final double widthMm;  // Bề rộng B (hoặc bề rộng 1 cánh B₁ cho 2L / 2C / Z)
  final double tfMm;     // Chiều dày cánh t_f hoặc chiều dày thành t
  final double twMm;     // Chiều dày bụng t_w
  final double gapMm;    // Khe hở bản mã s cho tiết diện ghép đôi (2L, 2C)

  const CustomSectionGeometry({
    required this.heightMm,
    required this.widthMm,
    required this.tfMm,
    required this.twMm,
    this.gapMm = 10.0,
  });

  CustomSectionGeometry copyWith({
    double? heightMm,
    double? widthMm,
    double? tfMm,
    double? twMm,
    double? gapMm,
  }) {
    return CustomSectionGeometry(
      heightMm: heightMm ?? this.heightMm,
      widthMm: widthMm ?? this.widthMm,
      tfMm: tfMm ?? this.tfMm,
      twMm: twMm ?? this.twMm,
      gapMm: gapMm ?? this.gapMm,
    );
  }

  /// Quy đổi kích thước khởi đầu tương ứng với diện tích A hiện tại
  static CustomSectionGeometry fromArea(SectionShape shape, double areaMm2) {
    final d = SectionDimensions.fromArea(shape, areaMm2);
    return CustomSectionGeometry(
      heightMm: double.parse(d.height.toStringAsFixed(1)),
      widthMm: double.parse((d.legWidth > 0 ? d.legWidth : d.width).toStringAsFixed(1)),
      tfMm: double.parse((d.tf > 0 ? d.tf : 6.0).toStringAsFixed(1)),
      twMm: double.parse((d.tw > 0 ? d.tw : (d.tf > 0 ? d.tf : 6.0)).toStringAsFixed(1)),
      gapMm: double.parse((d.gap > 0 ? d.gap : 10.0).toStringAsFixed(1)),
    );
  }

  /// Nhân đồng dạng kích thước theo hệ số scale (dùng khi thay đổi diện tích cơ sở A)
  CustomSectionGeometry scaled(double factor) {
    final f = factor.clamp(0.1, 10.0);
    return CustomSectionGeometry(
      heightMm: double.parse((heightMm * f).clamp(10.0, 2000.0).toStringAsFixed(1)),
      widthMm: double.parse((widthMm * f).clamp(10.0, 2000.0).toStringAsFixed(1)),
      tfMm: double.parse((tfMm * f).clamp(1.0, 400.0).toStringAsFixed(1)),
      twMm: double.parse((twMm * f).clamp(1.0, 400.0).toStringAsFixed(1)),
      gapMm: double.parse((gapMm * f).clamp(0.0, 200.0).toStringAsFixed(1)),
    );
  }

  /// Tính đầy đủ đặc trưng hình học mặt cắt (A, Ix, Iy, I1, I2) từ kích thước vừa nhập
  SectionDimensions toDimensions(SectionShape shape, {double scale = 1.0}) {
    final s = scale.clamp(0.1, 10.0);
    final h = (heightMm * s).clamp(8.0, 3000.0);
    final b = (widthMm * s).clamp(8.0, 3000.0);
    switch (shape) {
      case SectionShape.solidRod:
        final r = 0.5 * h;
        final area = math.pi * r * r;
        final inertia = 0.25 * math.pi * math.pow(r, 4).toDouble();
        return SectionDimensions(
          height: h,
          width: h,
          legWidth: h,
          radiusOut: r,
          radiusIn: 0.0,
          areaMm2: area,
          ix: inertia,
          iy: inertia,
          iMajor: inertia,
          iMinor: inertia,
        );
      case SectionShape.circTube:
        final r = 0.5 * h;
        final t = (tfMm * s).clamp(0.8, r * 0.92);
        final rin = math.max(0.0, r - t);
        final area = math.pi * (r * r - rin * rin);
        final inertia = 0.25 * math.pi * (math.pow(r, 4) - math.pow(rin, 4)).toDouble();
        return SectionDimensions(
          height: h,
          width: h,
          legWidth: h,
          tf: t,
          tw: t,
          radiusOut: r,
          radiusIn: rin,
          areaMm2: area,
          ix: inertia,
          iy: inertia,
          iMajor: inertia,
          iMinor: inertia,
        );
      case SectionShape.solidRect:
        final area = b * h;
        final ix = b * math.pow(h, 3).toDouble() / 12.0;
        final iy = h * math.pow(b, 3).toDouble() / 12.0;
        return SectionDimensions(
          height: h,
          width: b,
          legWidth: b,
          areaMm2: area,
          ix: ix,
          iy: iy,
          iMajor: math.max(ix, iy),
          iMinor: math.min(ix, iy),
        );
      case SectionShape.boxSection:
        final t = (tfMm * s).clamp(0.8, 0.46 * math.min(h, b));
        final props = _InertiaResult.fromRects(
          SectionDimensions._buildRectParts(shape, h, b, b, t, t, 0.0),
        );
        return SectionDimensions(
          height: h,
          width: b,
          legWidth: b,
          tf: t,
          tw: t,
          areaMm2: props.area,
          ix: props.ix,
          iy: props.iy,
          iMajor: props.iMajor,
          iMinor: props.iMinor,
        );
      case SectionShape.iSection:
        final tf = (tfMm * s).clamp(0.8, 0.44 * h);
        final tw = (twMm * s).clamp(0.8, 0.90 * b);
        final props = _InertiaResult.fromRects(
          SectionDimensions._buildRectParts(shape, h, b, b, tf, tw, 0.0),
        );
        return SectionDimensions(
          height: h,
          width: b,
          legWidth: b,
          tf: tf,
          tw: tw,
          areaMm2: props.area,
          ix: props.ix,
          iy: props.iy,
          iMajor: props.iMajor,
          iMinor: props.iMinor,
        );
      case SectionShape.channelC:
        final tf = (tfMm * s).clamp(0.8, 0.44 * h);
        final tw = (twMm * s).clamp(0.8, 0.85 * b);
        final props = _InertiaResult.fromRects(
          SectionDimensions._buildRectParts(shape, h, b, b, tf, tw, 0.0),
        );
        return SectionDimensions(
          height: h,
          width: b,
          legWidth: b,
          tf: tf,
          tw: tw,
          areaMm2: props.area,
          ix: props.ix,
          iy: props.iy,
          iMajor: props.iMajor,
          iMinor: props.iMinor,
        );
      case SectionShape.angleL:
        final t = (tfMm * s).clamp(0.8, 0.48 * math.min(h, b));
        final props = _InertiaResult.fromRects(
          SectionDimensions._buildRectParts(shape, h, b, b, t, t, 0.0),
        );
        return SectionDimensions(
          height: h,
          width: b,
          legWidth: b,
          tf: t,
          tw: t,
          areaMm2: props.area,
          ix: props.ix,
          iy: props.iy,
          iMajor: props.iMajor,
          iMinor: props.iMinor,
        );
      case SectionShape.doubleAngle:
        final t = (tfMm * s).clamp(0.8, 0.46 * math.min(h, b));
        final gap = (gapMm * s).clamp(0.0, 2.0 * b);
        final wTot = 2.0 * b + gap;
        final props = _InertiaResult.fromRects(
          SectionDimensions._buildRectParts(shape, h, wTot, b, t, t, gap),
        );
        return SectionDimensions(
          height: h,
          width: wTot,
          legWidth: b,
          tf: t,
          tw: t,
          gap: gap,
          areaMm2: props.area,
          ix: props.ix,
          iy: props.iy,
          iMajor: props.iMajor,
          iMinor: props.iMinor,
        );
      case SectionShape.doubleChannel:
        final tf = (tfMm * s).clamp(0.8, 0.44 * h);
        final tw = (twMm * s).clamp(0.8, 0.80 * b);
        final gap = (gapMm * s).clamp(0.0, 2.0 * b);
        final wTot = 2.0 * b + gap;
        final props = _InertiaResult.fromRects(
          SectionDimensions._buildRectParts(shape, h, wTot, b, tf, tw, gap),
        );
        return SectionDimensions(
          height: h,
          width: wTot,
          legWidth: b,
          tf: tf,
          tw: tw,
          gap: gap,
          areaMm2: props.area,
          ix: props.ix,
          iy: props.iy,
          iMajor: props.iMajor,
          iMinor: props.iMinor,
        );
      case SectionShape.teeSection:
        final tf = (tfMm * s).clamp(0.8, 0.80 * h);
        final tw = (twMm * s).clamp(0.8, 0.90 * b);
        final props = _InertiaResult.fromRects(
          SectionDimensions._buildRectParts(shape, h, b, b, tf, tw, 0.0),
        );
        return SectionDimensions(
          height: h,
          width: b,
          legWidth: b,
          tf: tf,
          tw: tw,
          areaMm2: props.area,
          ix: props.ix,
          iy: props.iy,
          iMajor: props.iMajor,
          iMinor: props.iMinor,
        );
      case SectionShape.zeeSection:
        final t = (tfMm * s).clamp(0.8, 0.42 * math.min(h, b));
        final wTot = math.max(t + 2.0, 2.0 * b - t);
        final props = _InertiaResult.fromRects(
          SectionDimensions._buildRectParts(shape, h, wTot, b, t, t, 0.0),
        );
        return SectionDimensions(
          height: h,
          width: wTot,
          legWidth: b,
          tf: t,
          tw: t,
          areaMm2: props.area,
          ix: props.ix,
          iy: props.iy,
          iMajor: props.iMajor,
          iMinor: props.iMinor,
        );
      case SectionShape.cruciform:
        final tf = (tfMm * s).clamp(0.8, 0.85 * h);
        final tw = (twMm * s).clamp(0.8, 0.85 * b);
        final props = _InertiaResult.fromRects(
          SectionDimensions._buildRectParts(shape, h, b, b, tf, tw, 0.0),
        );
        return SectionDimensions(
          height: h,
          width: b,
          legWidth: b,
          tf: tf,
          tw: tw,
          areaMm2: props.area,
          ix: props.ix,
          iy: props.iy,
          iMajor: props.iMajor,
          iMinor: props.iMinor,
        );
    }
  }

  double computedAreaMm2(SectionShape shape) => toDimensions(shape).areaMm2;

  /// Danh sách thép hình / tiết diện khung tiêu chuẩn chọn nhanh theo từng loại mặt cắt
  static List<(String, CustomSectionGeometry)> presetsFor(SectionShape shape) {
    switch (shape) {
      case SectionShape.iSection:
        return const [
          ('I100', CustomSectionGeometry(heightMm: 100, widthMm: 55, tfMm: 7.2, twMm: 4.5)),
          ('H100', CustomSectionGeometry(heightMm: 100, widthMm: 100, tfMm: 8.0, twMm: 6.0)),
          ('I150', CustomSectionGeometry(heightMm: 150, widthMm: 75, tfMm: 9.0, twMm: 5.5)),
          ('H150', CustomSectionGeometry(heightMm: 150, widthMm: 150, tfMm: 10.0, twMm: 7.0)),
          ('I200', CustomSectionGeometry(heightMm: 200, widthMm: 100, tfMm: 11.0, twMm: 6.0)),
        ];
      case SectionShape.boxSection:
        return const [
          ('□80×5', CustomSectionGeometry(heightMm: 80, widthMm: 80, tfMm: 5.0, twMm: 5.0)),
          ('□100×6', CustomSectionGeometry(heightMm: 100, widthMm: 100, tfMm: 6.0, twMm: 6.0)),
          ('▭120×80×6', CustomSectionGeometry(heightMm: 120, widthMm: 80, tfMm: 6.0, twMm: 6.0)),
          ('□150×8', CustomSectionGeometry(heightMm: 150, widthMm: 150, tfMm: 8.0, twMm: 8.0)),
        ];
      case SectionShape.circTube:
        return const [
          ('Ø76×5', CustomSectionGeometry(heightMm: 76, widthMm: 76, tfMm: 5.0, twMm: 5.0)),
          ('Ø114×6', CustomSectionGeometry(heightMm: 114, widthMm: 114, tfMm: 6.0, twMm: 6.0)),
          ('Ø140×8', CustomSectionGeometry(heightMm: 140, widthMm: 140, tfMm: 8.0, twMm: 8.0)),
          ('Ø168×8', CustomSectionGeometry(heightMm: 168, widthMm: 168, tfMm: 8.0, twMm: 8.0)),
        ];
      case SectionShape.solidRect:
        return const [
          ('40×50', CustomSectionGeometry(heightMm: 50, widthMm: 40, tfMm: 10, twMm: 10)),
          ('50×80', CustomSectionGeometry(heightMm: 80, widthMm: 50, tfMm: 10, twMm: 10)),
          ('100×150', CustomSectionGeometry(heightMm: 150, widthMm: 100, tfMm: 10, twMm: 10)),
          ('200×300', CustomSectionGeometry(heightMm: 300, widthMm: 200, tfMm: 10, twMm: 10)),
        ];
      case SectionShape.solidRod:
        return const [
          ('Ø36', CustomSectionGeometry(heightMm: 36, widthMm: 36, tfMm: 18, twMm: 18)),
          ('Ø50', CustomSectionGeometry(heightMm: 50, widthMm: 50, tfMm: 25, twMm: 25)),
          ('Ø65', CustomSectionGeometry(heightMm: 65, widthMm: 65, tfMm: 32.5, twMm: 32.5)),
          ('Ø80', CustomSectionGeometry(heightMm: 80, widthMm: 80, tfMm: 40, twMm: 40)),
        ];
      case SectionShape.channelC:
        return const [
          ('C100', CustomSectionGeometry(heightMm: 100, widthMm: 50, tfMm: 7.5, twMm: 5.0)),
          ('C120', CustomSectionGeometry(heightMm: 120, widthMm: 55, tfMm: 8.0, twMm: 5.5)),
          ('C150', CustomSectionGeometry(heightMm: 150, widthMm: 75, tfMm: 10.0, twMm: 6.5)),
          ('C200', CustomSectionGeometry(heightMm: 200, widthMm: 80, tfMm: 11.0, twMm: 7.5)),
        ];
      case SectionShape.angleL:
        return const [
          ('L75×6', CustomSectionGeometry(heightMm: 75, widthMm: 75, tfMm: 6.0, twMm: 6.0)),
          ('L90×8', CustomSectionGeometry(heightMm: 90, widthMm: 90, tfMm: 8.0, twMm: 8.0)),
          ('L100×10', CustomSectionGeometry(heightMm: 100, widthMm: 100, tfMm: 10.0, twMm: 10.0)),
          ('L125×80×10', CustomSectionGeometry(heightMm: 125, widthMm: 80, tfMm: 10.0, twMm: 10.0)),
        ];
      case SectionShape.doubleAngle:
        return const [
          ('2L63×6', CustomSectionGeometry(heightMm: 63, widthMm: 63, tfMm: 6.0, twMm: 6.0, gapMm: 10)),
          ('2L75×8', CustomSectionGeometry(heightMm: 75, widthMm: 75, tfMm: 8.0, twMm: 8.0, gapMm: 10)),
          ('2L90×8', CustomSectionGeometry(heightMm: 90, widthMm: 90, tfMm: 8.0, twMm: 8.0, gapMm: 12)),
          ('2L100×10', CustomSectionGeometry(heightMm: 100, widthMm: 100, tfMm: 10.0, twMm: 10.0, gapMm: 12)),
        ];
      case SectionShape.doubleChannel:
        return const [
          ('2C100', CustomSectionGeometry(heightMm: 100, widthMm: 50, tfMm: 7.5, twMm: 5.0, gapMm: 10)),
          ('2C120', CustomSectionGeometry(heightMm: 120, widthMm: 55, tfMm: 8.0, twMm: 5.5, gapMm: 10)),
          ('2C150', CustomSectionGeometry(heightMm: 150, widthMm: 75, tfMm: 10.0, twMm: 6.5, gapMm: 12)),
          ('2C200', CustomSectionGeometry(heightMm: 200, widthMm: 80, tfMm: 11.0, twMm: 7.5, gapMm: 14)),
        ];
      case SectionShape.teeSection:
        return const [
          ('T100×100', CustomSectionGeometry(heightMm: 100, widthMm: 100, tfMm: 10.0, twMm: 8.0)),
          ('T120×120', CustomSectionGeometry(heightMm: 120, widthMm: 120, tfMm: 11.0, twMm: 8.0)),
          ('T150×150', CustomSectionGeometry(heightMm: 150, widthMm: 150, tfMm: 12.0, twMm: 9.0)),
          ('T200×150', CustomSectionGeometry(heightMm: 200, widthMm: 150, tfMm: 14.0, twMm: 10.0)),
        ];
      case SectionShape.zeeSection:
        return const [
          ('Z120×50×4', CustomSectionGeometry(heightMm: 120, widthMm: 50, tfMm: 4.0, twMm: 4.0)),
          ('Z150×60×5', CustomSectionGeometry(heightMm: 150, widthMm: 60, tfMm: 5.0, twMm: 5.0)),
          ('Z180×65×6', CustomSectionGeometry(heightMm: 180, widthMm: 65, tfMm: 6.0, twMm: 6.0)),
          ('Z200×75×6', CustomSectionGeometry(heightMm: 200, widthMm: 75, tfMm: 6.0, twMm: 6.0)),
        ];
      case SectionShape.cruciform:
        return const [
          ('+100×8', CustomSectionGeometry(heightMm: 100, widthMm: 100, tfMm: 8.0, twMm: 8.0)),
          ('+120×10', CustomSectionGeometry(heightMm: 120, widthMm: 120, tfMm: 10.0, twMm: 10.0)),
          ('+150×12', CustomSectionGeometry(heightMm: 150, widthMm: 150, tfMm: 12.0, twMm: 12.0)),
          ('+200×14', CustomSectionGeometry(heightMm: 200, widthMm: 200, tfMm: 14.0, twMm: 14.0)),
        ];
    }
  }
}

/// Kích thước hình học mặt cắt ngang 3D quy đổi từ diện tích A (mm²) hoặc nhập trực tiếp
class SectionDimensions {
  final double height;    // Chiều cao phủ bì H (mm)
  final double width;     // Bề rộng phủ bì W_tot (mm)
  final double legWidth;  // Bề rộng 1 cánh B (dùng cho 2L, 2C, Z; bằng width với tiết diện đơn)
  final double tf;        // Chiều dày cánh / thành (mm)
  final double tw;        // Chiều dày bụng (mm)
  final double gap;       // Khe hở bản mã s cho tiết diện ghép đôi 2L, 2C (mm)
  final double radiusOut;
  final double radiusIn;
  final double areaMm2;
  final double ix;        // Mô-men quán tính trục ngang x-x (mm⁴)
  final double iy;        // Mô-men quán tính trục đứng y-y (mm⁴)
  final double iMajor;    // Mô-men quán tính chính cực đại I_1 (mm⁴)
  final double iMinor;    // Mô-men quán tính chính cực tiểu I_2 (mm⁴)

  const SectionDimensions({
    required this.height,
    required this.width,
    double? legWidth,
    this.tf = 0,
    this.tw = 0,
    this.gap = 0,
    this.radiusOut = 0,
    this.radiusIn = 0,
    this.areaMm2 = 0,
    double? ix,
    double? iy,
    required this.iMajor,
    required this.iMinor,
  })  : legWidth = legWidth ?? width,
        ix = ix ?? iMajor,
        iy = iy ?? iMinor;

  double get rGyrationMin => areaMm2 > 1e-6 ? math.sqrt(iMinor / areaMm2) : 0.0;

  String formatSpec(SectionShape shape) {
    final hS = height.toStringAsFixed(1);
    final wS = width.toStringAsFixed(1);
    final bS = legWidth.toStringAsFixed(1);
    final tfS = tf.toStringAsFixed(1);
    final twS = tw.toStringAsFixed(1);
    final gS = gap.toStringAsFixed(1);
    switch (shape) {
      case SectionShape.iSection:
        return 'I $hS×$wS×tf=$tfS×tw=$twS mm';
      case SectionShape.boxSection:
        return 'Hộp $hS×$wS×t=$tfS mm';
      case SectionShape.circTube:
        return 'Ống Ø$hS×t=$tfS mm';
      case SectionShape.solidRect:
        return 'Chữ nhật $wS×$hS mm';
      case SectionShape.solidRod:
        return 'Tròn đặc Ø$hS mm';
      case SectionShape.channelC:
        return 'C $hS×$wS×tf=$tfS×tw=$twS mm';
      case SectionShape.angleL:
        return 'L $hS×$wS×t=$tfS mm';
      case SectionShape.doubleAngle:
        return '2L $hS×$bS×t=$tfS (s=$gS) mm';
      case SectionShape.doubleChannel:
        return '2C $hS×$bS×tf=$tfS×tw=$twS (s=$gS) mm';
      case SectionShape.teeSection:
        return 'T $hS×$wS×tf=$tfS×tw=$twS mm';
      case SectionShape.zeeSection:
        return 'Z $hS×$bS×t=$tfS mm';
      case SectionShape.cruciform:
        return '+ $hS×$wS×tf=$tfS×tw=$twS mm';
    }
  }

  /// Danh sách hình chữ nhật vật liệu của mặt cắt (tọa độ tâm khung bao, đơn vị mm)
  static List<_RectPart> _buildRectParts(
    SectionShape shape,
    double h,
    double wTot,
    double b1,
    double tf,
    double tw,
    double gap,
  ) {
    final hh = 0.5 * h;
    final hw = 0.5 * wTot;
    final hg = 0.5 * gap;
    switch (shape) {
      case SectionShape.solidRect:
        return [_RectPart(-hw, hw, -hh, hh)];
      case SectionShape.boxSection:
        return [
          _RectPart(-hw, hw, -hh, -hh + tf),
          _RectPart(-hw, hw, hh - tf, hh),
          _RectPart(-hw, -hw + tf, -hh + tf, hh - tf),
          _RectPart(hw - tf, hw, -hh + tf, hh - tf),
        ];
      case SectionShape.iSection:
        return [
          _RectPart(-hw, hw, -hh, -hh + tf),
          _RectPart(-hw, hw, hh - tf, hh),
          _RectPart(-0.5 * tw, 0.5 * tw, -hh + tf, hh - tf),
        ];
      case SectionShape.channelC:
        return [
          _RectPart(-hw, hw, -hh, -hh + tf),
          _RectPart(-hw, hw, hh - tf, hh),
          _RectPart(-hw, -hw + tw, -hh + tf, hh - tf),
        ];
      case SectionShape.angleL:
        return [
          _RectPart(-hw, hw, -hh, -hh + tf),
          _RectPart(-hw, -hw + tf, -hh + tf, hh),
        ];
      case SectionShape.doubleAngle:
        return [
          _RectPart(-hg - b1, -hg, -hh, -hh + tf),
          _RectPart(-hg - tf, -hg, -hh + tf, hh),
          _RectPart(hg, hg + b1, -hh, -hh + tf),
          _RectPart(hg, hg + tf, -hh + tf, hh),
        ];
      case SectionShape.doubleChannel:
        return [
          _RectPart(-hg - b1, -hg, -hh, -hh + tf),
          _RectPart(-hg - b1, -hg, hh - tf, hh),
          _RectPart(-hg - tw, -hg, -hh + tf, hh - tf),
          _RectPart(hg, hg + b1, -hh, -hh + tf),
          _RectPart(hg, hg + b1, hh - tf, hh),
          _RectPart(hg, hg + tw, -hh + tf, hh - tf),
        ];
      case SectionShape.teeSection:
        return [
          _RectPart(-hw, hw, hh - tf, hh),
          _RectPart(-0.5 * tw, 0.5 * tw, -hh, hh - tf),
        ];
      case SectionShape.zeeSection:
        return [
          _RectPart(-b1 + 0.5 * tf, 0.5 * tf, -hh, -hh + tf),
          _RectPart(-0.5 * tf, b1 - 0.5 * tf, hh - tf, hh),
          _RectPart(-0.5 * tf, 0.5 * tf, -hh + tf, hh - tf),
        ];
      case SectionShape.cruciform:
        return [
          _RectPart(-0.5 * tw, 0.5 * tw, -hh, hh),
          _RectPart(-hw, -0.5 * tw, -0.5 * tf, 0.5 * tf),
          _RectPart(0.5 * tw, hw, -0.5 * tf, 0.5 * tf),
        ];
      case SectionShape.solidRod:
      case SectionShape.circTube:
        return const [];
    }
  }

  /// Kiểm tra điểm vật liệu (xMm, yMm) trong mặt cắt ngang (dùng chung cho Phẫu thuật 2D)
  bool containsLocalPoint(SectionShape shape, double xMm, double yMm) {
    if (shape == SectionShape.solidRod) {
      final r = radiusOut > 0 ? radiusOut : 0.5 * height;
      return xMm * xMm + yMm * yMm <= r * r;
    }
    if (shape == SectionShape.circTube) {
      final r = radiusOut > 0 ? radiusOut : 0.5 * height;
      final r2 = xMm * xMm + yMm * yMm;
      return r2 >= radiusIn * radiusIn && r2 <= r * r;
    }
    final parts = _buildRectParts(shape, height, width, legWidth, tf, tw, gap);
    for (final p in parts) {
      if (p.contains(xMm, yMm)) return true;
    }
    return false;
  }

  /// Danh sách đa giác viền đóng [[xMm, yMm], ...] dùng cho dựng khối 3D & đường biên 2D
  /// Nếu `includeInnerHole == true`, trả thêm vòng lỗ rỗng bên trong cho thép hộp (phẫu thuật 2D).
  List<List<List<double>>> outlinePolygonsMm(SectionShape shape, {bool includeInnerHole = false}) {
    final hh = 0.5 * height;
    final hw = 0.5 * width;
    final hg = 0.5 * gap;
    final b1 = legWidth;
    switch (shape) {
      case SectionShape.solidRod:
      case SectionShape.circTube:
        const nSeg = 14;
        final r = radiusOut > 0 ? radiusOut : hh;
        final outer = [
          for (int k = 0; k < nSeg; k++)
            [r * math.cos(2 * math.pi * k / nSeg), r * math.sin(2 * math.pi * k / nSeg)],
        ];
        if (includeInnerHole && shape == SectionShape.circTube && radiusIn > 1e-3) {
          final inner = [
            for (int k = 0; k < nSeg; k++)
              [radiusIn * math.cos(2 * math.pi * k / nSeg), radiusIn * math.sin(2 * math.pi * k / nSeg)],
          ];
          return [outer, inner];
        }
        return [outer];
      case SectionShape.solidRect:
        return [
          [
            [-hw, -hh],
            [hw, -hh],
            [hw, hh],
            [-hw, hh],
          ],
        ];
      case SectionShape.boxSection:
        final outer = [
          [-hw, -hh],
          [hw, -hh],
          [hw, hh],
          [-hw, hh],
        ];
        if (includeInnerHole && tf > 0 && width > 2 * tf && height > 2 * tf) {
          final inner = [
            [-hw + tf, -hh + tf],
            [hw - tf, -hh + tf],
            [hw - tf, hh - tf],
            [-hw + tf, hh - tf],
          ];
          return [outer, inner];
        }
        return [outer];
      case SectionShape.iSection:
        return [
          [
            [-hw, -hh],
            [hw, -hh],
            [hw, -hh + tf],
            [0.5 * tw, -hh + tf],
            [0.5 * tw, hh - tf],
            [hw, hh - tf],
            [hw, hh],
            [-hw, hh],
            [-hw, hh - tf],
            [-0.5 * tw, hh - tf],
            [-0.5 * tw, -hh + tf],
            [-hw, -hh + tf],
          ],
        ];
      case SectionShape.channelC:
        return [
          [
            [-hw, -hh],
            [hw, -hh],
            [hw, -hh + tf],
            [-hw + tw, -hh + tf],
            [-hw + tw, hh - tf],
            [hw, hh - tf],
            [hw, hh],
            [-hw, hh],
          ],
        ];
      case SectionShape.angleL:
        return [
          [
            [-hw, -hh],
            [hw, -hh],
            [hw, -hh + tf],
            [-hw + tf, -hh + tf],
            [-hw + tf, hh],
            [-hw, hh],
          ],
        ];
      case SectionShape.doubleAngle:
        return [
          [
            [-hg - b1, -hh],
            [-hg, -hh],
            [-hg, hh],
            [-hg - tf, hh],
            [-hg - tf, -hh + tf],
            [-hg - b1, -hh + tf],
          ],
          [
            [hg, -hh],
            [hg + b1, -hh],
            [hg + b1, -hh + tf],
            [hg + tf, -hh + tf],
            [hg + tf, hh],
            [hg, hh],
          ],
        ];
      case SectionShape.doubleChannel:
        return [
          [
            [-hg - b1, -hh],
            [-hg, -hh],
            [-hg, hh],
            [-hg - b1, hh],
            [-hg - b1, hh - tf],
            [-hg - tw, hh - tf],
            [-hg - tw, -hh + tf],
            [-hg - b1, -hh + tf],
          ],
          [
            [hg, -hh],
            [hg + b1, -hh],
            [hg + b1, -hh + tf],
            [hg + tw, -hh + tf],
            [hg + tw, hh - tf],
            [hg + b1, hh - tf],
            [hg + b1, hh],
            [hg, hh],
          ],
        ];
      case SectionShape.teeSection:
        return [
          [
            [-0.5 * tw, -hh],
            [0.5 * tw, -hh],
            [0.5 * tw, hh - tf],
            [hw, hh - tf],
            [hw, hh],
            [-hw, hh],
            [-hw, hh - tf],
            [-0.5 * tw, hh - tf],
          ],
        ];
      case SectionShape.zeeSection:
        return [
          [
            [-b1 + 0.5 * tf, -hh],
            [0.5 * tf, -hh],
            [0.5 * tf, hh - tf],
            [b1 - 0.5 * tf, hh - tf],
            [b1 - 0.5 * tf, hh],
            [-0.5 * tf, hh],
            [-0.5 * tf, -hh + tf],
            [-b1 + 0.5 * tf, -hh + tf],
          ],
        ];
      case SectionShape.cruciform:
        return [
          [
            [-0.5 * tw, -hh],
            [0.5 * tw, -hh],
            [0.5 * tw, -0.5 * tf],
            [hw, -0.5 * tf],
            [hw, 0.5 * tf],
            [0.5 * tw, 0.5 * tf],
            [0.5 * tw, hh],
            [-0.5 * tw, hh],
            [-0.5 * tw, 0.5 * tf],
            [-hw, 0.5 * tf],
            [-hw, -0.5 * tf],
            [-0.5 * tw, -0.5 * tf],
          ],
        ];
    }
  }

  static SectionDimensions fromArea(SectionShape shape, double areaMm2) {
    final double a = math.max(1.0, areaMm2);
    switch (shape) {
      case SectionShape.solidRod:
        final d = 2.0 * math.sqrt(a / math.pi);
        return CustomSectionGeometry(heightMm: d, widthMm: d, tfMm: 0.5 * d, twMm: 0.5 * d)
            .toDimensions(shape);
      case SectionShape.circTube:
        const alpha = 0.85;
        final r = math.sqrt(a / (math.pi * (1.0 - alpha * alpha)));
        return CustomSectionGeometry(heightMm: 2 * r, widthMm: 2 * r, tfMm: (1 - alpha) * r, twMm: (1 - alpha) * r)
            .toDimensions(shape);
      case SectionShape.solidRect:
        final h = math.sqrt(a / 0.65);
        final b = 0.65 * h;
        return CustomSectionGeometry(heightMm: h, widthMm: b, tfMm: 0.2 * b, twMm: 0.2 * b)
            .toDimensions(shape);
      case SectionShape.boxSection:
        const cin = 0.76;
        final h = math.sqrt(a / (1.0 - cin * cin));
        final t = 0.12 * h;
        return CustomSectionGeometry(heightMm: h, widthMm: h, tfMm: t, twMm: t)
            .toDimensions(shape);
      case SectionShape.iSection:
        const coeff = 2.0 * 0.85 * 0.12 + 0.76 * 0.08;
        final h = math.sqrt(a / coeff);
        return CustomSectionGeometry(heightMm: h, widthMm: 0.85 * h, tfMm: 0.12 * h, twMm: 0.08 * h)
            .toDimensions(shape);
      case SectionShape.channelC:
        const coeff = 2.0 * 0.50 * 0.11 + 0.78 * 0.08;
        final h = math.sqrt(a / coeff);
        return CustomSectionGeometry(heightMm: h, widthMm: 0.50 * h, tfMm: 0.11 * h, twMm: 0.08 * h)
            .toDimensions(shape);
      case SectionShape.angleL:
        const coeff = 2.0 * 0.12 - 0.12 * 0.12;
        final h = math.sqrt(a / coeff);
        return CustomSectionGeometry(heightMm: h, widthMm: h, tfMm: 0.12 * h, twMm: 0.12 * h)
            .toDimensions(shape);
      case SectionShape.doubleAngle:
        const coeff = 2.0 * (2.0 * 0.11 - 0.11 * 0.11);
        final h = math.sqrt(a / coeff);
        return CustomSectionGeometry(
          heightMm: h,
          widthMm: h,
          tfMm: 0.11 * h,
          twMm: 0.11 * h,
          gapMm: math.max(8.0, 0.14 * h),
        ).toDimensions(shape);
      case SectionShape.doubleChannel:
        const coeff = 2.0 * (2.0 * 0.48 * 0.10 + 0.80 * 0.07);
        final h = math.sqrt(a / coeff);
        return CustomSectionGeometry(
          heightMm: h,
          widthMm: 0.48 * h,
          tfMm: 0.10 * h,
          twMm: 0.07 * h,
          gapMm: math.max(8.0, 0.12 * h),
        ).toDimensions(shape);
      case SectionShape.teeSection:
        const coeff = 1.0 * 0.14 + 0.86 * 0.10;
        final h = math.sqrt(a / coeff);
        return CustomSectionGeometry(heightMm: h, widthMm: h, tfMm: 0.14 * h, twMm: 0.10 * h)
            .toDimensions(shape);
      case SectionShape.zeeSection:
        const coeff = (1.0 + 2.0 * 0.45 - 2.0 * 0.08) * 0.08;
        final h = math.sqrt(a / coeff);
        return CustomSectionGeometry(heightMm: h, widthMm: 0.45 * h, tfMm: 0.08 * h, twMm: 0.08 * h)
            .toDimensions(shape);
      case SectionShape.cruciform:
        const coeff = 0.14 + 0.86 * 0.14;
        final h = math.sqrt(a / coeff);
        return CustomSectionGeometry(heightMm: h, widthMm: h, tfMm: 0.14 * h, twMm: 0.14 * h)
            .toDimensions(shape);
    }
  }
}

/// Dữ liệu mô hình dàn phẳng
class TrussModelData {
  final String name;
  final String description;
  final List<List<double>> coords; // [[x, y], ...] (mm)
  final List<List<int>> conn;      // [[ni_1based, nj_1based], ...]
  final List<double> areas;        // mm²
  final double E;                  // MPa
  final double nu;                 // Hệ số Poisson
  final double fyRef;              // MPa (tham khảo)
  final List<int> fixedDofs0;      // Chỉ số DOF bị khóa cứng (0-based)
  final List<NodeSupportType> nodeSupports; // Loại liên kết tại từng nút
  final List<SupportDirection> supportDirections; // Hướng gối tựa tại từng nút
  final double springStiffnessKnMm;         // Độ cứng lò xo đàn hồi k (kN/mm)
  final List<double> fRef;         // Véc-tơ tải trọng tham chiếu (N)
  final List<String> memberLabels;
  final List<String> nodeLabels;
  final SectionShape sectionShape;
  final CustomSectionGeometry? customSection; // Thông số hình học mặt cắt 3D nhập từ giao diện
  final double baseL;
  final double baseA;
  final double basePKn;

  const TrussModelData({
    required this.name,
    required this.description,
    required this.coords,
    required this.conn,
    required this.areas,
    required this.E,
    required this.nu,
    required this.fyRef,
    required this.fixedDofs0,
    required this.nodeSupports,
    this.supportDirections = const [],
    this.springStiffnessKnMm = 500.0,
    required this.fRef,
    required this.memberLabels,
    required this.nodeLabels,
    required this.sectionShape,
    this.customSection,
    required this.baseL,
    required this.baseA,
    required this.basePKn,
  });

  /// Trả về kích thước mặt cắt thực tế của thanh `e` (tôn trọng thông số người dùng nhập nếu có!)
  SectionDimensions sectionDimsForElem(int e) {
    final idx = e.clamp(0, nElems - 1);
    final aElem = areas[idx];
    if (customSection != null) {
      final aBase = math.max(1.0, customSection!.computedAreaMm2(sectionShape));
      final linearScale = math.sqrt(math.max(0.05, aElem / aBase));
      return customSection!.toDimensions(sectionShape, scale: linearScale);
    }
    return SectionDimensions.fromArea(sectionShape, aElem);
  }

  /// Trả về hướng bố trí thực tế (bottom / top / left / right) của liên kết tại nút `i`
  SupportDirection resolvedDirectionFor(int i) {
    final raw = i < supportDirections.length ? supportDirections[i] : SupportDirection.auto;
    if (raw != SupportDirection.auto) return raw;
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final c in coords) {
      minX = math.min(minX, c[0]);
      maxX = math.max(maxX, c[0]);
      minY = math.min(minY, c[1]);
      maxY = math.max(maxY, c[1]);
    }
    final isTop = coords[i][1] > 0.5 * (minY + maxY) + 1e-3;
    final isRight = coords[i][0] > 0.5 * (minX + maxX) + 1e-3;
    final sup = i < nodeSupports.length ? nodeSupports[i] : NodeSupportType.free;
    if (sup == NodeSupportType.rollerY || sup == NodeSupportType.springX) {
      return isRight ? SupportDirection.right : SupportDirection.left;
    }
    return isTop ? SupportDirection.top : SupportDirection.bottom;
  }

  int get nNodes => coords.length;
  int get nElems => conn.length;
  int get nDofs => 2 * nNodes;

  /// Véc-tơ độ cứng lò xo đàn hồi tại từng bậc tự do (N/mm)
  List<double> get springKPerDofNmm {
    final kNmm = springStiffnessKnMm * 1000.0;
    final out = List<double>.filled(nDofs, 0.0);
    for (int i = 0; i < nNodes && i < nodeSupports.length; i++) {
      if (nodeSupports[i].hasSpringX && !nodeSupports[i].locksX) {
        out[2 * i] = kNmm;
      }
      if (nodeSupports[i].hasSpringY && !nodeSupports[i].locksY) {
        out[2 * i + 1] = kNmm;
      }
    }
    return out;
  }

  bool get hasAnySpring => nodeSupports.any((s) => s.hasSpring);

  int get totalRestraintsCount =>
      nodeSupports.fold<int>(0, (sum, s) => sum + s.restraintCount);

  List<int> get freeDofs0 {
    final fixed = fixedDofs0.toSet();
    return [
      for (int i = 0; i < nDofs; i++)
        if (!fixed.contains(i)) i,
    ];
  }

  /// Danh sách loại liên kết mặc định cho từng bài toán mẫu
  static List<NodeSupportType> defaultSupportsFor(TrussPreset preset) {
    switch (preset) {
      case TrussPreset.dahlblomEx91:
        return const [NodeSupportType.pin, NodeSupportType.pin, NodeSupportType.free];
      case TrussPreset.calfemExs3:
        return const [
          NodeSupportType.pin,
          NodeSupportType.pin,
          NodeSupportType.free,
          NodeSupportType.pin,
        ];
      case TrussPreset.vonMisesArch:
        return const [NodeSupportType.pin, NodeSupportType.free, NodeSupportType.pin];
      case TrussPreset.assignment5Bar:
        return const [
          NodeSupportType.pin,
          NodeSupportType.free,
          NodeSupportType.free,
          NodeSupportType.rollerX,
        ];
    }
  }

  static List<int> fixedDofsFromSupports(List<NodeSupportType> supports) {
    final out = <int>[];
    for (int i = 0; i < supports.length; i++) {
      if (supports[i].locksX) out.add(2 * i);
      if (supports[i].locksY) out.add(2 * i + 1);
    }
    return out;
  }

  static List<String> _buildNodeLabels(List<String> baseNames, List<NodeSupportType> supports) {
    return [
      for (int i = 0; i < baseNames.length; i++)
        i < supports.length ? '${baseNames[i]} (${supports[i].shortLabel})' : baseNames[i],
    ];
  }

  List<int> elemDofs0(int e) {
    final ni = conn[e][0] - 1;
    final nj = conn[e][1] - 1;
    return [2 * ni, 2 * ni + 1, 2 * nj, 2 * nj + 1];
  }

  double initialLength(int e) {
    final ni = conn[e][0] - 1;
    final nj = conn[e][1] - 1;
    final dx = coords[nj][0] - coords[ni][0];
    final dy = coords[nj][1] - coords[ni][1];
    return math.sqrt(dx * dx + dy * dy);
  }

  static TrussModelData create({
    required TrussPreset preset,
    double lMm = 1000.0,
    double eMpa = 200000.0,
    double aMm2 = 2001.0,
    double pKn = 208.0,
    double nu = 0.30,
    SectionShape sectionShape = SectionShape.iSection,
    CustomSectionGeometry? customSection,
    List<NodeSupportType>? customSupports,
    List<SupportDirection>? customDirections,
    double springStiffnessKnMm = 500.0,
  }) {
    final defSup = defaultSupportsFor(preset);
    final supports = (customSupports != null && customSupports.length == defSup.length)
        ? List<NodeSupportType>.from(customSupports)
        : List<NodeSupportType>.from(defSup);
    final directions = (customDirections != null && customDirections.length == defSup.length)
        ? List<SupportDirection>.from(customDirections)
        : List<SupportDirection>.filled(defSup.length, SupportDirection.auto);
    final fixed = fixedDofsFromSupports(supports);
    final effectiveA = customSection != null ? customSection.computedAreaMm2(sectionShape) : aMm2;

    switch (preset) {
      case TrussPreset.dahlblomEx91:
        return TrussModelData(
          name: 'Dahlblom Example 9.1',
          description: 'Ví dụ kiểm chứng phi tuyến bar2g (Dahlblom 2016, tr. 260-261)',
          coords: const [
            [0.0, 0.0],
            [0.0, 1200.0],
            [1600.0, 0.0],
          ],
          conn: const [
            [1, 3],
            [2, 3],
          ],
          areas: const [2000.0, 500.0],
          E: 200000.0,
          nu: nu,
          fyRef: 355.0,
          fixedDofs0: fixed,
          nodeSupports: supports,
          supportDirections: directions,
          springStiffnessKnMm: springStiffnessKnMm,
          fRef: const [0.0, 0.0, 0.0, 0.0, -10.0e6, -0.2e6],
          memberLabels: const ['1-3 (AB)', '2-3 (CB)'],
          nodeLabels: _buildNodeLabels(const ['Nút 1 (A)', 'Nút 2 (C)', 'Nút 3 (B)'], supports),
          sectionShape: sectionShape,
          customSection: customSection,
          baseL: 1600.0,
          baseA: 2000.0,
          basePKn: 10000.0,
        );
      case TrussPreset.calfemExs3:
        return TrussModelData(
          name: 'CALFEM 3.4 exs3.m',
          description: 'Ví dụ chuẩn CALFEM 3.4 exs3 (calfem34.pdf tr. 9.3-9..12)',
          coords: const [
            [0.0, 0.0],
            [0.0, 1200.0],
            [1600.0, 0.0],
            [1600.0, 1200.0],
          ],
          conn: const [
            [1, 3],
            [3, 4],
            [2, 3],
          ],
          areas: const [600.0, 300.0, 1000.0],
          E: 200000.0,
          nu: nu,
          fyRef: 250.0,
          fixedDofs0: fixed,
          nodeSupports: supports,
          supportDirections: directions,
          springStiffnessKnMm: springStiffnessKnMm,
          fRef: const [0.0, 0.0, 0.0, 0.0, 0.0, -80000.0, 0.0, 0.0],
          memberLabels: const ['1-3', '3-4', '2-3'],
          nodeLabels: _buildNodeLabels(const ['Nút 1', 'Nút 2', 'Nút 3', 'Nút 4'], supports),
          sectionShape: sectionShape,
          customSection: customSection,
          baseL: 1600.0,
          baseA: 600.0,
          basePKn: 80.0,
        );
      case TrussPreset.vonMisesArch:
        return TrussModelData(
          name: 'Vòm Von Mises 2 thanh',
          description: 'Vòm dàn nông 2 thanh minh họa bật nhảy Snap-Through (McGuire Ex 9.2)',
          coords: [
            [0.0, 0.0],
            [lMm, 0.2 * lMm],
            [2.0 * lMm, 0.0],
          ],
          conn: const [
            [1, 2],
            [2, 3],
          ],
          areas: [effectiveA, effectiveA],
          E: eMpa,
          nu: nu,
          fyRef: 250.0,
          fixedDofs0: fixed,
          nodeSupports: supports,
          supportDirections: directions,
          springStiffnessKnMm: springStiffnessKnMm,
          fRef: [0.0, 0.0, 0.0, -pKn * 1000.0, 0.0, 0.0],
          memberLabels: const ['1-2', '2-3'],
          nodeLabels: _buildNodeLabels(const ['Nút 1', 'Nút 2', 'Nút 3'], supports),
          sectionShape: sectionShape,
          customSection: customSection,
          baseL: lMm,
          baseA: effectiveA,
          basePKn: pKn,
        );
      case TrussPreset.assignment5Bar:
        final diagA = 2.0 * math.sqrt(2.0) * effectiveA;
        return TrussModelData(
          name: 'Dàn 4 nút – 5 thanh (Đề bài 1.jpg)',
          description:
              'L=${lMm.toStringAsFixed(0)} mm, E=${(eMpa / 1000).toStringAsFixed(0)} GPa, '
              'A=${effectiveA.toStringAsFixed(0)} mm², P=${pKn.toStringAsFixed(1)} kN hướng lên (+Y)',
          coords: [
            [0.0, 0.0],
            [lMm, 0.0],
            [0.0, lMm],
            [2.0 * lMm, lMm],
          ],
          conn: const [
            [1, 2],
            [1, 3],
            [3, 4],
            [3, 2],
            [2, 4],
          ],
          areas: [effectiveA, effectiveA, effectiveA, diagA, diagA],
          E: eMpa,
          nu: nu,
          fyRef: 250.0,
          fixedDofs0: fixed,
          nodeSupports: supports,
          supportDirections: directions,
          springStiffnessKnMm: springStiffnessKnMm,
          fRef: [0.0, 0.0, 0.0, pKn * 1000.0, 0.0, 0.0, 0.0, 0.0],
          memberLabels: const ['1-2', '1-3', '3-4', '3-2', '2-4'],
          nodeLabels: _buildNodeLabels(const ['Nút 1', 'Nút 2', 'Nút 3', 'Nút 4'], supports),
          sectionShape: sectionShape,
          customSection: customSection,
          baseL: lMm,
          baseA: effectiveA,
          basePKn: pKn,
        );
    }
  }
}

/// Một bước lịch sử trong quá trình gia tải / lặp phi tuyến
class LoadStepRecord {
  final int step;
  final double lambda;
  final int iterations;
  final double residualInfN;
  final List<double> uMm;
  final List<double> nForcesN;

  const LoadStepRecord({
    required this.step,
    required this.lambda,
    required this.iterations,
    required this.residualInfN,
    required this.uMm,
    required this.nForcesN,
  });
}

/// Kết quả đầy đủ của một phương pháp phân tích
class TrussAnalysisResult {
  final String methodName;
  final String engineSource;
  final bool converged;
  final List<double> uMm;
  final List<double> reactionsN;
  final List<double> nForcesN;
  final List<double> stressMpa;
  final List<double> strain;
  final List<double> elongationMm;
  final List<double> currentLengthsMm;
  final List<double> memberEnergyNmm;
  final double totalEnergyNmm;
  final double sumFxN;
  final double sumFyN;
  final double sumMNmm;
  final double maxFreeResidualN;
  final int totalIterations;
  final int totalFactorizations;
  final List<LoadStepRecord> history;
  final String? warningMessage;

  const TrussAnalysisResult({
    required this.methodName,
    required this.engineSource,
    required this.converged,
    required this.uMm,
    required this.reactionsN,
    required this.nForcesN,
    required this.stressMpa,
    required this.strain,
    required this.elongationMm,
    required this.currentLengthsMm,
    required this.memberEnergyNmm,
    required this.totalEnergyNmm,
    required this.sumFxN,
    required this.sumFyN,
    required this.sumMNmm,
    required this.maxFreeResidualN,
    required this.totalIterations,
    required this.totalFactorizations,
    required this.history,
    this.warningMessage,
  });
}

/// Điểm trên đường cong cân bằng chuyển vị lớn (Snap-Through / P-u)
class EquilibriumPoint {
  final double uMainMm;
  final double pKn;
  final double lambda;
  final double n12Kn;
  final bool isUnstable;

  const EquilibriumPoint({
    required this.uMainMm,
    required this.pKn,
    required this.lambda,
    required this.n12Kn,
    required this.isUnstable,
  });
}

/// Kết quả khảo sát tại 1 điểm bất kỳ (e, ξ, η, ζ)
class ProbeInspection {
  final int elemIndex;
  final String memberLabel;
  final double xi;
  final double sMm;
  final double l0Mm;
  final double lCurMm;
  final double elongationMm;
  final double rotationDeg;
  final double x0, y0, xCur, yCur;
  final double uxMm, uyMm, uMagMm;
  final double nKn;
  final double nLinearKn;
  final double sigmaAxialMpa;
  final double sigmaBendingMpa;
  final double sigmaXxMpa;
  final double sigmaVonMisesMpa;
  final double tauMaxMohrMpa;
  final double epsXxMicro;
  final double epsPoissonMicro;
  final double energyDensityKjM3;
  final double daf;
  final double pEulerLocalKn;
  final double etaNorm;
  final double zetaNorm;
  final double yFiberMm;
  final double zFiberMm;
  final String stateLabel;
  final SectionDimensions sectionDims;

  const ProbeInspection({
    required this.elemIndex,
    required this.memberLabel,
    required this.xi,
    required this.sMm,
    required this.l0Mm,
    required this.lCurMm,
    required this.elongationMm,
    required this.rotationDeg,
    required this.x0,
    required this.y0,
    required this.xCur,
    required this.yCur,
    required this.uxMm,
    required this.uyMm,
    required this.uMagMm,
    required this.nKn,
    required this.nLinearKn,
    required this.sigmaAxialMpa,
    required this.sigmaBendingMpa,
    required this.sigmaXxMpa,
    required this.sigmaVonMisesMpa,
    required this.tauMaxMohrMpa,
    required this.epsXxMicro,
    required this.epsPoissonMicro,
    required this.energyDensityKjM3,
    required this.daf,
    required this.pEulerLocalKn,
    required this.etaNorm,
    required this.zetaNorm,
    required this.yFiberMm,
    required this.zFiberMm,
    required this.stateLabel,
    required this.sectionDims,
  });
}

/// Lớp lõi đại số tuyến tính và thuật toán CALFEM phi tuyến viết bằng thuần Dart
class CalfemNonlinearEngine {
  // --------------------------------------------------------------------------
  // Giải hệ phương trình tuyến tính A*x = b bằng khử Gauss chọn phần tử trụ
  // --------------------------------------------------------------------------
  static List<double> solveLinearSystem(List<List<double>> aIn, List<double> bIn) {
    final n = bIn.length;
    final a = [for (int i = 0; i < n; i++) List<double>.from(aIn[i])];
    final b = List<double>.from(bIn);

    for (int col = 0; col < n; col++) {
      int pivotRow = col;
      double maxVal = a[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        final v = a[row][col].abs();
        if (v > maxVal) {
          maxVal = v;
          pivotRow = row;
        }
      }
      if (maxVal < 1e-18) {
        return List<double>.filled(n, 0.0);
      }
      if (pivotRow != col) {
        final tmpRow = a[col];
        a[col] = a[pivotRow];
        a[pivotRow] = tmpRow;
        final tmpB = b[col];
        b[col] = b[pivotRow];
        b[pivotRow] = tmpB;
      }
      final pivot = a[col][col];
      for (int row = col + 1; row < n; row++) {
        final factor = a[row][col] / pivot;
        if (factor == 0.0) continue;
        for (int k = col; k < n; k++) {
          a[row][k] -= factor * a[col][k];
        }
        b[row] -= factor * b[col];
      }
    }

    final x = List<double>.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      double s = b[i];
      for (int j = i + 1; j < n; j++) {
        s -= a[i][j] * x[j];
      }
      x[i] = s / a[i][i];
    }
    return x;
  }

  /// Tính định thức ma trận vuông nhỏ (dùng kiểm tra dấu det(Kt) mất ổn định)
  static double determinant(List<List<double>> mat) {
    final n = mat.length;
    final a = [for (int i = 0; i < n; i++) List<double>.from(mat[i])];
    double det = 1.0;
    for (int col = 0; col < n; col++) {
      int pivot = col;
      for (int r = col + 1; r < n; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-18) return 0.0;
      if (pivot != col) {
        final t = a[col];
        a[col] = a[pivot];
        a[pivot] = t;
        det = -det;
      }
      det *= a[col][col];
      for (int r = col + 1; r < n; r++) {
        final f = a[r][col] / a[col][col];
        for (int k = col; k < n; k++) {
          a[r][k] -= f * a[col][k];
        }
      }
    }
    return det;
  }

  static List<List<double>> _zeros(int n) =>
      List.generate(n, (_) => List<double>.filled(n, 0.0));

  static List<List<double>> _subMatrix(List<List<double>> m, List<int> idx) =>
      [for (final r in idx) [for (final c in idx) m[r][c]]];

  static List<double> _subVec(List<double> v, List<int> idx) =>
      [for (final i in idx) v[i]];

  static List<double> _matVec(List<List<double>> m, List<double> v) {
    final n = v.length;
    final out = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      double s = 0.0;
      for (int j = 0; j < n; j++) {
        s += m[i][j] * v[j];
      }
      out[i] = s;
    }
    return out;
  }

  /// Hàm CALFEM chuẩn `bar2e`: ma trận độ cứng tuyến tính 4x4
  static List<List<double>> bar2e(
      double x1, double y1, double x2, double y2, double E, double A) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final l = math.sqrt(dx * dx + dy * dy);
    final c = dx / l;
    final s = dy / l;
    final k = E * A / l;
    final cc = c * c * k;
    final cs = c * s * k;
    final ss = s * s * k;
    return [
      [cc, cs, -cc, -cs],
      [cs, ss, -cs, -ss],
      [-cc, -cs, cc, cs],
      [-cs, -ss, cs, ss],
    ];
  }

  /// Hàm CALFEM chuẩn `bar2g`: ma trận độ cứng bậc hai 4x4 (Ke0 + Keσ)
  static List<List<double>> bar2g(
      double x1, double y1, double x2, double y2, double E, double A, double N) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final l = math.sqrt(dx * dx + dy * dy);
    final c = dx / l;
    final s = dy / l;
    final kMat = E * A / l;
    final kGeo = N / l;
    final k11 = kMat * c * c + kGeo * s * s;
    final k12 = (kMat - kGeo) * c * s;
    final k22 = kMat * s * s + kGeo * c * c;
    return [
      [k11, k12, -k11, -k12],
      [k12, k22, -k12, -k22],
      [-k11, -k12, k11, k12],
      [-k12, -k22, k12, k22],
    ];
  }

  /// Hàm CALFEM chuẩn `bar2s`: tính lực dọc tuyến tính N (N)
  static double bar2s(double x1, double y1, double x2, double y2, double E,
      double A, List<double> ed) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final l = math.sqrt(dx * dx + dy * dy);
    final c = dx / l;
    final s = dy / l;
    return (E * A / l) * (c * (ed[2] - ed[0]) + s * (ed[3] - ed[1]));
  }

  /// Lắp ráp nội lực & tiếp tuyến phi tuyến (Corotational UL hoặc Total Lagrangian)
  static _AssembledState _assembleNonlinear(
      TrussModelData model, List<double> u, bool isTotalLagrangian) {
    final nd = model.nDofs;
    final ne = model.nElems;
    final fInt = List<double>.filled(nd, 0.0);
    final kt = _zeros(nd);
    final nForces = List<double>.filled(ne, 0.0);
    final strains = List<double>.filled(ne, 0.0);
    final lengths = List<double>.filled(ne, 0.0);
    final energies = List<double>.filled(ne, 0.0);

    for (int e = 0; e < ne; e++) {
      final ni = model.conn[e][0] - 1;
      final nj = model.conn[e][1] - 1;
      final dofs = model.elemDofs0(e);
      final dx0 = model.coords[nj][0] - model.coords[ni][0];
      final dy0 = model.coords[nj][1] - model.coords[ni][1];
      final l0 = math.sqrt(dx0 * dx0 + dy0 * dy0);

      final dux = u[dofs[2]] - u[dofs[0]];
      final duy = u[dofs[3]] - u[dofs[1]];
      final dxc = dx0 + dux;
      final dyc = dy0 + duy;
      final lCur = math.sqrt(dxc * dxc + dyc * dyc);
      final cCur = dxc / lCur;
      final sCur = dyc / lCur;
      final ea = model.E * model.areas[e];

      // Hằng đẳng thức khử mất chữ số có nghĩa: l^2 - L0^2 = dux*(2*dx0 + dux) + duy*(2*dy0 + duy)
      final dl2 = dux * (2.0 * dx0 + dux) + duy * (2.0 * dy0 + duy);

      late double nPhys;
      late double eps;
      late double en;
      late List<double> fe;
      late double k11, k12, k22;

      if (!isTotalLagrangian) {
        final dlExact = dl2 / (lCur + l0);
        eps = dlExact / l0;
        nPhys = ea * eps;
        en = 0.5 * ea * l0 * eps * eps;
        fe = [-nPhys * cCur, -nPhys * sCur, nPhys * cCur, nPhys * sCur];
        final kMat = ea / l0;
        final kGeo = nPhys / lCur;
        k11 = kMat * cCur * cCur + kGeo * sCur * sCur;
        k12 = (kMat - kGeo) * cCur * sCur;
        k22 = kMat * sCur * sCur + kGeo * cCur * cCur;
      } else {
        eps = dl2 / (2.0 * l0 * l0);
        final sn = ea * eps;
        en = 0.5 * ea * l0 * eps * eps;
        fe = [
          -(sn / l0) * dxc,
          -(sn / l0) * dyc,
          (sn / l0) * dxc,
          (sn / l0) * dyc,
        ];
        final cMat = ea / (l0 * l0 * l0);
        final kGeo = sn / l0;
        k11 = cMat * dxc * dxc + kGeo;
        k12 = cMat * dxc * dyc;
        k22 = cMat * dyc * dyc + kGeo;
        nPhys = sn * (lCur / l0);
      }

      nForces[e] = nPhys;
      strains[e] = eps;
      lengths[e] = lCur;
      energies[e] = en;

      final ke = [
        [k11, k12, -k11, -k12],
        [k12, k22, -k12, -k22],
        [-k11, -k12, k11, k12],
        [-k12, -k22, k12, k22],
      ];
      for (int a = 0; a < 4; a++) {
        fInt[dofs[a]] += fe[a];
        for (int b = 0; b < 4; b++) {
          kt[dofs[a]][dofs[b]] += ke[a][b];
        }
      }
    }
    // Bổ sung đóng góp của các liên kết gối đàn hồi lò xo k_x, k_y (N/mm)
    final kSpr = model.springKPerDofNmm;
    for (int d = 0; d < nd; d++) {
      if (kSpr[d] > 0.0) {
        fInt[d] += kSpr[d] * u[d];
        kt[d][d] += kSpr[d];
      }
    }
    return _AssembledState(fInt, kt, nForces, strains, lengths, energies);
  }

  /// Kiểm tra tính bất biến hình (ma trận độ cứng ban đầu K0_ff không suy biến)
  static String? checkKinematicStability(TrussModelData model) {
    final free = model.freeDofs0;
    if (free.isEmpty) return null; // Tất cả các nút đã được khóa cứng
    final nd = model.nDofs;
    final K = _zeros(nd);
    for (int e = 0; e < model.nElems; e++) {
      final ni = model.conn[e][0] - 1;
      final nj = model.conn[e][1] - 1;
      final ke = bar2e(model.coords[ni][0], model.coords[ni][1],
          model.coords[nj][0], model.coords[nj][1], model.E, model.areas[e]);
      final dofs = model.elemDofs0(e);
      for (int a = 0; a < 4; a++) {
        for (int b = 0; b < 4; b++) {
          K[dofs[a]][dofs[b]] += ke[a][b];
        }
      }
    }
    final kSpr = model.springKPerDofNmm;
    for (int d = 0; d < nd; d++) {
      K[d][d] += kSpr[d];
    }
    final kff = _subMatrix(K, free);
    final n = free.length;
    double maxDiag = 0.0;
    for (int i = 0; i < n; i++) {
      maxDiag = math.max(maxDiag, kff[i][i].abs());
    }
    if (maxDiag < 1e-12) {
      return 'Hệ kết cấu BIẾN HÌNH (độ cứng bằng 0). Vui lòng bổ sung thêm liên kết gối tựa!';
    }
    // Khử Gauss kiểm tra suy biến
    final a = [for (int i = 0; i < n; i++) List<double>.from(kff[i])];
    for (int col = 0; col < n; col++) {
      int pivotRow = col;
      double maxVal = a[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        final v = a[row][col].abs();
        if (v > maxVal) {
          maxVal = v;
          pivotRow = row;
        }
      }
      if (maxVal < 1e-7 * maxDiag) {
        return 'Hệ kết cấu BIẾN HÌNH (ma trận độ cứng suy biến — thiếu liên kết gối tựa hoặc các phản lực đồng quy/song song)! Hãy bổ sung tối thiểu 3 bậc liên kết độc lập.';
      }
      if (pivotRow != col) {
        final tmp = a[col];
        a[col] = a[pivotRow];
        a[pivotRow] = tmp;
      }
      final piv = a[col][col];
      for (int row = col + 1; row < n; row++) {
        final f = a[row][col] / piv;
        if (f == 0.0) continue;
        for (int k = col; k < n; k++) {
          a[row][k] -= f * a[col][k];
        }
      }
    }
    return null;
  }

  static TrussAnalysisResult _unstableResult(
      TrussModelData model, String methodName, double loadFactor, String warning) {
    final nd = model.nDofs;
    final ne = model.nElems;
    return TrussAnalysisResult(
      methodName: methodName,
      engineSource: 'Python CALFEM Engine (Offline 100%)',
      converged: false,
      uMm: List<double>.filled(nd, 0.0),
      reactionsN: List<double>.filled(nd, 0.0),
      nForcesN: List<double>.filled(ne, 0.0),
      stressMpa: List<double>.filled(ne, 0.0),
      strain: List<double>.filled(ne, 0.0),
      elongationMm: List<double>.filled(ne, 0.0),
      currentLengthsMm: [for (int e = 0; e < ne; e++) model.initialLength(e)],
      memberEnergyNmm: List<double>.filled(ne, 0.0),
      totalEnergyNmm: 0.0,
      sumFxN: 0.0,
      sumFyN: 0.0,
      sumMNmm: 0.0,
      maxFreeResidualN: 0.0,
      totalIterations: 0,
      totalFactorizations: 0,
      history: const [],
      warningMessage: warning,
    );
  }

  static TrussAnalysisResult _buildResult({
    required TrussModelData model,
    required String methodName,
    required bool converged,
    required List<double> u,
    required List<double> reactions,
    required List<double> nForces,
    required List<double> strains,
    required List<double> lengths,
    required List<double> energies,
    required double loadFactor,
    required bool useDeformedCoords,
    required int totalIterations,
    required int totalFactorizations,
    required List<LoadStepRecord> history,
    String? warningMessage,
  }) {
    final ne = model.nElems;
    final nd = model.nDofs;
    final stress = [for (int e = 0; e < ne; e++) nForces[e] / model.areas[e]];
    final elong = [for (int e = 0; e < ne; e++) lengths[e] - model.initialLength(e)];
    final kSpr = model.springKPerDofNmm;
    double springEnergy = 0.0;
    for (int d = 0; d < nd; d++) {
      if (kSpr[d] > 0.0) {
        springEnergy += 0.5 * kSpr[d] * u[d] * u[d];
      }
    }
    final totalU = energies.fold(0.0, (a, b) => a + b) + springEnergy;

    // Sai số lực dư thực tại các bậc tự do không khóa cứng
    double maxFreeRes = 0.0;
    for (final d in model.freeDofs0) {
      maxFreeRes = math.max(maxFreeRes, reactions[d].abs());
    }

    // Phản lực hiển thị & kiểm tra cân bằng: cộng thêm phản lực đàn hồi lò xo R_spring = -k*u
    final totalReactions = List<double>.from(reactions);
    for (int d = 0; d < nd; d++) {
      if (kSpr[d] > 0.0) {
        totalReactions[d] -= kSpr[d] * u[d];
      }
    }

    double sfx = 0.0, sfy = 0.0, sm = 0.0;
    for (int i = 0; i < model.nNodes; i++) {
      final fx = loadFactor * model.fRef[2 * i] + totalReactions[2 * i];
      final fy = loadFactor * model.fRef[2 * i + 1] + totalReactions[2 * i + 1];
      final x = model.coords[i][0] + (useDeformedCoords ? u[2 * i] : 0.0);
      final y = model.coords[i][1] + (useDeformedCoords ? u[2 * i + 1] : 0.0);
      sfx += fx;
      sfy += fy;
      sm += x * fy - y * fx;
    }

    return TrussAnalysisResult(
      methodName: methodName,
      engineSource: 'Python CALFEM Engine (Offline 100%)',
      converged: converged,
      uMm: u,
      reactionsN: totalReactions,
      nForcesN: nForces,
      stressMpa: stress,
      strain: strains,
      elongationMm: elong,
      currentLengthsMm: lengths,
      memberEnergyNmm: energies,
      totalEnergyNmm: totalU,
      sumFxN: sfx,
      sumFyN: sfy,
      sumMNmm: sm,
      maxFreeResidualN: maxFreeRes,
      totalIterations: totalIterations,
      totalFactorizations: totalFactorizations,
      history: history,
      warningMessage: warningMessage,
    );
  }

  /// Giải theo phương pháp người dùng chọn
  static TrussAnalysisResult solve(
    TrussModelData model, {
    required SolverMethod method,
    double loadFactor = 1.0,
    int nSteps = 10,
  }) {
    switch (method) {
      case SolverMethod.linearFirstOrder:
        return solveLinear(model, loadFactor: loadFactor);
      case SolverMethod.bar2gSecondOrder:
        return solveBar2gSecondOrder(model, loadFactor: loadFactor);
      case SolverMethod.corotationalNR:
        return solveFullNR(model, isTotalLagrangian: false, loadFactor: loadFactor, nSteps: nSteps);
      case SolverMethod.totalLagrangian:
        return solveFullNR(model, isTotalLagrangian: true, loadFactor: loadFactor, nSteps: nSteps);
      case SolverMethod.modifiedNR:
        return solveModifiedNR(model, loadFactor: loadFactor, nSteps: nSteps);
      case SolverMethod.eulerSingleStep:
        return solveEuler(model, loadFactor: loadFactor, nSteps: nSteps);
      case SolverMethod.rk2Midpoint:
        return solveRK2(model, loadFactor: loadFactor, nSteps: nSteps);
    }
  }

  /// 1. Đàn hồi tuyến tính bậc 1 (CALFEM bar2e)
  static TrussAnalysisResult solveLinear(TrussModelData model, {double loadFactor = 1.0}) {
    final stabWarn = checkKinematicStability(model);
    if (stabWarn != null) {
      return _unstableResult(model, SolverMethod.linearFirstOrder.label, loadFactor, stabWarn);
    }
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final K = _zeros(nd);
    for (int e = 0; e < model.nElems; e++) {
      final ni = model.conn[e][0] - 1;
      final nj = model.conn[e][1] - 1;
      final ke = bar2e(model.coords[ni][0], model.coords[ni][1],
          model.coords[nj][0], model.coords[nj][1], model.E, model.areas[e]);
      final dofs = model.elemDofs0(e);
      for (int a = 0; a < 4; a++) {
        for (int b = 0; b < 4; b++) {
          K[dofs[a]][dofs[b]] += ke[a][b];
        }
      }
    }
    final kSpr = model.springKPerDofNmm;
    for (int d = 0; d < nd; d++) {
      K[d][d] += kSpr[d];
    }
    final f = [for (final v in model.fRef) v * loadFactor];
    final u = List<double>.filled(nd, 0.0);
    if (free.isNotEmpty) {
      final uf = solveLinearSystem(_subMatrix(K, free), _subVec(f, free));
      for (int i = 0; i < free.length; i++) {
        u[free[i]] = uf[i];
      }
    }
    final ku = _matVec(K, u);
    final r = [for (int i = 0; i < nd; i++) ku[i] - f[i]];

    final nForces = List<double>.filled(model.nElems, 0.0);
    final strains = List<double>.filled(model.nElems, 0.0);
    final lengths = List<double>.filled(model.nElems, 0.0);
    final energies = List<double>.filled(model.nElems, 0.0);
    for (int e = 0; e < model.nElems; e++) {
      final ni = model.conn[e][0] - 1;
      final nj = model.conn[e][1] - 1;
      final dofs = model.elemDofs0(e);
      final ed = [for (final d in dofs) u[d]];
      nForces[e] = bar2s(model.coords[ni][0], model.coords[ni][1],
          model.coords[nj][0], model.coords[nj][1], model.E, model.areas[e], ed);
      final l0 = model.initialLength(e);
      strains[e] = nForces[e] / (model.E * model.areas[e]);
      lengths[e] = l0 * (1.0 + strains[e]);
      energies[e] = 0.5 * nForces[e] * nForces[e] * l0 / (model.E * model.areas[e]);
    }
    return _buildResult(
      model: model,
      methodName: SolverMethod.linearFirstOrder.label,
      converged: true,
      u: u,
      reactions: r,
      nForces: nForces,
      strains: strains,
      lengths: lengths,
      energies: energies,
      loadFactor: loadFactor,
      useDeformedCoords: false,
      totalIterations: 1,
      totalFactorizations: 1,
      history: [
        LoadStepRecord(
            step: 1, lambda: loadFactor, iterations: 1, residualInfN: 0.0, uMm: u, nForcesN: nForces),
      ],
    );
  }

  /// 2. Phi tuyến bậc 2 CALFEM gốc (`bar2g` cố định tọa độ ban đầu, Dahlblom Ch. 9)
  static TrussAnalysisResult solveBar2gSecondOrder(
    TrussModelData model, {
    double loadFactor = 1.0,
    double tolRel = 1e-10,
    int maxIter = 50,
  }) {
    final stabWarn = checkKinematicStability(model);
    if (stabWarn != null) {
      return _unstableResult(model, SolverMethod.bar2gSecondOrder.label, loadFactor, stabWarn);
    }
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final kSpr = model.springKPerDofNmm;
    final f = [for (final v in model.fRef) v * loadFactor];
    var nCur = List<double>.filled(model.nElems, 0.0);
    var u = List<double>.filled(nd, 0.0);
    var K = _zeros(nd);
    bool converged = free.isEmpty;
    final history = <LoadStepRecord>[];

    for (int it = 1; it <= maxIter; it++) {
      K = _zeros(nd);
      for (int e = 0; e < model.nElems; e++) {
        final ni = model.conn[e][0] - 1;
        final nj = model.conn[e][1] - 1;
        final ke = bar2g(model.coords[ni][0], model.coords[ni][1],
            model.coords[nj][0], model.coords[nj][1], model.E, model.areas[e], nCur[e]);
        final dofs = model.elemDofs0(e);
        for (int a = 0; a < 4; a++) {
          for (int b = 0; b < 4; b++) {
            K[dofs[a]][dofs[b]] += ke[a][b];
          }
        }
      }
      for (int d = 0; d < nd; d++) {
        K[d][d] += kSpr[d];
      }
      u = List<double>.filled(nd, 0.0);
      if (free.isNotEmpty) {
        final uf = solveLinearSystem(_subMatrix(K, free), _subVec(f, free));
        for (int i = 0; i < free.length; i++) {
          u[free[i]] = uf[i];
        }
      }
      final nNext = List<double>.filled(model.nElems, 0.0);
      double diff2 = 0.0, norm2 = 0.0;
      for (int e = 0; e < model.nElems; e++) {
        final ni = model.conn[e][0] - 1;
        final nj = model.conn[e][1] - 1;
        final dofs = model.elemDofs0(e);
        final ed = [for (final d in dofs) u[d]];
        nNext[e] = bar2s(model.coords[ni][0], model.coords[ni][1],
            model.coords[nj][0], model.coords[nj][1], model.E, model.areas[e], ed);
        diff2 += (nNext[e] - nCur[e]) * (nNext[e] - nCur[e]);
        norm2 += nNext[e] * nNext[e];
      }
      final relErr = math.sqrt(diff2) / math.max(1.0, math.sqrt(norm2));
      history.add(LoadStepRecord(
          step: it,
          lambda: loadFactor,
          iterations: it,
          residualInfN: relErr,
          uMm: List<double>.from(u),
          nForcesN: List<double>.from(nNext)));
      nCur = nNext;
      if (it > 1 && relErr < tolRel) {
        converged = true;
        break;
      }
    }
    final ku = _matVec(K, u);
    final r = [for (int i = 0; i < nd; i++) ku[i] - f[i]];
    final strains = [for (int e = 0; e < model.nElems; e++) nCur[e] / (model.E * model.areas[e])];
    final lengths = [for (int e = 0; e < model.nElems; e++) model.initialLength(e) * (1.0 + strains[e])];
    final energies = [
      for (int e = 0; e < model.nElems; e++)
        0.5 * nCur[e] * nCur[e] * model.initialLength(e) / (model.E * model.areas[e])
    ];
    return _buildResult(
      model: model,
      methodName: SolverMethod.bar2gSecondOrder.label,
      converged: converged,
      u: u,
      reactions: r,
      nForces: nCur,
      strains: strains,
      lengths: lengths,
      energies: energies,
      loadFactor: loadFactor,
      useDeformedCoords: false,
      totalIterations: history.length,
      totalFactorizations: history.length,
      history: history,
    );
  }

  /// 3 & 4. Full Newton-Raphson (Corotational UL hoặc Total Lagrangian)
  static TrussAnalysisResult solveFullNR(
    TrussModelData model, {
    required bool isTotalLagrangian,
    double loadFactor = 1.0,
    int nSteps = 10,
    double tolForce = 1e-7,
    int maxIter = 40,
  }) {
    final mLabel = isTotalLagrangian ? SolverMethod.totalLagrangian.label : SolverMethod.corotationalNR.label;
    final stabWarn = checkKinematicStability(model);
    if (stabWarn != null) {
      return _unstableResult(model, mLabel, loadFactor, stabWarn);
    }
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final u = List<double>.filled(nd, 0.0);
    if (free.isEmpty) {
      final st0 = _assembleNonlinear(model, u, isTotalLagrangian);
      final r0 = [for (int i = 0; i < nd; i++) st0.fInt[i] - loadFactor * model.fRef[i]];
      return _buildResult(
        model: model,
        methodName: mLabel,
        converged: true,
        u: u,
        reactions: r0,
        nForces: st0.nForces,
        strains: st0.strains,
        lengths: st0.lengths,
        energies: st0.energies,
        loadFactor: loadFactor,
        useDeformedCoords: true,
        totalIterations: 0,
        totalFactorizations: 0,
        history: const [],
      );
    }
    final history = <LoadStepRecord>[
      LoadStepRecord(
        step: 0,
        lambda: 0.0,
        iterations: 0,
        residualInfN: 0.0,
        uMm: List<double>.filled(nd, 0.0),
        nForcesN: List<double>.filled(model.nElems, 0.0),
      )
    ];

    int totalIt = 0;
    bool allConv = true;
    var state = _assembleNonlinear(model, u, isTotalLagrangian);

    for (int s = 1; s <= nSteps; s++) {
      final lam = loadFactor * s / nSteps;
      bool stepConv = false;
      int nIt = 0;
      double resInf = 0.0;

      for (int it = 1; it <= maxIter; it++) {
        nIt = it;
        state = _assembleNonlinear(model, u, isTotalLagrangian);
        final resF = [for (final d in free) lam * model.fRef[d] - state.fInt[d]];
        resInf = resF.fold(0.0, (m, v) => math.max(m, v.abs()));
        if (resInf < tolForce) {
          stepConv = true;
          break;
        }
        final duF = solveLinearSystem(_subMatrix(state.kt, free), resF);
        for (int i = 0; i < free.length; i++) {
          u[free[i]] += duF[i];
        }
        totalIt++;
        state = _assembleNonlinear(model, u, isTotalLagrangian);
        resInf = free.fold(0.0, (m, d) => math.max(m, (lam * model.fRef[d] - state.fInt[d]).abs()));
        if (resInf < tolForce) {
          stepConv = true;
          break;
        }
      }
      if (!stepConv) {
        allConv = false;
        break;
      }
      history.add(LoadStepRecord(
        step: s,
        lambda: lam,
        iterations: nIt,
        residualInfN: resInf,
        uMm: List<double>.from(u),
        nForcesN: List<double>.from(state.nForces),
      ));
    }

    final r = [for (int i = 0; i < nd; i++) state.fInt[i] - loadFactor * model.fRef[i]];
    return _buildResult(
      model: model,
      methodName: isTotalLagrangian ? SolverMethod.totalLagrangian.label : SolverMethod.corotationalNR.label,
      converged: allConv,
      u: u,
      reactions: r,
      nForces: state.nForces,
      strains: state.strains,
      lengths: state.lengths,
      energies: state.energies,
      loadFactor: loadFactor,
      useDeformedCoords: true,
      totalIterations: totalIt,
      totalFactorizations: totalIt,
      history: history,
    );
  }

  /// 5. Modified Newton-Raphson (giữ [K_i^0] cố định trong từng bước gia tải)
  static TrussAnalysisResult solveModifiedNR(
    TrussModelData model, {
    double loadFactor = 1.0,
    int nSteps = 10,
    double tolForce = 1e-7,
    int maxIter = 100,
  }) {
    final stabWarn = checkKinematicStability(model);
    if (stabWarn != null) {
      return _unstableResult(model, SolverMethod.modifiedNR.label, loadFactor, stabWarn);
    }
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final u = List<double>.filled(nd, 0.0);
    if (free.isEmpty) {
      return solveFullNR(model, isTotalLagrangian: false, loadFactor: loadFactor, nSteps: 1);
    }
    final history = <LoadStepRecord>[
      LoadStepRecord(
          step: 0,
          lambda: 0.0,
          iterations: 0,
          residualInfN: 0.0,
          uMm: List<double>.filled(nd, 0.0),
          nForcesN: List<double>.filled(model.nElems, 0.0)),
    ];
    int totalIt = 0;
    bool allConv = true;
    var state = _assembleNonlinear(model, u, false);

    for (int s = 1; s <= nSteps; s++) {
      final lam = loadFactor * s / nSteps;
      state = _assembleNonlinear(model, u, false);
      final kt0 = _subMatrix(state.kt, free);
      bool stepConv = false;
      int nIt = 0;
      double resInf = 0.0;
      for (int it = 1; it <= maxIter; it++) {
        nIt = it;
        final resF = [for (final d in free) lam * model.fRef[d] - state.fInt[d]];
        resInf = resF.fold(0.0, (m, v) => math.max(m, v.abs()));
        if (resInf < tolForce) {
          stepConv = true;
          break;
        }
        final duF = solveLinearSystem(kt0, resF);
        for (int i = 0; i < free.length; i++) {
          u[free[i]] += duF[i];
        }
        totalIt++;
        state = _assembleNonlinear(model, u, false);
        resInf = free.fold(0.0, (m, d) => math.max(m, (lam * model.fRef[d] - state.fInt[d]).abs()));
        if (resInf < tolForce) {
          stepConv = true;
          break;
        }
      }
      if (!stepConv) {
        allConv = false;
        break;
      }
      history.add(LoadStepRecord(
        step: s,
        lambda: lam,
        iterations: nIt,
        residualInfN: resInf,
        uMm: List<double>.from(u),
        nForcesN: List<double>.from(state.nForces),
      ));
    }
    final r = [for (int i = 0; i < nd; i++) state.fInt[i] - loadFactor * model.fRef[i]];
    return _buildResult(
      model: model,
      methodName: SolverMethod.modifiedNR.label,
      converged: allConv,
      u: u,
      reactions: r,
      nForces: state.nForces,
      strains: state.strains,
      lengths: state.lengths,
      energies: state.energies,
      loadFactor: loadFactor,
      useDeformedCoords: true,
      totalIterations: totalIt,
      totalFactorizations: nSteps,
      history: history,
    );
  }

  /// 6. Euler bước đơn (không hiệu chỉnh lực dư)
  static TrussAnalysisResult solveEuler(TrussModelData model, {double loadFactor = 1.0, int nSteps = 10}) {
    final stabWarn = checkKinematicStability(model);
    if (stabWarn != null) {
      return _unstableResult(model, SolverMethod.eulerSingleStep.label, loadFactor, stabWarn);
    }
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final u = List<double>.filled(nd, 0.0);
    if (free.isEmpty) {
      return solveFullNR(model, isTotalLagrangian: false, loadFactor: loadFactor, nSteps: 1);
    }
    final dlam = loadFactor / nSteps;
    final history = <LoadStepRecord>[];
    var state = _assembleNonlinear(model, u, false);

    for (int s = 1; s <= nSteps; s++) {
      final dfF = [for (final d in free) dlam * model.fRef[d]];
      final duF = solveLinearSystem(_subMatrix(state.kt, free), dfF);
      for (int i = 0; i < free.length; i++) {
        u[free[i]] += duF[i];
      }
      state = _assembleNonlinear(model, u, false);
      final lam = s * dlam;
      final resInf = free.fold(0.0, (m, d) => math.max(m, (lam * model.fRef[d] - state.fInt[d]).abs()));
      history.add(LoadStepRecord(
          step: s,
          lambda: lam,
          iterations: 1,
          residualInfN: resInf,
          uMm: List<double>.from(u),
          nForcesN: List<double>.from(state.nForces)));
    }
    final r = [for (int i = 0; i < nd; i++) state.fInt[i] - loadFactor * model.fRef[i]];
    return _buildResult(
      model: model,
      methodName: SolverMethod.eulerSingleStep.label,
      converged: true,
      u: u,
      reactions: r,
      nForces: state.nForces,
      strains: state.strains,
      lengths: state.lengths,
      energies: state.energies,
      loadFactor: loadFactor,
      useDeformedCoords: true,
      totalIterations: nSteps,
      totalFactorizations: nSteps,
      history: history,
    );
  }

  /// 7. Runge-Kutta bậc 2 điểm giữa (Midpoint RK2)
  static TrussAnalysisResult solveRK2(TrussModelData model, {double loadFactor = 1.0, int nSteps = 10}) {
    final stabWarn = checkKinematicStability(model);
    if (stabWarn != null) {
      return _unstableResult(model, SolverMethod.rk2Midpoint.label, loadFactor, stabWarn);
    }
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final u = List<double>.filled(nd, 0.0);
    if (free.isEmpty) {
      return solveFullNR(model, isTotalLagrangian: false, loadFactor: loadFactor, nSteps: 1);
    }
    final dlam = loadFactor / nSteps;
    final history = <LoadStepRecord>[];
    var state = _assembleNonlinear(model, u, false);

    for (int s = 1; s <= nSteps; s++) {
      final halfDf = [for (final d in free) 0.5 * dlam * model.fRef[d]];
      final duHalf = solveLinearSystem(_subMatrix(state.kt, free), halfDf);
      final uMid = List<double>.from(u);
      for (int i = 0; i < free.length; i++) {
        uMid[free[i]] += duHalf[i];
      }
      final stateMid = _assembleNonlinear(model, uMid, false);
      final fullDf = [for (final d in free) dlam * model.fRef[d]];
      final duFull = solveLinearSystem(_subMatrix(stateMid.kt, free), fullDf);
      for (int i = 0; i < free.length; i++) {
        u[free[i]] += duFull[i];
      }
      state = _assembleNonlinear(model, u, false);
      final lam = s * dlam;
      final resInf = free.fold(0.0, (m, d) => math.max(m, (lam * model.fRef[d] - state.fInt[d]).abs()));
      history.add(LoadStepRecord(
          step: s,
          lambda: lam,
          iterations: 2,
          residualInfN: resInf,
          uMm: List<double>.from(u),
          nForcesN: List<double>.from(state.nForces)));
    }
    final r = [for (int i = 0; i < nd; i++) state.fInt[i] - loadFactor * model.fRef[i]];
    return _buildResult(
      model: model,
      methodName: SolverMethod.rk2Midpoint.label,
      converged: true,
      u: u,
      reactions: r,
      nForces: state.nForces,
      strains: state.strains,
      lengths: state.lengths,
      energies: state.energies,
      loadFactor: loadFactor,
      useDeformedCoords: true,
      totalIterations: 2 * nSteps,
      totalFactorizations: 2 * nSteps,
      history: history,
    );
  }

  /// 8. Truy vết đường cong cân bằng chuyển vị lớn (Snap-Through bằng Displacement Control)
  static List<EquilibriumPoint> traceSnapThroughCurve(TrussModelData model) {
    if (checkKinematicStability(model) != null) return const [];
    final free = model.freeDofs0;
    if (free.isEmpty) return const [];
    int qGlobal = 0;
    double maxF = 0.0;
    for (int i = 0; i < model.fRef.length; i++) {
      if (model.fRef[i].abs() > maxF) {
        maxF = model.fRef[i].abs();
        qGlobal = i;
      }
    }
    final qLocal = free.indexOf(qGlobal);
    if (qLocal < 0 || maxF <= 0) return const [];

    final signDir = model.fRef[qGlobal] >= 0 ? 1.0 : -1.0;
    final targetDisp = signDir *
        (model.name.contains('Von Mises') ? 0.46 * model.baseL : 1.45 * model.baseL);
    const nSteps = 65;
    final duStep = targetDisp / nSteps;

    final u = List<double>.filled(model.nDofs, 0.0);
    double lam = 0.0;
    final pts = <EquilibriumPoint>[
      const EquilibriumPoint(uMainMm: 0, pKn: 0, lambda: 0, n12Kn: 0, isUnstable: false),
    ];

    for (int s = 1; s <= nSteps; s++) {
      var st = _assembleNonlinear(model, u, false);
      final ktff = _subMatrix(st.kt, free);
      final duBar = solveLinearSystem(ktff, _subVec(model.fRef, free));
      if (duBar[qLocal].abs() < 1e-14) break;
      final dlam = duStep / duBar[qLocal];
      lam += dlam;
      for (int i = 0; i < free.length; i++) {
        u[free[i]] += dlam * duBar[i];
      }

      for (int it = 0; it < 20; it++) {
        st = _assembleNonlinear(model, u, false);
        final resF = [for (final d in free) lam * model.fRef[d] - st.fInt[d]];
        final err = resF.fold(0.0, (m, v) => math.max(m, v.abs()));
        if (err < 1e-3) break;
        final kff = _subMatrix(st.kt, free);
        final dBar = solveLinearSystem(kff, _subVec(model.fRef, free));
        final dDbl = solveLinearSystem(kff, resF);
        if (dBar[qLocal].abs() < 1e-14) break;
        final dlCorr = -dDbl[qLocal] / dBar[qLocal];
        lam += dlCorr;
        for (int i = 0; i < free.length; i++) {
          u[free[i]] += dlCorr * dBar[i] + dDbl[i];
        }
      }
      st = _assembleNonlinear(model, u, false);
      final detKt = determinant(_subMatrix(st.kt, free));
      pts.add(EquilibriumPoint(
        uMainMm: u[qGlobal].abs(),
        pKn: lam * maxF / 1000.0,
        lambda: lam,
        n12Kn: st.nForces[0] / 1000.0,
        isUnstable: detKt < 0,
      ));
    }
    return pts;
  }

  /// 9. Khảo sát & Phẫu thuật tại điểm bất kỳ (e, ξ, η, ζ)
  static ProbeInspection probeMember({
    required TrussModelData model,
    required TrussAnalysisResult resultNL,
    required TrussAnalysisResult resultLin,
    required int elemIndex,
    required double xi,
    double etaNorm = 0.0,
    double zetaNorm = 0.0,
    double imperfectionRatio = 0.0,
  }) {
    final e = elemIndex.clamp(0, model.nElems - 1);
    final xiC = xi.clamp(0.0, 1.0);
    final eta = etaNorm.clamp(-1.0, 1.0);
    final zeta = zetaNorm.clamp(-1.0, 1.0);

    final ni = model.conn[e][0] - 1;
    final nj = model.conn[e][1] - 1;
    final x1 = model.coords[ni][0], y1 = model.coords[ni][1];
    final x2 = model.coords[nj][0], y2 = model.coords[nj][1];
    final l0 = math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
    final th0 = math.atan2(y2 - y1, x2 - x1);

    final u1x = resultNL.uMm[2 * ni], u1y = resultNL.uMm[2 * ni + 1];
    final u2x = resultNL.uMm[2 * nj], u2y = resultNL.uMm[2 * nj + 1];
    final dxc = (x2 + u2x) - (x1 + u1x);
    final dyc = (y2 + u2y) - (y1 + u1y);
    final lCur = math.sqrt(dxc * dxc + dyc * dyc);
    final thC = math.atan2(dyc, dxc);
    final dTh = math.atan2(math.sin(thC - th0), math.cos(thC - th0));

    final n1 = 1.0 - xiC, n2 = xiC;
    final x0 = n1 * x1 + n2 * x2;
    final y0 = n1 * y1 + n2 * y2;
    final ux = n1 * u1x + n2 * u2x;
    final uy = n1 * u1y + n2 * u2y;

    final nForce = resultNL.nForcesN[e];
    final sigmaAxial = resultNL.stressMpa[e];
    final dims = model.sectionDimsForElem(e);
    final pEuler = (math.pi * math.pi) * model.E * dims.iMinor / (l0 * l0);

    final yFiber = 0.5 * dims.height * eta;
    final zFiber = 0.5 * dims.width * zeta;
    double sigmaBend = 0.0;
    double daf = 1.0;
    if (imperfectionRatio > 0.0 && nForce.abs() > 1e-6) {
      final e0 = imperfectionRatio * l0;
      if (nForce < 0) {
        final ratio = math.min(0.95, nForce.abs() / math.max(1.0, pEuler));
        daf = 1.0 / (1.0 - ratio);
      } else {
        daf = 1.0 / (1.0 + nForce.abs() / math.max(1.0, pEuler));
      }
      final mSec = nForce.abs() * e0 * daf * math.sin(math.pi * xiC);
      final signB = nForce < 0 ? -1.0 : 1.0;
      sigmaBend = signB * (mSec * yFiber / math.max(1e-9, dims.ix));
    }

    final sigmaXx = sigmaAxial + sigmaBend;
    final epsXx = sigmaXx / model.E;
    final epsPoisson = -model.nu * epsXx;
    final stateLbl = nForce > 1e-3
        ? 'KÉO (Tension)'
        : (nForce < -1e-3 ? 'NÉN (Compression)' : 'KHÔNG LỰC (Zero-force)');

    return ProbeInspection(
      elemIndex: e,
      memberLabel: model.memberLabels[e],
      xi: xiC,
      sMm: xiC * l0,
      l0Mm: l0,
      lCurMm: lCur,
      elongationMm: lCur - l0,
      rotationDeg: dTh * 180.0 / math.pi,
      x0: x0,
      y0: y0,
      xCur: x0 + ux,
      yCur: y0 + uy,
      uxMm: ux,
      uyMm: uy,
      uMagMm: math.sqrt(ux * ux + uy * uy),
      nKn: nForce / 1000.0,
      nLinearKn: resultLin.nForcesN[e] / 1000.0,
      sigmaAxialMpa: sigmaAxial,
      sigmaBendingMpa: sigmaBend,
      sigmaXxMpa: sigmaXx,
      sigmaVonMisesMpa: sigmaXx.abs(),
      tauMaxMohrMpa: 0.5 * sigmaXx.abs(),
      epsXxMicro: epsXx * 1e6,
      epsPoissonMicro: epsPoisson * 1e6,
      energyDensityKjM3: 0.5 * sigmaXx * epsXx * 1000.0,
      daf: daf,
      pEulerLocalKn: pEuler / 1000.0,
      etaNorm: eta,
      zetaNorm: zeta,
      yFiberMm: yFiber,
      zFiberMm: zFiber,
      stateLabel: stateLbl,
      sectionDims: dims,
    );
  }
}

class _AssembledState {
  final List<double> fInt;
  final List<List<double>> kt;
  final List<double> nForces;
  final List<double> strains;
  final List<double> lengths;
  final List<double> energies;
  const _AssembledState(
      this.fInt, this.kt, this.nForces, this.strains, this.lengths, this.energies);
}
