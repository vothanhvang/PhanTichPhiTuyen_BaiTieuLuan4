// ============================================================================
// MÀN HÌNH CHÍNH: CALFEM PYTHON STUDIO — PHÂN TÍCH PHI TUYẾN KẾT CẤU 2D/3D
// ============================================================================
// Bố cục thích ứng đa nền tảng (Windows Desktop / Tablet / Mobile / Web):
//   • Màn hình rộng (≥ 920px): 3 cột có thể ẩn/hiện & kéo thay đổi bề rộng
//       - Cột trái (3 Tab gọn): Mô hình & Tiết diện (12 dạng + xoay 360°) |
//         Hình học & Custom Truss Builder & Gối tựa | Tải nhiều nút & GMNIA.
//       - Cột giữa: Khung nhìn 2D/3D trực quan, chạm chọn Nút & Phẫu thuật Thanh.
//       - Cột phải (4 Tab): Phẫu thuật | Liên kết | Biểu đồ (P-u, NR, Buckling) | Lý thuyết.
//   • Màn hình nhỏ (< 920px): Thanh điều hướng cảm ứng 5 tab hiện đại.
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../core/calfem_engine.dart';
import '../core/connection_calculator.dart';
import '../core/project_serializer.dart';
import '../core/report_generator.dart';
import '../core/python_bridge_stub.dart'
    if (dart.library.io) '../core/python_bridge_io.dart';
import '../widgets/ansys_viewport_2d.dart';
import '../widgets/ansys_viewport_3d.dart';
import '../widgets/surgical_dissection_panel.dart';
import '../widgets/connection_detail_panel.dart';
import '../widgets/charts_and_tables_panel.dart';
import '../widgets/theory_and_code_panel.dart';

class HomeStudioScreen extends StatefulWidget {
  const HomeStudioScreen({super.key});

  @override
  State<HomeStudioScreen> createState() => _HomeStudioScreenState();
}

class _HomeStudioScreenState extends State<HomeStudioScreen> {
  // Tham số mô hình & thuật toán
  TrussPreset _preset = TrussPreset.assignment5Bar;
  SolverMethod _method = SolverMethod.corotationalNR;
  List<ElementSectionConfig> _elemSections = List<ElementSectionConfig>.generate(
    5,
    (_) => const ElementSectionConfig(shape: SectionShape.iSection),
  );
  List<List<double>>? _customCoords;
  List<List<int>>? _customConn;
  List<List<double>>? _customNodalLoadsKn;
  bool _editNodeCoordsMode = false;
  ContourField _contourField = ContourField.axialStress;

  double _lMm = 1000.0;
  double _eGpa = 200.0;
  double _aMm2 = 2001.0;
  double _pKn = 208.0;
  double _fyMpa = 250.0;
  bool _materialNonlinear = false;
  double _hardeningRatio = 0.02;
  double _loadFactor = 1.0;
  int _nSteps = 10;

  // Liên kết gối tựa & hướng liên kết tại từng nút
  List<NodeSupportType> _nodeSupports =
      List<NodeSupportType>.from(TrussModelData.defaultSupportsFor(TrussPreset.assignment5Bar));
  List<SupportDirection> _supportDirections =
      List<SupportDirection>.from(TrussModelData.defaultDirectionsFor(TrussPreset.assignment5Bar));
  double _springStiffnessKnMm = 500.0;
  ConnectionDisplayMode _connectionMode = ConnectionDisplayMode.schematic;
  ConnectionDesignParams _connParams = const ConnectionDesignParams();
  int _selectedNode = 0;

  // Trạng thái hiển thị 2D/3D, Phẫu thuật & Bố cục Pro (ẩn/hiện & kéo giãn cột)
  bool _is3D = true;
  bool _surgicalMode = true;
  bool _showColorBar = true;
  bool _darkMode = true;
  bool _showLeftPanel = true;
  bool _showRightPanel = true;
  double _leftWidth = 326.0;
  double _rightWidth = 428.0;
  int _leftTab = 0; // 0: Mô hình | 1: Hình học | 2: Tải & VL
  int _rightTab = 0; // 0: Phẫu thuật | 1: Liên kết | 2: Biểu đồ | 3: Lý thuyết
  int _mobileTab = 0;

  double _deformScale = 180.0;
  double _playbackFrac = 1.0;
  int _peakHoldTicks = 0;
  Timer? _animTimer;

  // Trạng thái Phẫu thuật & Đầu dò
  int _selectedElem = 3;
  double _probeXi = 0.5;
  double _etaNorm = 0.0;
  double _zetaNorm = 0.0;
  double _imperfectionRatio = 0.002;

  // Nút thêm thanh tùy biến (Custom Truss Builder)
  int _newBarNodeA = 1;
  int _newBarNodeB = 2;

  // Ngăn xếp lịch sử Undo / Redo
  final List<ProjectSnapshot> _undoStack = [];
  final List<ProjectSnapshot> _redoStack = [];
  static const int _maxHistory = 40;

  // Khóa chụp ảnh khung nhìn 3D/2D nhúng vào báo cáo Word/PDF & xuất PNG
  final GlobalKey _viewportShotKey = GlobalKey();

  // Kết quả phân tích hiện hành
  late TrussModelData _model;
  late TrussAnalysisResult _resLinear;
  late TrussAnalysisResult _resBar2g;
  late TrussAnalysisResult _resCorot;
  late TrussAnalysisResult _resTL;
  late TrussAnalysisResult _resActive;
  late List<EquilibriumPoint> _snapCurve;
  late List<MemberDesignCheck> _designChecks;
  late BucklingAnalysisResult _buckling;

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

  ProjectSnapshot _captureSnapshot() {
    return ProjectSnapshot(
      preset: _preset,
      method: _method,
      lMm: _lMm,
      eGpa: _eGpa,
      aMm2: _aMm2,
      pKn: _pKn,
      fyMpa: _fyMpa,
      materialNonlinear: _materialNonlinear,
      hardeningRatio: _hardeningRatio,
      loadFactor: _loadFactor,
      nSteps: _nSteps,
      customCoords: _customCoords,
      customConn: _customConn,
      customNodalLoadsKn: _customNodalLoadsKn,
      elemSections: _elemSections,
      nodeSupports: _nodeSupports,
      supportDirections: _supportDirections,
      springStiffnessKnMm: _springStiffnessKnMm,
      connParams: _connParams,
    ).deepCopy();
  }

  void _applySnapshot(ProjectSnapshot snap) {
    final s = snap.deepCopy();
    _preset = s.preset;
    _method = s.method;
    _lMm = s.lMm;
    _eGpa = s.eGpa;
    _aMm2 = s.aMm2;
    _pKn = s.pKn;
    _fyMpa = s.fyMpa;
    _materialNonlinear = s.materialNonlinear;
    _hardeningRatio = s.hardeningRatio;
    _loadFactor = s.loadFactor;
    _nSteps = s.nSteps;
    _customCoords = s.customCoords;
    _customConn = s.customConn;
    _customNodalLoadsKn = s.customNodalLoadsKn;
    _elemSections = s.elemSections;
    _nodeSupports = s.nodeSupports;
    _supportDirections = s.supportDirections;
    _springStiffnessKnMm = s.springStiffnessKnMm;
    _connParams = s.connParams;
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    FocusScope.of(context).unfocus();
    final cur = _captureSnapshot();
    final prev = _undoStack.removeLast();
    _redoStack.add(cur);
    setState(() {
      _applySnapshot(prev);
      _recomputeLocal();
    });
    _syncFromPythonIfAvailable();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    FocusScope.of(context).unfocus();
    final cur = _captureSnapshot();
    final next = _redoStack.removeLast();
    _undoStack.add(cur);
    setState(() {
      _applySnapshot(next);
      _recomputeLocal();
    });
    _syncFromPythonIfAvailable();
  }

  void _recomputeLocal() {
    final defSup = TrussModelData.defaultSupportsFor(_preset);
    final defDir = TrussModelData.defaultDirectionsFor(_preset);
    final defElems = TrussModelData.defaultElemCountFor(_preset);

    final targetNodes = (_customCoords != null && _customCoords!.length >= 2)
        ? _customCoords!.length
        : defSup.length;
    final targetElems = (_customConn != null && _customConn!.isNotEmpty)
        ? _customConn!.length
        : defElems;

    if (_nodeSupports.length != targetNodes) {
      _nodeSupports = [
        for (int i = 0; i < targetNodes; i++)
          i < _nodeSupports.length
              ? _nodeSupports[i]
              : (i < defSup.length ? defSup[i] : NodeSupportType.free),
      ];
    }
    if (_supportDirections.length != targetNodes) {
      _supportDirections = [
        for (int i = 0; i < targetNodes; i++)
          i < _supportDirections.length
              ? _supportDirections[i]
              : (i < defDir.length ? defDir[i] : SupportDirection.auto),
      ];
    }
    if (_elemSections.length != targetElems) {
      _elemSections = [
        for (int e = 0; e < targetElems; e++)
          e < _elemSections.length
              ? _elemSections[e]
              : const ElementSectionConfig(shape: SectionShape.iSection),
      ];
    }
    if (_customNodalLoadsKn != null && _customNodalLoadsKn!.length != targetNodes) {
      final defLoads = TrussModelData.defaultNodalLoadsKnFor(_preset, _pKn);
      _customNodalLoadsKn = [
        for (int i = 0; i < targetNodes; i++)
          i < _customNodalLoadsKn!.length
              ? List<double>.from(_customNodalLoadsKn![i])
              : (i < defLoads.length ? List<double>.from(defLoads[i]) : [0.0, 0.0]),
      ];
    }

    _selectedElem = _selectedElem.clamp(0, math.max(0, targetElems - 1));
    _selectedNode = _selectedNode.clamp(0, math.max(0, targetNodes - 1));
    _newBarNodeA = _newBarNodeA.clamp(1, targetNodes);
    _newBarNodeB = _newBarNodeB.clamp(1, targetNodes);
    if (_newBarNodeA == _newBarNodeB && targetNodes >= 2) {
      _newBarNodeB = _newBarNodeA == 1 ? 2 : 1;
    }

    _model = TrussModelData.create(
      preset: _preset,
      lMm: _lMm,
      eMpa: _eGpa * 1000.0,
      aMm2: _aMm2,
      pKn: _pKn,
      yieldFyMpa: _fyMpa,
      materialNonlinear: _materialNonlinear,
      hardeningRatio: _hardeningRatio,
      sectionShape: _elemSections[_selectedElem].shape,
      elementSections: _elemSections,
      customCoords: _customCoords,
      customConn: _customConn,
      customNodalLoadsKn: _customNodalLoadsKn,
      customSupports: _nodeSupports,
      customDirections: _supportDirections,
      springStiffnessKnMm: _springStiffnessKnMm,
    );
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
    _designChecks = CalfemNonlinearEngine.checkMembers(_model, _resActive);
    _buckling = CalfemNonlinearEngine.solveElasticBuckling(_model, _resLinear);
  }

  Future<void> _syncFromPythonIfAvailable() async {
    if (!_pythonOnline) return;
    if (_resActive.warningMessage != null) return;
    if (_model.materialNonlinear) return;
    final pyRes = await PythonBridge.tryAnalyzeViaPython(_model, _method, _loadFactor, _nSteps);
    if (pyRes != null && mounted) {
      setState(() {
        _resActive = pyRes;
        _designChecks = CalfemNonlinearEngine.checkMembers(_model, _resActive);
      });
    }
  }

  void _updateAndSolve(VoidCallback mutate, {bool recordHistory = true}) {
    if (recordHistory) {
      _undoStack.add(_captureSnapshot());
      if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
      _redoStack.clear();
    }
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
        _peakHoldTicks = 0;
      });
      return;
    }
    setState(() {
      _playbackFrac = 0.0;
      _peakHoldTicks = 0;
    });
    _animTimer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_playbackFrac < 1.0) {
          _playbackFrac = (_playbackFrac + 0.018).clamp(0.0, 1.0);
        } else {
          _peakHoldTicks++;
          if (_peakHoldTicks >= 18) {
            _playbackFrac = 0.0;
            _peakHoldTicks = 0;
          }
        }
      });
    });
  }

  /// Chụp ảnh PNG độ phân giải cao của khung nhìn 3D/2D (dùng cho Xuất PNG và nhúng vào Word/PDF)
  Future<({Uint8List bytes, int width, int height})?> _captureViewportPng() async {
    try {
      final ctx = _viewportShotKey.currentContext;
      if (ctx == null) return null;
      final ro = ctx.findRenderObject();
      if (ro is! RenderRepaintBoundary) return null;
      final img = await ro.toImage(pixelRatio: 2.0);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      final w = img.width;
      final h = img.height;
      img.dispose();
      if (bd == null) return null;
      return (bytes: bd.buffer.asUint8List(), width: w, height: h);
    } catch (_) {
      return null;
    }
  }

  void _showSnack(String msg, {Color bg = const Color(0xFF0F766E), int seconds = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: bg, duration: Duration(seconds: seconds), content: Text(msg)),
    );
  }

  Future<void> _exportReport(bool asPdf) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final shot = await _captureViewportPng();
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
      final connReports = [
        for (int i = 0; i < _model.nNodes; i++)
          ConnectionCalculator.analyzeNode(
            model: _model,
            result: _resActive,
            nodeIndex: i,
            params: _connParams,
            loadFactor: _loadFactor,
          ),
      ];
      final savedPath = asPdf
          ? await FlutterReportGenerator.exportPdf(
              model: _model,
              linear: _resLinear,
              nonlinear: _resActive,
              probe: probe,
              loadFactor: _loadFactor,
              connectionReports: connReports,
              designChecks: _designChecks,
              buckling: _buckling,
              viewportPngBytes: shot?.bytes,
            )
          : await FlutterReportGenerator.exportDocx(
              model: _model,
              linear: _resLinear,
              nonlinear: _resActive,
              probe: probe,
              loadFactor: _loadFactor,
              connectionReports: connReports,
              designChecks: _designChecks,
              buckling: _buckling,
              viewportPngBytes: shot?.bytes,
              pngWidthPx: shot?.width,
              pngHeightPx: shot?.height,
            );
      if (savedPath == null) {
        _showSnack('Đã hủy lưu tệp báo cáo.', bg: const Color(0xFF475569), seconds: 2);
      } else {
        _showSnack('Xuất báo cáo ${asPdf ? "PDF" : "Word (.docx)"} (kèm ảnh mô hình 3D/2D) thành công!\n$savedPath',
            seconds: 5);
      }
    } catch (e) {
      _showSnack('Lỗi xuất báo cáo: $e', bg: const Color(0xFFB91C1C), seconds: 4);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await FlutterReportGenerator.exportCsv(
        model: _model,
        linear: _resLinear,
        nonlinear: _resActive,
        designChecks: _designChecks,
        buckling: _buckling,
        loadFactor: _loadFactor,
      );
      if (path == null) {
        _showSnack('Đã hủy xuất CSV.', bg: const Color(0xFF475569), seconds: 2);
      } else {
        _showSnack('Xuất bảng Excel (.csv UTF-8) thành công!\n$path', seconds: 4);
      }
    } catch (e) {
      _showSnack('Lỗi xuất CSV: $e', bg: const Color(0xFFB91C1C), seconds: 4);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPngSnapshot() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final shot = await _captureViewportPng();
      if (shot == null) {
        _showSnack('Không chụp được ảnh khung nhìn (hãy chuyển sang tab Mô phỏng).', bg: const Color(0xFFB91C1C));
        return;
      }
      final path = await FlutterReportGenerator.exportPngSnapshot(shot.bytes);
      if (path == null) {
        _showSnack('Đã hủy lưu ảnh PNG.', bg: const Color(0xFF475569), seconds: 2);
      } else {
        _showSnack('Đã lưu ảnh khung nhìn độ phân giải cao (${shot.width}×${shot.height} px)!\n$path', seconds: 4);
      }
    } catch (e) {
      _showSnack('Lỗi lưu ảnh PNG: $e', bg: const Color(0xFFB91C1C));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveProjectJson() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final jsonStr = _captureSnapshot().toJsonString();
      final path = await FlutterReportGenerator.exportProjectJson(jsonStr);
      if (path == null) {
        _showSnack('Đã hủy lưu dự án.', bg: const Color(0xFF475569), seconds: 2);
      } else {
        _showSnack('Đã lưu dự án cấu hình mô hình (.json)!\n$path', seconds: 4);
      }
    } catch (e) {
      _showSnack('Lỗi lưu dự án: $e', bg: const Color(0xFFB91C1C));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openProjectJson() async {
    try {
      final content = await FlutterReportGenerator.importProjectJson();
      if (content == null || content.trim().isEmpty) return;
      final snap = ProjectSnapshot.tryFromJsonString(content);
      if (snap == null) {
        _showSnack('Tệp JSON không đúng định dạng dự án CALFEM.', bg: const Color(0xFFB91C1C));
        return;
      }
      _updateAndSolve(() => _applySnapshot(snap));
      _showSnack('Đã nạp thành công dự án: ${_model.name} (${_model.nNodes} nút, ${_model.nElems} thanh)!', seconds: 3);
    } catch (e) {
      _showSnack('Lỗi mở tệp dự án: $e', bg: const Color(0xFFB91C1C));
    }
  }

  bool get _isEditingText => FocusManager.instance.primaryFocus?.context?.widget is EditableText;

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
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
            if (!_isEditingText) _undo();
          },
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
            if (!_isEditingText) _redo();
          },
          const SingleActivator(LogicalKeyboardKey.space): () {
            if (!_isEditingText) _toggleAnimation();
          },
          const SingleActivator(LogicalKeyboardKey.digit2): () {
            if (!_isEditingText) setState(() => _is3D = false);
          },
          const SingleActivator(LogicalKeyboardKey.digit3): () {
            if (!_isEditingText) setState(() => _is3D = true);
          },
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 920;
              return Scaffold(
                appBar: AppBar(
                  backgroundColor: barBg,
                  elevation: 0,
                  toolbarHeight: 58,
                  title: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset('assets/python_logo.png', width: 36, height: 36, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'CALFEM Python Studio — Phân tích Phi tuyến Kết cấu 2D/3D',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'ĐH Bách Khoa TP.HCM • GVHD: PGS. TS Ngô Hữu Cường • HV: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.8,
                                fontWeight: FontWeight.w600,
                                color: _darkMode ? const Color(0xFFFBBF24) : const Color(0xFF0F3D6E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    // Undo / Redo
                    IconButton(
                      tooltip: 'Hoàn tác (Ctrl+Z)',
                      icon: const Icon(Icons.undo, size: 19),
                      onPressed: _undoStack.isEmpty ? null : _undo,
                    ),
                    IconButton(
                      tooltip: 'Làm lại (Ctrl+Y)',
                      icon: const Icon(Icons.redo, size: 19),
                      onPressed: _redoStack.isEmpty ? null : _redo,
                    ),
                    // Lưu / Mở dự án (.json)
                    PopupMenuButton<String>(
                      tooltip: 'Lưu / Mở Dự án (.json)',
                      icon: const Icon(Icons.folder_open_outlined, color: Color(0xFF38BDF8), size: 20),
                      onSelected: (v) {
                        if (v == 'save') _saveProjectJson();
                        if (v == 'open') _openProjectJson();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'save',
                          child: Row(children: [
                            Icon(Icons.save_outlined, size: 17, color: Color(0xFF06B6D4)),
                            SizedBox(width: 8),
                            Text('Lưu dự án (.json)', style: TextStyle(fontSize: 12.2)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'open',
                          child: Row(children: [
                            Icon(Icons.file_open_outlined, size: 17, color: Color(0xFF10B981)),
                            SizedBox(width: 8),
                            Text('Mở dự án (.json)', style: TextStyle(fontSize: 12.2)),
                          ]),
                        ),
                      ],
                    ),
                    // Xuất báo cáo tổng hợp (Word / PDF kèm ảnh 3D + CSV Excel + PNG)
                    PopupMenuButton<String>(
                      tooltip: 'Xuất Báo cáo & Dữ liệu',
                      enabled: !_exporting,
                      onSelected: (v) {
                        if (v == 'docx') _exportReport(false);
                        if (v == 'pdf') _exportReport(true);
                        if (v == 'csv') _exportCsv();
                        if (v == 'png') _exportPngSnapshot();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'docx',
                          child: Row(children: [
                            Icon(Icons.description, size: 17, color: Color(0xFF3B82F6)),
                            SizedBox(width: 8),
                            Text('Xuất Word (.docx + ảnh 3D/2D)', style: TextStyle(fontSize: 12.2)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'pdf',
                          child: Row(children: [
                            Icon(Icons.picture_as_pdf, size: 17, color: Color(0xFFEF4444)),
                            SizedBox(width: 8),
                            Text('Xuất PDF (.pdf + ảnh 3D/2D)', style: TextStyle(fontSize: 12.2)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'csv',
                          child: Row(children: [
                            Icon(Icons.table_chart_outlined, size: 17, color: Color(0xFF10B981)),
                            SizedBox(width: 8),
                            Text('Xuất bảng Excel (.csv UTF-8)', style: TextStyle(fontSize: 12.2)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'png',
                          child: Row(children: [
                            Icon(Icons.camera_alt_outlined, size: 17, color: Color(0xFFF59E0B)),
                            SizedBox(width: 8),
                            Text('Chụp ảnh khung hình (.png 2×)', style: TextStyle(fontSize: 12.2)),
                          ]),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: isWide ? 10 : 7, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.download_rounded, size: 15, color: Colors.white),
                              if (isWide) ...[
                                const SizedBox(width: 5),
                                Text(
                                  _exporting ? 'Đang xuất...' : 'Xuất báo cáo',
                                  style: const TextStyle(
                                      fontSize: 11.4, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Thông tin nhóm & Liên hệ (vothanhvang@gmail.com)',
                      icon: const Icon(Icons.contact_mail_outlined, color: Color(0xFF38BDF8), size: 20),
                      onPressed: _showContactDialog,
                    ),
                    IconButton(
                      tooltip: _darkMode ? 'Chế độ sáng' : 'Chế độ tối',
                      icon: Icon(_darkMode ? Icons.light_mode : Icons.dark_mode, size: 20),
                      onPressed: () => setState(() => _darkMode = !_darkMode),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                body: isWide
                    ? _buildWideWorkbench(probe, constraints.maxWidth)
                    : _buildMobileWorkbench(probe),
                bottomNavigationBar: isWide
                    ? null
                    : NavigationBar(
                        selectedIndex: _mobileTab,
                        height: 60,
                        onDestinationSelected: (i) => setState(() => _mobileTab = i),
                        destinations: const [
                          NavigationDestination(icon: Icon(Icons.view_in_ar), label: 'Mô phỏng'),
                          NavigationDestination(icon: Icon(Icons.precision_manufacturing), label: 'Liên kết'),
                          NavigationDestination(icon: Icon(Icons.biotech), label: 'Phẫu thuật'),
                          NavigationDestination(icon: Icon(Icons.tune), label: 'Thông số'),
                          NavigationDestination(icon: Icon(Icons.analytics), label: 'Phân tích'),
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Bố cục 3 cột chuyên nghiệp (ẩn/hiện & kéo thay đổi kích thước mượt mà)
  Widget _buildWideWorkbench(ProbeInspection probe, double totalW) {
    final border = _darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final maxSide = math.max(270.0, totalW * 0.36);

    Widget splitter(void Function(double dx) onDrag) {
      return MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          child: Container(
            width: 6,
            color: Colors.transparent,
            child: Center(
              child: Container(
                width: 1.4,
                color: border,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        if (_showLeftPanel) ...[
          SizedBox(
            width: _leftWidth.clamp(270.0, maxSide),
            child: _buildControlPanel(),
          ),
          splitter((dx) => setState(() => _leftWidth = (_leftWidth + dx).clamp(270.0, maxSide))),
        ],
        Expanded(
          child: _buildViewportColumn(probe, isWide: true),
        ),
        if (_showRightPanel) ...[
          splitter((dx) => setState(() => _rightWidth = (_rightWidth - dx).clamp(330.0, math.max(350.0, totalW * 0.44)))),
          SizedBox(
            width: _rightWidth.clamp(330.0, math.max(350.0, totalW * 0.44)),
            child: Column(
              children: [
                Container(
                  color: _darkMode ? const Color(0xFF0F172A) : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, icon: Icon(Icons.biotech, size: 13.5), label: Text('Phẫu thuật', style: TextStyle(fontSize: 10.0))),
                      ButtonSegment(value: 1, icon: Icon(Icons.precision_manufacturing, size: 13.5), label: Text('Liên kết', style: TextStyle(fontSize: 10.0))),
                      ButtonSegment(value: 2, icon: Icon(Icons.analytics, size: 13.5), label: Text('Biểu đồ', style: TextStyle(fontSize: 10.0))),
                      ButtonSegment(value: 3, icon: Icon(Icons.code, size: 13.5), label: Text('Lý thuyết', style: TextStyle(fontSize: 10.0))),
                    ],
                    selected: {_rightTab},
                    onSelectionChanged: (s) => setState(() => _rightTab = s.first),
                  ),
                ),
                Expanded(child: _buildRightContent(probe, _rightTab)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Bố cục 5 tab tối ưu cho màn hình hẹp / điện thoại
  Widget _buildMobileWorkbench(ProbeInspection probe) {
    switch (_mobileTab) {
      case 0:
        return _buildViewportColumn(probe, isWide: false);
      case 1:
        return _buildRightContent(probe, 1);
      case 2:
        return _buildRightContent(probe, 0);
      case 3:
        return _buildControlPanel();
      default:
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 2, icon: Icon(Icons.analytics, size: 14), label: Text('Biểu đồ & Bảng', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 3, icon: Icon(Icons.menu_book, size: 14), label: Text('Lý thuyết', style: TextStyle(fontSize: 11))),
                ],
                selected: {_rightTab == 3 ? 3 : 2},
                onSelectionChanged: (s) => setState(() => _rightTab = s.first),
              ),
            ),
            Expanded(child: _buildRightContent(probe, _rightTab == 3 ? 3 : 2)),
          ],
        );
    }
  }

  Widget _buildViewportColumn(ProbeInspection probe, {required bool isWide}) {
    final barBg = _darkMode ? const Color(0xFF0F172A) : Colors.white;
    final border = _darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final maxUtil = _designChecks.isEmpty
        ? 0.0
        : _designChecks.map((c) => c.utilizationPct).reduce(math.max);

    return Column(
      children: [
        // Thanh công cụ 1 dòng gọn gàng: ghim 2 nút ẩn/hiện cột trái & phải ở 2 mép ngoài!
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: barBg,
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              if (isWide)
                IconButton(
                  tooltip: _showLeftPanel ? 'Ẩn cột thông số trái' : 'Hiện cột thông số trái',
                  icon: Icon(
                    _showLeftPanel ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                    size: 18,
                    color: _showLeftPanel ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _showLeftPanel = !_showLeftPanel),
                ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        segments: const [
                          ButtonSegment(value: false, label: Text('2D', style: TextStyle(fontSize: 10.8, fontWeight: FontWeight.bold))),
                          ButtonSegment(value: true, label: Text('3D', style: TextStyle(fontSize: 10.8, fontWeight: FontWeight.bold))),
                        ],
                        selected: {_is3D},
                        onSelectionChanged: (s) => setState(() => _is3D = s.first),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(Icons.content_cut, size: 14, color: _surgicalMode ? Colors.black : const Color(0xFF00E5FF)),
                        label: Text('Phẫu thuật', style: TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold, color: _surgicalMode ? Colors.black : null)),
                        selected: _surgicalMode,
                        selectedColor: const Color(0xFF00E5FF),
                        onSelected: (v) => setState(() => _surgicalMode = v),
                      ),
                      const SizedBox(width: 5),
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(
                          Icons.precision_manufacturing,
                          size: 14,
                          color: _connectionMode == ConnectionDisplayMode.fabrication
                              ? Colors.black
                              : const Color(0xFFFBBF24),
                        ),
                        label: Text(
                          _connectionMode == ConnectionDisplayMode.fabrication ? 'Chế tạo' : 'Sơ đồ',
                          style: TextStyle(
                            fontSize: 10.6,
                            fontWeight: FontWeight.bold,
                            color: _connectionMode == ConnectionDisplayMode.fabrication ? Colors.black : null,
                          ),
                        ),
                        selected: _connectionMode == ConnectionDisplayMode.fabrication,
                        selectedColor: const Color(0xFFFBBF24),
                        onSelected: (v) => setState(() {
                          _connectionMode = v ? ConnectionDisplayMode.fabrication : ConnectionDisplayMode.schematic;
                          if (v) {
                            _rightTab = 1;
                            _showRightPanel = true;
                          }
                        }),
                      ),
                      const SizedBox(width: 5),
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(
                          _showColorBar ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 14,
                          color: _showColorBar ? Colors.black : const Color(0xFF38BDF8),
                        ),
                        label: Text(
                          'Thang màu',
                          style: TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold, color: _showColorBar ? Colors.black : null),
                        ),
                        selected: _showColorBar,
                        selectedColor: const Color(0xFF38BDF8),
                        onSelected: (v) => setState(() => _showColorBar = v),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _darkMode ? const Color(0xFF0A1426) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: border),
                        ),
                        child: DropdownButton<ContourField>(
                          value: _contourField,
                          isDense: true,
                          underline: const SizedBox(),
                          items: [
                            for (final f in ContourField.values)
                              DropdownMenuItem(value: f, child: Text(f.label, style: const TextStyle(fontSize: 11.0))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _contourField = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: _toggleAnimation,
                        icon: Icon(
                          _animTimer == null ? Icons.play_arrow : Icons.stop,
                          size: 15,
                          color: _animTimer == null ? null : const Color(0xFFF43F5E),
                        ),
                        label: Text(
                          _animTimer == null ? 'Mô phỏng' : '${(_playbackFrac * 100).round()}%',
                          style: TextStyle(
                            fontSize: 10.6,
                            fontWeight: FontWeight.w600,
                            color: _animTimer == null ? null : const Color(0xFFF43F5E),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          visualDensity: VisualDensity.compact,
                          side: _animTimer == null ? null : const BorderSide(color: Color(0xFFF43F5E), width: 1.2),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Chụp ảnh khung nhìn (.png 2×)',
                        icon: const Icon(Icons.camera_alt_outlined, size: 17, color: Color(0xFFF59E0B)),
                        visualDensity: VisualDensity.compact,
                        onPressed: _exporting ? null : _exportPngSnapshot,
                      ),
                    ],
                  ),
                ),
              ),
              if (isWide)
                IconButton(
                  tooltip: _showRightPanel ? 'Ẩn cột kết quả phải' : 'Hiện cột kết quả phải',
                  icon: Icon(
                    _showRightPanel ? Icons.vertical_split : Icons.vertical_split_outlined,
                    size: 18,
                    color: _showRightPanel ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _showRightPanel = !_showRightPanel),
                ),
            ],
          ),
        ),

        // Cảnh báo tức thời nếu hệ biến hình
        if (_resActive.warningMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFFB91C1C),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFDE047), size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _resActive.warningMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 11.0, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _updateAndSolve(() {
                    final defSup = TrussModelData.defaultSupportsFor(_preset);
                    _nodeSupports = [
                      for (int i = 0; i < _model.nNodes; i++) i < defSup.length ? defSup[i] : NodeSupportType.free,
                    ];
                    _supportDirections = List<SupportDirection>.filled(_model.nNodes, SupportDirection.auto);
                    _springStiffnessKnMm = 500.0;
                  }),
                  child: const Text('Khôi phục gối', style: TextStyle(fontSize: 10.8, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

        // Cửa sổ hiển thị 2D hoặc 3D bọc trong RepaintBoundary để chụp ảnh PNG nhúng Word/PDF
        Expanded(
          child: RepaintBoundary(
            key: _viewportShotKey,
            child: _is3D
                ? AnsysViewport3D(
                    model: _model,
                    result: _resActive,
                    field: _contourField,
                    deformScale: _deformScale,
                    playbackFraction: _playbackFrac,
                    selectedElem: _selectedElem,
                    selectedNode: _selectedNode,
                    probeXi: _probeXi,
                    surgicalMode: _surgicalMode,
                    darkMode: _darkMode,
                    showColorBar: _showColorBar,
                    onToggleColorBar: (v) => setState(() => _showColorBar = v),
                    connectionMode: _connectionMode,
                    connectionType: _connParams.detailType,
                    designChecks: _designChecks,
                    onProbeChanged: (e, xi) => setState(() {
                      _selectedElem = e;
                      _probeXi = xi;
                    }),
                    onNodeTapped: (n) => setState(() {
                      _selectedNode = n;
                      _rightTab = 1;
                      _showRightPanel = true;
                    }),
                  )
                : AnsysViewport2D(
                    model: _model,
                    result: _resActive,
                    field: _contourField,
                    deformScale: _deformScale,
                    playbackFraction: _playbackFrac,
                    selectedElem: _selectedElem,
                    selectedNode: _selectedNode,
                    probeXi: _probeXi,
                    surgicalMode: _surgicalMode,
                    darkMode: _darkMode,
                    showColorBar: _showColorBar,
                    onToggleColorBar: (v) => setState(() => _showColorBar = v),
                    connectionMode: _connectionMode,
                    connectionType: _connParams.detailType,
                    designChecks: _designChecks,
                    onProbeChanged: (e, xi) => setState(() {
                      _selectedElem = e;
                      _probeXi = xi;
                    }),
                    onNodeTapped: (n) => setState(() {
                      _selectedNode = n;
                      _rightTab = 1;
                      _showRightPanel = true;
                    }),
                  ),
          ),
        ),

        // Thanh trạng thái gọn dưới đáy Viewport
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: barBg,
            border: Border(top: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              const Text('Phóng đại:', style: TextStyle(fontSize: 10.6)),
              SizedBox(
                width: 105,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.8,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 11.0),
                  ),
                  child: Slider(
                    value: _deformScale.clamp(1.0, 500.0),
                    min: 1.0,
                    max: 500.0,
                    onChanged: (v) => setState(() => _deformScale = v),
                  ),
                ),
              ),
              Text('×${_deformScale.round()}',
                  style: const TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_animTimer != null ? "▶ ${(100 * _playbackFrac).round()}% | " : ""}'
                  'T${_selectedElem + 1}(${probe.memberLabel}, ξ=${probe.xi.toStringAsFixed(2)}) '
                  'σ=${(probe.sigmaXxMpa * _playbackFrac).toStringAsFixed(2)} MPa  |  '
                  'U_max=${maxUtil.toStringAsFixed(1)}%'
                  '${_buckling.hasBucklingMode ? "  |  α_cr=${_buckling.alphaCr.toStringAsFixed(1)}" : ""}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.3, fontFamily: 'DejaVuSansMono'),
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
            const Text(
                '• Đơn vị: Trường ĐH Bách Khoa – ĐHQG TP.HCM\n'
                '• Học phần: Phân tích Phi tuyến Kết cấu\n'
                '• Giảng viên hướng dẫn: PGS. TS Ngô Hữu Cường\n'
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
                      _showSnack('Đã sao chép email liên hệ: vothanhvang@gmail.com', seconds: 2);
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
              style: TextStyle(fontSize: 10.6, color: _darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Đóng')),
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
      _elemSections = List<ElementSectionConfig>.generate(
        5,
        (_) => const ElementSectionConfig(shape: SectionShape.iSection),
      );
      _customCoords = null;
      _customConn = null;
      _customNodalLoadsKn = null;
      _editNodeCoordsMode = false;
      _contourField = ContourField.axialStress;
      _lMm = 1000.0;
      _eGpa = 200.0;
      _aMm2 = 2001.0;
      _pKn = 208.0;
      _fyMpa = 250.0;
      _materialNonlinear = false;
      _hardeningRatio = 0.02;
      _loadFactor = 1.0;
      _nSteps = 10;
      _deformScale = 180.0;
      _playbackFrac = 1.0;
      _selectedElem = 3;
      _probeXi = 0.5;
      _etaNorm = 0.0;
      _zetaNorm = 0.0;
      _imperfectionRatio = 0.002;
      _nodeSupports = List<NodeSupportType>.from(TrussModelData.defaultSupportsFor(TrussPreset.assignment5Bar));
      _supportDirections = List<SupportDirection>.from(TrussModelData.defaultDirectionsFor(TrussPreset.assignment5Bar));
      _springStiffnessKnMm = 500.0;
      _connectionMode = ConnectionDisplayMode.schematic;
      _connParams = const ConnectionDesignParams();
      _selectedNode = 0;
    });
    _showSnack('Đã đặt lại toàn bộ thông số về đề bài mặc định.', bg: const Color(0xFF0F3D6E), seconds: 2);
  }

  /// Cột điều khiển trái tổ chức thành 3 Tab gọn gàng: Mô hình | Hình học | Tải & VL
  Widget _buildControlPanel() {
    final barBg = _darkMode ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = _darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = _darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: barBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(value: 0, label: Text('Mô hình', style: TextStyle(fontSize: 10.4, fontWeight: FontWeight.w600))),
              ButtonSegment(value: 1, label: Text('Hình học', style: TextStyle(fontSize: 10.4, fontWeight: FontWeight.w600))),
              ButtonSegment(value: 2, label: Text('Tải & VL', style: TextStyle(fontSize: 10.4, fontWeight: FontWeight.w600))),
            ],
            selected: {_leftTab},
            onSelectionChanged: (s) => setState(() => _leftTab = s.first),
          ),
        ),
        Expanded(
          child: _leftTab == 0
              ? _buildLeftModelTab(cardBg, border)
              : (_leftTab == 1 ? _buildLeftGeometryTab(cardBg, border) : _buildLeftLoadsMaterialTab(cardBg, border)),
        ),
      ],
    );
  }

  /// TAB 0 TRÁI: Bài toán mẫu (8 dàn) + Thuật toán + Chọn tiết diện & Xoay 360° riêng từng thanh
  Widget _buildLeftModelTab(Color cardBg, Color border) {
    final activeIdx = _selectedElem.clamp(0, _model.nElems - 1);
    final activeCfg = _model.sectionConfigForElem(activeIdx);

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. Mô hình kết cấu & Bộ giải CALFEM',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.4, color: Color(0xFF38BDF8))),
              const SizedBox(height: 7),
              DropdownButtonFormField<TrussPreset>(
                key: ValueKey('preset_${_preset.code}'),
                initialValue: _preset,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Thư viện kết cấu mẫu (8 mô hình)', isDense: true, border: OutlineInputBorder()),
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
                    _customCoords = null;
                    _customConn = null;
                    _customNodalLoadsKn = null;
                    final defSup = TrussModelData.defaultSupportsFor(v);
                    _nodeSupports = List<NodeSupportType>.from(defSup);
                    _supportDirections = List<SupportDirection>.from(TrussModelData.defaultDirectionsFor(v));
                    final nE = TrussModelData.defaultElemCountFor(v);
                    _elemSections = List<ElementSectionConfig>.generate(
                      nE,
                      (_) => const ElementSectionConfig(shape: SectionShape.iSection),
                    );
                    _selectedElem = _selectedElem.clamp(0, nE - 1);
                    _selectedNode = 0;
                    _loadFactor = 1.0;
                    _deformScale = v == TrussPreset.dahlblomEx91
                        ? 3.0
                        : (v == TrussPreset.vonMisesArch ? 5.0 : (nE >= 8 ? 80.0 : 180.0));
                  });
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<SolverMethod>(
                key: ValueKey('method_${_method.code}'),
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
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Card Tiết diện & Xoay 360° riêng từng thanh gắn với Mặt cắt Phẫu thuật
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.content_cut, size: 13.5, color: Color(0xFF00E5FF)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '2. Tiết diện Thanh T${activeIdx + 1} (${_model.memberLabels[activeIdx]})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.2, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
                    ),
                  ),
                  Tooltip(
                    message: 'Sao chép tiết diện + góc xoay của T${activeIdx + 1} cho toàn bộ các thanh',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: () => _updateAndSolve(() {
                        final cur = _elemSections[activeIdx];
                        _elemSections = List<ElementSectionConfig>.generate(
                          _elemSections.length,
                          (_) => ElementSectionConfig(
                            shape: cur.shape,
                            customGeometry: cur.customGeometry?.copyWith(),
                            rotationDeg: cur.rotationDeg,
                          ),
                        );
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                        ),
                        child: const Text('Gán tất cả',
                            style: TextStyle(fontSize: 9.2, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (int e = 0; e < _model.nElems; e++)
                    Builder(builder: (_) {
                      final isSel = e == activeIdx;
                      final cfgE = _model.sectionConfigForElem(e);
                      final rotTag = cfgE.isRotated ? '↻${cfgE.rotationDeg.round()}°' : '';
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => setState(() => _selectedElem = e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSel
                                ? const Color(0xFF06B6D4).withValues(alpha: 0.25)
                                : (_darkMode ? const Color(0xFF0A1426) : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSel
                                  ? const Color(0xFF00E5FF)
                                  : ((cfgE.isManualMm || cfgE.isRotated)
                                      ? const Color(0xFFF59E0B).withValues(alpha: 0.65)
                                      : border),
                              width: isSel ? 1.4 : 1.0,
                            ),
                          ),
                          child: Text(
                            'T${e + 1}·${cfgE.shape.shortLabel}${cfgE.isManualMm ? "*" : ""}$rotTag',
                            style: TextStyle(
                              fontSize: 9.2,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                              color: isSel
                                  ? const Color(0xFF00E5FF)
                                  : ((cfgE.isManualMm || cfgE.isRotated)
                                      ? const Color(0xFFFBBF24)
                                      : (_darkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155))),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<SectionShape>(
                key: ValueKey('sec_${activeIdx}_${activeCfg.shape.code}'),
                initialValue: activeCfg.shape,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Dạng mặt cắt 3D Thanh T${activeIdx + 1} (12 tiết diện)',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final s in SectionShape.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _updateAndSolve(() {
                    final next = List<ElementSectionConfig>.from(_elemSections);
                    final prev = next[activeIdx];
                    next[activeIdx] = prev.isManualMm
                        ? ElementSectionConfig(
                            shape: v,
                            customGeometry: CustomSectionGeometry.fromArea(v, _model.areas[activeIdx]),
                            rotationDeg: prev.rotationDeg,
                          )
                        : ElementSectionConfig(shape: v, rotationDeg: prev.rotationDeg);
                    _elemSections = next;
                  });
                },
              ),
              const SizedBox(height: 8),
              // Thanh điều khiển Xoay tiết diện 0..360° quanh trục dọc thanh (Áp dụng cho TOÀN BỘ 12 tiết diện!)
              _buildSectionRotationBox(border, activeIdx, activeCfg),
              const SizedBox(height: 8),
              _buildSectionGeometryBox(border, activeIdx),
            ],
          ),
        ),
      ],
    );
  }

  /// Hộp xoay tiết diện 360° quanh trục dọc thanh (áp dụng cho cả 12 dạng tiết diện)
  Widget _buildSectionRotationBox(Color border, int activeIdx, ElementSectionConfig cfg) {
    final boxBg = _darkMode ? const Color(0xFF0A1426) : const Color(0xFFF8FAFC);
    final curRot = cfg.rotationDeg;

    void setRot(double deg) {
      final norm = ((deg % 360.0) + 360.0) % 360.0;
      _updateAndSolve(() {
        final next = List<ElementSectionConfig>.from(_elemSections);
        next[activeIdx] = next[activeIdx].copyWith(rotationDeg: norm);
        _elemSections = next;
      });
    }

    Widget rotBtn(String lbl, VoidCallback onTap, {bool selected = false}) {
      return InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF06B6D4).withValues(alpha: 0.25)
                : const Color(0xFF0EA5E9).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: selected ? const Color(0xFF00E5FF) : const Color(0xFF38BDF8).withValues(alpha: 0.4),
              width: selected ? 1.3 : 0.9,
            ),
          ),
          child: Text(
            lbl,
            style: TextStyle(
              fontSize: 9.6,
              fontWeight: FontWeight.bold,
              color: selected ? const Color(0xFF00E5FF) : const Color(0xFF38BDF8),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cfg.isRotated ? const Color(0xFFF59E0B).withValues(alpha: 0.7) : border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rotate_right, size: 14, color: Color(0xFFF59E0B)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Xoay tiết diện quanh trục thanh (β = ${curRot.toStringAsFixed(0)}°)',
                  style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Tooltip(
                message: 'Áp dụng góc xoay ${curRot.toStringAsFixed(0)}° cho toàn bộ các thanh',
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => _updateAndSolve(() {
                    _elemSections = [
                      for (final s in _elemSections) s.copyWith(rotationDeg: curRot),
                    ];
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                    ),
                    child: const Text('Xoay hết',
                        style: TextStyle(fontSize: 8.8, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24))),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    rotBtn('0°', () => setRot(0), selected: (curRot % 360).abs() < 0.5),
                    rotBtn('90°', () => setRot(90), selected: (curRot - 90).abs() < 0.5),
                    rotBtn('180°', () => setRot(180), selected: (curRot - 180).abs() < 0.5),
                    rotBtn('270°', () => setRot(270), selected: (curRot - 270).abs() < 0.5),
                    rotBtn('-45°', () => setRot(curRot - 45)),
                    rotBtn('+45°', () => setRot(curRot + 45)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 66,
                child: _CompactDimField(
                  key: ValueKey('rot_${activeIdx}_${curRot.round()}'),
                  label: 'Góc β',
                  value: double.parse(curRot.toStringAsFixed(1)),
                  minVal: 0,
                  maxVal: 360,
                  unit: '°',
                  darkMode: _darkMode,
                  onChanged: setRot,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// TAB 1 TRÁI: Khoảng cách & Chiều dài Thanh + Custom Truss Builder (Thêm/Xóa Nút & Thanh) + Liên kết Gối tựa
  Widget _buildLeftGeometryTab(Color cardBg, Color border) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _buildMemberLengthsCard(cardBg, border),
        const SizedBox(height: 10),
        _buildCustomTrussBuilderCard(cardBg, border),
        const SizedBox(height: 10),
        _buildSupportsCard(cardBg, border),
      ],
    );
  }

  /// Card Custom Truss Builder: Thêm / Xóa Nút & Thanh trực tiếp
  Widget _buildCustomTrussBuilderCard(Color cardBg, Color border) {
    final boxBg = _darkMode ? const Color(0xFF0A1426) : const Color(0xFFF8FAFC);
    final textSub = _darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    void addNewNode() {
      double maxX = 0.0, avgY = 0.0;
      for (final c in _model.coords) {
        if (c[0] > maxX) maxX = c[0];
        avgY += c[1];
      }
      avgY /= math.max(1, _model.nNodes);
      final newX = double.parse((maxX + _lMm).toStringAsFixed(1));
      final newY = double.parse(avgY.toStringAsFixed(1));
      _updateAndSolve(() {
        final coords = [for (final c in _model.coords) List<double>.from(c), [newX, newY]];
        final conn = [for (final e in _model.conn) List<int>.from(e)];
        final newNodeIdx = coords.length; // 1-based
        // Tự nối 2 thanh tới 2 nút gần nhất để hệ mới thêm vào không bị biến hình tự do!
        final dists = [
          for (int i = 0; i < coords.length - 1; i++)
            (
              i + 1,
              math.pow(coords[i][0] - newX, 2) + math.pow(coords[i][1] - newY, 2),
            ),
        ]..sort((a, b) => a.$2.compareTo(b.$2));
        for (int k = 0; k < math.min(2, dists.length); k++) {
          conn.add([dists[k].$1, newNodeIdx]);
        }
        _customCoords = coords;
        _customConn = conn;
        _nodeSupports = [..._nodeSupports, NodeSupportType.free];
        _supportDirections = [..._supportDirections, SupportDirection.auto];
        for (int k = 0; k < math.min(2, dists.length); k++) {
          _elemSections = [..._elemSections, const ElementSectionConfig(shape: SectionShape.iSection)];
        }
        if (_customNodalLoadsKn != null) {
          _customNodalLoadsKn = [..._customNodalLoadsKn!, [0.0, 0.0]];
        }
      });
      _showSnack('Đã thêm Nút N${_model.nNodes} tại ($newX, $newY) mm và tự nối thanh liên kết!', seconds: 2);
    }

    void addNewBar() {
      if (_newBarNodeA == _newBarNodeB) return;
      final exists = _model.conn.any(
        (c) => (c[0] == _newBarNodeA && c[1] == _newBarNodeB) || (c[0] == _newBarNodeB && c[1] == _newBarNodeA),
      );
      if (exists) {
        _showSnack('Thanh nối N$_newBarNodeA–N$_newBarNodeB đã tồn tại!', bg: const Color(0xFFB45309), seconds: 2);
        return;
      }
      _updateAndSolve(() {
        _customCoords = [for (final c in _model.coords) List<double>.from(c)];
        _customConn = [for (final e in _model.conn) List<int>.from(e), [_newBarNodeA, _newBarNodeB]];
        _elemSections = [..._elemSections, const ElementSectionConfig(shape: SectionShape.iSection)];
      });
    }

    void removeBar(int elemIdx) {
      if (_model.nElems <= 1) {
        _showSnack('Mô hình cần giữ tối thiểu 1 thanh!', bg: const Color(0xFFB45309), seconds: 2);
        return;
      }
      _updateAndSolve(() {
        _customCoords = [for (final c in _model.coords) List<double>.from(c)];
        final nextConn = [for (final e in _model.conn) List<int>.from(e)]..removeAt(elemIdx);
        final nextSec = List<ElementSectionConfig>.from(_elemSections)..removeAt(elemIdx);
        _customConn = nextConn;
        _elemSections = nextSec;
      });
    }

    void removeLastNode() {
      if (_model.nNodes <= 3) {
        _showSnack('Hệ dàn cần tối thiểu 3 nút!', bg: const Color(0xFFB45309), seconds: 2);
        return;
      }
      final delNode1 = _model.nNodes;
      final remainingConn = <List<int>>[];
      final remainingSec = <ElementSectionConfig>[];
      for (int e = 0; e < _model.nElems; e++) {
        if (_model.conn[e][0] != delNode1 && _model.conn[e][1] != delNode1) {
          remainingConn.add(List<int>.from(_model.conn[e]));
          remainingSec.add(_elemSections[e]);
        }
      }
      if (remainingConn.isEmpty) {
        _showSnack('Không thể xóa nút cuối vì sẽ không còn thanh nào!', bg: const Color(0xFFB45309), seconds: 2);
        return;
      }
      _updateAndSolve(() {
        _customCoords = [for (int i = 0; i < _model.nNodes - 1; i++) List<double>.from(_model.coords[i])];
        _customConn = remainingConn;
        _elemSections = remainingSec;
        _nodeSupports = _nodeSupports.sublist(0, _model.nNodes - 1);
        _supportDirections = _supportDirections.sublist(0, _model.nNodes - 1);
        if (_customNodalLoadsKn != null && _customNodalLoadsKn!.length >= _model.nNodes) {
          _customNodalLoadsKn = _customNodalLoadsKn!.sublist(0, _model.nNodes - 1);
        }
      });
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '2. Tạo / Sửa Topo Hệ Dàn (Thêm Nút & Thanh)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.1, color: Color(0xFF10B981)),
                ),
              ),
              Text(
                '${_model.nNodes}N · ${_model.nElems}T',
                style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: addNewNode,
                  icon: const Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF10B981)),
                  label: const Text('+ Thêm nút', style: TextStyle(fontSize: 10.2, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: removeLastNode,
                  icon: const Icon(Icons.remove_circle_outline, size: 14, color: Color(0xFFF43F5E)),
                  label: Text('Xóa N${_model.nNodes}', style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(color: boxBg, borderRadius: BorderRadius.circular(7), border: Border.all(color: border)),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Nối:', style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    DropdownButton<int>(
                      value: _newBarNodeA.clamp(1, _model.nNodes),
                      isDense: true,
                      iconSize: 16,
                      underline: const SizedBox(),
                      items: [
                        for (int i = 1; i <= _model.nNodes; i++)
                          DropdownMenuItem(value: i, child: Text('N$i', style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.bold))),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _newBarNodeA = v);
                      },
                    ),
                    const Text('→', style: TextStyle(fontSize: 10.5)),
                    const SizedBox(width: 2),
                    DropdownButton<int>(
                      value: _newBarNodeB.clamp(1, _model.nNodes),
                      isDense: true,
                      iconSize: 16,
                      underline: const SizedBox(),
                      items: [
                        for (int i = 1; i <= _model.nNodes; i++)
                          DropdownMenuItem(value: i, child: Text('N$i', style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.bold))),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _newBarNodeB = v);
                      },
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: addNewBar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('+ Thanh', style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (int e = 0; e < _model.nElems; e++)
                Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.only(left: 6, right: 2),
                  label: Text('T${e + 1}(${_model.conn[e][0]}-${_model.conn[e][1]})', style: const TextStyle(fontSize: 9.2)),
                  deleteIcon: const Icon(Icons.close, size: 12),
                  deleteButtonTooltipMessage: 'Xóa thanh T${e + 1}',
                  onDeleted: _model.nElems > 1 ? () => removeBar(e) : null,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Mẹo: Nhấn "+ Thêm nút" rồi chỉnh (X, Y) ở mục 1 để dựng hệ dàn tùy ý bất kỳ!',
            style: TextStyle(fontSize: 9.0, color: textSub),
          ),
        ],
      ),
    );
  }

  /// Card Liên kết Gối tựa tại các Nút (đã bỏ nút Sơ đồ/Chế tạo bị trùng)
  Widget _buildSupportsCard(Color cardBg, Color border) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _resActive.warningMessage != null
              ? const Color(0xFFEF4444)
              : const Color(0xFF06B6D4).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('3. Liên kết Gối tựa tại các Nút',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.2, color: Color(0xFF38BDF8))),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.55)),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => _updateAndSolve(() {
                  final defSup = TrussModelData.defaultSupportsFor(_preset);
                  final defDir = TrussModelData.defaultDirectionsFor(_preset);
                  _nodeSupports = [
                    for (int i = 0; i < _model.nNodes; i++) i < defSup.length ? defSup[i] : NodeSupportType.free,
                  ];
                  _supportDirections = [
                    for (int i = 0; i < _model.nNodes; i++) i < defDir.length ? defDir[i] : SupportDirection.auto,
                  ];
                  _springStiffnessKnMm = 500.0;
                }),
                icon: const Icon(Icons.undo, size: 12),
                label: const Text('Mặc định', style: TextStyle(fontSize: 9.8, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: _resActive.warningMessage != null
                  ? const Color(0x33EF4444)
                  : (_model.totalRestraintsCount > 3 ? const Color(0x2238BDF8) : const Color(0x2210B981)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _resActive.warningMessage != null
                  ? '⚠ Hệ BIẾN HÌNH (${_model.totalRestraintsCount} ràng buộc — thiếu gối!)'
                  : (_model.totalRestraintsCount == 3
                      ? '✓ Bất biến hình — Tĩnh định ngoài (3 ràng buộc)'
                      : '✓ Bất biến hình — Siêu tĩnh bậc ${_model.totalRestraintsCount - 3} (${_model.totalRestraintsCount} ràng buộc)'),
              style: TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.w600,
                color: _resActive.warningMessage != null
                    ? const Color(0xFFFCA5A5)
                    : (_model.totalRestraintsCount > 3 ? const Color(0xFF38BDF8) : const Color(0xFF10B981)),
              ),
            ),
          ),
          const SizedBox(height: 7),
          for (int i = 0; i < _model.nNodes; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() {
                      _selectedNode = i;
                      _rightTab = 1;
                      _showRightPanel = true;
                    }),
                    child: Container(
                      width: 34,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _supportBadgeColor(_nodeSupports[i]).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _selectedNode == i ? const Color(0xFF00E5FF) : _supportBadgeColor(_nodeSupports[i]).withValues(alpha: 0.7),
                          width: _selectedNode == i ? 1.5 : 1.0,
                        ),
                      ),
                      child: Text(
                        'N${i + 1}',
                        style: TextStyle(
                          fontSize: 10.2,
                          fontWeight: FontWeight.bold,
                          color: _supportBadgeColor(_nodeSupports[i]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButtonFormField<NodeSupportType>(
                      key: ValueKey('sup_${_preset.code}_${_model.nNodes}_${i}_${_nodeSupports[i].code}'),
                      initialValue: _nodeSupports[i],
                      isExpanded: true,
                      isDense: true,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final st in NodeSupportType.values)
                          DropdownMenuItem(
                            value: st,
                            child: Text(st.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.2)),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        _updateAndSolve(() {
                          final next = List<NodeSupportType>.from(_nodeSupports);
                          next[i] = v;
                          _nodeSupports = next;
                        });
                      },
                    ),
                  ),
                  if (_nodeSupports[i] != NodeSupportType.free) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Hướng gối Nút ${i + 1}: ${_supportDirections[i].label}',
                      child: PopupMenuButton<SupportDirection>(
                        padding: EdgeInsets.zero,
                        initialValue: _supportDirections[i],
                        onSelected: (d) => _updateAndSolve(() {
                          final next = List<SupportDirection>.from(_supportDirections);
                          next[i] = d;
                          _supportDirections = next;
                        }),
                        itemBuilder: (_) => [
                          for (final d in SupportDirection.values)
                            PopupMenuItem(value: d, height: 30, child: Text(d.label, style: const TextStyle(fontSize: 11.2))),
                        ],
                        child: Container(
                          width: 34,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0EA5E9).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.55)),
                          ),
                          child: Text(
                            _supportDirections[i].shortIcon,
                            style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_model.hasAnySpring) ...[
            const Divider(height: 10),
            _EditableParamSlider(
              label: 'Độ cứng gối lò xo k',
              value: _springStiffnessKnMm,
              min: 10,
              max: 5000,
              hardMin: 0.1,
              hardMax: 1000000,
              unit: 'kN/mm',
              darkMode: _darkMode,
              onChanged: (v) => _updateAndSolve(() => _springStiffnessKnMm = v),
            ),
          ],
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _connectionMode = ConnectionDisplayMode.fabrication;
                _rightTab = 1;
                _mobileTab = 1;
                _showRightPanel = true;
              }),
              icon: const Icon(Icons.calculate_outlined, size: 14, color: Color(0xFFFBBF24)),
              label: const Text('Mở bản vẽ & kiểm tra liên kết chi tiết',
                  style: TextStyle(fontSize: 10.2, fontWeight: FontWeight.w600, color: Color(0xFFFBBF24))),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: const Color(0xFFFBBF24).withValues(alpha: 0.55)),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// TAB 2 TRÁI: Tải trọng nhiều nút (Fx, Fy) + Thông số cơ sở + Phi tuyến Vật liệu GMNIA + KPI
  Widget _buildLeftLoadsMaterialTab(Color cardBg, Color border) {
    final boxBg = _darkMode ? const Color(0xFF0A1426) : const Color(0xFFF8FAFC);
    final textSub = _darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    void setNodeLoad(int nodeIdx, int axis, double valKn) {
      final loads = [
        for (int i = 0; i < _model.nNodes; i++)
          [
            double.parse((_model.fRef[2 * i] / 1000.0).toStringAsFixed(2)),
            double.parse((_model.fRef[2 * i + 1] / 1000.0).toStringAsFixed(2)),
          ],
      ];
      loads[nodeIdx][axis] = valKn;
      _updateAndSolve(() => _customNodalLoadsKn = loads);
    }

    double maxDispMm = 0.0;
    for (int i = 0; i < _model.nNodes; i++) {
      final u = math.sqrt(math.pow(_resActive.uMm[2 * i], 2) + math.pow(_resActive.uMm[2 * i + 1], 2));
      if (u > maxDispMm) maxDispMm = u;
    }
    final maxUtil = _designChecks.isEmpty ? 0.0 : _designChecks.map((c) => c.utilizationPct).reduce(math.max);
    final yieldedCnt = _resActive.yieldedElems.where((y) => y).length;

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // 1. Tải trọng tập trung tùy biến (Fx, Fy) tại bất kỳ nút nào
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _customNodalLoadsKn != null ? const Color(0xFFFF3B5C).withValues(alpha: 0.65) : border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('1. Tải trọng tại các Nút (Fx, Fy kN)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.2, color: Color(0xFFFF5A79))),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _updateAndSolve(() => _customNodalLoadsKn = null),
                    icon: const Icon(Icons.undo, size: 11.5),
                    label: const Text('Mặc định', style: TextStyle(fontSize: 9.6)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (int i = 0; i < _model.nNodes; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i + 1 < _model.nNodes ? 5 : 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        width: 32,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: (_model.fRef[2 * i].abs() > 1e-3 || _model.fRef[2 * i + 1].abs() > 1e-3)
                              ? const Color(0xFFFF3B5C).withValues(alpha: 0.20)
                              : boxBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (_model.fRef[2 * i].abs() > 1e-3 || _model.fRef[2 * i + 1].abs() > 1e-3)
                                ? const Color(0xFFFF5A79)
                                : border,
                          ),
                        ),
                        child: Text(
                          'N${i + 1}',
                          style: TextStyle(
                            fontSize: 10.0,
                            fontWeight: FontWeight.bold,
                            color: (_model.fRef[2 * i].abs() > 1e-3 || _model.fRef[2 * i + 1].abs() > 1e-3)
                                ? const Color(0xFFFF5A79)
                                : textSub,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _CompactDimField(
                          key: ValueKey('fx_${_preset.code}_${_model.nNodes}_$i'),
                          label: 'Fx${i + 1}',
                          value: double.parse((_model.fRef[2 * i] / 1000.0).toStringAsFixed(1)),
                          minVal: -100000,
                          maxVal: 100000,
                          allowNegative: true,
                          unit: 'kN',
                          darkMode: _darkMode,
                          onChanged: (v) => setNodeLoad(i, 0, v),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _CompactDimField(
                          key: ValueKey('fy_${_preset.code}_${_model.nNodes}_$i'),
                          label: 'Fy${i + 1}',
                          value: double.parse((_model.fRef[2 * i + 1] / 1000.0).toStringAsFixed(1)),
                          minVal: -100000,
                          maxVal: 100000,
                          allowNegative: true,
                          unit: 'kN',
                          darkMode: _darkMode,
                          onChanged: (v) => setNodeLoad(i, 1, v),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2. Thông số Vật liệu, Mức tải & Phi tuyến Vật liệu GMNIA
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('2. Thông số Vật liệu, Mức tải & GMNIA',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.2, color: Color(0xFF38BDF8))),
              const SizedBox(height: 4),
              _EditableParamSlider(
                label: 'Chiều dài cơ sở L',
                value: _lMm,
                min: 500,
                max: 4000,
                hardMin: 10,
                hardMax: 100000,
                unit: 'mm',
                darkMode: _darkMode,
                onChanged: (v) => _updateAndSolve(() {
                  if (_customCoords != null && _lMm > 1e-6) {
                    final ratio = v / _lMm;
                    _customCoords = [
                      for (final c in _customCoords!)
                        [
                          double.parse((c[0] * ratio).toStringAsFixed(1)),
                          double.parse((c[1] * ratio).toStringAsFixed(1)),
                        ],
                    ];
                  }
                  _lMm = v;
                }),
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
                label: 'Giới hạn chảy thép fy',
                value: _fyMpa,
                min: 150,
                max: 690,
                hardMin: 50,
                hardMax: 2000,
                unit: 'MPa',
                darkMode: _darkMode,
                onChanged: (v) => _updateAndSolve(() => _fyMpa = v),
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
                onChanged: (v) => _updateAndSolve(() {
                  _pKn = v;
                  _customNodalLoadsKn = null;
                }),
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
                    if (_loadFactor.abs() > 20) _deformScale = 1.5;
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
              const Divider(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Phi tuyến Vật liệu đàn-dẻo (GMNIA)',
                          style: TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _materialNonlinear
                              ? 'Đang kích hoạt chảy dẻo song tuyến (Et/E = ${(_hardeningRatio * 100).toStringAsFixed(1)}%, chảy: $yieldedCnt/${_model.nElems} thanh)'
                              : 'Tắt = Đàn hồi hình học thuần (GNIA)',
                          style: TextStyle(fontSize: 9.3, color: textSub),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _materialNonlinear,
                    onChanged: (v) => _updateAndSolve(() => _materialNonlinear = v),
                  ),
                ],
              ),
              if (_materialNonlinear)
                _EditableParamSlider(
                  label: 'Tỷ số tái bền Et / E',
                  value: _hardeningRatio * 100.0,
                  min: 0.5,
                  max: 20.0,
                  hardMin: 0.2,
                  hardMax: 50.0,
                  unit: '%',
                  darkMode: _darkMode,
                  onChanged: (v) => _updateAndSolve(() => _hardeningRatio = v / 100.0),
                ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _resetDefaults,
                  icon: const Icon(Icons.settings_backup_restore, size: 15),
                  label: const Text('Reset toàn bộ về mặc định', style: TextStyle(fontSize: 10.8, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _darkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                    side: BorderSide(color: border),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 3. Chỉ số Kết quả Tức thì (KPI)
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.3, color: Color(0xFF10B981))),
              const SizedBox(height: 6),
              Text(
                '• Chuyển vị max ||u|| : ${maxDispMm.toStringAsFixed(5)} mm\n'
                '• Tỷ số bền/ổn định  : U_max = ${maxUtil.toStringAsFixed(1)}% (${maxUtil <= 100 ? "ĐẠT" : "VƯỢT"})\n'
                '• Mất ổn định trị riêng: ${_buckling.hasBucklingMode ? "α_cr = ${_buckling.alphaCr.toStringAsFixed(2)} (P_cr = ${(_buckling.pCrKn / 1000).toStringAsFixed(2)} MN)" : "Không mất ổn định"}\n'
                '• Hội tụ thuật toán   : ${_resActive.converged ? "ĐẠT" : "KHÔNG ĐẠT"} (${_resActive.totalIterations} vòng lặp)',
                style: const TextStyle(fontSize: 10.2, fontFamily: 'DejaVuSansMono', height: 1.45),
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
        designChecks: _designChecks,
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
      return ConnectionDetailPanel(
        model: _model,
        resultNL: _resActive,
        loadFactor: _loadFactor,
        selectedNode: _selectedNode,
        connectionMode: _connectionMode,
        designParams: _connParams,
        darkMode: _darkMode,
        onNodeChanged: (n) => setState(() => _selectedNode = n),
        onModeChanged: (m) => setState(() => _connectionMode = m),
        onParamsChanged: (p) => setState(() => _connParams = p),
        onSupportChanged: (nodeIdx, newType) => _updateAndSolve(() {
          final next = List<NodeSupportType>.from(_nodeSupports);
          if (nodeIdx >= 0 && nodeIdx < next.length) {
            next[nodeIdx] = newType;
            _nodeSupports = next;
          }
        }),
        onDirectionChanged: (nodeIdx, newDir) => _updateAndSolve(() {
          final next = List<SupportDirection>.from(_supportDirections);
          if (nodeIdx >= 0 && nodeIdx < next.length) {
            next[nodeIdx] = newDir;
            _supportDirections = next;
          }
        }),
      );
    }
    if (tabIdx == 2) {
      return ChartsAndTablesPanel(
        model: _model,
        resLinear: _resLinear,
        resActive: _resActive,
        resBar2g: _resBar2g,
        resCorot: _resCorot,
        resTL: _resTL,
        snapCurve: _snapCurve,
        designChecks: _designChecks,
        buckling: _buckling,
        loadFactor: _loadFactor,
        darkMode: _darkMode,
      );
    }
    return TheoryAndCodePanel(darkMode: _darkMode);
  }

  void _applyCustomSectionForElem(int elemIdx, CustomSectionGeometry nextGeom) {
    _updateAndSolve(() {
      final idx = elemIdx.clamp(0, _elemSections.length - 1);
      final next = List<ElementSectionConfig>.from(_elemSections);
      next[idx] = next[idx].copyWith(customGeometry: nextGeom);
      _elemSections = next;
    });
  }

  bool _areCoordsValid(List<List<double>> coords) {
    for (final e in _model.conn) {
      final ni = e[0] - 1;
      final nj = e[1] - 1;
      final len = math.sqrt(
        math.pow(coords[nj][0] - coords[ni][0], 2) + math.pow(coords[nj][1] - coords[ni][1], 2),
      );
      if (len < 20.0) return false;
    }
    return true;
  }

  void _setMemberLength(int elemIdx, double newLenMm) {
    final idx = elemIdx.clamp(0, _model.nElems - 1);
    final coords = [for (final c in _model.coords) List<double>.from(c)];
    final ni = _model.conn[idx][0] - 1;
    final nj = _model.conn[idx][1] - 1;
    final anchor = (nj == 0 && ni != 0) ? nj : ni;
    final movable = (nj == 0 && ni != 0) ? ni : nj;
    final dx = coords[movable][0] - coords[anchor][0];
    final dy = coords[movable][1] - coords[anchor][1];
    final oldLen = math.sqrt(dx * dx + dy * dy);
    if (oldLen < 1e-6) return;
    final targetLen = newLenMm.clamp(50.0, 50000.0).toDouble();
    coords[movable][0] = double.parse((coords[anchor][0] + (dx / oldLen) * targetLen).toStringAsFixed(1));
    coords[movable][1] = double.parse((coords[anchor][1] + (dy / oldLen) * targetLen).toStringAsFixed(1));
    if (!_areCoordsValid(coords)) return;
    _updateAndSolve(() => _customCoords = coords);
  }

  void _setNodeCoord(int nodeIdx, int axis, double valMm) {
    if (nodeIdx < 0 || nodeIdx >= _model.nNodes) return;
    final coords = [for (final c in _model.coords) List<double>.from(c)];
    coords[nodeIdx][axis] = double.parse(valMm.clamp(-50000.0, 50000.0).toStringAsFixed(1));
    if (!_areCoordsValid(coords)) return;
    _updateAndSolve(() => _customCoords = coords);
  }

  Widget _buildMemberLengthsCard(Color cardBg, Color border) {
    final boxBg = _darkMode ? const Color(0xFF0A1426) : const Color(0xFFF8FAFC);
    final textSub = _darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final isCustom = _customCoords != null || _customConn != null;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isCustom ? const Color(0xFF06B6D4).withValues(alpha: 0.65) : border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '1. Khoảng cách & Chiều dài Thanh (mm)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.2, color: Color(0xFF38BDF8)),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.55)),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => _updateAndSolve(() {
                  _customCoords = null;
                  _customConn = null;
                }),
                icon: const Icon(Icons.undo, size: 12),
                label: const Text('Mặc định', style: TextStyle(fontSize: 9.8, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('Chiều dài thanh L', style: TextStyle(fontSize: 9.8))),
              ButtonSegment(value: true, label: Text('Tọa độ nút (X, Y)', style: TextStyle(fontSize: 9.8))),
            ],
            selected: {_editNodeCoordsMode},
            onSelectionChanged: (s) => setState(() => _editNodeCoordsMode = s.first),
          ),
          const SizedBox(height: 7),
          if (!_editNodeCoordsMode) ...[
            for (int e = 0; e < _model.nElems; e++)
              Padding(
                padding: EdgeInsets.only(bottom: e + 1 < _model.nElems ? 5 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _selectedElem = e),
                      child: Container(
                        width: 66,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: e == _selectedElem ? const Color(0xFF06B6D4).withValues(alpha: 0.24) : boxBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: e == _selectedElem ? const Color(0xFF00E5FF) : border),
                        ),
                        child: Text(
                          'T${e + 1} (${_model.memberLabels[e]})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.3,
                            fontWeight: FontWeight.bold,
                            color: e == _selectedElem
                                ? const Color(0xFF00E5FF)
                                : (_darkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _CompactDimField(
                        key: ValueKey('len_${_preset.code}_${_model.nElems}_$e'),
                        label: 'L${e + 1} (N${_model.conn[e][0]}→N${_model.conn[e][1]})',
                        value: double.parse(_model.initialLength(e).toStringAsFixed(1)),
                        minVal: 50,
                        maxVal: 50000,
                        darkMode: _darkMode,
                        onChanged: (v) => _setMemberLength(e, v),
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...[
            for (int i = 0; i < _model.nNodes; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i + 1 < _model.nNodes ? 5 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 32,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: boxBg, borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
                      child: Text('N${i + 1}',
                          style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _CompactDimField(
                        key: ValueKey('nx_${_preset.code}_${_model.nNodes}_$i'),
                        label: 'X${i + 1}',
                        value: double.parse(_model.coords[i][0].toStringAsFixed(1)),
                        minVal: -50000,
                        maxVal: 50000,
                        allowNegative: true,
                        darkMode: _darkMode,
                        onChanged: (v) => _setNodeCoord(i, 0, v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _CompactDimField(
                        key: ValueKey('ny_${_preset.code}_${_model.nNodes}_$i'),
                        label: 'Y${i + 1}',
                        value: double.parse(_model.coords[i][1].toStringAsFixed(1)),
                        minVal: -50000,
                        maxVal: 50000,
                        allowNegative: true,
                        darkMode: _darkMode,
                        onChanged: (v) => _setNodeCoord(i, 1, v),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 5),
          Text(
            _editNodeCoordsMode
                ? 'Chỉnh tọa độ (X, Y) tự do để đổi nhịp, chiều cao hoặc độ dốc dàn.'
                : 'Sửa chiều dài L sẽ dịch nút cuối thanh theo phương thanh.',
            style: TextStyle(fontSize: 9.0, height: 1.25, color: textSub),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionGeometryBox(Color border, int activeIdx) {
    final cfg = _model.sectionConfigForElem(activeIdx);
    final shapeE = cfg.shape;
    final isManual = cfg.isManualMm;
    final geom = cfg.customGeometry ?? CustomSectionGeometry.fromArea(shapeE, _model.areas[activeIdx]);
    final dims = _model.sectionDimsForElem(activeIdx);
    final boxBg = _darkMode ? const Color(0xFF0A1426) : const Color(0xFFF8FAFC);
    final textSub = _darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    final fields = <Widget>[];
    void addField(String lbl, double val, double minV, double maxV, ValueChanged<double> onSet) {
      fields.add(
        _CompactDimField(
          key: ValueKey('dim_${activeIdx}_${shapeE.code}_$lbl'),
          label: lbl,
          value: val,
          minVal: minV,
          maxVal: maxV,
          darkMode: _darkMode,
          onChanged: onSet,
        ),
      );
    }

    switch (shapeE) {
      case SectionShape.solidRod:
        addField('Đường kính D', geom.heightMm, 8, 2000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(heightMm: v, widthMm: v)));
        break;
      case SectionShape.circTube:
        addField('Đường kính D', geom.heightMm, 12, 2000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(heightMm: v, widthMm: v)));
        addField('Thành dày t', geom.tfMm, 1, 400,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(tfMm: v, twMm: v)));
        break;
      case SectionShape.solidRect:
        addField('Chiều cao H', geom.heightMm, 8, 2000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(heightMm: v)));
        addField('Bề rộng B', geom.widthMm, 8, 2000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(widthMm: v)));
        break;
      case SectionShape.boxSection:
        addField('Chiều cao H', geom.heightMm, 12, 2000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(heightMm: v)));
        addField('Bề rộng B', geom.widthMm, 12, 2000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(widthMm: v)));
        addField('Thành dày t', geom.tfMm, 1, 400,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(tfMm: v, twMm: v)));
        break;
      case SectionShape.angleL:
        addField('Cạnh đứng H', geom.heightMm, 15, 1000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(heightMm: v)));
        addField('Cạnh ngang B', geom.widthMm, 15, 1000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(widthMm: v)));
        addField('Chiều dày t', geom.tfMm, 1.5, 200,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(tfMm: v, twMm: v)));
        break;
      case SectionShape.zeeSection:
        addField('Chiều cao H', geom.heightMm, 20, 1000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(heightMm: v)));
        addField('Rộng cánh B₁', geom.widthMm, 15, 600,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(widthMm: v)));
        addField('Chiều dày t', geom.tfMm, 1, 150,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(tfMm: v, twMm: v)));
        break;
      case SectionShape.doubleAngle:
        addField('Cạnh đứng H', geom.heightMm, 15, 1000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(heightMm: v)));
        addField('1 cánh B₁', geom.widthMm, 15, 1000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(widthMm: v)));
        addField('Chiều dày t', geom.tfMm, 1.5, 200,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(tfMm: v, twMm: v)));
        addField('Khe hở s', geom.gapMm, 0, 200,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(gapMm: v)));
        break;
      case SectionShape.doubleChannel:
        addField('Chiều cao H', geom.heightMm, 20, 1500,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(heightMm: v)));
        addField('1 cánh B₁', geom.widthMm, 15, 800,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(widthMm: v)));
        addField('Dày cánh tf', geom.tfMm, 1.5, 200,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(tfMm: v)));
        addField('Dày bụng tw', geom.twMm, 1.5, 200,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(twMm: v)));
        addField('Khe hở s', geom.gapMm, 0, 200,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(gapMm: v)));
        break;
      case SectionShape.iSection:
      case SectionShape.channelC:
      case SectionShape.teeSection:
      case SectionShape.cruciform:
        final tfLbl = shapeE == SectionShape.cruciform ? 'Nhánh ngang tf' : 'Dày cánh tf';
        final twLbl = shapeE == SectionShape.cruciform ? 'Nhánh đứng tw' : 'Dày bụng tw';
        addField('Chiều cao H', geom.heightMm, 20, 2000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(heightMm: v)));
        addField('Bề rộng B', geom.widthMm, 15, 2000,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(widthMm: v)));
        addField(tfLbl, geom.tfMm, 1.5, 300,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(tfMm: v)));
        addField(twLbl, geom.twMm, 1.5, 300,
            (v) => _applyCustomSectionForElem(activeIdx, geom.copyWith(twMm: v)));
        break;
    }

    final presets = CustomSectionGeometry.presetsFor(shapeE);
    final isRot = dims.rotationDeg.abs() > 0.05;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isManual ? const Color(0xFF06B6D4).withValues(alpha: 0.65) : border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.straighten, size: 13.5, color: Color(0xFF38BDF8)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Kích thước T${activeIdx + 1} (${_model.memberLabels[activeIdx]})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () => _updateAndSolve(() {
                  final next = List<ElementSectionConfig>.from(_elemSections);
                  if (!isManual) {
                    next[activeIdx] = next[activeIdx].copyWith(
                      customGeometry: CustomSectionGeometry.fromArea(shapeE, _model.areas[activeIdx]),
                    );
                  } else {
                    next[activeIdx] = next[activeIdx].copyWith(clearCustom: true);
                  }
                  _elemSections = next;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isManual
                        ? const Color(0xFF06B6D4).withValues(alpha: 0.22)
                        : (_darkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: isManual ? const Color(0xFF38BDF8) : border),
                  ),
                  child: Text(
                    isManual ? 'Đang nhập mm ✓' : 'Nhập tay (mm)',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: isManual ? const Color(0xFF38BDF8) : textSub),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${dims.formatSpec(shapeE)} • L=${_model.initialLength(activeIdx).toStringAsFixed(0)} mm\n'
            'A=${dims.areaMm2.toStringAsFixed(0)} mm² • ${isRot ? "Ix(β)" : "Ix"}=${(dims.ixRotated / 1e4).toStringAsFixed(1)} • ${isRot ? "Iy(β)" : "Iy"}=${(dims.iyRotated / 1e4).toStringAsFixed(1)} cm⁴ • i=${dims.rGyrationMin.toStringAsFixed(1)} mm',
            style: TextStyle(
              fontSize: 9.3,
              height: 1.35,
              fontFamily: 'DejaVuSansMono',
              color: _darkMode ? const Color(0xFFBAE6FD) : const Color(0xFF0F3D6E),
            ),
          ),
          if (isManual) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final (name, pGeom) in presets)
                  InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => _applyCustomSectionForElem(activeIdx, pGeom),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0EA5E9).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.45)),
                      ),
                      child: Text(name, style: const TextStyle(fontSize: 9.4, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            for (int r = 0; r < fields.length; r += 2)
              Padding(
                padding: EdgeInsets.only(bottom: r + 2 < fields.length ? 6 : 0),
                child: Row(
                  children: [
                    Expanded(child: fields[r]),
                    if (r + 1 < fields.length) ...[
                      const SizedBox(width: 6),
                      Expanded(child: fields[r + 1]),
                    ] else
                      const Expanded(child: SizedBox()),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Color _supportBadgeColor(NodeSupportType type) {
    if (type == NodeSupportType.free) return const Color(0xFF94A3B8);
    if (type == NodeSupportType.pin) return const Color(0xFF38BDF8);
    if (type.hasSpring) return const Color(0xFFFBBF24);
    return const Color(0xFF10B981);
  }
}

/// Ô nhập thông số kết hợp Thanh trượt (Dual Numeric TextField + Slider)
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
    if ((v - v.roundToDouble()).abs() < 1e-6) return v.round().toString();
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
              Expanded(child: Text(widget.label, style: const TextStyle(fontSize: 10.8), overflow: TextOverflow.ellipsis)),
              SizedBox(
                width: 72,
                height: 25,
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.numberWithOptions(signed: widget.allowNegative, decimal: !widget.isInt),
                  inputFormatters: [FilteringTextInputFormatter.allow(allowedRegex)],
                  style: const TextStyle(
                    fontSize: 10.8,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF38BDF8),
                    fontFamily: 'DejaVuSansMono',
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: fill,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide(color: bdr)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: Color(0xFF06B6D4), width: 1.4)),
                  ),
                  onSubmitted: (_) => _commitText(),
                  onTapOutside: (_) {
                    if (_focus.hasFocus) _focus.unfocus();
                  },
                ),
              ),
              const SizedBox(width: 5),
              SizedBox(
                width: 34,
                child: Text(
                  widget.unit,
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w600,
                    color: widget.darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
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

/// Ô nhập số gọn đa đơn vị (mm / ° / kN)
class _CompactDimField extends StatefulWidget {
  final String label;
  final double value;
  final double minVal;
  final double maxVal;
  final bool allowNegative;
  final String unit;
  final bool darkMode;
  final ValueChanged<double> onChanged;

  const _CompactDimField({
    super.key,
    required this.label,
    required this.value,
    required this.minVal,
    required this.maxVal,
    required this.darkMode,
    required this.onChanged,
    this.allowNegative = false,
    this.unit = 'mm',
  });

  @override
  State<_CompactDimField> createState() => _CompactDimFieldState();
}

class _CompactDimFieldState extends State<_CompactDimField> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  String _fmt(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-6) return v.round().toString();
    var s = v.toStringAsFixed(2);
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
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _CompactDimField oldWidget) {
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

  void _commit() {
    final raw = _ctrl.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw);
    if (parsed == null || !parsed.isFinite) {
      _ctrl.text = _fmt(widget.value);
      return;
    }
    final clamped = parsed.clamp(widget.minVal, widget.maxVal).toDouble();
    _ctrl.text = _fmt(clamped);
    if ((clamped - widget.value).abs() > 1e-9) {
      widget.onChanged(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.darkMode ? const Color(0xFF0F172A) : Colors.white;
    final bdr = widget.darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    final lblCol = widget.darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 9.4, fontWeight: FontWeight.w600, color: lblCol),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 26,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: widget.allowNegative),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                widget.allowNegative ? RegExp(r'[0-9\.\,\-]') : RegExp(r'[0-9\.\,]'),
              ),
            ],
            style: const TextStyle(
              fontSize: 10.6,
              fontWeight: FontWeight.bold,
              color: Color(0xFF38BDF8),
              fontFamily: 'DejaVuSansMono',
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: fill,
              suffixText: widget.unit,
              suffixStyle: TextStyle(fontSize: 8.6, color: lblCol),
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide(color: bdr)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: Color(0xFF06B6D4), width: 1.4)),
            ),
            onSubmitted: (_) => _commit(),
            onTapOutside: (_) {
              if (_focus.hasFocus) _focus.unfocus();
            },
          ),
        ),
      ],
    );
  }
}
