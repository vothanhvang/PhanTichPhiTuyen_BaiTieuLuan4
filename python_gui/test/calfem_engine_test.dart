import 'package:flutter_test/flutter_test.dart';
import 'package:calfem_nonlinear_truss/core/calfem_engine.dart';
import 'package:calfem_nonlinear_truss/core/connection_calculator.dart';
import 'package:calfem_nonlinear_truss/core/project_serializer.dart';

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

    // 6. Kiểm chứng tùy biến tiết diện ĐỘC LẬP TỪNG THANH + tùy biến CHIỀU DÀI / KHOẢNG CÁCH THANH
    const tube140 = CustomSectionGeometry(heightMm: 140, widthMm: 140, tfMm: 8.0, twMm: 8.0);
    const twoL90 = CustomSectionGeometry(heightMm: 90, widthMm: 90, tfMm: 8.0, twMm: 8.0, gapMm: 12.0);
    final mixedSections = const [
      ElementSectionConfig(shape: SectionShape.iSection),
      ElementSectionConfig(shape: SectionShape.boxSection),
      ElementSectionConfig(shape: SectionShape.solidRect, customGeometry: rect100x200),
      ElementSectionConfig(shape: SectionShape.circTube, customGeometry: tube140),
      ElementSectionConfig(shape: SectionShape.doubleAngle, customGeometry: twoL90),
    ];
    final customCoords = const [
      [0.0, 0.0],
      [1200.0, 0.0],    // Kéo dài T1 (1-2) lên 1200 mm
      [0.0, 1300.0],    // Kéo cao T2 (1-3) lên 1300 mm
      [2600.0, 1300.0], // Kéo dài T3 (3-4) lên 2600 mm
    ];
    final mMixed = TrussModelData.create(
      preset: TrussPreset.assignment5Bar,
      elementSections: mixedSections,
      customCoords: customCoords,
    );
    expect(mMixed.hasMixedSections, isTrue);
    expect(mMixed.sectionShapeForElem(0), SectionShape.iSection);
    expect(mMixed.sectionShapeForElem(1), SectionShape.boxSection);
    expect(mMixed.sectionShapeForElem(2), SectionShape.solidRect);
    expect(mMixed.sectionShapeForElem(3), SectionShape.circTube);
    expect(mMixed.sectionShapeForElem(4), SectionShape.doubleAngle);
    expect(mMixed.areas[0], closeTo(2001.0, 1e-6));
    expect(mMixed.areas[2], closeTo(20000.0, 1e-6));
    expect(mMixed.areas[3], closeTo(tube140.computedAreaMm2(SectionShape.circTube), 1e-6));
    expect(mMixed.areas[4], closeTo(twoL90.computedAreaMm2(SectionShape.doubleAngle), 1e-6));
    expect(mMixed.initialLength(0), closeTo(1200.0, 1e-6));
    expect(mMixed.initialLength(1), closeTo(1300.0, 1e-6));
    expect(mMixed.initialLength(2), closeTo(2600.0, 1e-6));

    final rMixed = CalfemNonlinearEngine.solveFullNR(mMixed, isTotalLagrangian: false, nSteps: 10);
    expect(rMixed.converged, isTrue);
    expect(rMixed.sumFxN.abs(), lessThan(1e-4));
    expect(rMixed.sumFyN.abs(), lessThan(1e-4));
    expect(rMixed.sumMNmm.abs(), lessThan(1e-1));
    expect(rMixed.maxFreeResidualN, lessThan(1e-5));

    // 7. Kiểm chứng XOAY TIẾT DIỆN 0..360° quanh trục dọc thanh cho TOÀN BỘ 12 tiết diện!
    for (final shape in SectionShape.values) {
      final base = CustomSectionGeometry.presetsFor(shape).first.$2.toDimensions(shape, rotationDeg: 0.0);
      final rot90 = base.withRotation(90.0);
      final rot180 = base.withRotation(180.0);
      final rot45 = base.withRotation(45.0);
      // Xoay 90°: Ix(90°) == Iy(0°), Iy(90°) == Ix(0°); I_x + I_y bất biến (vòng tròn Mohr)!
      expect(rot90.ixRotated, closeTo(base.iy, 1e-3));
      expect(rot90.iyRotated, closeTo(base.ix, 1e-3));
      expect(rot45.ixRotated + rot45.iyRotated, closeTo(base.ix + base.iy, 1e-3));
      expect(rot180.ixRotated, closeTo(base.ix, 1e-3));
      // Xoay 180° trên 2L: đa giác lật ngược (-x, -y) chính xác tuyệt đối
      if (shape == SectionShape.doubleAngle) {
        final p0 = base.rotatedOutlinePolygonsMm(shape);
        final p180 = rot180.rotatedOutlinePolygonsMm(shape);
        expect(p180.length, 2);
        expect(p180[0][0][0], closeTo(-p0[0][0][0], 1e-6));
        expect(p180[0][0][1], closeTo(-p0[0][0][1], 1e-6));
        // Điểm trên cánh ngang của 2L nằm ở y < 0 khi 0° và nằm ở y > 0 khi xoay 180°!
        final yFlange = -0.5 * base.height + 0.5 * base.tf;
        final xFlange = 0.5 * base.gap + 0.5 * base.legWidth;
        expect(base.containsRotatedPoint(shape, xFlange, yFlange), isTrue);
        expect(rot180.containsRotatedPoint(shape, xFlange, yFlange), isFalse);
        expect(rot180.containsRotatedPoint(shape, -xFlange, -yFlange), isTrue);
        expect(rot180.formatSpec(shape), contains('↻180°'));
      }
      // Xoay 90° đổi khung bao width <-> height cho mặt cắt không tròn
      if (shape != SectionShape.solidRod && shape != SectionShape.circTube) {
        final b0 = base.rotatedBounds(shape);
        final b90 = rot90.rotatedBounds(shape);
        expect(b90.width, closeTo(b0.height, 1e-3));
        expect(b90.height, closeTo(b0.width, 1e-3));
      }
    }

    // 8. Kiểm chứng 4 mô hình dàn công nghiệp mới (Pratt, Warren, Mái Fink, Công-xôn)
    for (final preset in const [
      TrussPreset.prattTruss,
      TrussPreset.warrenTruss,
      TrussPreset.roofFinkTruss,
      TrussPreset.cantileverTruss,
    ]) {
      final m = TrussModelData.create(preset: preset, lMm: 2000.0, pKn: 120.0);
      final rL = CalfemNonlinearEngine.solveLinear(m);
      final rN = CalfemNonlinearEngine.solveFullNR(m, isTotalLagrangian: false, nSteps: 6);
      expect(rN.converged, isTrue, reason: '${preset.code} must converge');
      expect(rN.sumFxN.abs(), lessThan(1e-3));
      expect(rN.sumFyN.abs(), lessThan(1e-3));
      expect(rN.sumMNmm.abs(), lessThan(1.0));
      expect(rN.iterResidualsN.length, greaterThanOrEqualTo(2));

      // Kiểm tra TCVN 5575 / EN 1993-1-1 & Trị riêng mất ổn định
      final chks = CalfemNonlinearEngine.checkMembers(m, rN);
      expect(chks.length, m.nElems);
      expect(chks.every((c) => c.slenderness > 0 && c.chiBuckling > 0 && c.chiBuckling <= 1.0), isTrue);
      final buck = CalfemNonlinearEngine.solveElasticBuckling(m, rL);
      expect(buck.hasBucklingMode, isTrue);
      expect(buck.alphaCr, greaterThan(0.0));
    }

    // 9. Kiểm chứng Trị riêng mất ổn định khớp chính xác Python trên đề bài 5 thanh (α_cr ≈ 1663.45)
    final buck5 = CalfemNonlinearEngine.solveElasticBuckling(m5, lin);
    expect(buck5.hasBucklingMode, isTrue);
    expect(buck5.alphaCr, closeTo(1663.45, 1.5));

    // 10. Kiểm chứng Phi tuyến Vật liệu Đàn-Dẻo (GMNIA) khi ứng suất vượt fy
    final mPlastic = TrussModelData.create(
      preset: TrussPreset.assignment5Bar,
      yieldFyMpa: 250.0,
      materialNonlinear: true,
      hardeningRatio: 0.02,
    );
    final rElasticHigh = CalfemNonlinearEngine.solveFullNR(m5, isTotalLagrangian: false, loadFactor: 8.0, nSteps: 10);
    final rPlasticHigh = CalfemNonlinearEngine.solveFullNR(mPlastic, isTotalLagrangian: false, loadFactor: 8.0, nSteps: 10);
    expect(rPlasticHigh.converged, isTrue);
    expect(rPlasticHigh.yieldedElems.any((y) => y), isTrue);
    // Do chảy dẻo giảm độ cứng xuống Et = 0.02E, chuyển vị u2y của GMNIA lớn hơn đáng kể so với đàn hồi thuần!
    expect(rPlasticHigh.uMm[3].abs(), greaterThan(rElasticHigh.uMm[3].abs() * 1.5));

    // 11. Kiểm chứng Custom Truss Builder (thêm nút + thanh + tải nhiều nút) & ProjectSnapshot JSON round-trip
    final snap = ProjectSnapshot(
      preset: TrussPreset.prattTruss,
      method: SolverMethod.corotationalNR,
      lMm: 1500.0,
      eGpa: 210.0,
      aMm2: 2400.0,
      pKn: 150.0,
      fyMpa: 355.0,
      materialNonlinear: true,
      hardeningRatio: 0.03,
      loadFactor: 2.5,
      nSteps: 12,
      customCoords: const [
        [0.0, 0.0],
        [1500.0, 0.0],
        [3000.0, 0.0],
        [1500.0, 1200.0],
      ],
      customConn: const [
        [1, 2],
        [2, 3],
        [1, 4],
        [2, 4],
        [3, 4],
      ],
      customNodalLoadsKn: const [
        [0.0, 0.0],
        [25.0, -80.0],
        [0.0, 0.0],
        [10.0, -120.0],
      ],
      elemSections: const [
        ElementSectionConfig(shape: SectionShape.doubleAngle, customGeometry: twoL90, rotationDeg: 180.0),
        ElementSectionConfig(shape: SectionShape.channelC, rotationDeg: 90.0),
        ElementSectionConfig(shape: SectionShape.iSection, rotationDeg: 45.0),
        ElementSectionConfig(shape: SectionShape.boxSection, rotationDeg: 0.0),
        ElementSectionConfig(shape: SectionShape.angleL, rotationDeg: 270.0),
      ],
      nodeSupports: const [
        NodeSupportType.pin,
        NodeSupportType.free,
        NodeSupportType.rollerX,
        NodeSupportType.free,
      ],
      supportDirections: const [
        SupportDirection.bottom,
        SupportDirection.auto,
        SupportDirection.bottom,
        SupportDirection.auto,
      ],
      springStiffnessKnMm: 750.0,
      connParams: const ConnectionDesignParams(detailType: ConnectionDetailType.weldedGusset, steelGrade: SteelGrade.s355),
    );
    final decoded = ProjectSnapshot.tryFromJsonString(snap.toJsonString());
    expect(decoded, isNotNull);
    expect(decoded!.preset, TrussPreset.prattTruss);
    expect(decoded.fyMpa, closeTo(355.0, 1e-6));
    expect(decoded.materialNonlinear, isTrue);
    expect(decoded.elemSections.length, 5);
    expect(decoded.elemSections[0].shape, SectionShape.doubleAngle);
    expect(decoded.elemSections[0].rotationDeg, closeTo(180.0, 1e-6));
    expect(decoded.elemSections[4].rotationDeg, closeTo(270.0, 1e-6));
    expect(decoded.customNodalLoadsKn![1][0], closeTo(25.0, 1e-6));
    expect(decoded.customConn!.length, 5);

    final mSnap = TrussModelData.create(
      preset: decoded.preset,
      lMm: decoded.lMm,
      eMpa: decoded.eGpa * 1000.0,
      aMm2: decoded.aMm2,
      pKn: decoded.pKn,
      yieldFyMpa: decoded.fyMpa,
      materialNonlinear: decoded.materialNonlinear,
      hardeningRatio: decoded.hardeningRatio,
      elementSections: decoded.elemSections,
      customCoords: decoded.customCoords,
      customConn: decoded.customConn,
      customNodalLoadsKn: decoded.customNodalLoadsKn,
      customSupports: decoded.nodeSupports,
      customDirections: decoded.supportDirections,
      springStiffnessKnMm: decoded.springStiffnessKnMm,
    );
    final rSnap = CalfemNonlinearEngine.solveFullNR(mSnap, isTotalLagrangian: false, loadFactor: 1.0, nSteps: 8);
    expect(rSnap.converged, isTrue);
    expect(rSnap.sumFxN.abs(), lessThan(1e-3));
    expect(rSnap.sumFyN.abs(), lessThan(1e-3));
  });
}
