// ============================================================================
// BẢNG THIẾT KẾ, BẢN VẼ GIA CÔNG CHẾ TẠO & TÍNH TOÁN LIÊN KẾT KẾT CẤU THÉP
// ============================================================================
// Chức năng:
//   1. Chọn bất kỳ nút nào (N1..N4) để soi phóng to chi tiết liên kết theo:
//        - Chế độ "Sơ đồ tính" (trục thanh, lực dọc N, phản lực R, ký hiệu gối)
//        - Chế độ "Chi tiết chế tạo" (bản mã vát góc, bu-lông lục giác,
//          đường hàn góc cam, tai chốt Clevis, bản đế + sườn tăng cứng + bu-lông
//          neo + bê tông móng / gối con lăn cơ khí / gối lò xo công nghiệp).
//   2. Phủ bản đồ màu ứng suất tập trung von Mises trên bản mã.
//   3. Tùy chỉnh trực tiếp thông số gia công (mác thép, t_g, bu-lông, đường hàn,
//      chốt Clevis, bê tông móng) và xem bảng kiểm tra khả năng chịu lực tức thời
//      theo TCVN 5575 / EN 1993-1-8!
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/calfem_engine.dart';
import '../core/connection_calculator.dart';
import '../core/connection_drawing_exporter.dart';
import 'ansys_colorbar.dart';

class ConnectionDetailPanel extends StatefulWidget {
  final TrussModelData model;
  final TrussAnalysisResult resultNL;
  final double loadFactor;
  final int selectedNode;
  final ConnectionDisplayMode connectionMode;
  final ConnectionDesignParams designParams;
  final bool darkMode;
  final ValueChanged<int> onNodeChanged;
  final ValueChanged<ConnectionDisplayMode> onModeChanged;
  final ValueChanged<ConnectionDesignParams> onParamsChanged;
  final void Function(int nodeIndex, NodeSupportType newType) onSupportChanged;
  final void Function(int nodeIndex, SupportDirection newDir)? onDirectionChanged;

  const ConnectionDetailPanel({
    super.key,
    required this.model,
    required this.resultNL,
    required this.loadFactor,
    required this.selectedNode,
    required this.connectionMode,
    required this.designParams,
    required this.darkMode,
    required this.onNodeChanged,
    required this.onModeChanged,
    required this.onParamsChanged,
    required this.onSupportChanged,
    this.onDirectionChanged,
  });

  @override
  State<ConnectionDetailPanel> createState() => _ConnectionDetailPanelState();
}

class _ConnectionDetailPanelState extends State<ConnectionDetailPanel> {
  bool _showStressMap = true;
  bool _exportingDrawing = false;

  Future<void> _exportShopDrawing(NodeConnectionReport report, {required bool isAutoCad}) async {
    if (_exportingDrawing) return;
    setState(() => _exportingDrawing = true);
    try {
      final path = isAutoCad
          ? await ConnectionDrawingExporter.exportNodeDxf(model: widget.model, report: report)
          : await ConnectionDrawingExporter.exportNodeBlueprintPdf(model: widget.model, report: report);
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F766E),
            content: Text(
              isAutoCad
                  ? 'Đã xuất bản vẽ cấu tạo AutoCAD (.dxf) Nút ${report.nodeIndex + 1}:\n$path'
                  : 'Đã xuất bản vẽ kỹ thuật liên kết PDF Nút ${report.nodeIndex + 1}:\n$path',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB91C1C),
          content: Text('Lỗi xuất bản vẽ liên kết: $e', style: const TextStyle(color: Colors.white)),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingDrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.darkMode ? const Color(0xFF111B2E) : Colors.white;
    final border = widget.darkMode ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
    final textSub = widget.darkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    final ni = widget.selectedNode.clamp(0, widget.model.nNodes - 1);
    final report = ConnectionCalculator.analyzeNode(
      model: widget.model,
      result: widget.resultNL,
      nodeIndex: ni,
      params: widget.designParams,
      loadFactor: widget.loadFactor,
    );
    final p = widget.designParams;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. Tiêu đề Xưởng thiết kế & tính toán liên kết thép
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF0E7490)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.precision_manufacturing, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CHI TIẾT & TÍNH TOÁN LIÊN KẾT THÉP',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.6),
                    ),
                    Text(
                      'Bản vẽ chế tạo bản mã, bu-lông, đường hàn, bản đế & kiểm tra EN 1993-1-8 / TCVN 5575',
                      style: TextStyle(color: Color(0xFFE0F2FE), fontSize: 9.7),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: report.allPassed ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  report.allPassed
                      ? 'ĐẠT ${report.maxUtilizationPct.toStringAsFixed(0)}%'
                      : 'VƯỢT ${report.maxUtilizationPct.toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2. Chọn Nút + Chế độ Sơ đồ tính / Chi tiết chế tạo + Kiểu liên kết đầu thanh
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chọn nút khảo sát & chế độ bản vẽ liên kết:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (int i = 0; i < widget.model.nNodes; i++)
                    ChoiceChip(
                      label: Text(
                        'Nút ${i + 1} (${widget.model.nodeSupports[i].shortLabel})',
                        style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.w600),
                      ),
                      selected: i == ni,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => widget.onNodeChanged(i),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<ConnectionDisplayMode>(
                      segments: const [
                        ButtonSegment(
                          value: ConnectionDisplayMode.schematic,
                          icon: Icon(Icons.schema_outlined, size: 14),
                          label: Text('Sơ đồ tính', style: TextStyle(fontSize: 10.5)),
                        ),
                        ButtonSegment(
                          value: ConnectionDisplayMode.fabrication,
                          icon: Icon(Icons.construction, size: 14),
                          label: Text('Chi tiết chế tạo', style: TextStyle(fontSize: 10.5)),
                        ),
                      ],
                      selected: {widget.connectionMode},
                      onSelectionChanged: (s) => widget.onModeChanged(s.first),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<NodeSupportType>(
                key: ValueKey('panel_sup_${ni}_${report.supportType.code}'),
                initialValue: report.supportType,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  labelText: 'Loại liên kết gối tựa tại Nút ${ni + 1}',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final st in NodeSupportType.values)
                    DropdownMenuItem(
                      value: st,
                      child: Text(st.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.8)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) widget.onSupportChanged(ni, v);
                },
              ),
              if (report.supportType != NodeSupportType.free && widget.onDirectionChanged != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Hướng liên kết:',
                      style: TextStyle(fontSize: 10.2, fontWeight: FontWeight.w600, color: textSub),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final d in SupportDirection.values)
                            ChoiceChip(
                              label: Text(d.shortIcon, style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.bold)),
                              tooltip: d.label,
                              selected: (ni < widget.model.supportDirections.length
                                      ? widget.model.supportDirections[ni]
                                      : SupportDirection.auto) ==
                                  d,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                              onSelected: (_) => widget.onDirectionChanged!(ni, d),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              DropdownButtonFormField<ConnectionDetailType>(
                key: ValueKey('panel_dt_${p.detailType.code}'),
                initialValue: p.detailType,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Cấu tạo liên kết gia công thanh vào nút',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final dt in ConnectionDetailType.values)
                    DropdownMenuItem(
                      value: dt,
                      child: Text(dt.label, style: const TextStyle(fontSize: 10.8)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) widget.onParamsChanged(p.copyWith(detailType: v));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 3. Khung bản vẽ phóng to chi tiết nút liên kết
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.connectionMode == ConnectionDisplayMode.fabrication
                          ? 'Bản vẽ Gia công Chế tạo Nút ${ni + 1}'
                          : 'Sơ đồ Tính Cơ học tại Nút ${ni + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.3, color: Color(0xFF38BDF8)),
                    ),
                  ),
                  if (widget.connectionMode == ConnectionDisplayMode.fabrication)
                    FilterChip(
                      label: const Text('Bản đồ ứng suất', style: TextStyle(fontSize: 9.8)),
                      selected: _showStressMap,
                      visualDensity: VisualDensity.compact,
                      selectedColor: const Color(0xFF06B6D4).withValues(alpha: 0.35),
                      onSelected: (v) => setState(() => _showStressMap = v),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 295,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: widget.darkMode ? const Color(0xFF07101E) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    painter: _FabricationNodePainter(
                      model: widget.model,
                      report: report,
                      mode: widget.connectionMode,
                      showStressMap: _showStressMap,
                      darkMode: widget.darkMode,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '• Bản mã PL${p.gussetThicknessMm.toStringAsFixed(0)} (${report.gussetWidthMm.toStringAsFixed(0)}×${report.gussetHeightMm.toStringAsFixed(0)} mm, thép ${p.steelGrade.code})  •  '
                'Phản lực R = (${report.rxKn.toStringAsFixed(2)}, ${report.ryKn.toStringAsFixed(2)}) kN',
                style: TextStyle(fontSize: 9.8, color: textSub),
              ),
              const SizedBox(height: 8),
              // Nút xuất bản vẽ cấu tạo liên kết chuẩn xưởng chế tạo (PDF Vector & AutoCAD .dxf 1:1 mm)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _exportingDrawing ? null : () => _exportShopDrawing(report, isAutoCad: false),
                      icon: const Icon(Icons.picture_as_pdf, size: 15),
                      label: const Text('Bản vẽ PDF', style: TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB91C1C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _exportingDrawing ? null : () => _exportShopDrawing(report, isAutoCad: true),
                      icon: const Icon(Icons.architecture, size: 15),
                      label: const Text('AutoCAD (.dxf)', style: TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E7490),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 4. Thông số thiết kế liên kết tùy chỉnh
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Thông số Thiết kế & Gia công Liên kết',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.3, color: Color(0xFF38BDF8))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<SteelGrade>(
                      key: ValueKey('steel_${p.steelGrade.code}'),
                      initialValue: p.steelGrade,
                      isExpanded: true,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Mác thép bản mã', isDense: true, border: OutlineInputBorder()),
                      items: [
                        for (final g in SteelGrade.values)
                          DropdownMenuItem(value: g, child: Text(g.code, style: const TextStyle(fontSize: 10.8))),
                      ],
                      onChanged: (v) {
                        if (v != null) widget.onParamsChanged(p.copyWith(steelGrade: v));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      key: ValueKey('tg_${p.gussetThicknessMm}'),
                      initialValue: p.gussetThicknessMm,
                      isExpanded: true,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Dày bản mã t_g', isDense: true, border: OutlineInputBorder()),
                      items: [
                        for (final t in [10.0, 12.0, 14.0, 16.0, 20.0, 25.0])
                          DropdownMenuItem(value: t, child: Text('${t.toStringAsFixed(0)} mm', style: const TextStyle(fontSize: 10.8))),
                      ],
                      onChanged: (v) {
                        if (v != null) widget.onParamsChanged(p.copyWith(gussetThicknessMm: v));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (p.detailType == ConnectionDetailType.boltedGusset) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<BoltSpec>(
                        key: ValueKey('bolt_${p.boltSpec.code}'),
                        initialValue: p.boltSpec,
                        isExpanded: true,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Quy cách bu-lông', isDense: true, border: OutlineInputBorder()),
                        items: [
                          for (final b in BoltSpec.values)
                            DropdownMenuItem(value: b, child: Text(b.code, style: const TextStyle(fontSize: 10.8))),
                        ],
                        onChanged: (v) {
                          if (v != null) widget.onParamsChanged(p.copyWith(boltSpec: v));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('nb_${p.boltsPerMember}'),
                        initialValue: p.boltsPerMember,
                        isExpanded: true,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Số BL/thanh', isDense: true, border: OutlineInputBorder()),
                        items: [
                          for (final n in [2, 4, 6, 8])
                            DropdownMenuItem(value: n, child: Text('$n bu-lông', style: const TextStyle(fontSize: 10.8))),
                        ],
                        onChanged: (v) {
                          if (v != null) widget.onParamsChanged(p.copyWith(boltsPerMember: v));
                        },
                      ),
                    ),
                  ],
                ),
              ] else if (p.detailType == ConnectionDetailType.weldedGusset) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        key: ValueKey('hf_${p.weldLegMm}'),
                        initialValue: p.weldLegMm,
                        isExpanded: true,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Cạnh hàn h_f', isDense: true, border: OutlineInputBorder()),
                        items: [
                          for (final h in [6.0, 8.0, 10.0, 12.0])
                            DropdownMenuItem(value: h, child: Text('${h.toStringAsFixed(0)} mm', style: const TextStyle(fontSize: 10.8))),
                        ],
                        onChanged: (v) {
                          if (v != null) widget.onParamsChanged(p.copyWith(weldLegMm: v));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        key: ValueKey('lw_${p.weldLengthMm}'),
                        initialValue: p.weldLengthMm,
                        isExpanded: true,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Dài hàn l_w', isDense: true, border: OutlineInputBorder()),
                        items: [
                          for (final l in [100.0, 120.0, 160.0, 200.0, 250.0, 300.0])
                            DropdownMenuItem(value: l, child: Text('${l.toStringAsFixed(0)} mm', style: const TextStyle(fontSize: 10.8))),
                        ],
                        onChanged: (v) {
                          if (v != null) widget.onParamsChanged(p.copyWith(weldLengthMm: v));
                        },
                      ),
                    ),
                  ],
                ),
              ] else ...[
                DropdownButtonFormField<double>(
                  key: ValueKey('pin_${p.pinDiameterMm}'),
                  initialValue: p.pinDiameterMm,
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'Đường kính chốt bản lề d_pin', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final d in [40.0, 50.0, 60.0, 70.0, 80.0])
                      DropdownMenuItem(value: d, child: Text('Ø${d.toStringAsFixed(0)} mm (Thép C45/S355)', style: const TextStyle(fontSize: 10.8))),
                  ],
                  onChanged: (v) {
                    if (v != null) widget.onParamsChanged(p.copyWith(pinDiameterMm: v));
                  },
                ),
              ],
              if (report.supportType != NodeSupportType.free) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        key: ValueKey('fck_${p.concreteFckMpa}'),
                        initialValue: p.concreteFckMpa,
                        isExpanded: true,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Bê tông móng', isDense: true, border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 20.0, child: Text('C20/25 (B25)', style: TextStyle(fontSize: 10.5))),
                          DropdownMenuItem(value: 25.0, child: Text('C25/30 (B30)', style: TextStyle(fontSize: 10.5))),
                          DropdownMenuItem(value: 30.0, child: Text('C30/37 (B35)', style: TextStyle(fontSize: 10.5))),
                        ],
                        onChanged: (v) {
                          if (v != null) widget.onParamsChanged(p.copyWith(concreteFckMpa: v));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        key: ValueKey('tbp_${p.basePlateThickMm}'),
                        initialValue: p.basePlateThickMm,
                        isExpanded: true,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Dày bản đế t_bp', isDense: true, border: OutlineInputBorder()),
                        items: [
                          for (final tb in [16.0, 20.0, 25.0, 30.0, 40.0])
                            DropdownMenuItem(value: tb, child: Text('${tb.toStringAsFixed(0)} mm', style: const TextStyle(fontSize: 10.5))),
                        ],
                        onChanged: (v) {
                          if (v != null) widget.onParamsChanged(p.copyWith(basePlateThickMm: v));
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 5. Bảng Tính toán & Kiểm tra Khả năng Chịu lực Liên kết
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
                    child: Text(
                      'Kết quả Tính toán & Kiểm tra Liên kết (TCVN 5575 / EN 1993-1-8)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.2, color: Color(0xFF10B981)),
                    ),
                  ),
                  Text(
                    report.allPassed ? '✓ ĐẠT CHUẨN' : '✕ KHÔNG ĐẠT',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: report.allPassed ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Tóm tắt cân bằng lực tại nút
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.darkMode ? const Color(0xFF0A1426) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Nội lực quy tụ Nút ${ni + 1}: ${report.members.map((m) => "${m.label}=${m.forceKn >= 0 ? "+" : ""}${m.forceKn.toStringAsFixed(2)} kN").join("  |  ")}\n'
                  'Phản lực gối: Rₓ=${report.rxKn.toStringAsFixed(2)} kN, Rᵧ=${report.ryKn.toStringAsFixed(2)} kN  |  Chuyển vị: u=(${report.uxMm.toStringAsFixed(3)}, ${report.uyMm.toStringAsFixed(3)}) mm',
                  style: TextStyle(fontSize: 9.8, fontFamily: 'DejaVuSansMono', height: 1.4, color: textSub),
                ),
              ),
              const SizedBox(height: 8),
              for (final item in report.checks) _buildCheckCard(item, border, textSub),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCheckCard(ConnectionCheckItem item, Color border, Color textSub) {
    final pct = item.utilizationPct;
    final Color statusColor;
    if (pct > 100.0) {
      statusColor = const Color(0xFFEF4444);
    } else if (pct > 85.0) {
      statusColor = const Color(0xFFF97316);
    } else if (pct > 60.0) {
      statusColor = const Color(0xFFFBBF24);
    } else {
      statusColor = const Color(0xFF22C55E);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: widget.darkMode ? const Color(0xFF0B1528) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: statusColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                item.passed ? Icons.check_circle : Icons.error,
                size: 14,
                color: statusColor,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  item.category,
                  style: const TextStyle(fontSize: 10.6, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 10.2,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'DejaVuSansMono',
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (pct / 100.0).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: border,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '${item.demandLabel}  ≤  ${item.capacityLabel}',
                  style: const TextStyle(fontSize: 9.8, fontFamily: 'DejaVuSansMono'),
                ),
              ),
              Text(item.clauseRef, style: TextStyle(fontSize: 9.0, color: textSub)),
            ],
          ),
          const SizedBox(height: 2),
          Text(item.formulaText, style: TextStyle(fontSize: 9.3, color: textSub)),
        ],
      ),
    );
  }
}

/// Bộ vẽ phóng to bản vẽ chi tiết chế tạo nút liên kết & bản đồ ứng suất von Mises
class _FabricationNodePainter extends CustomPainter {
  final TrussModelData model;
  final NodeConnectionReport report;
  final ConnectionDisplayMode mode;
  final bool showStressMap;
  final bool darkMode;

  _FabricationNodePainter({
    required this.model,
    required this.report,
    required this.mode,
    required this.showStressMap,
    required this.darkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.50);

    // 1. Lưới bản vẽ CAD chế tạo
    final gridPaint = Paint()
      ..color = darkMode ? const Color(0xFF142238) : const Color(0xFFE2E8F0)
      ..strokeWidth = 0.7;
    for (double x = 0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Xác định hướng biên nút (trên/dưới, trái/phải) để bố trí bản đế móng hợp lý
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final c in model.coords) {
      minX = math.min(minX, c[0]);
      maxX = math.max(maxX, c[0]);
      minY = math.min(minY, c[1]);
      maxY = math.max(maxY, c[1]);
    }
    final cNode = model.coords[report.nodeIndex];
    final isTop = cNode[1] > 0.5 * (minY + maxY) + 1e-3;
    final isRight = cNode[0] > 0.5 * (minX + maxX) + 1e-3;

    if (mode == ConnectionDisplayMode.schematic) {
      _paintSchematicZoom(canvas, size, center, isTop, isRight);
      return;
    }

    // =========================================================================
    // CHẾ ĐỘ CHI TIẾT GIA CÔNG CHẾ TẠO NÚT THÉP
    // =========================================================================
    final p = report.params;
    final armLen = math.min(size.width, size.height) * 0.40;
    final gussetReach = armLen * 0.54;

    // 2. Tính đa giác Bản mã nút (Gusset Plate) cắt vát gia công bao trọn đầu thanh
    final hullPts = <Offset>[];
    for (final m in report.members) {
      final dir = Offset(math.cos(m.angleRad), -math.sin(m.angleRad));
      final perp = Offset(-dir.dy, dir.dx);
      final halfW = (m.heightMm * 0.24).clamp(16.0, 26.0) + 10.0;
      hullPts.add(center + dir * gussetReach + perp * halfW);
      hullPts.add(center + dir * gussetReach - perp * halfW);
      hullPts.add(center + perp * (halfW * 0.85));
      hullPts.add(center - perp * (halfW * 0.85));
    }
    if (report.supportType != NodeSupportType.free) {
      final outD = _dirOut(model.resolvedDirectionFor(report.nodeIndex));
      final tangD = Offset(-outD.dy, outD.dx);
      hullPts.add(center + outD * 46.0 - tangD * 38.0);
      hullPts.add(center + outD * 46.0 + tangD * 38.0);
    }
    final gussetPoly = _convexHull(hullPts);

    // 3. Vẽ chi tiết Gối tựa gia công chế tạo (Bản đế + Sườn + Bu-lông neo + Bê tông / Con lăn / Lò xo)
    _paintFabricationSupport(canvas, center, isTop, isRight);

    // 4. Vẽ các thanh thép ĐÃ CẮT NGẮN ĐẦU THANH (setback thực tế) NẰM PHÍA SAU bản mã trước!
    // Khi tô bản mã đặc 100% đè lên ở bước 5, mọi phần đầu thanh bị khuất sau bản mã sẽ ẩn hoàn toàn!
    final startDist = p.detailType == ConnectionDetailType.pinnedClevis
        ? gussetReach * 0.48
        : gussetReach * 0.44;
    for (final m in report.members) {
      final dir = Offset(math.cos(m.angleRad), -math.sin(m.angleRad));
      final perp = Offset(-dir.dy, dir.dx);
      final halfH = (m.heightMm * 0.24).clamp(15.0, 25.0);
      final endDist = armLen;

      final pA = center + dir * startDist;
      final pB = center + dir * endDist;
      final body = Path()
        ..moveTo((pA + perp * halfH).dx, (pA + perp * halfH).dy)
        ..lineTo((pB + perp * halfH).dx, (pB + perp * halfH).dy)
        ..lineTo((pB - perp * halfH).dx, (pB - perp * halfH).dy)
        ..lineTo((pA - perp * halfH).dx, (pA - perp * halfH).dy)
        ..close();

      final util = (m.activeUtilPct(p.detailType) / 100.0).clamp(0.05, 1.0);
      final memFill = showStressMap
          ? ansysRainbowColor(util * 0.85)
          : (darkMode ? const Color(0xFF334155) : const Color(0xFF94A3B8));
      canvas.drawPath(body, Paint()..color = memFill);
      canvas.drawPath(
        body,
        Paint()
          ..color = darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );

      // Hai đường cánh chữ I (Flange lines) chuẩn bản vẽ chế tạo
      final flangeOff = halfH * 0.68;
      final flangePaint = Paint()
        ..color = darkMode ? const Color(0xCC94A3B8) : const Color(0xCC334155)
        ..strokeWidth = 1.0;
      canvas.drawLine(pA + perp * flangeOff, pB + perp * flangeOff, flangePaint);
      canvas.drawLine(pA - perp * flangeOff, pB - perp * flangeOff, flangePaint);

      // Đường trục tâm thanh chỉ vẽ phía ngoài mép bản mã (không vẽ xuyên đè lên đầu thanh khuất)
      canvas.drawLine(
        center + dir * gussetReach,
        pB + dir * 10,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.55)
          ..strokeWidth = 0.9,
      );
    }

    // 5. Tô Bản mã nút ĐẶC 100% (alpha = 1.0) đè lên trên — che khuất tuyệt đối đầu thanh nằm sau bản mã!
    if (gussetPoly.length >= 3) {
      final gp = Path()..moveTo(gussetPoly.first.dx, gussetPoly.first.dy);
      for (int k = 1; k < gussetPoly.length; k++) {
        gp.lineTo(gussetPoly[k].dx, gussetPoly[k].dy);
      }
      gp.close();

      if (showStressMap) {
        // Phủ bản đồ ứng suất von Mises đặc 100% (không xuyên thấu chi tiết khuất phía sau)
        final tPeak = (report.maxGussetSigmaMpa / p.steelGrade.fyMpa).clamp(0.08, 1.0);
        final peakCol = ansysRainbowColor(tPeak);
        final midCol = ansysRainbowColor((tPeak * 0.55).clamp(0.05, 0.85));
        final edgeCol = ansysRainbowColor(0.06);
        final shader = ui.Gradient.radial(
          center,
          gussetReach * 1.15,
          [peakCol, midCol, edgeCol],
          const [0.0, 0.52, 1.0],
        );
        canvas.drawPath(gp, Paint()..shader = shader);
      } else {
        canvas.drawPath(gp, Paint()..color = darkMode ? const Color(0xFF1D4ED8) : const Color(0xFF93C5FD));
      }

      // Viền cắt laser/CNC bản mã
      canvas.drawPath(
        gp,
        Paint()
          ..color = darkMode ? const Color(0xFF93C5FD) : const Color(0xFF1E3A8A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    // 6. Vẽ chi tiết Bu-lông / Đường hàn / Tai chốt Clevis NỔI TRÊN MẶT NGOÀI bản mã + nhãn nội lực
    for (final m in report.members) {
      final dir = Offset(math.cos(m.angleRad), -math.sin(m.angleRad));
      final perp = Offset(-dir.dy, dir.dx);
      final halfH = (m.heightMm * 0.24).clamp(15.0, 25.0);
      final endDist = armLen;

      if (p.detailType == ConnectionDetailType.boltedGusset) {
        final nRows = math.max(1, (p.boltsPerMember / 2).ceil());
        final usable = math.max(14.0, gussetReach - startDist - 12.0);
        final rowStep = nRows > 1 ? math.min(18.0, usable / (nRows - 1)) : 0.0;
        final colOff = halfH * 0.44;
        for (int r = 0; r < nRows; r++) {
          final dist = startDist + 10.0 + r * rowStep;
          final rowsY = p.boltsPerMember == 2 ? [0.0] : [-colOff, colOff];
          for (final off in rowsY) {
            final bc = center + dir * dist + perp * off;
            _drawHexBolt(canvas, bc, 4.8);
          }
        }
      } else if (p.detailType == ConnectionDetailType.weldedGusset) {
        // Đường hàn góc 2 mép màu cam đỏ + nét vảy cá trên vùng chồng lấn [startDist..gussetReach]
        final wStart = startDist + 2.0;
        final wEnd = gussetReach - 3.0;
        final weldPaint = Paint()
          ..color = const Color(0xFFF97316)
          ..strokeWidth = 4.2
          ..strokeCap = StrokeCap.round;
        for (final sgn in [-1.0, 1.0]) {
          final wa = center + dir * wStart + perp * (halfH * sgn);
          final wb = center + dir * wEnd + perp * (halfH * sgn);
          canvas.drawLine(wa, wb, weldPaint);
          final tickPaint = Paint()..color = const Color(0xFFFDE047)..strokeWidth = 1.0;
          for (double d = wStart + 4; d < wEnd - 2; d += 7.0) {
            final q = center + dir * d + perp * (halfH * sgn);
            canvas.drawLine(q - perp * (sgn * 3.0), q + perp * (sgn * 2.5) + dir * 2.5, tickPaint);
          }
        }
      } else {
        // Tai chốt bản lề Clevis bo tròn tại tâm nút
        final earR = halfH * 0.95;
        canvas.drawCircle(center, earR, Paint()..color = const Color(0xFF475569));
        canvas.drawCircle(
          center,
          earR,
          Paint()
            ..color = const Color(0xFFE2E8F0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }

      // Nhãn nội lực thanh N (kN) tại đầu ngoài mỗi thanh
      final isTens = m.forceKn >= 0;
      final forceCol = isTens ? const Color(0xFFF43F5E) : const Color(0xFF38BDF8);
      final lblPos = center + dir * (endDist + 14.0);
      _drawTag(
        canvas,
        Offset(lblPos.dx.clamp(44.0, size.width - 44.0), lblPos.dy.clamp(30.0, size.height - 26.0)),
        '${m.label.split(" ").first}: ${isTens ? "+" : ""}${m.forceKn.toStringAsFixed(1)} kN',
        forceCol,
      );
    }

    // Tâm chốt Clevis nếu chọn kiểu Tai chốt
    if (p.detailType == ConnectionDetailType.pinnedClevis) {
      canvas.drawCircle(center, 11.5, Paint()..color = const Color(0xFFFBBF24));
      canvas.drawCircle(
        center,
        11.5,
        Paint()
          ..color = const Color(0xFF0F172A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      canvas.drawCircle(center, 3.0, Paint()..color = const Color(0xFF0F172A));
    }

    // 6. Ghi chú kích thước gia công góc trên trái & dưới phải
    final specStr = p.detailType == ConnectionDetailType.boltedGusset
        ? 'PL${p.gussetThicknessMm.toStringAsFixed(0)} (${p.steelGrade.code}) • ${p.boltsPerMember}×${p.boltSpec.code}/thanh'
        : (p.detailType == ConnectionDetailType.weldedGusset
            ? 'PL${p.gussetThicknessMm.toStringAsFixed(0)} (${p.steelGrade.code}) • Hàn góc 2×△${p.weldLegMm.toStringAsFixed(0)}×${p.weldLengthMm.toStringAsFixed(0)}'
            : 'PL${p.gussetThicknessMm.toStringAsFixed(0)} (${p.steelGrade.code}) • Chốt Clevis Ø${p.pinDiameterMm.toStringAsFixed(0)}');
    _drawText(canvas, const Offset(8, 6), specStr, const Color(0xFF38BDF8), 9.6, bold: true);
    if (showStressMap) {
      _drawText(
        canvas,
        Offset(8, size.height - 18),
        'Ứng suất von Mises: σ_eq,max = ${report.maxGussetSigmaMpa.toStringAsFixed(1)} MPa / ${p.steelGrade.fyMpa.toStringAsFixed(0)} MPa',
        const Color(0xFFFBBF24),
        9.2,
        bold: true,
      );
    }
  }

  Offset _dirOut(SupportDirection dir) {
    switch (dir) {
      case SupportDirection.top:
        return const Offset(0, -1);
      case SupportDirection.left:
        return const Offset(-1, 0);
      case SupportDirection.right:
        return const Offset(1, 0);
      case SupportDirection.bottom:
      case SupportDirection.auto:
        return const Offset(0, 1);
    }
  }

  void _paintFabricationSupport(Canvas canvas, Offset center, bool isTop, bool isRight) {
    final sup = report.supportType;
    if (sup == NodeSupportType.free) return;

    final concretePaint = Paint()..color = darkMode ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    final steelPlatePaint = Paint()..color = const Color(0xFF64748B);
    final edgePaint = Paint()
      ..color = darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final dir = model.resolvedDirectionFor(report.nodeIndex);
    final out = _dirOut(dir);
    final tang = Offset(-out.dy, out.dx);

    void drawOrientedRect(Offset c, double alongOut, double acrossTang, Paint fill, {bool stroke = true}) {
      final ha = 0.5 * alongOut;
      final hw = 0.5 * acrossTang;
      final rp = Path()
        ..moveTo((c - out * ha - tang * hw).dx, (c - out * ha - tang * hw).dy)
        ..lineTo((c + out * ha - tang * hw).dx, (c + out * ha - tang * hw).dy)
        ..lineTo((c + out * ha + tang * hw).dx, (c + out * ha + tang * hw).dy)
        ..lineTo((c - out * ha + tang * hw).dx, (c - out * ha + tang * hw).dy)
        ..close();
      canvas.drawPath(rp, fill);
      if (stroke) canvas.drawPath(rp, edgePaint);
    }

    if (sup == NodeSupportType.pin) {
      // Bản đế thép dày BP + 2 sườn tăng cứng + 4 bu-lông neo M24 + Lớp vữa + Khối móng bê tông (xoay đủ 4 hướng!)
      final bpFace = center + out * 44.0;
      drawOrientedRect(bpFace + out * 34.0, 36.0, 158.0, concretePaint);
      drawOrientedRect(bpFace + out * 13.0, 6.0, 128.0, Paint()..color = const Color(0xFF94A3B8), stroke: false);
      drawOrientedRect(bpFace + out * 5.0, 10.0, 122.0, steelPlatePaint);
      for (final sx in [-1.0, 1.0]) {
        final rib = Path()
          ..moveTo((bpFace + tang * (sx * 18)).dx, (bpFace + tang * (sx * 18)).dy)
          ..lineTo((bpFace + tang * (sx * 50)).dx, (bpFace + tang * (sx * 50)).dy)
          ..lineTo((center + out * 12.0 + tang * (sx * 18)).dx, (center + out * 12.0 + tang * (sx * 18)).dy)
          ..close();
        canvas.drawPath(rib, Paint()..color = const Color(0xFF475569));
        canvas.drawPath(rib, edgePaint);
        final aBase = bpFace + tang * (sx * 44);
        canvas.drawLine(
          aBase - out * 6.0,
          aBase + out * 36.0,
          Paint()..color = const Color(0xFFFBBF24)..strokeWidth = 2.6,
        );
        drawOrientedRect(aBase - out * 3.0, 5.0, 9.0, Paint()..color = const Color(0xFFFBBF24), stroke: false);
      }
      final lblC = bpFace + out * 34.0;
      _drawText(
        canvas,
        Offset(lblC.dx - 48, lblC.dy - 5),
        'MÓNG BT C${report.params.concreteFckMpa.toStringAsFixed(0)} • 4×M24',
        const Color(0xFFE2E8F0),
        8.2,
        bold: true,
      );
    } else if (sup == NodeSupportType.rollerX || sup == NodeSupportType.rollerXSpringX || sup == NodeSupportType.rollerY) {
      drawOrientedRect(center + out * 44.0, 8.0, 108.0, steelPlatePaint);
      for (final off in [-24.0, 24.0]) {
        final rc = center + out * 56.0 + tang * off;
        canvas.drawCircle(rc, 8.5, Paint()..color = const Color(0xFF38BDF8));
        canvas.drawCircle(rc, 8.5, edgePaint);
        canvas.drawCircle(rc, 2.5, Paint()..color = const Color(0xFF0F172A));
      }
      drawOrientedRect(center + out * 68.0, 8.0, 122.0, steelPlatePaint);
      drawOrientedRect(center + out * 84.0, 22.0, 146.0, concretePaint);
    }

    // Cụm gối lò xo thép công nghiệp (k_y và/hoặc k_x)
    final rawDir = report.nodeIndex < model.supportDirections.length
        ? model.supportDirections[report.nodeIndex]
        : SupportDirection.auto;
    if (sup.hasSpringY) {
      final sgn = rawDir == SupportDirection.top
          ? -1.0
          : (rawDir == SupportDirection.bottom ? 1.0 : (isTop ? -1.0 : 1.0));
      _drawIndustrialSpring(
        canvas,
        Offset(center.dx, center.dy + sgn * 42.0),
        Offset(center.dx, center.dy + sgn * 88.0),
        concretePaint,
        edgePaint,
      );
    }
    if (sup.hasSpringX) {
      final sgn = rawDir == SupportDirection.right
          ? 1.0
          : (rawDir == SupportDirection.left ? -1.0 : (isRight ? 1.0 : -1.0));
      _drawIndustrialSpring(
        canvas,
        Offset(center.dx + sgn * 44.0, center.dy),
        Offset(center.dx + sgn * 92.0, center.dy),
        concretePaint,
        edgePaint,
      );
    }
  }

  void _drawIndustrialSpring(Canvas canvas, Offset a, Offset b, Paint concPaint, Paint edgePaint) {
    final d = b - a;
    final len = d.distance;
    if (len < 10) return;
    final u = d / len;
    final n = Offset(-u.dy, u.dx);
    // Bản ép trên và bản đế dưới
    canvas.drawLine(a - n * 24, a + n * 24, Paint()..color = const Color(0xFF94A3B8)..strokeWidth = 6.0);
    canvas.drawLine(b - n * 28, b + n * 28, Paint()..color = const Color(0xFF64748B)..strokeWidth = 7.0);
    // 2 cuộn lò xo thép song song màu vàng
    for (final off in [-12.0, 12.0]) {
      final p0 = a + n * off;
      final path = Path()..moveTo(p0.dx, p0.dy);
      for (int c = 0; c < 5; c++) {
        final t1 = (c + 0.25) / 5.0;
        final t2 = (c + 0.75) / 5.0;
        final q1 = a + d * t1 + n * (off + 5.5);
        final q2 = a + d * t2 + n * (off - 5.5);
        path.lineTo(q1.dx, q1.dy);
        path.lineTo(q2.dx, q2.dy);
      }
      final pEnd = b + n * off;
      path.lineTo(pEnd.dx, pEnd.dy);
      canvas.drawPath(path, Paint()..color = const Color(0xFFFBBF24)..style = PaintingStyle.stroke..strokeWidth = 2.4);
    }
    // Bệ bê tông
    final bRect = Path()
      ..moveTo((b - n * 34).dx, (b - n * 34).dy)
      ..lineTo((b + n * 34).dx, (b + n * 34).dy)
      ..lineTo((b + u * 16 + n * 34).dx, (b + u * 16 + n * 34).dy)
      ..lineTo((b + u * 16 - n * 34).dx, (b + u * 16 - n * 34).dy)
      ..close();
    canvas.drawPath(bRect, concPaint);
    canvas.drawPath(bRect, edgePaint);
  }

  void _paintSchematicZoom(Canvas canvas, Size size, Offset center, bool isTop, bool isRight) {
    final armLen = math.min(size.width, size.height) * 0.36;
    for (final m in report.members) {
      final dir = Offset(math.cos(m.angleRad), -math.sin(m.angleRad));
      final pEnd = center + dir * armLen;
      final isTens = m.forceKn >= 0;
      final col = isTens ? const Color(0xFFF43F5E) : const Color(0xFF38BDF8);
      canvas.drawLine(center, pEnd, Paint()..color = col..strokeWidth = 5.0..strokeCap = StrokeCap.round);
      _drawTag(
        canvas,
        Offset((center.dx + dir.dx * (armLen * 0.7)).clamp(44.0, size.width - 44.0),
            (center.dy + dir.dy * (armLen * 0.7)).clamp(28.0, size.height - 28.0)),
        '${m.label.split(" ").first}: ${isTens ? "+" : ""}${m.forceKn.toStringAsFixed(1)} kN',
        col,
      );
    }
    // Ký hiệu gối tựa sơ đồ tính xoay đủ 4 hướng theo lựa chọn người dùng
    final sup = report.supportType;
    final supStroke = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final out = _dirOut(model.resolvedDirectionFor(report.nodeIndex));
    final tang = Offset(-out.dy, out.dx);

    if (sup == NodeSupportType.pin) {
      final tri = Path()
        ..moveTo((center + out * 9.0).dx, (center + out * 9.0).dy)
        ..lineTo((center + out * 34.0 - tang * 18.0).dx, (center + out * 34.0 - tang * 18.0).dy)
        ..lineTo((center + out * 34.0 + tang * 18.0).dx, (center + out * 34.0 + tang * 18.0).dy)
        ..close();
      canvas.drawPath(tri, Paint()..color = const Color(0xFF334155));
      canvas.drawPath(tri, supStroke);
      canvas.drawLine(center + out * 35.0 - tang * 24.0, center + out * 35.0 + tang * 24.0, supStroke);
    } else if (sup == NodeSupportType.rollerX || sup == NodeSupportType.rollerXSpringX || sup == NodeSupportType.rollerY) {
      final tri = Path()
        ..moveTo((center + out * 9.0).dx, (center + out * 9.0).dy)
        ..lineTo((center + out * 31.0 - tang * 17.0).dx, (center + out * 31.0 - tang * 17.0).dy)
        ..lineTo((center + out * 31.0 + tang * 17.0).dx, (center + out * 31.0 + tang * 17.0).dy)
        ..close();
      canvas.drawPath(tri, Paint()..color = const Color(0xFF334155));
      canvas.drawPath(tri, supStroke);
      canvas.drawCircle(center + out * 36.0 - tang * 8.0, 4.5, supStroke);
      canvas.drawCircle(center + out * 36.0 + tang * 8.0, 4.5, supStroke);
      canvas.drawLine(center + out * 41.0 - tang * 24.0, center + out * 41.0 + tang * 24.0, supStroke);
    }

    // Khớp tròn trung tâm
    canvas.drawCircle(center, 9.0, Paint()..color = darkMode ? const Color(0xFF0F172A) : Colors.white);
    canvas.drawCircle(center, 9.0, Paint()..color = const Color(0xFF38BDF8)..style = PaintingStyle.stroke..strokeWidth = 2.6);
    _drawText(
      canvas,
      const Offset(10, 8),
      'SƠ ĐỒ TÍNH: Nút ${report.nodeIndex + 1} (${report.supportType.label})',
      const Color(0xFF38BDF8),
      10.0,
      bold: true,
    );
    _drawText(
      canvas,
      Offset(10, size.height - 20),
      'Rₓ = ${report.rxKn.toStringAsFixed(2)} kN   |   Rᵧ = ${report.ryKn.toStringAsFixed(2)} kN',
      const Color(0xFFFBBF24),
      9.8,
      bold: true,
    );
  }

  void _drawHexBolt(Canvas canvas, Offset c, double r) {
    final hex = Path();
    for (int k = 0; k < 6; k++) {
      final a = k * math.pi / 3.0;
      final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      if (k == 0) {
        hex.moveTo(pt.dx, pt.dy);
      } else {
        hex.lineTo(pt.dx, pt.dy);
      }
    }
    hex.close();
    canvas.drawPath(hex, Paint()..color = const Color(0xFFEAB308));
    canvas.drawPath(
      hex,
      Paint()
        ..color = const Color(0xFF0F172A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    canvas.drawCircle(c, r * 0.35, Paint()..color = const Color(0xFFFEF08A));
  }

  /// Thuật toán Andrew Monotone Chain tìm bao lồi (đa giác vát góc bản mã)
  List<Offset> _convexHull(List<Offset> pts) {
    if (pts.length <= 3) return pts;
    final sorted = List<Offset>.from(pts)
      ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  void _drawTag(Canvas canvas, Offset center, String text, Color accent) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: darkMode ? Colors.white : const Color(0xFF0F172A),
          fontSize: 9.0,
          fontWeight: FontWeight.bold,
          fontFamily: 'DejaVuSansMono',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(center: center, width: tp.width + 8, height: tp.height + 4);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rr, Paint()..color = darkMode ? const Color(0xD90B1220) : const Color(0xE6FFFFFF));
    canvas.drawRRect(rr, Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = 1.0);
    tp.paint(canvas, Offset(rect.left + 4, rect.top + 2));
  }

  void _drawText(Canvas canvas, Offset pos, String text, Color col, double sz, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: col, fontSize: sz, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _FabricationNodePainter oldDelegate) => true;
}
