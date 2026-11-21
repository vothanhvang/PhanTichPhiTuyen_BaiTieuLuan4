import 'package:flutter_test/flutter_test.dart';
import 'package:calfem_nonlinear_truss/core/calfem_engine.dart';
import 'package:calfem_nonlinear_truss/core/connection_calculator.dart';

void main() {
  test('Dart CALFEM Engine khớp 100% Python & Dahlblom Ex 9.1 & Đề bài 5 thanh', () {
    // 1. Kiểm chứng Đề bài 5 thanh (Tuyến tính & Phi tuyến Corotational UL)
    final m5 = TrussModelData.create(preset: TrussPreset.assignment5Bar);
    final lin = CalfemNonlinearEngine.solveLinear(m5);
    final b2g = CalfemNonlinearEngine.solveBar2gSecondOrder(m5);
    final nl = CalfemNonlinearEngine.solveFullNR(m5, isTotalLagrangian: false, nSteps: 10);
    final tl = CalfemNonlinearEngine.solveFullNR(m5, isTotalLagrangian: true, nSteps: 10);

    expect(lin.uMm[3], closeTo(0.6496751624, 1e-9));
    expect(b2g.uMm[3], closeTo(0.64998774, 1e-6));
    expect(nl.uMm[3], closeTo(0.65014425, 1e-6));
    expect(nl.nForcesN[0], closeTo(13.5524, 1e-2));
    expect(tl.uMm[3], closeTo(0.65004282, 1e-6));
    expect(nl.maxFreeResidualN, lessThan(1e-6));

    // 2. Kiểm chứng Dahlblom Example 9.1 (tr. 261)
    final ex91 = TrussModelData.create(preset: TrussPreset.dahlblomEx91);
    final r91 = CalfemNonlinearEngine.solveBar2gSecondOrder(ex91);
    expect(r91.uMm[4], closeTo(-44.544, 0.005));
    expect(r91.uMm[5], closeTo(-108.835, 0.005));
    expect(r91.nForcesN[0] / 1e6, closeTo(-11.1360, 0.0005));
    expect(r91.nForcesN[1] / 1e6, closeTo(1.4833, 0.0005));

    // 3. Kiểm chứng tùy chọn các loại liên kết tại nút (Siêu tĩnh, Lò xo đàn hồi, Biến hình)
    // 3a. Gối cố định tại cả N1 và N4 (Siêu tĩnh bậc 1)
    final mIndet = TrussModelData.create(
      preset: TrussPreset.assignment5Bar,
      customSupports: const [
        NodeSupportType.pin,
        NodeSupportType.free,
        NodeSupportType.free,
        NodeSupportType.pin,
      ],
    );
    final rIndet = CalfemNonlinearEngine.solveFullNR(mIndet, isTotalLagrangian: false, nSteps: 10);
    expect(rIndet.converged, isTrue);
    expect(rIndet.warningMessage, isNull);
    expect(rIndet.uMm[6].abs(), lessThan(1e-12)); // u4x = 0
    expect(rIndet.uMm[7].abs(), lessThan(1e-12)); // u4y = 0
    expect(rIndet.sumFxN.abs(), lessThan(1e-5));
    expect(rIndet.sumFyN.abs(), lessThan(1e-5));
    expect(rIndet.sumMNmm.abs(), lessThan(1e-2));

    // 3b. Thay con lăn N4 bằng gối đàn hồi lò xo đứng k_y = 500 kN/mm
    final mSpring = TrussModelData.create(
      preset: TrussPreset.assignment5Bar,
      customSupports: const [
        NodeSupportType.pin,
        NodeSupportType.free,
        NodeSupportType.free,
        NodeSupportType.springY,
      ],
      springStiffnessKnMm: 500.0,
    );
    final rSpring = CalfemNonlinearEngine.solveFullNR(mSpring, isTotalLagrangian: false, nSteps: 10);
    expect(rSpring.converged, isTrue);
    expect(rSpring.warningMessage, isNull);
    expect(rSpring.uMm[7], closeTo(0.208, 0.002)); // u4y ≈ 104 kN / 500 kN/mm = 0.208 mm
    expect(rSpring.reactionsN[7] / 1000.0, closeTo(-104.0, 0.1));
    expect(rSpring.sumFxN.abs(), lessThan(1e-5));
    expect(rSpring.sumFyN.abs(), lessThan(1e-5));
    expect(rSpring.sumMNmm.abs(), lessThan(1e-2));

    // 3c. Hệ biến hình (tháo toàn bộ liên kết) -> phát hiện an toàn, không crash
    final mUnstable = TrussModelData.create(
      preset: TrussPreset.assignment5Bar,
      customSupports: const [
        NodeSupportType.free,
        NodeSupportType.free,
        NodeSupportType.free,
        NodeSupportType.free,
      ],
    );
    final rUnstable = CalfemNonlinearEngine.solveFullNR(mUnstable, isTotalLagrangian: false, nSteps: 10);
    expect(rUnstable.converged, isFalse);
    expect(rUnstable.warningMessage, isNotNull);

    // 3d. Khóa cứng tất cả 4 nút -> an toàn, u = 0, R2y = -208 kN
    final mAllPin = TrussModelData.create(
      preset: TrussPreset.assignment5Bar,
      customSupports: const [
        NodeSupportType.pin,
        NodeSupportType.pin,
        NodeSupportType.pin,
        NodeSupportType.pin,
      ],
    );
    final rAllPin = CalfemNonlinearEngine.solveFullNR(mAllPin, isTotalLagrangian: false, nSteps: 10);
    expect(rAllPin.converged, isTrue);
    expect(rAllPin.uMm[3], 0.0);
    expect(rAllPin.reactionsN[3] / 1000.0, closeTo(-208.0, 1e-6));

    // 4. Kiểm chứng mô-đun Tính toán Liên kết (TCVN 5575 / EN 1993-1-8) cho cả 3 kiểu gia công
    for (final dt in ConnectionDetailType.values) {
      final repN1 = ConnectionCalculator.analyzeNode(
        model: m5,
        result: nl,
        nodeIndex: 0, // Nút 1: Gối cố định (Pin)
        params: ConnectionDesignParams(detailType: dt),
      );
      expect(repN1.members.length, 2);
      expect(repN1.checks.length, greaterThanOrEqualTo(4));
      expect(repN1.allPassed, isTrue);
      expect(repN1.maxUtilizationPct, greaterThan(0.0));

      final repN4 = ConnectionCalculator.analyzeNode(
        model: m5,
        result: nl,
        nodeIndex: 3, // Nút 4: Con lăn X (Kiểm tra Hertz)
        params: ConnectionDesignParams(detailType: dt),
      );
      expect(repN4.members.length, 2);
      expect(repN4.allPassed, isTrue);
    }

    // Kiểm tra liên kết lò xo tại N4
    final repSpring = ConnectionCalculator.analyzeNode(
      model: mSpring,
      result: rSpring,
      nodeIndex: 3,
      params: const ConnectionDesignParams(),
    );
    expect(repSpring.checks.any((c) => c.category.contains('lò xo')), isTrue);
    expect(repSpring.allPassed, isTrue);

    // 5. Kiểm chứng đủ 12 tiết diện frame tiêu chuẩn & nhập thông số hình học mặt cắt 3D
    expect(SectionShape.values.length, 12);
    for (final shape in SectionShape.values) {
      // 5a. Quy đổi từ diện tích A = 2001 mm² cho mọi tiết diện
      final dAuto = SectionDimensions.fromArea(shape, 2001.0);
      expect(dAuto.areaMm2, closeTo(2001.0, 1.0));
      expect(dAuto.ix, greaterThan(0.0));
      expect(dAuto.iy, greaterThan(0.0));
      expect(dAuto.iMajor, greaterThanOrEqualTo(dAuto.iMinor - 1e-6));
      expect(dAuto.rGyrationMin, greaterThan(0.0));
      expect(dAuto.outlinePolygonsMm(shape, includeInnerHole: true), isNotEmpty);

      // 5b. Presets tiêu chuẩn & tính toán ngược vào mô hình dàn + Phẫu thuật mặt cắt
      final presets = CustomSectionGeometry.presetsFor(shape);
      expect(presets.length, greaterThanOrEqualTo(4));
      final customGeom = presets[1].$2;
      final dCustom = customGeom.toDimensions(shape);
      expect(dCustom.areaMm2, greaterThan(100.0));

      final mCustom = TrussModelData.create(
        preset: TrussPreset.assignment5Bar,
        sectionShape: shape,
        customSection: customGeom,
      );
      expect(mCustom.areas[0], closeTo(dCustom.areaMm2, 1e-6));
      final resCustom = CalfemNonlinearEngine.solveFullNR(mCustom, isTotalLagrangian: false, nSteps: 6);
      final resLinCustom = CalfemNonlinearEngine.solveLinear(mCustom);
      expect(resCustom.converged, isTrue);
      final pr = CalfemNonlinearEngine.probeMember(
        model: mCustom,
        resultNL: resCustom,
        resultLin: resLinCustom,
        elemIndex: 3,
        xi: 0.5,
        etaNorm: 0.8,
        imperfectionRatio: 0.002,
      );
      expect(pr.pEulerLocalKn, greaterThan(0.0));
      expect(pr.sectionDims.formatSpec(shape), isNotEmpty);
    }

    // Kiểm tra công thức giải tích chính xác cho các tiết diện điển hình
    // I150: H=150, B=75, tf=9, tw=5.5 -> A = 2*75*9 + 132*5.5 = 2076 mm²
    const i150 = CustomSectionGeometry(heightMm: 150, widthMm: 75, tfMm: 9.0, twMm: 5.5);
    final dI150 = i150.toDimensions(SectionShape.iSection);
    expect(dI150.areaMm2, closeTo(2076.0, 1e-6));

    // Chữ nhật đặc 100×200 -> A = 20000 mm², Ix = 100*200^3/12, Iy = 200*100^3/12
    const rect100x200 = CustomSectionGeometry(heightMm: 200, widthMm: 100, tfMm: 10, twMm: 10);
    final dRect = rect100x200.toDimensions(SectionShape.solidRect);
    expect(dRect.areaMm2, closeTo(20000.0, 1e-6));
    expect(dRect.ix, closeTo(100.0 * 8e6 / 12.0, 1e-3));
    expect(dRect.iy, closeTo(200.0 * 1e6 / 12.0, 1e-3));

    // Thép góc đôi 2L75×8 (s=10): A = 2*(75*8 + 67*8) = 2272 mm², W_tot = 2*75 + 10 = 160 mm
    const twoL75 = CustomSectionGeometry(heightMm: 75, widthMm: 75, tfMm: 8.0, twMm: 8.0, gapMm: 10.0);
    final d2L = twoL75.toDimensions(SectionShape.doubleAngle);
    expect(d2L.areaMm2, closeTo(2272.0, 1e-6));
    expect(d2L.width, closeTo(160.0, 1e-6));
    expect(d2L.outlinePolygonsMm(SectionShape.doubleAngle).length, 2);

    // Thép góc đơn L100×10: I_x == I_y nhưng mô-men quán tính chính cực tiểu I_minor < I_x (do I_xy ≠ 0!)
    const l100 = CustomSectionGeometry(heightMm: 100, widthMm: 100, tfMm: 10.0, twMm: 10.0);
    final dL100 = l100.toDimensions(SectionShape.angleL);
    expect(dL100.areaMm2, closeTo(1900.0, 1e-6));
    expect(dL100.ix, closeTo(dL100.iy, 1e-3));
    expect(dL100.iMinor, lessThan(dL100.ix * 0.5));
  });
}
