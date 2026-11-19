import 'package:flutter_test/flutter_test.dart';
import 'package:calfem_nonlinear_truss/core/calfem_engine.dart';

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
  });
}
