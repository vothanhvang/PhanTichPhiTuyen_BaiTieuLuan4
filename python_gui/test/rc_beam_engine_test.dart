import 'package:flutter_test/flutter_test.dart';
import 'package:calfem_nonlinear_truss/core/calfem_engine.dart';
import 'package:calfem_nonlinear_truss/core/connection_calculator.dart';
import 'package:calfem_nonlinear_truss/core/connection_drawing_exporter.dart';
import 'package:calfem_nonlinear_truss/core/rc_beam_engine.dart';

void main() {
  group('Dầm BTCT Phi tuyến Vật liệu — Phương pháp Thớ & Rayleigh-Ritz', () {
    test('Đàn hồi tuyến tính (beam2e) khớp giải tích chính xác: M_max = QL/4 và v = -QL³/(48EI)', () {
      const cfg = RcBeamConfig(
        spanMm: 4000,
        widthMm: 250,
        heightMm: 500,
        loadType: RcBeamLoadType.threePoint,
        loadQKn: 120,
        loadAMm: 2000,
        nElems: 8,
        nonlinearMaterial: false,
      );
      final res = RcBeamFiberEngine.solve(cfg, method: SolverMethod.linearFirstOrder, forceNonlinear: false);
      expect(res.converged, isTrue);
      expect(res.mMaxKnm, closeTo(120.0, 1e-3)); // QL/4 = 120 * 4 / 4 = 120 kN·m
      expect(res.rLeftKn, closeTo(60.0, 1e-3));
      expect(res.rRightKn, closeTo(60.0, 1e-3));
      expect(res.sumFyN.abs(), lessThan(1e-3));

      // Công thức giải tích độ võng giữa nhịp dầm đơn giản: v = -Q*L^3 / (48 * EI_gross)
      final vExact = -(120000.0 * 4000.0 * 4000.0 * 4000.0) / (48.0 * res.eiGrossNmm2);
      expect(res.vMidMm, closeTo(vExact, 1e-3));
    });

    test('Uốn 3 điểm lệch tâm (a = 1200 mm) và Uốn 4 điểm (a = 1300 mm) khớp mô-men giải tích', () {
      const cfg3 = RcBeamConfig(
        spanMm: 4000,
        loadType: RcBeamLoadType.threePoint,
        loadQKn: 100,
        loadAMm: 1200,
        nonlinearMaterial: true,
      );
      final r3 = RcBeamFiberEngine.solve(cfg3);
      expect(r3.converged, isTrue);
      // M_max = Q * a * (L - a) / L = 100 * 1.2 * 2.8 / 4.0 = 84.0 kN·m
      expect(r3.mMaxKnm, closeTo(84.0, 0.05));
      expect(r3.sumFyN.abs(), lessThan(1e-2));

      const cfg4 = RcBeamConfig(
        spanMm: 4000,
        loadType: RcBeamLoadType.fourPoint,
        loadQKn: 150,
        loadAMm: 1300,
        nonlinearMaterial: true,
      );
      final r4 = RcBeamFiberEngine.solve(cfg4);
      expect(r4.converged, isTrue);
      // M_max = (Q/2) * a = 75 * 1.3 = 97.5 kN·m
      expect(r4.mMaxKnm, closeTo(97.5, 0.05));
      expect(r4.sumFyN.abs(), lessThan(1e-2));
    });

    test('Phi tuyến vật liệu thớ: nứt kéo làm giảm EI_eff, nâng trục trung hòa x_NA và tăng độ võng', () {
      const cfg = RcBeamConfig(
        spanMm: 4000,
        widthMm: 250,
        heightMm: 500,
        loadType: RcBeamLoadType.threePoint,
        loadQKn: 120,
        loadAMm: 2000,
        nElems: 8,
        nFibers: 40,
        nonlinearMaterial: true,
      );
      final rLin = RcBeamFiberEngine.solve(cfg, method: SolverMethod.linearFirstOrder, forceNonlinear: false);
      final rNL = RcBeamFiberEngine.solve(cfg, method: SolverMethod.corotationalNR);

      expect(rNL.converged, isTrue);
      expect(rNL.hasCracking, isTrue);
      expect(rNL.mMaxKnm, closeTo(120.0, 0.05));
      expect(rNL.vMidMm.abs(), greaterThan(rLin.vMidMm.abs() * 2.0));
      expect(rNL.sumFyN.abs(), lessThan(1e-2));

      // Phẫu thuật lát cắt giữa nhịp: trục trung hòa dịch lên vùng nén (x_NA < h/2 = 250 mm)
      final midProbe = RcBeamFiberEngine.probeBeamAt(rNL, 0.5);
      expect(midProbe.section.xNeutralDepthMm, lessThan(250.0));
      expect(midProbe.section.eiEffNmm2, lessThan(rNL.eiGrossNmm2));
      expect(midProbe.section.crackDepthMm, greaterThan(100.0));
    });

    test('Dầm cốt cứng (thép hình chữ I đặt lõi) giảm mạnh độ võng và tăng khả năng chịu tải', () {
      const baseCfg = RcBeamConfig(loadQKn: 160, hasRigidCore: false);
      const coreCfg = RcBeamConfig(loadQKn: 160, hasRigidCore: true);
      final rBase = RcBeamFiberEngine.solve(baseCfg);
      final rCore = RcBeamFiberEngine.solve(coreCfg);

      expect(rBase.converged, isTrue);
      expect(rCore.converged, isTrue);
      expect(rCore.vMidMm.abs(), lessThan(rBase.vMidMm.abs() * 0.75));
      expect(rCore.eiGrossNmm2, greaterThan(rBase.eiGrossNmm2));
    });

    test('Tùy chỉnh gối tựa (Ngàm 2 đầu, Công-xôn, Lò xo) và cảnh báo dầm biến hình', () {
      const fixedCfg = RcBeamConfig(
        leftSupport: BeamSupportType.fixed,
        rightSupport: BeamSupportType.fixed,
        loadQKn: 150,
      );
      final rFixed = RcBeamFiberEngine.solve(fixedCfg);
      expect(rFixed.converged, isTrue);
      expect(rFixed.warningMessage, isNull);
      expect(rFixed.vMidMm.abs(), lessThan(2.5));

      const unstableCfg = RcBeamConfig(
        leftSupport: BeamSupportType.free,
        rightSupport: BeamSupportType.free,
      );
      final rUnstable = RcBeamFiberEngine.solve(unstableCfg);
      expect(rUnstable.converged, isFalse);
      expect(rUnstable.warningMessage, isNotNull);
    });

    test('Đường cong P-Δ, M-κ và Khảo sát hội tụ lưới chia hai nửa (2, 4, 8, 16, 32 phần tử)', () {
      const cfg = RcBeamConfig(loadQKn: 120);
      final pushover = RcBeamFiberEngine.tracePushoverCurve(cfg);
      expect(pushover.length, greaterThan(10));
      expect(pushover.any((p) => p.cracked), isTrue);

      final mk = RcBeamFiberEngine.computeMomentCurvature(cfg);
      expect(mk.length, greaterThan(15));
      expect(mk.any((p) => p.yielded), isTrue);

      final conv = RcBeamFiberEngine.runMeshConvergenceStudy(cfg);
      expect(conv.length, equals(5));
      expect(conv.first.nElems, equals(2));
      expect(conv.last.nElems, equals(32));
      expect(conv.last.relErrorPct, closeTo(0.0, 1e-6));
    });
  });

  group('Xuất bản vẽ cấu tạo liên kết AutoCAD (.dxf)', () {
    test('Tạo chuỗi DXF AC1009 hợp lệ đa lớp cho nút liên kết thép', () {
      final model = TrussModelData.create(preset: TrussPreset.assignment5Bar);
      final res = CalfemNonlinearEngine.solveFullNR(model, isTotalLagrangian: false);
      final rep = ConnectionCalculator.analyzeNode(
        model: model,
        result: res,
        nodeIndex: 0,
        params: const ConnectionDesignParams(),
      );
      final dxf = ConnectionDrawingExporter.buildDxfString(model: model, report: rep);
      expect(dxf, contains('AC1009'));
      expect(dxf, contains('TABLES'));
      expect(dxf, contains('LAYER'));
      expect(dxf, contains('BAN_MA'));
      expect(dxf, contains('THANH_THEP'));
      expect(dxf, contains('BU_LONG'));
      expect(dxf, contains('KICH_THUOC'));
      expect(dxf, contains('KHUNG_TEN'));
      expect(dxf, contains('ENTITIES'));
      expect(dxf.trim().endsWith('EOF'), isTrue);
    });
  });
}
