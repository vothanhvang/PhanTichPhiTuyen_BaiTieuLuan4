// ============================================================================
// ĐIỂM KHỞI CHẠY ỨNG DỤNG FLUTTER DART: PHÂN TÍCH PHI TUYẾN HÌNH HỌC CALFEM
// ============================================================================
// Đóng gói chạy đồng thời trên:
//   1. Windows x64 (.exe chạy trực tiếp trên mọi máy tính Windows)
//   2. Android ARM64 (.apk tối ưu cho Xiaomi Pad 8 Pro & Xiaomi 13T Pro)
//   3. Web (GitHub Pages chạy trực tiếp trên trình duyệt tại GitHub)
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'screens/home_studio_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CalfemNonlinearApp());
}

class CalfemNonlinearApp extends StatelessWidget {
  const CalfemNonlinearApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isWindowsDesktop = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    return MaterialApp(
      title: 'CALFEM Nonlinear Studio — Phân tích Phi tuyến Hình học 2D/3D',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => ExcludeSemantics(
        excluding: isWindowsDesktop,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeStudioScreen(),
    );
  }
}
