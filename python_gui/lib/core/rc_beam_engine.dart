// ============================================================================
// LÕI TÍNH TOÁN PHI TUYẾN VẬT LIỆU DẦM BÊ TÔNG CỐT THÉP (PHƯƠNG PHÁP THỚ)
// ============================================================================
// Áp dụng cho Mục 1. Mô hình kết cấu & Bộ giải CALFEM:
//   • Dầm BTCT đơn giản (tỷ lệ nhịp/chiều cao L/h khuyến nghị 5..10), tùy biến
//     gối trái/phải (Khớp cố định, Gối di động, Ngàm, Lò xo, Tự do).
//   • Tải 3 điểm (2 phản lực + 1 lực Q tại khoảng cách a, mặc định a = L/2 → M = QL/4)
//     và Tải 4 điểm (2 phản lực + 2 lực Q/2 tại x = a và x = L - a).
//   • Phương pháp Thớ (Fiber Section): chia bê tông thành n_fib dải nhỏ, cốt thép
//     chịu kéo As, nén As' và tùy chọn Cốt cứng thép hình I đặt đúng trọng tâm.
//   • Thiết lập PTHH theo phương pháp Rayleigh-Ritz (năng lượng biến dạng Π = U - W
//     → điều kiện dừng δΠ = 0 → tuyến tính hóa [K_t]{Δd} = {ΔF}), tích phân
//     Gauss-Legendre 3 điểm xác định EA, ES, EI, trục trung hòa x_NA, ma trận
//     độ cứng 6×6, quan hệ nội lực - chuyển vị phần tử & khảo sát hội tụ lưới!
// ============================================================================

import 'dart:math' as math;
import 'calfem_engine.dart';

/// Loại gối tựa cho hai đầu dầm BTCT (3 DOF: u, v, θ)
enum BeamSupportType {
  pin('Khớp cố định (Pin: u=0, v=0)', 'Khớp cố định', 'pin'),
  roller('Gối di động (Roller: v=0)', 'Gối di động', 'roller'),
  fixed('Ngàm cứng (Fixed: u=v=θ=0)', 'Ngàm cứng', 'fixed'),
  spring('Gối lò xo đàn hồi (kv, kθ)', 'Lò xo', 'spring'),
  free('Đầu tự do (Free / Công-xôn)', 'Tự do', 'free');

  final String label;
  final String shortLabel;
  final String code;
  const BeamSupportType(this.label, this.shortLabel, this.code);

  bool get locksU => this == pin || this == fixed;
  bool get locksV => this == pin || this == roller || this == fixed;
  bool get locksTheta => this == fixed;
}

/// Sơ đồ chất tải dầm BTCT
enum RcBeamLoadType {
  threePoint('Uốn 3 điểm (2 gối + 1 lực Q tại a)', '3 điểm', '3pt'),
  fourPoint('Uốn 4 điểm (2 gối + 2 lực Q/2 tại a & L−a)', '4 điểm', '4pt');

  final String label;
  final String shortLabel;
  final String code;
  const RcBeamLoadType(this.label, this.shortLabel, this.code);
}

/// Trường màu hiển thị trên dầm BTCT 2D/3D
enum RcBeamContourField {
  bendingMoment('Mô-men uốn M (kN·m)', 'kN·m', 'M'),
  deflection('Độ võng đứng |v| (mm)', 'mm', '|v|'),
  curvature('Độ cong κ (10⁻⁶/mm)', '10⁻⁶/mm', 'κ'),
  concreteCompStress('Ứng suất nén bê tông mép trên σ_c (MPa)', 'MPa', 'σc'),
  rebarStress('Ứng suất cốt thép kéo σ_s (MPa)', 'MPa', 'σs'),
  stiffnessRatio('Tỷ lệ độ cứng uốn EI_eff / EI₀ (%)', '%', 'EI%');

  final String label;
  final String unit;
  final String symbol;
  const RcBeamContourField(this.label, this.unit, this.symbol);

  String formatValue(double v) {
    if (this == stiffnessRatio) return '${v.toStringAsFixed(1)}%';
    if (this == deflection) return '${v.toStringAsFixed(2)} mm';
    if (this == curvature) return '${v.toStringAsFixed(2)}×10⁻⁶';
    return '${v.toStringAsFixed(1)} $unit';
  }
}

/// Tham số mô hình Dầm Bê tông Cốt thép (nhập hoàn toàn từ giao diện)
class RcBeamConfig {
  final double spanMm;           // Nhịp dầm L (mm)
  final double widthMm;          // Bề rộng b (mm)
  final double heightMm;         // Chiều cao h (mm)
  final double asBotMm2;         // Diện tích cốt thép chịu kéo đáy As (mm²)
  final double asTopMm2;         // Diện tích cốt thép chịu nén đỉnh As' (mm²)
  final double coverBotMm;       // Trọng tâm cốt thép kéo tới mép dưới a_s (mm)
  final double coverTopMm;       // Trọng tâm cốt thép nén tới mép trên a_s' (mm)
  // Tùy chọn dầm cốt cứng (thép hình chữ I đặt lõi dầm BTCT)
  final bool hasRigidCore;
  final double coreHMm;
  final double coreBMm;
  final double coreTfMm;
  final double coreTwMm;
  final double coreFyMpa;
  // Vật liệu bê tông
  final double fcMpa;            // Cường độ chịu nén f'c (MPa)
  final double ecMpa;            // Mô-đun đàn hồi bê tông Ec (MPa)
  final double fctMpa;           // Cường độ chịu kéo nứt fct (MPa)
  final double epsC0;            // Biến dạng đỉnh nén ε_c0
  final double epsCu;            // Biến dạng giới hạn vỡ nén ε_cu
  // Vật liệu cốt thép
  final double fyMpa;            // Giới hạn chảy cốt thép fy (MPa)
  final double esMpa;            // Mô-đun đàn hồi thép Es (MPa)
  final double hardeningRatio;   // Tỷ số tái bền E_sh / Es
  // Sơ đồ tải & liên kết hai đầu
  final RcBeamLoadType loadType;
  final double loadQKn;          // Tổng ngoại lực Q (kN)
  final double loadAMm;          // Khoảng cách lực cách gối trái a (mm)
  final BeamSupportType leftSupport;
  final BeamSupportType rightSupport;
  final double springKvKnMm;
  final double springKthKnmRad;
  // Tham số chia lưới PTHH & Thớ
  final int nElems;              // Số phần tử (chẵn để chia 2 nửa đối xứng)
  final int nFibers;             // Số thớ bê tông
  final int nSteps;              // Số bước gia tải
  final bool nonlinearMaterial;  // Bật/tắt phi tuyến vật liệu

  const RcBeamConfig({
    this.spanMm = 4000.0,
    this.widthMm = 250.0,
    this.heightMm = 500.0,
    this.asBotMm2 = 942.5,       // 3Ø20
    this.asTopMm2 = 402.1,       // 2Ø16
    this.coverBotMm = 40.0,
    this.coverTopMm = 40.0,
    this.hasRigidCore = false,
    this.coreHMm = 240.0,
    this.coreBMm = 120.0,
    this.coreTfMm = 10.0,
    this.coreTwMm = 7.0,
    this.coreFyMpa = 275.0,
    this.fcMpa = 30.0,
    this.ecMpa = 32500.0,
    this.fctMpa = 2.9,
    this.epsC0 = 0.0020,
    this.epsCu = 0.0035,
    this.fyMpa = 400.0,
    this.esMpa = 200000.0,
    this.hardeningRatio = 0.01,
    this.loadType = RcBeamLoadType.threePoint,
    this.loadQKn = 120.0,
    this.loadAMm = 2000.0,
    this.leftSupport = BeamSupportType.pin,
    this.rightSupport = BeamSupportType.roller,
    this.springKvKnMm = 200.0,
    this.springKthKnmRad = 50000.0,
    this.nElems = 8,
    this.nFibers = 40,
    this.nSteps = 12,
    this.nonlinearMaterial = true,
  });

  double get spanToDepthRatio => spanMm / math.max(1.0, heightMm);
  double get effectiveDepthMm => math.max(20.0, heightMm - coverBotMm);
  double get steelRatioPct => 100.0 * asBotMm2 / math.max(1.0, widthMm * effectiveDepthMm);

  /// Khoảng cách hợp lệ a (mm) theo loại tải 3 điểm / 4 điểm
  double get effectiveAMm {
    if (loadType == RcBeamLoadType.threePoint) {
      return loadAMm.clamp(0.05 * spanMm, 0.95 * spanMm);
    }
    return loadAMm.clamp(0.05 * spanMm, 0.49 * spanMm);
  }

  /// Mô-men uốn giải tích cực đại của dầm đơn giản (kN·m)
  double get simpleBeamMaxMomentKnm {
    final a = effectiveAMm;
    if (loadType == RcBeamLoadType.threePoint) {
      return loadQKn * a * (spanMm - a) / (spanMm * 1000.0);
    }
    return 0.5 * loadQKn * a / 1000.0;
  }

  /// Công thức mô-men lý thuyết hiển thị trực quan
  String get momentFormulaLabel {
    final a = effectiveAMm;
    if (loadType == RcBeamLoadType.threePoint) {
      if ((a - 0.5 * spanMm).abs() < 1.0) {
        return 'M_max = Q·L / 4 = ${simpleBeamMaxMomentKnm.toStringAsFixed(2)} kN·m';
      }
      return 'M_max = Q·a(L−a)/L = ${simpleBeamMaxMomentKnm.toStringAsFixed(2)} kN·m';
    }
    return 'M_max = (Q/2)·a = ${simpleBeamMaxMomentKnm.toStringAsFixed(2)} kN·m (QL/4 = ${(loadQKn * spanMm / 4000.0).toStringAsFixed(1)})';
  }

  RcBeamConfig copyWith({
    double? spanMm,
    double? widthMm,
    double? heightMm,
    double? asBotMm2,
    double? asTopMm2,
    double? coverBotMm,
    double? coverTopMm,
    bool? hasRigidCore,
    double? coreHMm,
    double? coreBMm,
    double? coreTfMm,
    double? coreTwMm,
    double? coreFyMpa,
    double? fcMpa,
    double? ecMpa,
    double? fctMpa,
    double? epsC0,
    double? epsCu,
    double? fyMpa,
    double? esMpa,
    double? hardeningRatio,
    RcBeamLoadType? loadType,
    double? loadQKn,
    double? loadAMm,
    BeamSupportType? leftSupport,
    BeamSupportType? rightSupport,
    double? springKvKnMm,
    double? springKthKnmRad,
    int? nElems,
    int? nFibers,
    int? nSteps,
    bool? nonlinearMaterial,
  }) {
    return RcBeamConfig(
      spanMm: spanMm ?? this.spanMm,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      asBotMm2: asBotMm2 ?? this.asBotMm2,
      asTopMm2: asTopMm2 ?? this.asTopMm2,
      coverBotMm: coverBotMm ?? this.coverBotMm,
      coverTopMm: coverTopMm ?? this.coverTopMm,
      hasRigidCore: hasRigidCore ?? this.hasRigidCore,
      coreHMm: coreHMm ?? this.coreHMm,
      coreBMm: coreBMm ?? this.coreBMm,
      coreTfMm: coreTfMm ?? this.coreTfMm,
      coreTwMm: coreTwMm ?? this.coreTwMm,
      coreFyMpa: coreFyMpa ?? this.coreFyMpa,
      fcMpa: fcMpa ?? this.fcMpa,
      ecMpa: ecMpa ?? this.ecMpa,
      fctMpa: fctMpa ?? this.fctMpa,
      epsC0: epsC0 ?? this.epsC0,
      epsCu: epsCu ?? this.epsCu,
      fyMpa: fyMpa ?? this.fyMpa,
      esMpa: esMpa ?? this.esMpa,
      hardeningRatio: hardeningRatio ?? this.hardeningRatio,
      loadType: loadType ?? this.loadType,
      loadQKn: loadQKn ?? this.loadQKn,
      loadAMm: loadAMm ?? this.loadAMm,
      leftSupport: leftSupport ?? this.leftSupport,
      rightSupport: rightSupport ?? this.rightSupport,
      springKvKnMm: springKvKnMm ?? this.springKvKnMm,
      springKthKnmRad: springKthKnmRad ?? this.springKthKnmRad,
      nElems: nElems ?? this.nElems,
      nFibers: nFibers ?? this.nFibers,
      nSteps: nSteps ?? this.nSteps,
      nonlinearMaterial: nonlinearMaterial ?? this.nonlinearMaterial,
    );
  }
}

/// Một thớ vật liệu trong mặt cắt dầm BTCT
class BeamFiberSpec {
  final double yMm;        // Tọa độ trọng tâm thớ y ∈ [-h/2, +h/2] (mm)
  final double heightMm;   // Bề dày thớ dy (mm)
  final double widthMm;    // Bề rộng thớ (mm)
  final double areaMm2;    // Diện tích thớ A_i (mm²)
  final String kind;       // 'concrete', 'rebar_bot', 'rebar_top', 'core'
  final double fyMpa;      // Giới hạn chảy nếu là thép / cốt cứng

  const BeamFiberSpec({
    required this.yMm,
    required this.heightMm,
    required this.widthMm,
    required this.areaMm2,
    required this.kind,
    this.fyMpa = 0.0,
  });
}

/// Trạng thái cơ học tức thời của một thớ tại lát cắt khảo sát
class FiberResponseState {
  final BeamFiberSpec spec;
  final double strain;
  final double stressMpa;
  final double tangentMpa;
  final String status;     // 'Đàn hồi nén', 'Phi tuyến nén', 'Vỡ nén', 'Kéo chưa nứt', 'Nứt kéo', 'Cốt thép chảy dẻo'...
  final bool isCracked;
  final bool isCrushed;
  final bool isYielded;

  const FiberResponseState({
    required this.spec,
    required this.strain,
    required this.stressMpa,
    required this.tangentMpa,
    required this.status,
    required this.isCracked,
    required this.isCrushed,
    required this.isYielded,
  });
}

/// Trạng thái toàn mặt cắt tại tọa độ x (EA, ES, EI, Trục trung hòa, ứng suất thớ)
class RcSectionState {
  final double xMm;
  final double eps0;
  final double kappa;        // 1/mm
  final double nForceN;      // N
  final double mForceNmm;    // N·mm
  final double eaTangentN;   // N
  final double esTangentNmm; // N·mm
  final double eiTangentNmm2;// N·mm²
  final double eiEffNmm2;    // N·mm² (độ cứng uốn hiệu dụng quanh trục trung hòa)
  final double yNeutralMm;   // Tọa độ trục trung hòa y_NA (mm)
  final double xNeutralDepthMm; // Chiều cao vùng nén tính từ mép trên x_NA = h/2 - y_NA (mm)
  final double crackDepthMm; // Chiều sâu vết nứt tính từ mép dưới (mm)
  final double sigmaTopConcMpa;
  final double sigmaBotSteelMpa;
  final double sigmaTopSteelMpa;
  final bool hasCracked;
  final bool steelYielded;
  final bool concreteCrushed;
  final List<FiberResponseState> fibers;

  const RcSectionState({
    required this.xMm,
    required this.eps0,
    required this.kappa,
    required this.nForceN,
    required this.mForceNmm,
    required this.eaTangentN,
    required this.esTangentNmm,
    required this.eiTangentNmm2,
    required this.eiEffNmm2,
    required this.yNeutralMm,
    required this.xNeutralDepthMm,
    required this.crackDepthMm,
    required this.sigmaTopConcMpa,
    required this.sigmaBotSteelMpa,
    required this.sigmaTopSteelMpa,
    required this.hasCracked,
    required this.steelYielded,
    required this.concreteCrushed,
    required this.fibers,
  });
}

/// Kết quả chi tiết của từng phần tử dầm 2 nút (6 DOF)
class RcBeamElementResult {
  final int elemIndex;
  final double x1Mm;
  final double x2Mm;
  final double lengthMm;
  final List<double> dElem;       // [u1, v1, θ1, u2, v2, θ2]
  final List<double> fEndElem;    // [N1, V1, M1, N2, V2, M2] (N, N·mm)
  final List<List<double>> kt6x6; // Ma trận độ cứng tiếp tuyến 6×6
  final List<RcSectionState> gaussSections; // 3 điểm Gauss
  final RcSectionState midSection;          // Mặt cắt giữa phần tử

  const RcBeamElementResult({
    required this.elemIndex,
    required this.x1Mm,
    required this.x2Mm,
    required this.lengthMm,
    required this.dElem,
    required this.fEndElem,
    required this.kt6x6,
    required this.gaussSections,
    required this.midSection,
  });

  double get m1Knm => -fEndElem[2] / 1e6; // Mô-men uốn mặt cắt đầu trái (dương = căng thớ dưới)
  double get m2Knm => fEndElem[5] / 1e6;  // Mô-men uốn mặt cắt đầu phải
  double get vShearKn => fEndElem[1] / 1000.0;
}

/// Một điểm trên đường cong Tải – Độ võng (P-Δ)
class RcLoadDeflectionPoint {
  final double loadQKn;
  final double deflectionMidMm;
  final double mMaxKnm;
  final double xNeutralMm;
  final double eiRatioPct;
  final bool cracked;
  final bool yielded;
  final bool crushed;

  const RcLoadDeflectionPoint({
    required this.loadQKn,
    required this.deflectionMidMm,
    required this.mMaxKnm,
    required this.xNeutralMm,
    required this.eiRatioPct,
    required this.cracked,
    required this.yielded,
    required this.crushed,
  });
}

/// Một điểm trên đường cong Mô-men – Độ cong (M-κ)
class RcMomentCurvaturePoint {
  final double kappaPerMm;
  final double momentKnm;
  final double xNeutralMm;
  final double eiEffNmm2;
  final bool cracked;
  final bool yielded;
  final bool crushed;

  const RcMomentCurvaturePoint({
    required this.kappaPerMm,
    required this.momentKnm,
    required this.xNeutralMm,
    required this.eiEffNmm2,
    required this.cracked,
    required this.yielded,
    required this.crushed,
  });
}

/// Một dòng kết quả khảo sát hội tụ lưới PTHH (nElem = 2, 4, 8, 16, 32)
class RcMeshConvergencePoint {
  final int nElems;
  final int nNodes;
  final double vMidMm;
  final double mMaxKnm;
  final double xNeutralMm;
  final double eiRatioPct;
  final double relErrorPct;
  final int iterations;

  const RcMeshConvergencePoint({
    required this.nElems,
    required this.nNodes,
    required this.vMidMm,
    required this.mMaxKnm,
    required this.xNeutralMm,
    required this.eiRatioPct,
    required this.relErrorPct,
    required this.iterations,
  });
}

/// Kết quả phân tích tổng thể Dầm BTCT
class RcBeamAnalysisResult {
  final RcBeamConfig config;
  final String methodName;
  final bool converged;
  final String? warningMessage;
  final List<double> xNodesMm;
  final List<double> dGlobal;      // 3 * nNodes: [u, v, θ, ...]
  final List<double> reactions;    // 3 * nNodes: [Rx, Ry, Mr, ...] (N, N·mm)
  final List<double> fExt;         // 3 * nNodes
  final List<RcBeamElementResult> elements;
  final double eiGrossNmm2;        // Độ cứng uốn ban đầu nguyên vẹn EI₀ (N·mm²)
  final double eaGrossN;           // Độ cứng kéo nén ban đầu EA₀ (N)
  final double vMidMm;             // Độ võng tại giữa dầm (âm = võng xuống)
  final double maxAbsDeflectionMm;
  final double mMaxKnm;
  final double vMaxKn;
  final double rLeftKn;
  final double rRightKn;
  final double sumFyN;
  final double maxFreeResidualN;
  final int totalIterations;
  final List<double> iterResidualsN;
  final bool hasCracking;
  final bool hasYielding;
  final bool hasCrushing;

  const RcBeamAnalysisResult({
    required this.config,
    required this.methodName,
    required this.converged,
    this.warningMessage,
    required this.xNodesMm,
    required this.dGlobal,
    required this.reactions,
    required this.fExt,
    required this.elements,
    required this.eiGrossNmm2,
    required this.eaGrossN,
    required this.vMidMm,
    required this.maxAbsDeflectionMm,
    required this.mMaxKnm,
    required this.vMaxKn,
    required this.rLeftKn,
    required this.rRightKn,
    required this.sumFyN,
    required this.maxFreeResidualN,
    required this.totalIterations,
    required this.iterResidualsN,
    required this.hasCracking,
    required this.hasYielding,
    required this.hasCrushing,
  });

  int get nNodes => xNodesMm.length;
  int get nElems => elements.length;
}

/// Bộ giải PTHH Phi tuyến Vật liệu Dầm BTCT (Phương pháp Thớ + Rayleigh-Ritz)
class RcBeamFiberEngine {
  static const List<double> _gpXi = [
    0.11270166537925831, // 0.5*(1 - sqrt(3/5))
    0.5,
    0.8872983346207417,  // 0.5*(1 + sqrt(3/5))
  ];
  static const List<double> _gpW = [
    5.0 / 18.0,
    8.0 / 18.0,
    5.0 / 18.0,
  ];

  /// 1. Xây dựng danh sách thớ mặt cắt (bê tông chia n_fib dải + cốt thép + tùy chọn cốt cứng I)
  static List<BeamFiberSpec> buildFibers(RcBeamConfig cfg) {
    final fibers = <BeamFiberSpec>[];
    final nf = cfg.nFibers.clamp(6, 120);
    final dy = cfg.heightMm / nf;
    for (int k = 0; k < nf; k++) {
      final yk = -0.5 * cfg.heightMm + (k + 0.5) * dy;
      fibers.add(BeamFiberSpec(
        yMm: yk,
        heightMm: dy,
        widthMm: cfg.widthMm,
        areaMm2: cfg.widthMm * dy,
        kind: 'concrete',
      ));
    }
    if (cfg.asBotMm2 > 1e-3) {
      final yBot = -0.5 * cfg.heightMm + cfg.coverBotMm.clamp(10.0, 0.45 * cfg.heightMm);
      fibers.add(BeamFiberSpec(
        yMm: yBot,
        heightMm: 16.0,
        widthMm: cfg.asBotMm2 / 16.0,
        areaMm2: cfg.asBotMm2,
        kind: 'rebar_bot',
        fyMpa: cfg.fyMpa,
      ));
    }
    if (cfg.asTopMm2 > 1e-3) {
      final yTop = 0.5 * cfg.heightMm - cfg.coverTopMm.clamp(10.0, 0.45 * cfg.heightMm);
      fibers.add(BeamFiberSpec(
        yMm: yTop,
        heightMm: 14.0,
        widthMm: cfg.asTopMm2 / 14.0,
        areaMm2: cfg.asTopMm2,
        kind: 'rebar_top',
        fyMpa: cfg.fyMpa,
      ));
    }
    if (cfg.hasRigidCore && cfg.coreHMm > 20.0 && cfg.coreBMm > 10.0) {
      final ch = cfg.coreHMm.clamp(30.0, cfg.heightMm - 40.0);
      final cb = cfg.coreBMm.clamp(20.0, cfg.widthMm - 20.0);
      final tf = cfg.coreTfMm.clamp(3.0, 0.35 * ch);
      final tw = cfg.coreTwMm.clamp(3.0, cb);
      final hh = 0.5 * ch;
      fibers.add(BeamFiberSpec(
        yMm: -hh + 0.5 * tf,
        heightMm: tf,
        widthMm: cb,
        areaMm2: cb * tf,
        kind: 'core',
        fyMpa: cfg.coreFyMpa,
      ));
      fibers.add(BeamFiberSpec(
        yMm: hh - 0.5 * tf,
        heightMm: tf,
        widthMm: cb,
        areaMm2: cb * tf,
        kind: 'core',
        fyMpa: cfg.coreFyMpa,
      ));
      final hw = ch - 2.0 * tf;
      if (hw > 2.0) {
        const nw = 6;
        final dw = hw / nw;
        for (int j = 0; j < nw; j++) {
          fibers.add(BeamFiberSpec(
            yMm: -0.5 * hw + (j + 0.5) * dw,
            heightMm: dw,
            widthMm: tw,
            areaMm2: tw * dw,
            kind: 'core',
            fyMpa: cfg.coreFyMpa,
          ));
        }
      }
    }
    return fibers;
  }

  /// 2. Định luật ứng suất – biến dạng bê tông (Hognestad nén + nứt kéo tension stiffening)
  static ({double sig, double et, String status, bool cracked, bool crushed}) concreteLaw(
    double eps,
    RcBeamConfig cfg,
    bool nonlinear,
  ) {
    if (!nonlinear) {
      return (
        sig: cfg.ecMpa * eps,
        et: cfg.ecMpa,
        status: eps < 0 ? 'Nén ĐH' : 'Kéo ĐH',
        cracked: false,
        crushed: false,
      );
    }
    if (eps <= 0.0) {
      final ec = -eps;
      final e0 = math.max(1e-4, cfg.epsC0);
      final eu = math.max(e0 + 5e-4, cfg.epsCu);
      if (ec <= e0) {
        final r = ec / e0;
        final sig = -cfg.fcMpa * (2.0 * r - r * r);
        final et = math.max(0.005 * cfg.ecMpa, (2.0 * cfg.fcMpa / e0) * (1.0 - r));
        return (
          sig: sig,
          et: et,
          status: r < 0.4 ? 'Đàn hồi nén' : 'Phi tuyến nén',
          cracked: false,
          crushed: false,
        );
      }
      if (ec <= eu) {
        final frac = (ec - e0) / (eu - e0);
        final sig = -cfg.fcMpa * (1.0 - 0.15 * frac);
        return (
          sig: sig,
          et: 0.004 * cfg.ecMpa,
          status: 'Nén tiệm cận vỡ',
          cracked: false,
          crushed: false,
        );
      }
      return (
        sig: -0.20 * cfg.fcMpa,
        et: 0.002 * cfg.ecMpa,
        status: 'Vỡ ép bê tông',
        cracked: false,
        crushed: true,
      );
    }
    // Miền kéo bê tông (mềm hóa hàm mũ mượt Tension Stiffening + mô-đun tiếp tuyến nhất quán chính xác!)
    final epsCr = cfg.fctMpa / math.max(1.0, cfg.ecMpa);
    if (eps <= epsCr) {
      return (
        sig: cfg.ecMpa * eps,
        et: cfg.ecMpa,
        status: 'Kéo chưa nứt',
        cracked: false,
        crushed: false,
      );
    }
    final ratio = (eps - epsCr) / math.max(1e-8, epsCr);
    final sig = cfg.fctMpa * math.exp(-0.35 * ratio);
    final etExact = -0.35 * sig / math.max(1e-8, epsCr);
    return (
      sig: sig,
      et: etExact,
      status: sig > 0.08 * cfg.fctMpa ? 'Nứt kéo (mềm hóa)' : 'Nứt hoàn toàn',
      cracked: true,
      crushed: false,
    );
  }

  /// 3. Định luật ứng suất – biến dạng cốt thép & cốt cứng (đàn-dẻo song tuyến)
  static ({double sig, double et, String status, bool yielded}) steelLaw(
    double eps,
    double esMpa,
    double fyMpa,
    double hardeningRatio,
    bool nonlinear,
  ) {
    if (!nonlinear) {
      return (sig: esMpa * eps, et: esMpa, status: 'Thép đàn hồi', yielded: false);
    }
    final ey = fyMpa / math.max(1.0, esMpa);
    final etH = math.max(0.001, hardeningRatio) * esMpa;
    if (eps.abs() <= ey) {
      return (sig: esMpa * eps, et: esMpa, status: 'Thép đàn hồi', yielded: false);
    }
    final sgn = eps >= 0.0 ? 1.0 : -1.0;
    final sig = sgn * (fyMpa + etH * (eps.abs() - ey));
    return (sig: sig, et: etH, status: 'Thép chảy dẻo', yielded: true);
  }

  /// 4. Đánh giá toàn bộ mặt cắt tại tọa độ x từ (ε₀, κ)
  static RcSectionState evaluateSection({
    required double xMm,
    required double eps0,
    required double kappa,
    required List<BeamFiberSpec> fibers,
    required RcBeamConfig cfg,
    required bool nonlinear,
  }) {
    double nVal = 0.0, mVal = 0.0;
    double eaT = 0.0, esT = 0.0, eiT = 0.0;
    double sigTopConc = 0.0, sigBotSteel = 0.0, sigTopSteel = 0.0;
    bool hasCracked = false, steelYielded = false, concCrushed = false;
    double maxCrackY = -0.5 * cfg.heightMm;

    final states = <FiberResponseState>[];
    for (final f in fibers) {
      final eps = eps0 - f.yMm * kappa;
      if (f.kind == 'concrete') {
        final c = concreteLaw(eps, cfg, nonlinear);
        nVal += c.sig * f.areaMm2;
        mVal -= c.sig * f.yMm * f.areaMm2;
        eaT += c.et * f.areaMm2;
        esT -= c.et * f.yMm * f.areaMm2;
        eiT += c.et * f.yMm * f.yMm * f.areaMm2;
        if (c.cracked) {
          hasCracked = true;
          final topEdge = f.yMm + 0.5 * f.heightMm;
          if (topEdge > maxCrackY) maxCrackY = topEdge;
        }
        if (c.crushed) concCrushed = true;
        if (f.yMm > 0.5 * cfg.heightMm - f.heightMm * 1.1) {
          sigTopConc = c.sig;
        }
        states.add(FiberResponseState(
          spec: f,
          strain: eps,
          stressMpa: c.sig,
          tangentMpa: c.et,
          status: c.status,
          isCracked: c.cracked,
          isCrushed: c.crushed,
          isYielded: false,
        ));
      } else {
        final s = steelLaw(eps, cfg.esMpa, f.fyMpa, cfg.hardeningRatio, nonlinear);
        nVal += s.sig * f.areaMm2;
        mVal -= s.sig * f.yMm * f.areaMm2;
        eaT += s.et * f.areaMm2;
        esT -= s.et * f.yMm * f.areaMm2;
        eiT += s.et * f.yMm * f.yMm * f.areaMm2;
        if (s.yielded) steelYielded = true;
        if (f.kind == 'rebar_bot') sigBotSteel = s.sig;
        if (f.kind == 'rebar_top') sigTopSteel = s.sig;
        states.add(FiberResponseState(
          spec: f,
          strain: eps,
          stressMpa: s.sig,
          tangentMpa: s.et,
          status: s.status,
          isCracked: false,
          isCrushed: false,
          isYielded: s.yielded,
        ));
      }
    }

    // Bảo đảm ma trận độ cứng mặt cắt 2×2 [D_t] luôn xác định dương (an toàn khi vỡ nén / cốt thép rất nhỏ)
    final eaMin = 0.005 * cfg.ecMpa * cfg.widthMm * cfg.heightMm;
    final eiMin = 0.005 * cfg.ecMpa * cfg.widthMm * cfg.heightMm * cfg.heightMm * cfg.heightMm / 12.0;
    if (eaT < eaMin) eaT = eaMin;
    if (eiT - (esT * esT) / eaT < eiMin) {
      eiT = (esT * esT) / eaT + eiMin;
    }

    final eiEff = math.max(eiMin, eiT - (esT * esT) / math.max(1.0, eaT));
    final yNa = kappa.abs() > 1e-10 ? (eps0 / kappa).clamp(-0.5 * cfg.heightMm, 0.5 * cfg.heightMm) : 0.0;
    final xNaDepth = (0.5 * cfg.heightMm - yNa).clamp(0.0, cfg.heightMm);
    final crackDepth = hasCracked ? (maxCrackY + 0.5 * cfg.heightMm).clamp(0.0, cfg.heightMm) : 0.0;

    return RcSectionState(
      xMm: xMm,
      eps0: eps0,
      kappa: kappa,
      nForceN: nVal,
      mForceNmm: mVal,
      eaTangentN: eaT,
      esTangentNmm: esT,
      eiTangentNmm2: eiT,
      eiEffNmm2: eiEff,
      yNeutralMm: yNa,
      xNeutralDepthMm: xNaDepth,
      crackDepthMm: crackDepth,
      sigmaTopConcMpa: sigTopConc,
      sigmaBotSteelMpa: sigBotSteel,
      sigmaTopSteelMpa: sigTopSteel,
      hasCracked: hasCracked,
      steelYielded: steelYielded,
      concreteCrushed: concCrushed,
      fibers: states,
    );
  }

  /// 5. Sinh lưới phần tử hữu hạn dọc dầm (chia hai nửa đối xứng + bám nút lực a, L-a)
  static List<double> buildMeshNodes(RcBeamConfig cfg) {
    final nHalf = math.max(1, (cfg.nElems / 2).round());
    final nTot = 2 * nHalf;
    final l = cfg.spanMm;
    final pts = <double>{
      for (int i = 0; i <= nTot; i++) double.parse((l * i / nTot).toStringAsFixed(2)),
    };
    final a = cfg.effectiveAMm;
    if (cfg.loadType == RcBeamLoadType.threePoint) {
      pts.add(double.parse(a.toStringAsFixed(2)));
    } else {
      pts.add(double.parse(a.toStringAsFixed(2)));
      pts.add(double.parse((l - a).toStringAsFixed(2)));
    }
    final sorted = pts.toList()..sort();
    final cleaned = <double>[sorted.first];
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] - cleaned.last > 1.5) {
        cleaned.add(sorted[i]);
      }
    }
    if ((cleaned.last - l).abs() > 1e-2) {
      cleaned[cleaned.length - 1] = l;
    }
    return cleaned;
  }

  /// 6. Lắp ráp {F_int} & [K_t] toàn cục theo Rayleigh-Ritz (Gauss-Legendre 3 điểm)
  static ({
    List<double> fInt,
    List<List<double>> kt,
    List<RcBeamElementResult> elements,
  }) _assemble({
    required List<double> xNodes,
    required List<double> d,
    required List<BeamFiberSpec> fibers,
    required RcBeamConfig cfg,
    required bool nonlinear,
  }) {
    final nn = xNodes.length;
    final nd = 3 * nn;
    final fInt = List<double>.filled(nd, 0.0);
    final kt = List.generate(nd, (_) => List<double>.filled(nd, 0.0));
    final elements = <RcBeamElementResult>[];

    for (int e = 0; e < nn - 1; e++) {
      final x1 = xNodes[e];
      final x2 = xNodes[e + 1];
      final le = x2 - x1;
      final dofs = [3 * e, 3 * e + 1, 3 * e + 2, 3 * (e + 1), 3 * (e + 1) + 1, 3 * (e + 1) + 2];
      final de = [for (final idx in dofs) d[idx]];
      final fe = List<double>.filled(6, 0.0);
      final ke = List.generate(6, (_) => List<double>.filled(6, 0.0));
      final gpSecs = <RcSectionState>[];

      for (int g = 0; g < 3; g++) {
        final xi = _gpXi[g];
        final wDx = _gpW[g] * le;
        final bu = [-1.0 / le, 0.0, 0.0, 1.0 / le, 0.0, 0.0];
        final bk = [
          0.0,
          (-6.0 + 12.0 * xi) / (le * le),
          (-4.0 + 6.0 * xi) / le,
          0.0,
          (6.0 - 12.0 * xi) / (le * le),
          (-2.0 + 6.0 * xi) / le,
        ];
        double eps0 = 0.0, kappa = 0.0;
        for (int k = 0; k < 6; k++) {
          eps0 += bu[k] * de[k];
          kappa += bk[k] * de[k];
        }
        final sec = evaluateSection(
          xMm: x1 + xi * le,
          eps0: eps0,
          kappa: kappa,
          fibers: fibers,
          cfg: cfg,
          nonlinear: nonlinear,
        );
        gpSecs.add(sec);

        for (int a = 0; a < 6; a++) {
          fe[a] += (bu[a] * sec.nForceN + bk[a] * sec.mForceNmm) * wDx;
          for (int b = 0; b < 6; b++) {
            final kTerm = bu[a] * (sec.eaTangentN * bu[b] + sec.esTangentNmm * bk[b]) +
                bk[a] * (sec.esTangentNmm * bu[b] + sec.eiTangentNmm2 * bk[b]);
            ke[a][b] += kTerm * wDx;
          }
        }
      }

      for (int a = 0; a < 6; a++) {
        fInt[dofs[a]] += fe[a];
        for (int b = 0; b < 6; b++) {
          kt[dofs[a]][dofs[b]] += ke[a][b];
        }
      }

      elements.add(RcBeamElementResult(
        elemIndex: e,
        x1Mm: x1,
        x2Mm: x2,
        lengthMm: le,
        dElem: de,
        fEndElem: fe,
        kt6x6: ke,
        gaussSections: gpSecs,
        midSection: gpSecs[1], // Điểm Gauss giữa ξ = 0.50!
      ));
    }

    // Lò xo đàn hồi hai đầu (nếu người dùng chọn gối lò xo)
    for (final (nodeIdx, sup) in [(0, cfg.leftSupport), (nn - 1, cfg.rightSupport)]) {
      if (sup == BeamSupportType.spring) {
        final kv = cfg.springKvKnMm * 1000.0;
        final kth = cfg.springKthKnmRad * 1e6;
        fInt[3 * nodeIdx + 1] += kv * d[3 * nodeIdx + 1];
        kt[3 * nodeIdx + 1][3 * nodeIdx + 1] += kv;
        fInt[3 * nodeIdx + 2] += kth * d[3 * nodeIdx + 2];
        kt[3 * nodeIdx + 2][3 * nodeIdx + 2] += kth;
      }
    }

    return (fInt: fInt, kt: kt, elements: elements);
  }

  static ({List<int> fixed, List<int> free, String? warning}) _boundaryDofs(RcBeamConfig cfg, int nNodes) {
    final fixed = <int>{};
    int vRestraints = 0;
    int rotRestraints = 0;
    for (final (idx, sup) in [(0, cfg.leftSupport), (nNodes - 1, cfg.rightSupport)]) {
      if (sup.locksU) fixed.add(3 * idx);
      if (sup.locksV) {
        fixed.add(3 * idx + 1);
        vRestraints++;
      } else if (sup == BeamSupportType.spring) {
        vRestraints++;
        rotRestraints++;
      }
      if (sup.locksTheta) {
        fixed.add(3 * idx + 2);
        rotRestraints++;
      }
    }
    String? warn;
    if (vRestraints == 0) {
      warn = 'Dầm BIẾN HÌNH (không có liên kết chống dịch chuyển đứng v)! Hãy đặt tối thiểu 1 ngàm hoặc 2 gối đỡ.';
    } else if (vRestraints == 1 && rotRestraints == 0) {
      warn = 'Dầm BIẾN HÌNH xoay quanh khớp duy nhất! Hãy đặt thêm gối ở đầu còn lại hoặc chuyển sang Ngàm cứng.';
    }
    // Nếu không khóa u ở cả 2 đầu (ví dụ 2 gối di động), khóa u0 = 0 để khử chuyển vị cứng dọc trục
    if (!fixed.contains(0) && !fixed.contains(3 * (nNodes - 1))) {
      fixed.add(0);
    }
    final nd = 3 * nNodes;
    final free = [
      for (int i = 0; i < nd; i++)
        if (!fixed.contains(i)) i,
    ];
    return (fixed: fixed.toList()..sort(), free: free, warning: warn);
  }

  static List<double> _buildLoadVector(RcBeamConfig cfg, List<double> xNodes, double loadFactor) {
    final nd = 3 * xNodes.length;
    final f = List<double>.filled(nd, 0.0);
    final qN = cfg.loadQKn * loadFactor * 1000.0;
    final a = cfg.effectiveAMm;

    int nearest(double xTarget) {
      int best = 0;
      double bestD = double.infinity;
      for (int i = 0; i < xNodes.length; i++) {
        final d = (xNodes[i] - xTarget).abs();
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      return best;
    }

    if (cfg.loadType == RcBeamLoadType.threePoint) {
      final idx = nearest(a);
      f[3 * idx + 1] -= qN;
    } else {
      final i1 = nearest(a);
      final i2 = nearest(cfg.spanMm - a);
      f[3 * i1 + 1] -= 0.5 * qN;
      f[3 * i2 + 1] -= 0.5 * qN;
    }
    return f;
  }

  /// 7. Giải bài toán Dầm BTCT theo thuật toán đang chọn (Tuyến tính / Full NR / Modified NR / Euler / RK2)
  static RcBeamAnalysisResult solve(
    RcBeamConfig cfg, {
    SolverMethod method = SolverMethod.corotationalNR,
    double loadFactor = 1.0,
    bool? forceNonlinear,
  }) {
    final useNL = forceNonlinear ?? (cfg.nonlinearMaterial && method != SolverMethod.linearFirstOrder);
    final xNodes = buildMeshNodes(cfg);
    final nn = xNodes.length;
    final nd = 3 * nn;
    final fibers = buildFibers(cfg);
    final initSec = evaluateSection(xMm: 0.0, eps0: 0.0, kappa: 0.0, fibers: fibers, cfg: cfg, nonlinear: false);
    final eiGross = initSec.eiEffNmm2;
    final eaGross = initSec.eaTangentN;

    final bc = _boundaryDofs(cfg, nn);
    final fExt = _buildLoadVector(cfg, xNodes, loadFactor);
    final d = List<double>.filled(nd, 0.0);

    if (bc.warning != null) {
      final emptyAsm = _assemble(xNodes: xNodes, d: d, fibers: fibers, cfg: cfg, nonlinear: false);
      return RcBeamAnalysisResult(
        config: cfg,
        methodName: useNL ? 'Phi tuyến Thớ (${method.label})' : 'Đàn hồi Tuyến tính (beam2e)',
        converged: false,
        warningMessage: bc.warning,
        xNodesMm: xNodes,
        dGlobal: d,
        reactions: List<double>.filled(nd, 0.0),
        fExt: fExt,
        elements: emptyAsm.elements,
        eiGrossNmm2: eiGross,
        eaGrossN: eaGross,
        vMidMm: 0.0,
        maxAbsDeflectionMm: 0.0,
        mMaxKnm: 0.0,
        vMaxKn: 0.0,
        rLeftKn: 0.0,
        rRightKn: 0.0,
        sumFyN: 0.0,
        maxFreeResidualN: 0.0,
        totalIterations: 0,
        iterResidualsN: const [],
        hasCracking: false,
        hasYielding: false,
        hasCrushing: false,
      );
    }

    final free = bc.free;
    final steps = useNL ? cfg.nSteps.clamp(1, 50) : 1;
    int totalIt = 0;
    bool allConv = true;
    var lastStepRes = <double>[];

    List<List<double>> subMat(List<List<double>> m) => [
          for (final r in free) [for (final c in free) m[r][c]],
        ];

    if (!useNL) {
      final asm0 = _assemble(xNodes: xNodes, d: d, fibers: fibers, cfg: cfg, nonlinear: false);
      final rhs = [for (final i in free) fExt[i]];
      final uf = CalfemNonlinearEngine.solveLinearSystem(subMat(asm0.kt), rhs);
      for (int i = 0; i < free.length; i++) {
        d[free[i]] = uf[i];
      }
      totalIt = 1;
      lastStepRes = [rhs.fold(0.0, (m, v) => math.max(m, v.abs())), 1e-12];
    } else if (method == SolverMethod.eulerSingleStep) {
      final dlam = 1.0 / steps;
      for (int s = 1; s <= steps; s++) {
        final asm = _assemble(xNodes: xNodes, d: d, fibers: fibers, cfg: cfg, nonlinear: true);
        final df = [for (final i in free) dlam * fExt[i]];
        final du = CalfemNonlinearEngine.solveLinearSystem(subMat(asm.kt), df);
        for (int i = 0; i < free.length; i++) {
          d[free[i]] += du[i];
        }
        totalIt++;
      }
    } else if (method == SolverMethod.rk2Midpoint) {
      final dlam = 1.0 / steps;
      for (int s = 1; s <= steps; s++) {
        final asm1 = _assemble(xNodes: xNodes, d: d, fibers: fibers, cfg: cfg, nonlinear: true);
        final halfDf = [for (final i in free) 0.5 * dlam * fExt[i]];
        final duH = CalfemNonlinearEngine.solveLinearSystem(subMat(asm1.kt), halfDf);
        final dMid = List<double>.from(d);
        for (int i = 0; i < free.length; i++) {
          dMid[free[i]] += duH[i];
        }
        final asmMid = _assemble(xNodes: xNodes, d: dMid, fibers: fibers, cfg: cfg, nonlinear: true);
        final fullDf = [for (final i in free) dlam * fExt[i]];
        final duF = CalfemNonlinearEngine.solveLinearSystem(subMat(asmMid.kt), fullDf);
        for (int i = 0; i < free.length; i++) {
          d[free[i]] += duF[i];
        }
        totalIt += 2;
      }
    } else {
      // Full Newton-Raphson (hoặc Modified NR giữ [Kt0] theo bước) với chuẩn hóa lực/mô-men & Line Search!
      final isModNR = method == SolverMethod.modifiedNR;
      final qRefN = math.max(1e4, (cfg.loadQKn * loadFactor * 1000.0).abs());
      final fScale = qRefN;
      final mScale = math.max(1e7, qRefN * cfg.spanMm * 0.25);
      final dofScales = [for (final idx in free) (idx % 3 == 2) ? mScale : fScale];
      const double tolRel = 1e-5;
      final int maxIt = isModNR ? 90 : 45;

      double relNorm(List<double> fIntVec, double lam) {
        double m = 0.0;
        for (int i = 0; i < free.length; i++) {
          final idx = free[i];
          final v = (lam * fExt[idx] - fIntVec[idx]).abs() / dofScales[i];
          if (v > m) m = v;
        }
        return m;
      }

      for (int s = 1; s <= steps; s++) {
        final lam = s / steps;
        var asm = _assemble(xNodes: xNodes, d: d, fibers: fibers, cfg: cfg, nonlinear: true);
        final kt0 = isModNR ? subMat(asm.kt) : null;
        final stepRes = <double>[];
        bool stepOk = false;

        for (int it = 1; it <= maxIt; it++) {
          final res = [for (final i in free) lam * fExt[i] - asm.fInt[i]];
          final err = relNorm(asm.fInt, lam);
          if (it == 1) stepRes.add(err * fScale);
          if (err < tolRel) {
            stepOk = true;
            break;
          }
          final du = CalfemNonlinearEngine.solveLinearSystem(kt0 ?? subMat(asm.kt), res);
          // Tìm kiếm đường lùi (Backtracking Line Search) bảo đảm hội tụ toàn cục qua vùng bê tông bắt đầu nứt!
          double alpha = 1.0;
          List<double> bestD = List<double>.from(d);
          double bestErr = err;
          for (int ls = 0; ls < 5; ls++) {
            final dTry = List<double>.from(d);
            for (int i = 0; i < free.length; i++) {
              dTry[free[i]] += alpha * du[i];
            }
            final asmTry = _assemble(xNodes: xNodes, d: dTry, fibers: fibers, cfg: cfg, nonlinear: true);
            final eTry = relNorm(asmTry.fInt, lam);
            if (eTry < bestErr) {
              bestErr = eTry;
              bestD = dTry;
              if (eTry < 0.85 * err) break;
            }
            alpha *= 0.5;
          }
          if (bestErr < err) {
            for (int i = 0; i < nd; i++) {
              d[i] = bestD[i];
            }
          } else {
            for (int i = 0; i < free.length; i++) {
              d[free[i]] += 0.25 * du[i];
            }
          }
          totalIt++;
          asm = _assemble(xNodes: xNodes, d: d, fibers: fibers, cfg: cfg, nonlinear: true);
          final errAfter = relNorm(asm.fInt, lam);
          stepRes.add(errAfter * fScale);
          if (errAfter < tolRel) {
            stepOk = true;
            break;
          }
        }
        lastStepRes = stepRes;
        if (!stepOk) {
          allConv = false;
          break;
        }
      }
    }

    final finalAsm = _assemble(xNodes: xNodes, d: d, fibers: fibers, cfg: cfg, nonlinear: useNL);
    final reactions = [for (int i = 0; i < nd; i++) finalAsm.fInt[i] - fExt[i]];
    final maxFreeRes = free.fold(0.0, (m, idx) => math.max(m, (fExt[idx] - finalAsm.fInt[idx]).abs()));

    double sumFy = 0.0;
    for (int i = 0; i < nn; i++) {
      sumFy += reactions[3 * i + 1] + fExt[3 * i + 1];
    }

    int midIdx = 0;
    double bestMidD = double.infinity;
    double maxAbsV = 0.0;
    for (int i = 0; i < nn; i++) {
      final dm = (xNodes[i] - 0.5 * cfg.spanMm).abs();
      if (dm < bestMidD) {
        bestMidD = dm;
        midIdx = i;
      }
      if (d[3 * i + 1].abs() > maxAbsV) maxAbsV = d[3 * i + 1].abs();
    }

    double mMax = 0.0, vMax = 0.0;
    bool hasCrk = false, hasYld = false, hasCrsh = false;
    for (final el in finalAsm.elements) {
      mMax = math.max(mMax, math.max(el.m1Knm.abs(), el.m2Knm.abs()));
      vMax = math.max(vMax, el.vShearKn.abs());
      for (final gs in el.gaussSections) {
        if (gs.hasCracked) hasCrk = true;
        if (gs.steelYielded) hasYld = true;
        if (gs.concreteCrushed) hasCrsh = true;
      }
    }

    return RcBeamAnalysisResult(
      config: cfg,
      methodName: useNL ? 'Phi tuyến Thớ (${method.label})' : 'Đàn hồi Tuyến tính (beam2e)',
      converged: allConv,
      xNodesMm: xNodes,
      dGlobal: d,
      reactions: reactions,
      fExt: fExt,
      elements: finalAsm.elements,
      eiGrossNmm2: eiGross,
      eaGrossN: eaGross,
      vMidMm: d[3 * midIdx + 1],
      maxAbsDeflectionMm: maxAbsV,
      mMaxKnm: mMax,
      vMaxKn: vMax,
      rLeftKn: reactions[1] / 1000.0,
      rRightKn: reactions[3 * (nn - 1) + 1] / 1000.0,
      sumFyN: sumFy,
      maxFreeResidualN: maxFreeRes,
      totalIterations: totalIt,
      iterResidualsN: lastStepRes,
      hasCracking: hasCrk,
      hasYielding: hasYld,
      hasCrushing: hasCrsh,
    );
  }

  /// 8. Khảo sát lát cắt phẫu thuật tại tọa độ x ∈ [0, L] bất kỳ dọc dầm
  static ({
    RcBeamElementResult element,
    double xiLocal,
    double vMm,
    double thetaRad,
    double momentKnm,
    double shearKn,
    RcSectionState section,
  }) probeBeamAt(RcBeamAnalysisResult res, double xNorm) {
    final xMm = (xNorm.clamp(0.0, 1.0)) * res.config.spanMm;
    RcBeamElementResult el = res.elements.first;
    for (final item in res.elements) {
      if (xMm >= item.x1Mm - 1e-6 && xMm <= item.x2Mm + 1e-6) {
        el = item;
        break;
      }
    }
    final le = math.max(1e-6, el.lengthMm);
    final xi = ((xMm - el.x1Mm) / le).clamp(0.0, 1.0);
    final de = el.dElem;

    // Nội suy Hermite chính xác chuyển vị v(ξ), góc xoay θ(ξ), biến dạng ε₀, độ cong κ(ξ)
    final h1 = 1.0 - 3.0 * xi * xi + 2.0 * xi * xi * xi;
    final h2 = le * (xi - 2.0 * xi * xi + xi * xi * xi);
    final h3 = 3.0 * xi * xi - 2.0 * xi * xi * xi;
    final h4 = le * (-xi * xi + xi * xi * xi);
    final vMm = h1 * de[1] + h2 * de[2] + h3 * de[4] + h4 * de[5];

    final dh1 = (-6.0 * xi + 6.0 * xi * xi) / le;
    final dh2 = 1.0 - 4.0 * xi + 3.0 * xi * xi;
    final dh3 = (6.0 * xi - 6.0 * xi * xi) / le;
    final dh4 = -2.0 * xi + 3.0 * xi * xi;
    final thetaRad = dh1 * de[1] + dh2 * de[2] + dh3 * de[4] + dh4 * de[5];

    final eps0 = (de[3] - de[0]) / le;
    final kappa = ((-6.0 + 12.0 * xi) * de[1] +
            le * (-4.0 + 6.0 * xi) * de[2] +
            (6.0 - 12.0 * xi) * de[4] +
            le * (-2.0 + 6.0 * xi) * de[5]) /
        (le * le);

    final fibers = buildFibers(res.config);
    final useNL = !res.methodName.contains('Tuyến tính');
    final sec = evaluateSection(
      xMm: xMm,
      eps0: eps0,
      kappa: kappa,
      fibers: fibers,
      cfg: res.config,
      nonlinear: useNL,
    );
    final mLinInterp = el.m1Knm * (1.0 - xi) + el.m2Knm * xi;

    return (
      element: el,
      xiLocal: xi,
      vMm: vMm,
      thetaRad: thetaRad,
      momentKnm: useNL ? sec.mForceNmm / 1e6 : mLinInterp,
      shearKn: el.vShearKn,
      section: sec,
    );
  }

  /// 9. Dựng đường cong Mô-men – Độ cong (M-κ) của mặt cắt thớ (cân bằng lực dọc N = 0 chính xác!)
  static List<RcMomentCurvaturePoint> computeMomentCurvature(RcBeamConfig cfg) {
    final fibers = buildFibers(cfg);
    final pts = <RcMomentCurvaturePoint>[
      RcMomentCurvaturePoint(
        kappaPerMm: 0.0,
        momentKnm: 0.0,
        xNeutralMm: 0.5 * cfg.heightMm,
        eiEffNmm2: evaluateSection(xMm: 0, eps0: 0, kappa: 0, fibers: fibers, cfg: cfg, nonlinear: false).eiEffNmm2,
        cracked: false,
        yielded: false,
        crushed: false,
      ),
    ];

    final kappaMax = (cfg.epsCu * 3.5) / math.max(100.0, cfg.heightMm);
    const nPts = 45;
    double eps0 = 0.0;
    for (int i = 1; i <= nPts; i++) {
      final frac = i / nPts;
      // Mật độ điểm dày hơn ở vùng trước chảy dẻo để bắt chính xác điểm nứt M_cr & chảy M_y!
      final kappa = kappaMax * (frac * frac * 0.75 + frac * 0.25);
      // Lặp Newton-Raphson 1D tìm ε₀ sao cho N(ε₀, κ) = 0
      RcSectionState sec = evaluateSection(xMm: 0, eps0: eps0, kappa: kappa, fibers: fibers, cfg: cfg, nonlinear: true);
      for (int it = 0; it < 20; it++) {
        sec = evaluateSection(xMm: 0, eps0: eps0, kappa: kappa, fibers: fibers, cfg: cfg, nonlinear: true);
        if (sec.nForceN.abs() < 1e-1) break;
        eps0 -= sec.nForceN / math.max(1e3, sec.eaTangentN);
      }
      pts.add(RcMomentCurvaturePoint(
        kappaPerMm: kappa,
        momentKnm: sec.mForceNmm / 1e6,
        xNeutralMm: sec.xNeutralDepthMm,
        eiEffNmm2: sec.eiEffNmm2,
        cracked: sec.hasCracked,
        yielded: sec.steelYielded,
        crushed: sec.concreteCrushed,
      ));
      if (sec.concreteCrushed && i > 12) break;
    }
    return pts;
  }

  /// 10. Truy vết đường cong Tải – Độ võng toàn phần (P-Δ Pushover bằng điều khiển chuyển vị giữa nhịp!)
  static List<RcLoadDeflectionPoint> tracePushoverCurve(RcBeamConfig cfg) {
    final xNodes = buildMeshNodes(cfg);
    final nn = xNodes.length;
    final nd = 3 * nn;
    final bc = _boundaryDofs(cfg, nn);
    if (bc.warning != null) return const [];

    final fibers = buildFibers(cfg);
    final eiGross = evaluateSection(xMm: 0, eps0: 0, kappa: 0, fibers: fibers, cfg: cfg, nonlinear: false).eiEffNmm2;
    final fRef = _buildLoadVector(cfg, xNodes, 1.0); // Q = cfg.loadQKn
    final free = bc.free;

    // Bậc tự do khống chế: độ võng đứng v tại điểm giữa dầm (hoặc điểm đặt lực)
    int qNode = 0;
    double bestDist = double.infinity;
    final targetX = cfg.loadType == RcBeamLoadType.threePoint ? cfg.effectiveAMm : 0.5 * cfg.spanMm;
    for (int i = 0; i < nn; i++) {
      final dm = (xNodes[i] - targetX).abs();
      if (dm < bestDist) {
        bestDist = dm;
        qNode = i;
      }
    }
    final qDof = 3 * qNode + 1;
    final qLocal = free.indexOf(qDof);
    if (qLocal < 0) return const [];

    final d = List<double>.filled(nd, 0.0);
    double lam = 0.0;
    final pts = <RcLoadDeflectionPoint>[
      RcLoadDeflectionPoint(
        loadQKn: 0.0,
        deflectionMidMm: 0.0,
        mMaxKnm: 0.0,
        xNeutralMm: 0.5 * cfg.heightMm,
        eiRatioPct: 100.0,
        cracked: false,
        yielded: false,
        crushed: false,
      ),
    ];

    final maxDispTarget = (cfg.spanMm / 45.0).clamp(25.0, 140.0);
    const nSteps = 36;
    final dvStep = -maxDispTarget / nSteps;

    List<List<double>> subMat(List<List<double>> m) => [
          for (final r in free) [for (final c in free) m[r][c]],
        ];

    for (int s = 1; s <= nSteps; s++) {
      // Dự báo theo Displacement Control (Batoz-Dhatt)
      var asm = _assemble(xNodes: xNodes, d: d, fibers: fibers, cfg: cfg, nonlinear: true);
      final fFree = [for (final i in free) fRef[i]];
      final duBar = CalfemNonlinearEngine.solveLinearSystem(subMat(asm.kt), fFree);
      if (duBar[qLocal].abs() < 1e-14) break;
      final dlam = dvStep / duBar[qLocal];
      lam += dlam;
      for (int i = 0; i < free.length; i++) {
        d[free[i]] += dlam * duBar[i];
      }

      final qRefScale = math.max(1e4, cfg.loadQKn * 1000.0);
      final mRefScale = math.max(1e7, qRefScale * cfg.spanMm * 0.25);
      for (int it = 0; it < 20; it++) {
        asm = _assemble(xNodes: xNodes, d: d, fibers: fibers, cfg: cfg, nonlinear: true);
        final res = [for (final i in free) lam * fRef[i] - asm.fInt[i]];
        double relErr = 0.0;
        for (int i = 0; i < free.length; i++) {
          final sc = (free[i] % 3 == 2) ? mRefScale : qRefScale;
          final e = res[i].abs() / sc;
          if (e > relErr) relErr = e;
        }
        if (relErr < 1e-4) break;
        final kff = subMat(asm.kt);
        final dBar = CalfemNonlinearEngine.solveLinearSystem(kff, fFree);
        final dR = CalfemNonlinearEngine.solveLinearSystem(kff, res);
        if (dBar[qLocal].abs() < 1e-14) break;
        final dlCorr = -dR[qLocal] / dBar[qLocal];
        lam += dlCorr;
        for (int i = 0; i < free.length; i++) {
          d[free[i]] += dlCorr * dBar[i] + dR[i];
        }
      }

      asm = _assemble(xNodes: xNodes, d: d, fibers: fibers, cfg: cfg, nonlinear: true);
      double mMax = 0.0;
      double minEiRatio = 100.0;
      double xNaCrit = 0.5 * cfg.heightMm;
      bool crk = false, yld = false, crsh = false;
      for (final el in asm.elements) {
        mMax = math.max(mMax, math.max(el.m1Knm.abs(), el.m2Knm.abs()));
        final ms = el.midSection;
        final rEi = 100.0 * ms.eiEffNmm2 / math.max(1.0, eiGross);
        if (rEi < minEiRatio) {
          minEiRatio = rEi;
          xNaCrit = ms.xNeutralDepthMm;
        }
        for (final gs in el.gaussSections) {
          if (gs.hasCracked) crk = true;
          if (gs.steelYielded) yld = true;
          if (gs.concreteCrushed) crsh = true;
        }
      }
      pts.add(RcLoadDeflectionPoint(
        loadQKn: lam * cfg.loadQKn,
        deflectionMidMm: d[qDof].abs(),
        mMaxKnm: mMax,
        xNeutralMm: xNaCrit,
        eiRatioPct: minEiRatio.clamp(0.0, 100.0),
        cracked: crk,
        yielded: yld,
        crushed: crsh,
      ));
      if (crsh && s > 10) break;
    }
    return pts;
  }

  /// 11. Khảo sát bài toán hội tụ lưới phần tử (chia hai nửa: nElem = 2, 4, 8, 16, 32)
  static List<RcMeshConvergencePoint> runMeshConvergenceStudy(
    RcBeamConfig cfg, {
    double loadFactor = 1.0,
  }) {
    const meshes = [2, 4, 8, 16, 32];
    final raw = <RcBeamAnalysisResult>[];
    for (final ne in meshes) {
      raw.add(solve(
        cfg.copyWith(nElems: ne, nSteps: math.min(cfg.nSteps, 8)),
        method: SolverMethod.corotationalNR,
        loadFactor: loadFactor,
      ));
    }
    final refV = raw.last.vMidMm.abs();
    final out = <RcMeshConvergencePoint>[];
    for (int i = 0; i < raw.length; i++) {
      final r = raw[i];
      double minEi = 100.0;
      double xNa = 0.5 * cfg.heightMm;
      for (final el in r.elements) {
        final ratio = 100.0 * el.midSection.eiEffNmm2 / math.max(1.0, r.eiGrossNmm2);
        if (ratio < minEi) {
          minEi = ratio;
          xNa = el.midSection.xNeutralDepthMm;
        }
      }
      final errPct = refV > 1e-6 ? 100.0 * (r.vMidMm.abs() - refV).abs() / refV : 0.0;
      out.add(RcMeshConvergencePoint(
        nElems: r.nElems,
        nNodes: r.nNodes,
        vMidMm: r.vMidMm.abs(),
        mMaxKnm: r.mMaxKnm,
        xNeutralMm: xNa,
        eiRatioPct: minEi.clamp(0.0, 100.0),
        relErrorPct: errPct,
        iterations: r.totalIterations,
      ));
    }
    return out;
  }
}
