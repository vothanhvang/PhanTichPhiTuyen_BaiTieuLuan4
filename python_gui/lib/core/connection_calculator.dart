// ============================================================================
// LÕI TÍNH TOÁN & KIỂM TRA LIÊN KẾT KẾT CẤU THÉP (TCVN 5575 / EN 1993-1-8)
// ============================================================================
// Phân tích & kiểm tra chi tiết nút liên kết kết cấu thép (CBFEm / Whitmore):
//   1. Tự động lấy nội lực phi tuyến (N_e) của mọi thanh quy tụ vào nút N_k
//      và phản lực gối (R_x, R_y) từ kết quả CALFEM hiện hành.
//   2. Tính toán chi tiết theo 3 kiểu gia công chế tạo:
//        • Bản mã + Bu-lông cường độ cao (Cắt, Ép mặt, Xé khối Block Tearing)
//        • Bản mã + Đường hàn góc (Ứng suất cắt đường hàn, Chiều dài hàn yêu cầu)
//        • Tai chốt bản lề Clevis (Cắt chốt, Ép mặt lỗ chốt, Uốn chốt)
//   3. Kiểm tra Bản mã nút (Mặt cắt hữu hiệu Whitmore, Von Mises tương đương).
//   4. Kiểm tra Liên kết Gối tựa theo đúng loại gối tại nút (Bản đế + Bu-lông
//      neo + Bê tông móng; Ứng suất tiếp xúc Hertz con lăn; Hành trình & lực lò xo).
// ============================================================================

import 'dart:math' as math;
import 'calfem_engine.dart';

/// Mác thép chế tạo bản mã, bản đế và tai chốt
enum SteelGrade {
  s235('S235 / CCT34 (fy=235, fu=360 MPa)', 'S235', 235.0, 360.0, 0.80),
  s275('S275 / CCT38 (fy=275, fu=430 MPa)', 'S275', 275.0, 430.0, 0.85),
  s355('S355 / Q345 (fy=355, fu=490 MPa)', 'S355', 355.0, 490.0, 0.90);

  final String label;
  final String code;
  final double fyMpa;
  final double fuMpa;
  final double betaW; // Hệ số tương quan đường hàn EN 1993-1-8 Bảng 4.1
  const SteelGrade(this.label, this.code, this.fyMpa, this.fuMpa, this.betaW);
}

/// Thông số bu-lông cường độ cao (ISO 898-1 / EN 1993-1-8)
enum BoltSpec {
  m16g88('M16 cấp 8.8 (d=16, As=157 mm²)', 'M16-8.8', 16.0, 18.0, 157.0, 800.0, 0.6),
  m20g88('M20 cấp 8.8 (d=20, As=245 mm²)', 'M20-8.8', 20.0, 22.0, 245.0, 800.0, 0.6),
  m20g109('M20 cấp 10.9 (d=20, As=245 mm²)', 'M20-10.9', 20.0, 22.0, 245.0, 1000.0, 0.5),
  m24g88('M24 cấp 8.8 (d=24, As=353 mm²)', 'M24-8.8', 24.0, 26.0, 353.0, 800.0, 0.6),
  m24g109('M24 cấp 10.9 (d=24, As=353 mm²)', 'M24-10.9', 24.0, 26.0, 353.0, 1000.0, 0.5);

  final String label;
  final String code;
  final double dMm;
  final double d0Mm; // Đường kính lỗ bu-lông tiêu chuẩn
  final double asMm2; // Diện tích tiết diện thực vùng ren
  final double fubMpa;
  final double alphaV; // EN 1993-1-8 Bảng 3.4 (0.6 cho 8.8; 0.5 cho 10.9)
  const BoltSpec(this.label, this.code, this.dMm, this.d0Mm, this.asMm2, this.fubMpa, this.alphaV);
}

/// Bộ tham số thiết kế chi tiết liên kết (do người dùng tùy biến trong Tab Liên kết)
class ConnectionDesignParams {
  final ConnectionDetailType detailType;
  final SteelGrade steelGrade;
  final BoltSpec boltSpec;
  final double gussetThicknessMm; // Bề dày bản mã t_g (mm)
  final int boltsPerMember;       // Số bu-lông mỗi đầu thanh (2, 4, 6, 8)
  final double weldLegMm;         // Chiều cao đường hàn góc h_f (mm)
  final double weldLengthMm;      // Chiều dài mỗi dải hàn dọc l_w (mm)
  final double pinDiameterMm;     // Đường kính chốt bản lề Clevis d_pin (mm)
  final double basePlateWidthMm;  // Bề rộng bản đế B (mm)
  final double basePlateLengthMm; // Chiều dài bản đế H (mm)
  final double basePlateThickMm;  // Chiều dày bản đế t_bp (mm)
  final double concreteFckMpa;    // Cường độ bê tông móng f_ck (MPa, ví dụ 25 = C25/30)

  const ConnectionDesignParams({
    this.detailType = ConnectionDetailType.boltedGusset,
    this.steelGrade = SteelGrade.s275,
    this.boltSpec = BoltSpec.m20g88,
    this.gussetThicknessMm = 16.0,
    this.boltsPerMember = 4,
    this.weldLegMm = 8.0,
    this.weldLengthMm = 160.0,
    this.pinDiameterMm = 60.0,
    this.basePlateWidthMm = 280.0,
    this.basePlateLengthMm = 240.0,
    this.basePlateThickMm = 25.0,
    this.concreteFckMpa = 25.0,
  });

  ConnectionDesignParams copyWith({
    ConnectionDetailType? detailType,
    SteelGrade? steelGrade,
    BoltSpec? boltSpec,
    double? gussetThicknessMm,
    int? boltsPerMember,
    double? weldLegMm,
    double? weldLengthMm,
    double? pinDiameterMm,
    double? basePlateWidthMm,
    double? basePlateLengthMm,
    double? basePlateThickMm,
    double? concreteFckMpa,
  }) {
    return ConnectionDesignParams(
      detailType: detailType ?? this.detailType,
      steelGrade: steelGrade ?? this.steelGrade,
      boltSpec: boltSpec ?? this.boltSpec,
      gussetThicknessMm: gussetThicknessMm ?? this.gussetThicknessMm,
      boltsPerMember: boltsPerMember ?? this.boltsPerMember,
      weldLegMm: weldLegMm ?? this.weldLegMm,
      weldLengthMm: weldLengthMm ?? this.weldLengthMm,
      pinDiameterMm: pinDiameterMm ?? this.pinDiameterMm,
      basePlateWidthMm: basePlateWidthMm ?? this.basePlateWidthMm,
      basePlateLengthMm: basePlateLengthMm ?? this.basePlateLengthMm,
      basePlateThickMm: basePlateThickMm ?? this.basePlateThickMm,
      concreteFckMpa: concreteFckMpa ?? this.concreteFckMpa,
    );
  }
}

/// Một hạng mục kiểm tra chịu lực của chi tiết liên kết
class ConnectionCheckItem {
  final String category;       // Tên hạng mục (vd: "Bu-lông Thanh T4 (3-2)")
  final String clauseRef;      // Điều khoản tiêu chuẩn (EN 1993-1-8 / TCVN 5575)
  final String demandLabel;    // Giá trị nội lực / ứng suất tác dụng
  final String capacityLabel;  // Khả năng chịu lực thiết kế
  final double utilizationPct; // Tỷ lệ làm việc % (<= 100% là ĐẠT)
  final String formulaText;    // Diễn giải công thức ngắn gọn

  const ConnectionCheckItem({
    required this.category,
    required this.clauseRef,
    required this.demandLabel,
    required this.capacityLabel,
    required this.utilizationPct,
    required this.formulaText,
  });

  bool get passed => utilizationPct <= 100.0;
}

/// Thông tin từng thanh thép quy tụ vào nút
class ConnectedMemberInfo {
  final int elemIndex;
  final String label;
  final double angleRad; // Hướng véc-tơ đi ra khỏi nút trong hệ XY thực (rad)
  final double forceKn;  // Lực dọc N (kN): >0 kéo, <0 nén
  final double areaMm2;
  final double heightMm;
  final double boltUtilPct;
  final double weldUtilPct;
  final double pinUtilPct;
  final double whitmoreUtilPct;
  final int requiredBolts;
  final double requiredWeldLenMm;

  const ConnectedMemberInfo({
    required this.elemIndex,
    required this.label,
    required this.angleRad,
    required this.forceKn,
    required this.areaMm2,
    required this.heightMm,
    required this.boltUtilPct,
    required this.weldUtilPct,
    required this.pinUtilPct,
    required this.whitmoreUtilPct,
    required this.requiredBolts,
    required this.requiredWeldLenMm,
  });

  double activeUtilPct(ConnectionDetailType type) {
    switch (type) {
      case ConnectionDetailType.boltedGusset:
        return math.max(boltUtilPct, whitmoreUtilPct);
      case ConnectionDetailType.weldedGusset:
        return math.max(weldUtilPct, whitmoreUtilPct);
      case ConnectionDetailType.pinnedClevis:
        return pinUtilPct;
    }
  }
}

/// Báo cáo tổng hợp tính toán liên kết tại 1 nút
class NodeConnectionReport {
  final int nodeIndex;
  final String nodeName;
  final NodeSupportType supportType;
  final ConnectionDesignParams params;
  final List<ConnectedMemberInfo> members;
  final double rxKn;
  final double ryKn;
  final double rMagKn;
  final double extFxKn;
  final double extFyKn;
  final double uxMm;
  final double uyMm;
  final double gussetWidthMm;
  final double gussetHeightMm;
  final double maxGussetSigmaMpa;
  final double maxUtilizationPct;
  final List<ConnectionCheckItem> checks;

  const NodeConnectionReport({
    required this.nodeIndex,
    required this.nodeName,
    required this.supportType,
    required this.params,
    required this.members,
    required this.rxKn,
    required this.ryKn,
    required this.rMagKn,
    required this.extFxKn,
    required this.extFyKn,
    required this.uxMm,
    required this.uyMm,
    required this.gussetWidthMm,
    required this.gussetHeightMm,
    required this.maxGussetSigmaMpa,
    required this.maxUtilizationPct,
    required this.checks,
  });

  bool get allPassed => checks.every((c) => c.passed);
}

class ConnectionCalculator {
  static const double gammaM0 = 1.00;
  static const double gammaM2 = 1.25;

  /// Tính toán đầy đủ thiết kế & kiểm tra bền cho nút `nodeIndex` (0-based)
  static NodeConnectionReport analyzeNode({
    required TrussModelData model,
    required TrussAnalysisResult result,
    required int nodeIndex,
    required ConnectionDesignParams params,
    double loadFactor = 1.0,
  }) {
    final ni = nodeIndex.clamp(0, model.nNodes - 1);
    final sup = ni < model.nodeSupports.length ? model.nodeSupports[ni] : NodeSupportType.free;
    final rxKn = result.reactionsN[2 * ni] / 1000.0;
    final ryKn = result.reactionsN[2 * ni + 1] / 1000.0;
    final rMagKn = math.sqrt(rxKn * rxKn + ryKn * ryKn);
    final extFxKn = model.fRef[2 * ni] * loadFactor / 1000.0;
    final extFyKn = model.fRef[2 * ni + 1] * loadFactor / 1000.0;
    final uxMm = result.uMm[2 * ni];
    final uyMm = result.uMm[2 * ni + 1];

    final steel = params.steelGrade;
    final bolt = params.boltSpec;
    final tg = params.gussetThicknessMm;
    final nb = params.boltsPerMember.clamp(1, 16);
    final hf = params.weldLegMm;
    final lw = params.weldLengthMm;
    final dPin = params.pinDiameterMm;

    // 1. Tính khả năng chịu lực đơn vị theo EN 1993-1-8 / TCVN 5575
    // Bu-lông kẹp đôi 2 mặt cắt (m = 2)
    final fvRd1Kn = 2.0 * bolt.alphaV * bolt.fubMpa * bolt.asMm2 / (gammaM2 * 1000.0);
    // Ép mặt bản mã dày tg (e1 = 2*d0, p1 = 3*d0 -> alpha_b ≈ 0.67, k1 = 2.5)
    final e1 = math.max(35.0, 1.8 * bolt.d0Mm);
    final p1 = math.max(60.0, 3.0 * bolt.d0Mm);
    final alphaB = math.min(1.0, math.min(e1 / (3.0 * bolt.d0Mm), bolt.fubMpa / steel.fuMpa));
    final fbRd1Kn = 2.5 * alphaB * steel.fuMpa * bolt.dMm * tg / (gammaM2 * 1000.0);
    final fBolt1Kn = math.min(fvRd1Kn, fbRd1Kn);

    // Đường hàn góc đối xứng 2 mép: a = 0.7 * hf
    final aWeld = 0.7 * hf;
    final fvwRdMpa = (steel.fuMpa / math.sqrt(3.0)) / (steel.betaW * gammaM2);
    final weldCapKn = 2.0 * aWeld * lw * fvwRdMpa / 1000.0;

    // Tai chốt bản lề Clevis (EN 1993-1-8 Mục 3.13)
    final aPin = 0.25 * math.pi * dPin * dPin;
    final fupPin = math.max(steel.fuMpa, 500.0); // Thép chốt C45 / S355
    final fypPin = math.max(steel.fyMpa, 355.0);
    final fvPinRdKn = 2.0 * 0.6 * aPin * fupPin / (gammaM2 * 1000.0);
    final fbPinRdKn = 1.5 * tg * dPin * steel.fyMpa / (gammaM0 * 1000.0);
    final wPin = math.pi * math.pow(dPin, 3) / 32.0;
    final mPinRdNmm = 1.5 * wPin * fypPin / gammaM0;
    final leverPin = (tg + 2.0 * math.max(12.0, tg * 0.75)) / 8.0;
    final fmPinRdKn = (mPinRdNmm / math.max(1.0, leverPin)) / 1000.0;
    final fPinCapKn = math.min(fvPinRdKn, math.min(fbPinRdKn, fmPinRdKn));

    // 2. Duyệt tất cả các thanh quy tụ vào nút ni
    final members = <ConnectedMemberInfo>[];
    final checks = <ConnectionCheckItem>[];
    double maxGussetSigma = 0.0;
    double maxMemberH = 80.0;

    for (int e = 0; e < model.nElems; e++) {
      final n1 = model.conn[e][0] - 1;
      final n2 = model.conn[e][1] - 1;
      if (n1 != ni && n2 != ni) continue;
      final other = n1 == ni ? n2 : n1;
      final dx = model.coords[other][0] - model.coords[ni][0];
      final dy = model.coords[other][1] - model.coords[ni][1];
      final ang = math.atan2(dy, dx);
      final nKn = result.nForcesN[e] / 1000.0;
      final nAbs = nKn.abs();
      final dims = model.sectionDimsForElem(e);
      maxMemberH = math.max(maxMemberH, dims.height);

      final boltCapTotal = nb * fBolt1Kn;
      final boltUtil = boltCapTotal > 1e-6 ? 100.0 * nAbs / boltCapTotal : 0.0;
      final reqBolts = math.max(2, (nAbs / math.max(1e-6, fBolt1Kn)).ceil());

      // Xé khối Block Tearing bản mã vùng bu-lông
      final nRows = math.max(1, (nb / 2).ceil());
      final p2 = math.max(55.0, dims.height * 0.55);
      final ant = math.max(20.0, (p2 - bolt.d0Mm)) * tg;
      final anv = 2.0 * math.max(30.0, (e1 + (nRows - 1) * p1 - (nRows - 0.5) * bolt.d0Mm)) * tg;
      final vEffRdKn = (steel.fuMpa * ant / gammaM2 + steel.fyMpa * anv / (math.sqrt(3.0) * gammaM0)) / 1000.0;
      final blockUtil = vEffRdKn > 1e-6 ? 100.0 * nAbs / vEffRdKn : 0.0;

      // Đường hàn góc
      final weldUtil = weldCapKn > 1e-6 ? 100.0 * nAbs / weldCapKn : 0.0;
      final reqWeldLen = math.max(40.0, (nAbs * 1000.0) / math.max(1e-6, 2.0 * aWeld * fvwRdMpa));

      // Chốt Clevis
      final pinUtil = fPinCapKn > 1e-6 ? 100.0 * nAbs / fPinCapKn : 0.0;

      // Mặt cắt hữu hiệu Whitmore bản mã
      final lConn = params.detailType == ConnectionDetailType.weldedGusset
          ? lw
          : math.max(60.0, (nRows - 1) * p1);
      final bWhitmore = p2 + 2.0 * lConn * math.tan(math.pi / 6.0); // góc phân tán 30°
      final sigmaWhitmore = (nAbs * 1000.0) / math.max(1.0, bWhitmore * tg);
      // Nếu thanh nén, xét hệ số uốn dọc cục bộ bản mã χ ≈ 0.85
      final fDesignPlate = (nKn < 0 ? 0.85 : 1.0) * steel.fyMpa / gammaM0;
      final whitmoreUtil = 100.0 * sigmaWhitmore / fDesignPlate;
      // Khuếch đại tập trung ứng suất cục bộ tại mép lỗ bu-lông / chân đường hàn
      final kConc = params.detailType == ConnectionDetailType.boltedGusset ? 1.35 : 1.20;
      maxGussetSigma = math.max(maxGussetSigma, sigmaWhitmore * kConc);

      members.add(ConnectedMemberInfo(
        elemIndex: e,
        label: 'T${e + 1} (${model.memberLabels[e]})',
        angleRad: ang,
        forceKn: nKn,
        areaMm2: model.areas[e],
        heightMm: dims.height,
        boltUtilPct: math.max(boltUtil, blockUtil),
        weldUtilPct: weldUtil,
        pinUtilPct: pinUtil,
        whitmoreUtilPct: whitmoreUtil,
        requiredBolts: reqBolts,
        requiredWeldLenMm: reqWeldLen,
      ));

      // Tạo hạng mục kiểm tra chi tiết cho từng thanh quy tụ vào nút
      if (params.detailType == ConnectionDetailType.boltedGusset) {
        checks.add(ConnectionCheckItem(
          category: 'Bu-lông T${e + 1} (${model.memberLabels[e]}): $nb×${bolt.code}',
          clauseRef: 'EN 1993-1-8 Bảng 3.4',
          demandLabel: '|N| = ${nAbs.toStringAsFixed(2)} kN',
          capacityLabel: 'F_Rd = ${boltCapTotal.toStringAsFixed(1)} kN (cần $reqBolts BL)',
          utilizationPct: boltUtil,
          formulaText:
              'F_v,Rd(1)=${fvRd1Kn.toStringAsFixed(1)} kN, F_b,Rd(1)=${fbRd1Kn.toStringAsFixed(1)} kN → min=${fBolt1Kn.toStringAsFixed(1)} kN/BL',
        ));
        if (nAbs > 0.5) {
          checks.add(ConnectionCheckItem(
            category: 'Xé khối bản mã T${e + 1} (Block Tearing)',
            clauseRef: 'EN 1993-1-8 Mục 3.10.2',
            demandLabel: '|N| = ${nAbs.toStringAsFixed(2)} kN',
            capacityLabel: 'V_eff,Rd = ${vEffRdKn.toStringAsFixed(1)} kN',
            utilizationPct: blockUtil,
            formulaText: 'A_nt=${ant.toStringAsFixed(0)} mm², A_nv=${anv.toStringAsFixed(0)} mm², t_g=${tg.toStringAsFixed(0)} mm',
          ));
        }
      } else if (params.detailType == ConnectionDetailType.weldedGusset) {
        final tauW = (nAbs * 1000.0) / math.max(1.0, 2.0 * aWeld * lw);
        checks.add(ConnectionCheckItem(
          category: 'Đường hàn góc T${e + 1} (2×hf=${hf.toStringAsFixed(0)}, lw=${lw.toStringAsFixed(0)})',
          clauseRef: 'EN 1993-1-8 Mục 4.5.3',
          demandLabel: 'τ_w = ${tauW.toStringAsFixed(2)} MPa',
          capacityLabel: 'f_vw,d = ${fvwRdMpa.toStringAsFixed(1)} MPa (l_yc=${reqWeldLen.toStringAsFixed(0)} mm)',
          utilizationPct: weldUtil,
          formulaText: 'a=0.7·h_f=${aWeld.toStringAsFixed(1)} mm; R_w=2·a·l_w·f_vw,d=${weldCapKn.toStringAsFixed(1)} kN',
        ));
      } else {
        checks.add(ConnectionCheckItem(
          category: 'Chốt bản lề Clevis T${e + 1} (Ø${dPin.toStringAsFixed(0)})',
          clauseRef: 'EN 1993-1-8 Mục 3.13',
          demandLabel: '|N| = ${nAbs.toStringAsFixed(2)} kN',
          capacityLabel: 'F_pin,Rd = ${fPinCapKn.toStringAsFixed(1)} kN',
          utilizationPct: pinUtil,
          formulaText:
              'Cắt=${fvPinRdKn.toStringAsFixed(1)}, Ép mặt=${fbPinRdKn.toStringAsFixed(1)}, Uốn=${fmPinRdKn.toStringAsFixed(1)} kN',
        ));
      }
    }

    // 3. Kiểm tra Bản mã nút (Mặt cắt hữu hiệu Whitmore & Von Mises)
    final maxWhitmoreUtil = members.isEmpty
        ? 0.0
        : members.map((m) => m.whitmoreUtilPct).reduce(math.max);
    final gussetW = math.max(220.0, maxMemberH * 2.2 + (params.detailType == ConnectionDetailType.weldedGusset ? lw * 0.9 : 140.0));
    final gussetH = math.max(200.0, maxMemberH * 2.0 + 110.0);
    final sigmaAllow = steel.fyMpa / gammaM0;
    final vmUtil = 100.0 * maxGussetSigma / sigmaAllow;
    checks.add(ConnectionCheckItem(
      category: 'Bản mã nút PL${tg.toStringAsFixed(0)} (${steel.code} — Whitmore / Von Mises)',
      clauseRef: 'EN 1993-1-1 & AISC Whitmore',
      demandLabel: 'σ_eq,max = ${maxGussetSigma.toStringAsFixed(2)} MPa',
      capacityLabel: 'f_y/γ_M0 = ${sigmaAllow.toStringAsFixed(1)} MPa',
      utilizationPct: math.max(maxWhitmoreUtil, vmUtil),
      formulaText: 'Kích thước bản mã ≈ ${gussetW.toStringAsFixed(0)}×${gussetH.toStringAsFixed(0)}×${tg.toStringAsFixed(0)} mm',
    ));

    // 4. Kiểm tra chi tiết Gối tựa tại nút (theo đúng 1 trong 8 loại liên kết)
    if (sup != NodeSupportType.free) {
      final fcd = 0.85 * params.concreteFckMpa / 1.5; // Cường độ nén thiết kế bê tông
      final fjd = 1.5 * fcd; // Hệ số nén cục bộ khớp bê tông (EN 1993-1-8 Mục 6.2.5)
      final areaBp = params.basePlateWidthMm * params.basePlateLengthMm;

      if (sup == NodeSupportType.pin) {
        final bearingMpa = (ryKn.abs() * 1000.0) / math.max(1.0, areaBp);
        final bearUtil = 100.0 * bearingMpa / fjd;
        checks.add(ConnectionCheckItem(
          category: 'Bản đế móng BP ${params.basePlateWidthMm.toStringAsFixed(0)}×${params.basePlateLengthMm.toStringAsFixed(0)}×${params.basePlateThickMm.toStringAsFixed(0)} (Nén BT)',
          clauseRef: 'EN 1993-1-8 Mục 6.2.5',
          demandLabel: 'p_c = ${bearingMpa.toStringAsFixed(2)} MPa (|R_y|=${ryKn.abs().toStringAsFixed(1)} kN)',
          capacityLabel: 'f_jd = ${fjd.toStringAsFixed(1)} MPa (C${params.concreteFckMpa.toStringAsFixed(0)})',
          utilizationPct: bearUtil,
          formulaText: 'A_bp=${(areaBp / 100).toStringAsFixed(0)} cm²; 4×BL neo M24-8.8 + 2 sườn ST12',
        ));
        // Kiểm tra 4 bu-lông neo M24 chịu cắt ngang R_x & nhổ kéo nếu R_y < 0 (lực nâng tách gối)
        final anchorShearCapKn = 4.0 * 0.6 * 800.0 * 353.0 / (gammaM2 * 1000.0);
        final anchorTensCapKn = 4.0 * 0.9 * 800.0 * 353.0 / (gammaM2 * 1000.0);
        final anchorUtil = 100.0 * (rxKn.abs() / anchorShearCapKn + ryKn.abs() / (1.4 * anchorTensCapKn));
        checks.add(ConnectionCheckItem(
          category: 'Cụm 4 bu-lông neo móng M24-8.8 (Cắt & Kéo nhổ)',
          clauseRef: 'EN 1993-1-8 Bảng 3.4',
          demandLabel: 'R_x=${rxKn.toStringAsFixed(1)}, R_y=${ryKn.toStringAsFixed(1)} kN',
          capacityLabel: 'V_Rd=${anchorShearCapKn.toStringAsFixed(0)} kN, N_Rd=${anchorTensCapKn.toStringAsFixed(0)} kN',
          utilizationPct: anchorUtil,
          formulaText: 'Tổ hợp cắt + kéo: |R_x|/V_Rd + |R_y|/(1.4·N_Rd) ≤ 1.0',
        ));
      } else if (sup == NodeSupportType.rollerX || sup == NodeSupportType.rollerY || sup == NodeSupportType.rollerXSpringX) {
        final fnKn = sup == NodeSupportType.rollerY ? rxKn.abs() : ryKn.abs();
        final slideMm = sup == NodeSupportType.rollerY ? uyMm : uxMm;
        // Ứng suất tiếp xúc Hertz cho 2 trục con lăn thép Ø60 dài 160 mm (E=200000, nu=0.3)
        const rRol = 30.0;
        const lRol = 160.0;
        final fnPerRollerN = 0.5 * fnKn * 1000.0;
        final sigmaHertz = math.sqrt((fnPerRollerN * 200000.0) / (math.pi * lRol * rRol * (1.0 - 0.09)));
        const sigmaHertzAllow = 1200.0; // Thép trục tôi bề mặt 42CrMo4 / C45
        final hertzUtil = 100.0 * sigmaHertz / sigmaHertzAllow;
        checks.add(ConnectionCheckItem(
          category: 'Gối con lăn thép 2×Ø60×160 (Tiếp xúc Hertz)',
          clauseRef: 'EN 1337-4 / Lý thuyết Hertz',
          demandLabel: 'σ_H = ${sigmaHertz.toStringAsFixed(1)} MPa (Trượt=${slideMm.toStringAsFixed(3)} mm)',
          capacityLabel: '[σ_H] = ${sigmaHertzAllow.toStringAsFixed(0)} MPa',
          utilizationPct: hertzUtil,
          formulaText: 'F_n=${fnKn.toStringAsFixed(2)} kN (2 con lăn); σ_H = √[F·E/(π·L·R·(1−ν²))]',
        ));
      }

      if (sup.hasSpring) {
        final kKnMm = model.springStiffnessKnMm;
        final fsKn = (sup.hasSpringX && sup.hasSpringY)
            ? rMagKn
            : (sup.hasSpringX ? rxKn.abs() : ryKn.abs());
        final deflMm = fsKn / math.max(1e-6, kKnMm);
        const allowDeflMm = 15.0; // Hành trình đàn hồi thiết kế của cụm gối lò xo
        final sprUtil = 100.0 * deflMm / allowDeflMm;
        final energyJ = 0.5 * kKnMm * deflMm * deflMm; // kN/mm * mm^2 = N·m = J
        checks.add(ConnectionCheckItem(
          category: 'Gối đàn hồi lò xo thép (k = ${kKnMm.toStringAsFixed(0)} kN/mm)',
          clauseRef: 'EN 1337-3 / Đàn hồi tuyến tính',
          demandLabel: 'δ_s = ${deflMm.toStringAsFixed(3)} mm (F_s=${fsKn.toStringAsFixed(2)} kN)',
          capacityLabel: '[δ] = ${allowDeflMm.toStringAsFixed(1)} mm (U_s=${energyJ.toStringAsFixed(2)} J)',
          utilizationPct: sprUtil,
          formulaText: 'F_s = k·δ_s; Năng lượng tích trữ U_s = ½·k·δ_s² = ${energyJ.toStringAsFixed(2)} J',
        ));
      }
    }

    final maxUtil = checks.isEmpty ? 0.0 : checks.map((c) => c.utilizationPct).reduce(math.max);

    return NodeConnectionReport(
      nodeIndex: ni,
      nodeName: ni < model.nodeLabels.length ? model.nodeLabels[ni] : 'Nút ${ni + 1}',
      supportType: sup,
      params: params,
      members: members,
      rxKn: rxKn,
      ryKn: ryKn,
      rMagKn: rMagKn,
      extFxKn: extFxKn,
      extFyKn: extFyKn,
      uxMm: uxMm,
      uyMm: uyMm,
      gussetWidthMm: gussetW,
      gussetHeightMm: gussetH,
      maxGussetSigmaMpa: maxGussetSigma,
      maxUtilizationPct: maxUtil,
      checks: checks,
    );
  }
}
