// ============================================================================
// ĐIỂM KHỞI CHẠY ỨNG DỤNG: PHÂN TÍCH PHI TUYẾN HÌNH HỌC HỆ DÀN CALFEM
// ============================================================================
// Đóng gói chạy đồng thời trên Windows x64, Android ARM64 và Web GitHub Pages
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'screens/home_studio_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CalfemNonlinearApp());
}

class CalfemNonlinearApp extends StatefulWidget {
  const CalfemNonlinearApp({super.key});

  @override
  State<CalfemNonlinearApp> createState() => _CalfemNonlinearAppState();
}

class _CalfemNonlinearAppState extends State<CalfemNonlinearApp> {
  bool _darkMode = true;

  @override
  Widget build(BuildContext context) {
    final isWindowsDesktop = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final darkTheme = ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF070D19),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF06B6D4),
        secondary: Color(0xFF10B981),
        surface: Color(0xFF0F172A),
      ),
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'DejaVuSans'),
    );
    final lightTheme = ThemeData.light(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0F3D6E),
        secondary: Color(0xFF0F766E),
      ),
      textTheme: ThemeData.light().textTheme.apply(fontFamily: 'DejaVuSans'),
    );

    return MaterialApp(
      title: 'CALFEM Python Studio — Phân tích Phi tuyến Hình học 2D/3D',
      debugShowCheckedModeBanner: false,
      theme: _darkMode ? darkTheme : lightTheme,
      builder: (context, child) => ExcludeSemantics(
        excluding: isWindowsDesktop,
        child: child ?? const SizedBox.shrink(),
      ),
      home: HomeStudioScreen(
        initialDarkMode: _darkMode,
        onThemeChanged: (v) => setState(() => _darkMode = v),
      ),
    );
  }
}
