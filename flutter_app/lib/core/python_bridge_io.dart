// ============================================================================
// CẦU NỐI LIVE PYTHON CALFEM ENGINE TRÊN WINDOWS DESKTOP
// ============================================================================
// Tự động tìm & khởi chạy `calfem_engine.exe` đi kèm cạnh file .exe Flutter
// (hoặc gọi python_core/api_server.py khi chạy trong môi trường phát triển).
// Nếu kết nối thành công, toàn bộ phép tính phi tuyến chạy trực tiếp trên lõi
// Python NumPy/SciPy CALFEM thật; nếu không (hoặc trên Android) tự động dùng
// lõi Dart CALFEM song song khớp 100%!
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'calfem_engine.dart';

class PythonBridge {
  static bool _connected = false;
  static const int _port = 18765;
  static Uri _uri(String path) => Uri.parse('http://127.0.0.1:$_port$path');

  static bool get isConnected => _connected;
  static String get statusLabel => _connected
      ? 'Python CALFEM Engine: ONLINE (Live)'
      : 'Dart CALFEM Core (Offline 100%)';

  static Future<bool> _ping() async {
    try {
      final resp = await http.get(_uri('/api/health')).timeout(const Duration(milliseconds: 450));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> initializeIfDesktop() async {
    if (!Platform.isWindows) return false;
    if (await _ping()) {
      _connected = true;
      return true;
    }

    // Tìm calfem_engine.exe nằm cùng thư mục với file .exe Flutter
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir\\calfem_engine.exe',
      '${Directory.current.path}\\python_core\\dist\\calfem_engine.exe',
      '${Directory.current.parent.path}\\python_core\\dist\\calfem_engine.exe',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) {
        try {
          await Process.start(path, ['--port', '$_port'], mode: ProcessStartMode.detached);
          for (int i = 0; i < 12; i++) {
            await Future.delayed(const Duration(milliseconds: 350));
            if (await _ping()) {
              _connected = true;
              return true;
            }
          }
        } catch (_) {}
      }
    }
    _connected = false;
    return false;
  }

  static Future<TrussAnalysisResult?> tryAnalyzeViaPython(
    TrussModelData model,
    SolverMethod method,
    double loadFactor,
    int nSteps,
  ) async {
    if (!_connected) return null;
    try {
      final presetCode = model.name.contains('Dahlblom')
          ? 'dahlblom_ex9_1'
          : (model.name.contains('exs3')
              ? 'calfem_exs3'
              : (model.name.contains('Von Mises') ? 'von_mises' : 'assignment_5bar'));
      final payload = {
        'preset': presetCode,
        'L_mm': model.baseL,
        'E_mpa': model.E,
        'A_mm2': model.baseA,
        'P_kN': model.basePKn,
        'nu': model.nu,
        'section_shape': model.sectionShape.code,
        'load_factor': loadFactor,
        'n_steps': nSteps,
      };
      final resp = await http
          .post(
            _uri('/api/analyze'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final keyMap = {
        SolverMethod.linearFirstOrder: 'linear',
        SolverMethod.bar2gSecondOrder: 'bar2g_second_order',
        SolverMethod.corotationalNR: 'corotational_nr',
        SolverMethod.totalLagrangian: 'total_lagrangian',
        SolverMethod.modifiedNR: 'modified_nr',
        SolverMethod.eulerSingleStep: 'euler',
        SolverMethod.rk2Midpoint: 'rk2',
      };
      final r = data[keyMap[method]] as Map<String, dynamic>?;
      if (r == null) return null;
      final eq = r['equilibrium_check'] as Map<String, dynamic>;
      final extra = (r['extra'] as Map<String, dynamic>?) ?? {};
      final histRaw = (r['history'] as List<dynamic>?) ?? [];
      final hist = <LoadStepRecord>[];
      for (final h in histRaw) {
        final m = h as Map<String, dynamic>;
        hist.add(LoadStepRecord(
          step: (m['step'] ?? m['iteration'] ?? 0) as int,
          lambda: ((m['lambda'] ?? loadFactor) as num).toDouble(),
          iterations: (m['iterations'] ?? m['iteration'] ?? 1) as int,
          residualInfN: ((m['residual_inf_N'] ?? m['rel_err_N'] ?? 0.0) as num).toDouble(),
          uMm: ((m['u_mm'] as List<dynamic>?) ?? (r['u_mm'] as List<dynamic>))
              .map((v) => (v as num).toDouble())
              .toList(),
          nForcesN: ((m['N_N'] as List<dynamic>?) ?? (r['N_N'] as List<dynamic>))
              .map((v) => (v as num).toDouble())
              .toList(),
        ));
      }
      return TrussAnalysisResult(
        methodName: r['method_name'] as String,
        engineSource: 'Python CALFEM Engine (Live NumPy/SciPy)',
        converged: r['converged'] as bool,
        uMm: (r['u_mm'] as List).map((e) => (e as num).toDouble()).toList(),
        reactionsN: (r['reactions_N'] as List).map((e) => (e as num).toDouble()).toList(),
        nForcesN: (r['N_N'] as List).map((e) => (e as num).toDouble()).toList(),
        stressMpa: (r['stress_MPa'] as List).map((e) => (e as num).toDouble()).toList(),
        strain: (r['strain'] as List).map((e) => (e as num).toDouble()).toList(),
        elongationMm: (r['elongation_mm'] as List).map((e) => (e as num).toDouble()).toList(),
        currentLengthsMm: (r['current_lengths_mm'] as List).map((e) => (e as num).toDouble()).toList(),
        memberEnergyNmm: (r['member_energy_Nmm'] as List).map((e) => (e as num).toDouble()).toList(),
        totalEnergyNmm: (r['total_energy_Nmm'] as num).toDouble(),
        sumFxN: (eq['sum_Fx_N'] as num).toDouble(),
        sumFyN: (eq['sum_Fy_N'] as num).toDouble(),
        sumMNmm: (eq['sum_M_Nmm'] as num).toDouble(),
        maxFreeResidualN: (eq['max_free_residual_N'] as num).toDouble(),
        totalIterations: (extra['total_iterations'] ?? extra['iterations'] ?? hist.length) as int,
        totalFactorizations: (extra['total_stiffness_factorizations'] ?? extra['iterations'] ?? hist.length) as int,
        history: hist,
      );
    } catch (_) {
      return null;
    }
  }

  static void dispose() {
    if (_connected) {
      http.post(_uri('/api/shutdown')).timeout(const Duration(milliseconds: 400)).catchError((_) => http.Response('', 200));
    }
    _connected = false;
  }
}
