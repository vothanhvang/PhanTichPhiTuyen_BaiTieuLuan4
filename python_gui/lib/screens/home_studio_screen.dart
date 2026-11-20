// ============================================================================
// MÀN HÌNH CHÍNH: ANSYS-STYLE CALFEM NONLINEAR STRUCTURAL STUDIO
// ============================================================================
// Thiết kế thích ứng hoàn hảo (Responsive Adaptive Layout):
//   • Windows Desktop & Máy tính bảng Xiaomi Pad 8 Pro (màn hình rộng ≥ 920px):
//       Bố cục 3 cột chuẩn ANSYS Workbench (Cây thông số trái | Cửa sổ 2D/3D
//       chính giữa | Bảng Phẫu thuật / Biểu đồ / Lý thuyết bên phải).
//   • Điện thoại Xiaomi 13T Pro (màn hình hẹp < 920px):
//       Bố cục 5 tab hiện đại dưới đáy (Mô phỏng 2D/3D | Phẫu thuật | Thông số
//       | Biểu đồ & Bảng | Lý thuyết) tối ưu cảm ứng một tay!
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/calfem_engine.dart';
import '../core/report_generator.dart';
import '../core/python_bridge_stub.dart'
    if (dart.library.io) '../core/python_bridge_io.dart';
import '../widgets/ansys_viewport_2d.dart';
import '../widgets/ansys_viewport_3d.dart';
import '../widgets/surgical_dissection_panel.dart';
import '../widgets/charts_and_tables_panel.dart';
import '../widgets/theory_and_code_panel.dart';

class HomeStudioScreen extends StatefulWidget {
  const HomeStudioScreen({super.key});

  @override
  State<HomeStudioScreen> createState() => _HomeStudioScreenState();
}

class _HomeStudioScreenState extends State<HomeStudioScreen> {
  // Tham số mô hình có thể tùy biến trực tiếp
  TrussPreset _preset = TrussPreset.assignment5Bar;
  SolverMethod _method = SolverMethod.corotationalNR;
  SectionShape _sectionShape = SectionShape.iSection;
  ContourField _contourField = ContourField.axialStress;

  double _lMm = 1000.0;
  double _eGpa = 200.0;
  double _aMm2 = 2001.0;
  double _pKn = 208.0;
  double _loadFactor = 1.0;
  int _nSteps = 10;

  // Trạng thái hiển thị 2D/3D & Phẫu thuật
  bool _is3D = true;
  bool _surgicalMode = true;
  bool _darkMode = true;
  double _deformScale = 180.0;
  double _playbackFrac = 1.0;
  Timer? _animTimer;

  // Trạng thái khảo sát & Phẫu thuật (Probe & Dissection)
  int _selectedElem = 3; // Mặc định Thanh 4 (3-2 chéo nén)
  double _probeXi = 0.5;
  double _etaNorm = 0.0;
  double _zetaNorm = 0.0;
  double _imperfectionRatio = 0.002; // L/500 (chuẩn Eurocode 3) để thấy rõ độ nhạy P-δ khi kéo lát cắt ξ

  // Tab chọn trên màn hình rộng (bảng phải) & màn hình hẹp (bottom nav)
  int _rightTab = 0;
  int _mobileTab = 0;

  // Dữ liệu tính toán hiện hành
  late TrussModelData _model;
  late TrussAnalysisResult _resLinear;
  late TrussAnalysisResult _resBar2g;
  late TrussAnalysisResult _resCorot;
  late TrussAnalysisResult _resTL;
  late TrussAnalysisResult _resActive;
  late List<EquilibriumPoint> _snapCurve;

  bool _pythonOnline = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _recomputeLocal();
    _initPythonBridge();
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    PythonBridge.dispose();
    super.dispose();
  }

  Future<void> _initPythonBridge() async {
    final ok = await PythonBridge.initializeIfDesktop();
    if (!mounted) return;
    setState(() => _pythonOnline = ok);
    if (ok) {
      await _syncFromPythonIfAvailable();
    }
  }

  void _recomputeLocal() {
    _model = TrussModelData.create(
      preset: _preset,
      lMm: _lMm,
      eMpa: _eGpa * 1000.0,
      aMm2: _aMm2,
      pKn: _pKn,
      sectionShape: _sectionShape,
    );
    if (_selectedElem >= _model.nElems) {
      _selectedElem = 0;
    }
    _resLinear = CalfemNonlinearEngine.solveLinear(_model, loadFactor: _loadFactor);
    _resBar2g = CalfemNonlinearEngine.solveBar2gSecondOrder(_model, loadFactor: _loadFactor);
    _resCorot = CalfemNonlinearEngine.solveFullNR(_model,
        isTotalLagrangian: false, loadFactor: _loadFactor, nSteps: _nSteps);
    _resTL = CalfemNonlinearEngine.solveFullNR(_model,
        isTotalLagrangian: true, loadFactor: _loadFactor, nSteps: _nSteps);
    _resActive = CalfemNonlinearEngine.solve(
      _model,
      method: _method,
      loadFactor: _loadFactor,
      nSteps: _nSteps,
    );
    _snapCurve = CalfemNonlinearEngine.traceSnapThroughCurve(_model);
  }

  Future<void> _syncFromPythonIfAvailable() async {
    if (!_pythonOnline) return;
    final pyRes = await PythonBridge.tryAnalyzeViaPython(_model, _method, _loadFactor, _nSteps);
    if (pyRes != null && mounted) {
      setState(() => _resActive = pyRes);
    }
  }

  void _updateAndSolve(VoidCallback mutate) {
    setState(() {
      mutate();
      _recomputeLocal();
    });
    _syncFromPythonIfAvailable();
  }

  void _toggleAnimation() {
    if (_animTimer != null) {
      _animTimer!.cancel();
      setState(() {
        _animTimer = null;
        _playbackFrac = 1.0;
      });
      return;
    }
    _playbackFrac = 0.0;
    _animTimer = Timer.periodic(const Duration(milliseconds: 36), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _playbackFrac += 0.025;
        if (_playbackFrac > 1.0) _playbackFrac = 0.0;
      });
    });
  }

  Future<void> _exportReport(bool asPdf) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final probe = CalfemNonlinearEngine.probeMember(
        model: _model,
        resultNL: _resActive,
        resultLin: _resLinear,
        elemIndex: _selectedElem,
        xi: _probeXi,
        etaNorm: _etaNorm,
        zetaNorm: _zetaNorm,
        imperfectionRatio: _imperfectionRatio,
      );
      final savedPath = asPdf
          ? await FlutterReportGenerator.exportPdf(
              model: _model,
              linear: _resLinear,
              nonlinear: _resActive,
              probe: probe,
              loadFactor: _loadFactor,
            )
          : await FlutterReportGenerator.exportDocx(
              model: _model,
              linear: _resLinear,
              nonlinear: _resActive,
              probe: probe,
              loadFactor: _loadFactor,
            );
      if (!mounted) return;
      if (savedPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF475569),
            duration: Duration(seconds: 2),
            content: Text('Đã hủy lưu tệp báo cáo.'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0F766E),
          duration: const Duration(seconds: 5),
          content: Text('Xuất báo cáo ${asPdf ? "PDF" : "Word (.docx)"} thành công!\n$savedPath'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFB91C1C), content: Text('Lỗi xuất báo cáo: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _darkMode ? const Color(0xFF070D19) : const Color(0xFFF1F5F9);
    final barBg = _darkMode ? const Color(0xFF0F172A) : Colors.white;
    final probe = CalfemNonlinearEngine.probeMember(
      model: _model,
      resultNL: _resActive,
      resultLin: _resLinear,
      elemIndex: _selectedElem,
      xi: _probeXi,
      etaNorm: _etaNorm,
      zetaNorm: _zetaNorm,
      imperfectionRatio: _imperfectionRatio,
    );

    return Theme(
      data: _darkMode
          ? ThemeData.dark(useMaterial3: true).copyWith(
              scaffoldBackgroundColor: bg,
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF06B6D4),
                secondary: Color(0xFF10B981),
                surface: Color(0xFF0F172A),
              ),
              textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'DejaVuSans'),
            )
          : ThemeData.light(useMaterial3: true).copyWith(
              scaffoldBackgroundColor: bg,
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF0F3D6E),
                secondary: Color(0xFF0F766E),
              ),
              textTheme: ThemeData.light().textTheme.apply(fontFamily: 'DejaVuSans'),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 920;
          return Scaffold(
            appBar: AppBar(
              backgroundColor: barBg,
              elevation: 0,
              toolbarHeight: 54,
              title: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/python_logo.png', width: 34, height: 34, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CALFEM Python Studio — Phân tích Phi tuyến Hình học 2D/3D',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'ĐH Bách Khoa TP.HCM • Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624) • Liên hệ: vothanhvang@gmail.com',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: _pythonOnline ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                if (isWide) ...[
                  _topActionBtn(Icons.description, 'Xuất Word', () => _exportReport(false), const Color(0xFF2563EB)),
                  const SizedBox(width: 6),
                  _topActionBtn(Icons.picture_as_pdf, 'Xuất PDF', () => _exportReport(true), const Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                ] else ...[
                  IconButton(
                    tooltip: 'Xuất Word (.docx)',
                    icon: const Icon(Icons.description, color: Color(0xFF38BDF8)),
                    onPressed: () => _exportReport(false),
                  ),
                  IconButton(
                    tooltip: 'Xuất PDF (.pdf)',
                    icon: const Icon(Icons.picture_as_pdf, color: Color(0xFFF43F5E)),
                    onPressed: () => _exportReport(true),
                  ),
                ],
                IconButton(
                  tooltip: 'Thông tin nhóm & Liên hệ (vothanhvang@gmail.com)',
                  icon: const Icon(Icons.contact_mail_outlined, color: Color(0xFF38BDF8)),
                  onPressed: _showContactDialog,
                ),
                IconButton(
                  tooltip: _darkMode ? 'Chế độ sáng' : 'Chế độ tối ANSYS',
                  icon: Icon(_darkMode ? Icons.light_mode : Icons.dark_mode),
                  onPressed: () => setState(() => _darkMode = !_darkMode),
                ),
                const SizedBox(width: 6),
              ],
            ),
            body: isWide
                ? _buildWideWorkbench(probe)
                : _buildMobileWorkbench(probe),
            bottomNavigationBar: isWide
                ? null
                : NavigationBar(
                    selectedIndex: _mobileTab,
                    height: 62,
                    onDestinationSelected: (i) => setState(() => _mobileTab = i),
                    destinations: const [
                      NavigationDestination(icon: Icon(Icons.view_in_ar), label: 'Mô phỏng'),
                      NavigationDestination(icon: Icon(Icons.biotech), label: 'Phẫu thuật'),
                      NavigationDestination(icon: Icon(Icons.tune), label: 'Thông số'),
                      NavigationDestination(icon: Icon(Icons.show_chart), label: 'Biểu đồ'),
                      NavigationDestination(icon: Icon(Icons.menu_book), label: 'Lý thuyết'),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _topActionBtn(IconData icon, String label, VoidCallback onTap, Color color) {
    return ElevatedButton.icon(
      onPressed: _exporting ? null : onTap,
      icon: Icon(icon, size: 15, color: Colors.white),
      label: Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Bố cục 3 cột chuẩn ANSYS Workbench cho Windows Desktop & Xiaomi Pad 8 Pro
  Widget _buildWideWorkbench(ProbeInspection probe) {
    final border = _darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    return Row(
      children: [
        // CỘT TRÁI: Cây tham số & bộ giải
        SizedBox(
          width: 318,
          child: Container(
            decoration: BoxDecoration(border: Border(right: BorderSide(color: border))),
            child: _buildControlPanel(),
          ),
        ),
        // CỘT GIỮA: Cửa sổ mô phỏng 2D / 3D chuẩn ANSYS + Thanh Playback & Mode
        Expanded(
          flex: 5,
          child: _buildViewportColumn(probe),
        ),
        // CỘT PHẢI: Phòng Phẫu thuật / Biểu đồ & Bảng / Lý thuyết & Code
        SizedBox(
          width: 390,
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: border))),
            child: Column(
              children: [
                Container(
                  color: _darkMode ? const Color(0xFF0F172A) : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, icon: Icon(Icons.biotech, size: 15), label: Text('Phẫu thuật', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 1, icon: Icon(Icons.analytics, size: 15), label: Text('Biểu đồ', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 2, icon: Icon(Icons.code, size: 15), label: Text('Lý thuyết', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_rightTab},
                    onSelectionChanged: (s) => setState(() => _rightTab = s.first),
                  ),
                ),
                Expanded(child: _buildRightContent(probe, _rightTab)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Bố cục 5 tab cảm ứng tối ưu cho điện thoại Xiaomi 13T Pro
  Widget _buildMobileWorkbench(ProbeInspection probe) {
    switch (_mobileTab) {
      case 0:
        return _buildViewportColumn(probe);
      case 1:
        return _buildRightContent(probe, 0);
      case 2:
        return _buildControlPanel();
      case 3:
        return _buildRightContent(probe, 1);
      default:
        return _buildRightContent(probe, 2);
    }
  }

  Widget _buildViewportColumn(ProbeInspection probe) {
    final barBg = _darkMode ? const Color(0xFF0F172A) : Colors.white;
    final border = _darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);

    return Column(
      children: [
        // Thanh công cụ chế độ 2D / 3D + Phẫu thuật + Trường màu ANSYS + Animation
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: barBg,
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.grid_on, size: 15), label: Text('2D', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: true, icon: Icon(Icons.view_in_ar, size: 15), label: Text('3D ANSYS', style: TextStyle(fontSize: 11))),
                ],
                selected: {_is3D},
                onSelectionChanged: (s) => setState(() => _is3D = s.first),
              ),
              FilterChip(
                avatar: Icon(Icons.content_cut, size: 15, color: _surgicalMode ? Colors.black : const Color(0xFF00E5FF)),
                label: Text('Phẫu thuật cắt mặt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _surgicalMode ? Colors.black : null)),
                selected: _surgicalMode,
                selectedColor: const Color(0xFF00E5FF),
                onSelected: (v) => setState(() => _surgicalMode = v),
              ),
              DropdownButton<ContourField>(
                value: _contourField,
                isDense: true,
                underline: const SizedBox(),
                items: [
                  for (final f in ContourField.values)
                    DropdownMenuItem(value: f, child: Text(f.label, style: const TextStyle(fontSize: 11.5))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _contourField = v);
                },
              ),
              OutlinedButton.icon(
                onPressed: _toggleAnimation,
                icon: Icon(_animTimer == null ? Icons.play_arrow : Icons.stop, size: 16),
                label: Text(_animTimer == null ? 'Chạy mô phỏng tải' : 'Dừng', style: const TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),

        // Cửa sổ hiển thị 2D hoặc 3D chính
        Expanded(
          child: _is3D
              ? AnsysViewport3D(
                  model: _model,
                  result: _resActive,
                  field: _contourField,
                  deformScale: _deformScale,
                  playbackFraction: _playbackFrac,
                  selectedElem: _selectedElem,
                  probeXi: _probeXi,
                  surgicalMode: _surgicalMode,
                  darkMode: _darkMode,
                  onProbeChanged: (e, xi) => setState(() {
                    _selectedElem = e;
                    _probeXi = xi;
                  }),
                )
              : AnsysViewport2D(
                  model: _model,
                  result: _resActive,
                  field: _contourField,
                  deformScale: _deformScale,
                  playbackFraction: _playbackFrac,
                  selectedElem: _selectedElem,
                  probeXi: _probeXi,
                  surgicalMode: _surgicalMode,
                  darkMode: _darkMode,
                  onProbeChanged: (e, xi) => setState(() {
                    _selectedElem = e;
                    _probeXi = xi;
                  }),
                ),
        ),

        // Thanh trạng thái nhanh dưới đáy Viewport (Tỷ lệ phóng đại + Tóm tắt Probe)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: barBg,
            border: Border(top: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              const Text('Phóng đại biến dạng:', style: TextStyle(fontSize: 11)),
              SizedBox(
                width: 120,
                child: Slider(
                  value: _deformScale.clamp(1.0, 500.0),
                  min: 1.0,
                  max: 500.0,
                  onChanged: (v) => setState(() => _deformScale = v),
                ),
              ),
              Text('×${_deformScale.round()}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Đầu dò: Thanh ${probe.memberLabel} (ξ=${probe.xi.toStringAsFixed(2)})  |  '
                  'σ=${probe.sigmaXxMpa.toStringAsFixed(2)} MPa  |  '
                  'ε=${probe.epsXxMicro.toStringAsFixed(1)} με  |  '
                  '||u||=${probe.uMagMm.toStringAsFixed(4)} mm',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.8, fontFamily: 'DejaVuSansMono'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showContactDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _darkMode ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF06B6D4), width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.contact_mail, color: Color(0xFF38BDF8), size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Thông tin Phần mềm & Liên hệ',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CALFEM Python Studio — Phân tích Phi tuyến Hình học 2D/3D',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF38BDF8)),
            ),
            const SizedBox(height: 8),
            const Text('• Đơn vị: Trường ĐH Bách Khoa – ĐHQG TP.HCM\n'
                '• Học phần: Phân tích Phi tuyến Kết cấu\n'
                '• GVHD: PGS.TS. Ngô Hữu Cường\n'
                '• Học viên thực hiện:\n'
                '    - Lâm Phúc Tâm (MSHV: 2670621)\n'
                '    - Võ Thanh Vang (MSHV: 2670624)',
                style: TextStyle(fontSize: 12, height: 1.5)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _darkMode ? const Color(0xFF0A1426) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.email_outlined, size: 18, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: SelectableText(
                      'vothanhvang@gmail.com',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: 'vothanhvang@gmail.com'));
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFF0F766E),
                          duration: Duration(seconds: 2),
                          content: Text('Đã sao chép email liên hệ: vothanhvang@gmail.com'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Sao chép', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              '• Lõi tính toán: ${_resActive.engineSource}\n'
              '• GitHub: https://github.com/vothanhvang/PhanTichPhiTuyen_BaiTieuLuan4',
              style: TextStyle(fontSize: 10.8, color: _darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _resetDefaults() {
    FocusScope.of(context).unfocus();
    _animTimer?.cancel();
    _animTimer = null;
    _updateAndSolve(() {
      _preset = TrussPreset.assignment5Bar;
      _method = SolverMethod.corotationalNR;
      _sectionShape = SectionShape.iSection;
      _contourField = ContourField.axialStress;
      _lMm = 1000.0;
      _eGpa = 200.0;
      _aMm2 = 2001.0;
      _pKn = 208.0;
      _loadFactor = 1.0;
      _nSteps = 10;
      _deformScale = 180.0;
      _playbackFrac = 1.0;
      _selectedElem = 3;
      _probeXi = 0.5;
      _etaNorm = 0.0;
      _zetaNorm = 0.0;
      _imperfectionRatio = 0.002;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF0F3D6E),
          duration: Duration(seconds: 2),
          content: Text('Đã Reset toàn bộ thông số về đề bài mặc định (L=1000 mm, E=200 GPa, A=2001 mm², P=208 kN, λ=1, n=10).'),
        ),
      );
    }
  }

  Widget _buildControlPanel() {
    final cardBg = _darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = _darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);

    // So sánh nhanh chuyển vị cực đại Tuyến tính vs Phi tuyến
    final u2yLin = _model.nDofs >= 4 ? _resLinear.uMm[3] : 0.0;
    final u2yNL = _model.nDofs >= 4 ? _resActive.uMm[3] : 0.0;
    final diffPct = u2yLin.abs() > 1e-12 ? 100.0 * (u2yNL - u2yLin) / u2yLin : 0.0;

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // Card 1: Chọn mô hình & thuật toán
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. Mô hình & Thuật toán CALFEM',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF38BDF8))),
              const SizedBox(height: 6),
              DropdownButtonFormField<TrussPreset>(
                initialValue: _preset,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bài toán mẫu', isDense: true, border: OutlineInputBorder()),
                items: [
                  for (final p in TrussPreset.values)
                    DropdownMenuItem(
                      value: p,
                      child: Text(p.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _updateAndSolve(() {
                    _preset = v;
                    _loadFactor = 1.0;
                    _deformScale = v == TrussPreset.dahlblomEx91 ? 3.0 : (v == TrussPreset.vonMisesArch ? 5.0 : 180.0);
                  });
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<SolverMethod>(
                initialValue: _method,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Thuật toán giải (NSA_4 & NSA_6)', isDense: true, border: OutlineInputBorder()),
                items: [
                  for (final m in SolverMethod.values)
                    DropdownMenuItem(value: m, child: Text(m.label, style: const TextStyle(fontSize: 11))),
                ],
                onChanged: (v) {
                  if (v != null) _updateAndSolve(() => _method = v);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<SectionShape>(
                initialValue: _sectionShape,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mặt cắt 3D để Phẫu thuật', isDense: true, border: OutlineInputBorder()),
                items: [
                  for (final s in SectionShape.values)
                    DropdownMenuItem(value: s, child: Text(s.label, style: const TextStyle(fontSize: 11))),
                ],
                onChanged: (v) {
                  if (v != null) _updateAndSolve(() => _sectionShape = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Card 2: Thông số hình học, vật liệu & mức tải (Nhập số trực tiếp + Thanh trượt + Reset)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('2. Thông số Vật liệu & Tải trọng',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.3, color: Color(0xFF38BDF8))),
                  ),
                  Tooltip(
                    message: 'Đặt lại toàn bộ thông số về đề bài gốc',
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.6)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: _resetDefaults,
                      icon: const Icon(Icons.restart_alt, size: 13),
                      label: const Text('Reset', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _EditableParamSlider(
                label: 'Chiều dài cơ sở L',
                value: _lMm,
                min: 500,
                max: 3000,
                hardMin: 10,
                hardMax: 100000,
                unit: 'mm',
                darkMode: _darkMode,
                onChanged: (v) => _updateAndSolve(() => _lMm = v),
              ),
              _EditableParamSlider(
                label: 'Mô-đun đàn hồi E',
                value: _eGpa,
                min: 50,
                max: 400,
                hardMin: 1,
                hardMax: 10000,
                unit: 'GPa',
                darkMode: _darkMode,
                onChanged: (v) => _updateAndSolve(() => _eGpa = v),
              ),
              _EditableParamSlider(
                label: 'Diện tích cơ sở A',
                value: _aMm2,
                min: 500,
                max: 5000,
                hardMin: 1,
                hardMax: 500000,
                unit: 'mm²',
                darkMode: _darkMode,
                onChanged: (v) => _updateAndSolve(() => _aMm2 = v),
              ),
              _EditableParamSlider(
                label: 'Tải trọng tham chiếu P',
                value: _pKn,
                min: -600,
                max: 600,
                hardMin: -100000,
                hardMax: 100000,
                allowNegative: true,
                unit: 'kN',
                darkMode: _darkMode,
                onChanged: (v) => _updateAndSolve(() => _pKn = v),
              ),
              _EditableParamSlider(
                label: 'Hệ số nhân tải λ',
                value: _loadFactor,
                min: -200,
                max: 300,
                hardMin: -1000,
                hardMax: 1000,
                allowNegative: true,
                unit: '×P',
                darkMode: _darkMode,
                onChanged: (v) {
                  _updateAndSolve(() {
                    _loadFactor = v.abs() < 1e-4 ? 1.0 : v;
                    if (_loadFactor.abs() > 20) {
                      _deformScale = 1.5;
                    }
                  });
                },
              ),
              _EditableParamSlider(
                label: 'Số bước tăng tải n',
                value: _nSteps.toDouble(),
                min: 1,
                max: 30,
                hardMin: 1,
                hardMax: 200,
                isInt: true,
                unit: 'bước',
                darkMode: _darkMode,
                onChanged: (v) => _updateAndSolve(() => _nSteps = v.round().clamp(1, 200)),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _resetDefaults,
                  icon: const Icon(Icons.settings_backup_restore, size: 15),
                  label: const Text('Reset thông số về mặc định', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _darkMode ? const Color(0xFF94A3B8) : const Color(0xFF334155),
                    side: BorderSide(color: border),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Card 3: Tóm tắt KPI trực quan
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('3. Chỉ số Kết quả Tức thì',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF10B981))),
              const SizedBox(height: 6),
              Text(
                '• u₂y Tuyến tính : ${u2yLin.toStringAsFixed(6)} mm\n'
                '• u₂y Phi tuyến  : ${u2yNL.toStringAsFixed(6)} mm (${diffPct >= 0 ? "+" : ""}${diffPct.toStringAsFixed(3)}%)\n'
                '• Thanh 1-2 N₁₂  : ${_resActive.nForcesN[0].toStringAsFixed(2)} N (TT = 0 N)\n'
                '• Hội tụ         : ${_resActive.converged ? "ĐẠT" : "CHƯA ĐẠT"} (${_resActive.totalIterations} vòng lặp)',
                style: const TextStyle(fontSize: 10.5, fontFamily: 'DejaVuSansMono', height: 1.45),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _exporting ? null : () => _exportReport(false),
                      icon: const Icon(Icons.description, size: 14, color: Colors.white),
                      label: const Text('Word', style: TextStyle(fontSize: 11, color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _exporting ? null : () => _exportReport(true),
                      icon: const Icon(Icons.picture_as_pdf, size: 14, color: Colors.white),
                      label: const Text('PDF', style: TextStyle(fontSize: 11, color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightContent(ProbeInspection probe, int tabIdx) {
    if (tabIdx == 0) {
      return SurgicalDissectionPanel(
        model: _model,
        resultNL: _resActive,
        resultLin: _resLinear,
        probe: probe,
        selectedElem: _selectedElem,
        probeXi: _probeXi,
        etaNorm: _etaNorm,
        zetaNorm: _zetaNorm,
        imperfectionRatio: _imperfectionRatio,
        darkMode: _darkMode,
        onElemChanged: (e) => setState(() => _selectedElem = e),
        onXiChanged: (xi) => setState(() => _probeXi = xi),
        onFiberChanged: (eta, zeta) => setState(() {
          _etaNorm = eta;
          _zetaNorm = zeta;
        }),
        onImperfectionChanged: (r) => setState(() => _imperfectionRatio = r),
      );
    }
    if (tabIdx == 1) {
      return ChartsAndTablesPanel(
        model: _model,
        resLinear: _resLinear,
        resActive: _resActive,
        resBar2g: _resBar2g,
        resCorot: _resCorot,
        resTL: _resTL,
        snapCurve: _snapCurve,
        darkMode: _darkMode,
      );
    }
    return TheoryAndCodePanel(darkMode: _darkMode);
  }
}

/// Ô nhập thông số kết hợp Thanh trượt (Dual Numeric TextField + Slider)
/// Cho phép gõ trực tiếp giá trị chính xác (Enter hoặc rời ô để áp dụng)
/// đồng bộ hai chiều tức thời với Slider và nút Reset mặc định.
class _EditableParamSlider extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double hardMin;
  final double hardMax;
  final String unit;
  final bool isInt;
  final bool allowNegative;
  final bool darkMode;
  final ValueChanged<double> onChanged;

  const _EditableParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.hardMin,
    required this.hardMax,
    required this.unit,
    required this.darkMode,
    required this.onChanged,
    this.isInt = false,
    this.allowNegative = false,
  });

  @override
  State<_EditableParamSlider> createState() => _EditableParamSliderState();
}

class _EditableParamSliderState extends State<_EditableParamSlider> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  String _fmt(double v) {
    if (widget.isInt) return v.round().toString();
    if ((v - v.roundToDouble()).abs() < 1e-6) {
      return v.round().toString();
    }
    var s = v.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
    _focus = FocusNode();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
      } else {
        _commitText();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _EditableParamSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && (oldWidget.value - widget.value).abs() > 1e-9) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _commitText() {
    final raw = _ctrl.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw);
    if (parsed == null || !parsed.isFinite) {
      _ctrl.text = _fmt(widget.value);
      return;
    }
    final clamped = parsed.clamp(widget.hardMin, widget.hardMax).toDouble();
    final finalVal = widget.isInt ? clamped.roundToDouble() : clamped;
    _ctrl.text = _fmt(finalVal);
    if ((finalVal - widget.value).abs() > 1e-9) {
      widget.onChanged(finalVal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.darkMode ? const Color(0xFF0A1324) : const Color(0xFFF8FAFC);
    final bdr = widget.darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    final allowedRegex = widget.isInt
        ? RegExp(r'[0-9]')
        : (widget.allowNegative ? RegExp(r'[0-9\.\,\-]') : RegExp(r'[0-9\.\,]'));

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 74,
                height: 26,
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.numberWithOptions(
                    signed: widget.allowNegative,
                    decimal: !widget.isInt,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.allow(allowedRegex)],
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF38BDF8),
                    fontFamily: 'DejaVuSansMono',
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: fill,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(5),
                      borderSide: BorderSide(color: bdr),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(5),
                      borderSide: const BorderSide(color: Color(0xFF06B6D4), width: 1.4),
                    ),
                  ),
                  onSubmitted: (_) => _commitText(),
                  onTapOutside: (_) {
                    if (_focus.hasFocus) {
                      _focus.unfocus();
                    }
                  },
                ),
              ),
              const SizedBox(width: 5),
              SizedBox(
                width: 34,
                child: Text(
                  widget.unit,
                  style: TextStyle(
                    fontSize: 10.2,
                    fontWeight: FontWeight.w600,
                    color: widget.darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 13.0),
            ),
            child: Slider(
              value: widget.value.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              onChanged: (v) {
                final next = widget.isInt ? v.roundToDouble() : double.parse(v.toStringAsFixed(v.abs() >= 100 ? 0 : 1));
                _ctrl.text = _fmt(next);
                widget.onChanged(next);
              },
            ),
          ),
        ],
      ),
    );
  }
}
