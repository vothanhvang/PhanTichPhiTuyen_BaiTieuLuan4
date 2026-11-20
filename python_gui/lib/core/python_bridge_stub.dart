// Cầu nối lõi Python CALFEM (Web / Android: chạy thuần Dart offline)
import 'calfem_engine.dart';

class PythonBridge {
  static bool get isConnected => false;
  static String get statusLabel => 'Python CALFEM Engine (Offline 100%)';

  static Future<bool> initializeIfDesktop() async => false;

  static Future<TrussAnalysisResult?> tryAnalyzeViaPython(
    TrussModelData model,
    SolverMethod method,
    double loadFactor,
    int nSteps,
  ) async =>
      null;

  static void dispose() {}
}
