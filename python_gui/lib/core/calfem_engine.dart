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

/// Kiểu mặt cắt ngang 3D của thanh dàn dùng cho mô phỏng 3D & Phẫu thuật
enum SectionShape {
  iSection('Thép chữ I (H-Beam)', 'I_SECTION'),
  circTube('Ống thép tròn rỗng', 'CIRC_TUBE'),
  boxSection('Thép hộp vuông rỗng', 'BOX_SECTION'),
  solidRod('Thanh thép tròn đặc', 'SOLID_ROD');

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

/// Kích thước hình học mặt cắt ngang 3D quy đổi từ diện tích A (mm²)
class SectionDimensions {
  final double height;
  final double width;
  final double tf;
  final double tw;
  final double radiusOut;
  final double radiusIn;
  final double iMajor;
  final double iMinor;

  const SectionDimensions({
    required this.height,
    required this.width,
    this.tf = 0,
    this.tw = 0,
    this.radiusOut = 0,
    this.radiusIn = 0,
    required this.iMajor,
    required this.iMinor,
  });

  static SectionDimensions fromArea(SectionShape shape, double areaMm2) {
    final double a = math.max(1.0, areaMm2);
    switch (shape) {
      case SectionShape.solidRod:
        final r = math.sqrt(a / math.pi);
        final inertia = 0.25 * math.pi * math.pow(r, 4);
        return SectionDimensions(
          height: 2 * r,
          width: 2 * r,
          radiusOut: r,
          radiusIn: 0,
          iMajor: inertia.toDouble(),
          iMinor: inertia.toDouble(),
        );
      case SectionShape.circTube:
        const alpha = 0.85;
        final r = math.sqrt(a / (math.pi * (1.0 - alpha * alpha)));
        final rin = alpha * r;
        final inertia = 0.25 * math.pi * (math.pow(r, 4) - math.pow(rin, 4));
        return SectionDimensions(
          height: 2 * r,
          width: 2 * r,
          radiusOut: r,
          radiusIn: rin,
          tf: r - rin,
          iMajor: inertia.toDouble(),
          iMinor: inertia.toDouble(),
        );
      case SectionShape.boxSection:
        const cin = 0.76;
        final h = math.sqrt(a / (1.0 - cin * cin));
        final t = 0.12 * h;
        final inertia = (math.pow(h, 4) - math.pow(cin * h, 4)) / 12.0;
        return SectionDimensions(
          height: h,
          width: h,
          tf: t,
          tw: t,
          iMajor: inertia.toDouble(),
          iMinor: inertia.toDouble(),
        );
      case SectionShape.iSection:
        const coeff = 2.0 * 0.85 * 0.12 + 0.76 * 0.08;
        final h = math.sqrt(a / coeff);
        final b = 0.85 * h;
        final tf = 0.12 * h;
        final tw = 0.08 * h;
        final hw = h - 2.0 * tf;
        final iMaj = (b * math.pow(h, 3) - (b - tw) * math.pow(hw, 3)) / 12.0;
        final iMin = (2.0 * tf * math.pow(b, 3) + hw * math.pow(tw, 3)) / 12.0;
        return SectionDimensions(
          height: h,
          width: b,
          tf: tf,
          tw: tw,
          iMajor: iMaj.toDouble(),
          iMinor: iMin.toDouble(),
        );
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
  final List<int> fixedDofs0;      // Chỉ số DOF bị khóa (0-based)
  final List<double> fRef;         // Véc-tơ tải trọng tham chiếu (N)
  final List<String> memberLabels;
  final List<String> nodeLabels;
  final SectionShape sectionShape;
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
    required this.fRef,
    required this.memberLabels,
    required this.nodeLabels,
    required this.sectionShape,
    required this.baseL,
    required this.baseA,
    required this.basePKn,
  });

  int get nNodes => coords.length;
  int get nElems => conn.length;
  int get nDofs => 2 * nNodes;

  List<int> get freeDofs0 {
    final fixed = fixedDofs0.toSet();
    return [
      for (int i = 0; i < nDofs; i++)
        if (!fixed.contains(i)) i,
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
  }) {
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
          fixedDofs0: const [0, 1, 2, 3],
          fRef: const [0.0, 0.0, 0.0, 0.0, -10.0e6, -0.2e6],
          memberLabels: const ['1-3 (AB)', '2-3 (CB)'],
          nodeLabels: const ['Nút 1 (A)', 'Nút 2 (C)', 'Nút 3 (B)'],
          sectionShape: sectionShape,
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
          fixedDofs0: const [0, 1, 2, 3, 6, 7],
          fRef: const [0.0, 0.0, 0.0, 0.0, 0.0, -80000.0, 0.0, 0.0],
          memberLabels: const ['1-3', '3-4', '2-3'],
          nodeLabels: const ['Nút 1', 'Nút 2', 'Nút 3 (Tải P)', 'Nút 4'],
          sectionShape: sectionShape,
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
          areas: [aMm2, aMm2],
          E: eMpa,
          nu: nu,
          fyRef: 250.0,
          fixedDofs0: const [0, 1, 4, 5],
          fRef: [0.0, 0.0, 0.0, -pKn * 1000.0, 0.0, 0.0],
          memberLabels: const ['1-2', '2-3'],
          nodeLabels: const ['Nút 1 (Gối trái)', 'Nút 2 (Đỉnh vòm)', 'Nút 3 (Gối phải)'],
          sectionShape: sectionShape,
          baseL: lMm,
          baseA: aMm2,
          basePKn: pKn,
        );
      case TrussPreset.assignment5Bar:
        final diagA = 2.0 * math.sqrt(2.0) * aMm2;
        return TrussModelData(
          name: 'Dàn 4 nút – 5 thanh (Đề bài 1.jpg)',
          description:
              'L=${lMm.toStringAsFixed(0)} mm, E=${(eMpa / 1000).toStringAsFixed(0)} GPa, '
              'A=${aMm2.toStringAsFixed(0)} mm², P=${pKn.toStringAsFixed(1)} kN hướng lên (+Y)',
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
          areas: [aMm2, aMm2, aMm2, diagA, diagA],
          E: eMpa,
          nu: nu,
          fyRef: 250.0,
          fixedDofs0: const [0, 1, 7],
          fRef: [0.0, 0.0, 0.0, pKn * 1000.0, 0.0, 0.0, 0.0, 0.0],
          memberLabels: const ['1-2', '1-3', '3-4', '3-2', '2-4'],
          nodeLabels: const [
            'Nút 1 (Khớp cố định)',
            'Nút 2 (Tải P)',
            'Nút 3 (Tự do)',
            'Nút 4 (Con lăn trên)',
          ],
          sectionShape: sectionShape,
          baseL: lMm,
          baseA: aMm2,
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
    return _AssembledState(fInt, kt, nForces, strains, lengths, energies);
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
  }) {
    final ne = model.nElems;
    final stress = [for (int e = 0; e < ne; e++) nForces[e] / model.areas[e]];
    final elong = [for (int e = 0; e < ne; e++) lengths[e] - model.initialLength(e)];
    final totalU = energies.fold(0.0, (a, b) => a + b);

    double sfx = 0.0, sfy = 0.0, sm = 0.0;
    for (int i = 0; i < model.nNodes; i++) {
      final fx = loadFactor * model.fRef[2 * i] + reactions[2 * i];
      final fy = loadFactor * model.fRef[2 * i + 1] + reactions[2 * i + 1];
      final x = model.coords[i][0] + (useDeformedCoords ? u[2 * i] : 0.0);
      final y = model.coords[i][1] + (useDeformedCoords ? u[2 * i + 1] : 0.0);
      sfx += fx;
      sfy += fy;
      sm += x * fy - y * fx;
    }
    double maxFreeRes = 0.0;
    for (final d in model.freeDofs0) {
      maxFreeRes = math.max(maxFreeRes, reactions[d].abs());
    }

    return TrussAnalysisResult(
      methodName: methodName,
      engineSource: 'Python CALFEM Engine (Offline 100%)',
      converged: converged,
      uMm: u,
      reactionsN: reactions,
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
    final f = [for (final v in model.fRef) v * loadFactor];
    final uf = solveLinearSystem(_subMatrix(K, free), _subVec(f, free));
    final u = List<double>.filled(nd, 0.0);
    for (int i = 0; i < free.length; i++) {
      u[free[i]] = uf[i];
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
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final f = [for (final v in model.fRef) v * loadFactor];
    var nCur = List<double>.filled(model.nElems, 0.0);
    var u = List<double>.filled(nd, 0.0);
    var K = _zeros(nd);
    bool converged = false;
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
      final uf = solveLinearSystem(_subMatrix(K, free), _subVec(f, free));
      u = List<double>.filled(nd, 0.0);
      for (int i = 0; i < free.length; i++) {
        u[free[i]] = uf[i];
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
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final u = List<double>.filled(nd, 0.0);
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
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final u = List<double>.filled(nd, 0.0);
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
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final u = List<double>.filled(nd, 0.0);
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
    final nd = model.nDofs;
    final free = model.freeDofs0;
    final u = List<double>.filled(nd, 0.0);
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
    final free = model.freeDofs0;
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
    final dims = SectionDimensions.fromArea(model.sectionShape, model.areas[e]);
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
      sigmaBend = signB * (mSec * yFiber / math.max(1e-9, dims.iMajor));
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
