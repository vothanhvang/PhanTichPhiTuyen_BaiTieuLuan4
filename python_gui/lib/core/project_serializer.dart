// ============================================================================
// MÔ-ĐUN LƯU / MỞ DỰ ÁN (.JSON) & QUẢN LÝ LỊCH SỬ UNDO / REDO
// ============================================================================

import 'dart:convert';

import 'calfem_engine.dart';
import 'connection_calculator.dart';

/// Ảnh chụp toàn bộ trạng thái thiết kế kết cấu phục vụ Undo/Redo & Lưu/Mở tệp .json
class ProjectSnapshot {
  final TrussPreset preset;
  final SolverMethod method;
  final double lMm;
  final double eGpa;
  final double aMm2;
  final double pKn;
  final double fyMpa;
  final bool materialNonlinear;
  final double hardeningRatio;
  final double loadFactor;
  final int nSteps;
  final List<List<double>>? customCoords;
  final List<List<int>>? customConn;
  final List<List<double>>? customNodalLoadsKn;
  final List<ElementSectionConfig> elemSections;
  final List<NodeSupportType> nodeSupports;
  final List<SupportDirection> supportDirections;
  final double springStiffnessKnMm;
  final ConnectionDesignParams connParams;

  const ProjectSnapshot({
    required this.preset,
    required this.method,
    required this.lMm,
    required this.eGpa,
    required this.aMm2,
    required this.pKn,
    required this.fyMpa,
    required this.materialNonlinear,
    required this.hardeningRatio,
    required this.loadFactor,
    required this.nSteps,
    required this.customCoords,
    required this.customConn,
    required this.customNodalLoadsKn,
    required this.elemSections,
    required this.nodeSupports,
    required this.supportDirections,
    required this.springStiffnessKnMm,
    required this.connParams,
  });

  /// Tạo bản sao sâu để lưu an toàn trong ngăn xếp Undo / Redo
  ProjectSnapshot deepCopy() {
    return ProjectSnapshot(
      preset: preset,
      method: method,
      lMm: lMm,
      eGpa: eGpa,
      aMm2: aMm2,
      pKn: pKn,
      fyMpa: fyMpa,
      materialNonlinear: materialNonlinear,
      hardeningRatio: hardeningRatio,
      loadFactor: loadFactor,
      nSteps: nSteps,
      customCoords: customCoords == null
          ? null
          : [for (final c in customCoords!) List<double>.from(c)],
      customConn: customConn == null
          ? null
          : [for (final e in customConn!) List<int>.from(e)],
      customNodalLoadsKn: customNodalLoadsKn == null
          ? null
          : [for (final ld in customNodalLoadsKn!) List<double>.from(ld)],
      elemSections: [
        for (final s in elemSections)
          ElementSectionConfig(
            shape: s.shape,
            customGeometry: s.customGeometry?.copyWith(),
            rotationDeg: s.rotationDeg,
          ),
      ],
      nodeSupports: List<NodeSupportType>.from(nodeSupports),
      supportDirections: List<SupportDirection>.from(supportDirections),
      springStiffnessKnMm: springStiffnessKnMm,
      connParams: connParams.copyWith(),
    );
  }

  Map<String, dynamic> toJsonMap() {
    return {
      'schemaVersion': 2,
      'app': 'CALFEM_Nonlinear_Truss_Studio',
      'preset': preset.name,
      'method': method.name,
      'lMm': lMm,
      'eGpa': eGpa,
      'aMm2': aMm2,
      'pKn': pKn,
      'fyMpa': fyMpa,
      'materialNonlinear': materialNonlinear,
      'hardeningRatio': hardeningRatio,
      'loadFactor': loadFactor,
      'nSteps': nSteps,
      'customCoords': customCoords,
      'customConn': customConn,
      'customNodalLoadsKn': customNodalLoadsKn,
      'elemSections': [
        for (final s in elemSections)
          {
            'shape': s.shape.name,
            'rotationDeg': s.rotationDeg,
            'customGeometry': s.customGeometry == null
                ? null
                : {
                    'heightMm': s.customGeometry!.heightMm,
                    'widthMm': s.customGeometry!.widthMm,
                    'tfMm': s.customGeometry!.tfMm,
                    'twMm': s.customGeometry!.twMm,
                    'gapMm': s.customGeometry!.gapMm,
                  },
          },
      ],
      'nodeSupports': [for (final sup in nodeSupports) sup.name],
      'supportDirections': [for (final dir in supportDirections) dir.name],
      'springStiffnessKnMm': springStiffnessKnMm,
      'connParams': {
        'detailType': connParams.detailType.name,
        'steelGrade': connParams.steelGrade.name,
        'boltSpec': connParams.boltSpec.name,
        'gussetThicknessMm': connParams.gussetThicknessMm,
        'boltsPerMember': connParams.boltsPerMember,
        'weldLegMm': connParams.weldLegMm,
        'weldLengthMm': connParams.weldLengthMm,
        'pinDiameterMm': connParams.pinDiameterMm,
        'basePlateWidthMm': connParams.basePlateWidthMm,
        'basePlateLengthMm': connParams.basePlateLengthMm,
        'basePlateThickMm': connParams.basePlateThickMm,
        'concreteFckMpa': connParams.concreteFckMpa,
      },
    };
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJsonMap());

  static T _enumByName<T extends Enum>(List<T> values, dynamic raw, T fallback) {
    if (raw is String) {
      for (final v in values) {
        if (v.name == raw) return v;
      }
    }
    return fallback;
  }

  static double _num(dynamic raw, double fallback) {
    if (raw is num && raw.isFinite) return raw.toDouble();
    return fallback;
  }

  static int _int(dynamic raw, int fallback) {
    if (raw is num && raw.isFinite) return raw.round();
    return fallback;
  }

  static ProjectSnapshot fromJsonMap(Map<String, dynamic> map) {
    final preset = _enumByName(TrussPreset.values, map['preset'], TrussPreset.assignment5Bar);
    final method = _enumByName(SolverMethod.values, map['method'], SolverMethod.corotationalNR);
    final lMm = _num(map['lMm'], 1000.0).clamp(100.0, 50000.0);
    final eGpa = _num(map['eGpa'], 200.0).clamp(10.0, 1000.0);
    final aMm2 = _num(map['aMm2'], 2001.0).clamp(50.0, 200000.0);
    final pKn = _num(map['pKn'], 208.0).clamp(-100000.0, 100000.0);
    final fyMpa = _num(map['fyMpa'], 250.0).clamp(100.0, 1200.0);
    final matNL = map['materialNonlinear'] == true;
    final hardRatio = _num(map['hardeningRatio'], 0.02).clamp(0.002, 0.5);
    final loadFactor = _num(map['loadFactor'], 1.0).clamp(0.05, 50.0);
    final nSteps = _int(map['nSteps'], 10).clamp(1, 50);

    List<List<double>>? coords;
    if (map['customCoords'] is List) {
      coords = [
        for (final row in (map['customCoords'] as List))
          if (row is List && row.length >= 2) [_num(row[0], 0.0), _num(row[1], 0.0)],
      ];
      if (coords.length < 2) coords = null;
    }

    List<List<int>>? conn;
    if (map['customConn'] is List) {
      conn = [
        for (final row in (map['customConn'] as List))
          if (row is List && row.length >= 2) [_int(row[0], 1), _int(row[1], 2)],
      ];
      if (conn.isEmpty) conn = null;
    }

    List<List<double>>? nodalLoads;
    if (map['customNodalLoadsKn'] is List) {
      nodalLoads = [
        for (final row in (map['customNodalLoadsKn'] as List))
          if (row is List && row.length >= 2) [_num(row[0], 0.0), _num(row[1], 0.0)],
      ];
      if (nodalLoads.isEmpty) nodalLoads = null;
    }

    final elemSections = <ElementSectionConfig>[];
    if (map['elemSections'] is List) {
      for (final item in (map['elemSections'] as List)) {
        if (item is Map) {
          final shape = _enumByName(SectionShape.values, item['shape'], SectionShape.iSection);
          final rot = _num(item['rotationDeg'], 0.0);
          CustomSectionGeometry? cg;
          if (item['customGeometry'] is Map) {
            final g = item['customGeometry'] as Map;
            cg = CustomSectionGeometry(
              heightMm: _num(g['heightMm'], 100.0),
              widthMm: _num(g['widthMm'], 80.0),
              tfMm: _num(g['tfMm'], 10.0),
              twMm: _num(g['twMm'], 8.0),
              gapMm: _num(g['gapMm'], 12.0),
            );
          }
          elemSections.add(ElementSectionConfig(
            shape: shape,
            customGeometry: cg,
            rotationDeg: ((rot % 360.0) + 360.0) % 360.0,
          ));
        }
      }
    }

    final nodeSupports = <NodeSupportType>[];
    if (map['nodeSupports'] is List) {
      for (final s in (map['nodeSupports'] as List)) {
        nodeSupports.add(_enumByName(NodeSupportType.values, s, NodeSupportType.free));
      }
    }

    final supportDirections = <SupportDirection>[];
    if (map['supportDirections'] is List) {
      for (final d in (map['supportDirections'] as List)) {
        supportDirections.add(_enumByName(SupportDirection.values, d, SupportDirection.auto));
      }
    }

    final springK = _num(map['springStiffnessKnMm'], 500.0).clamp(1.0, 100000.0);

    ConnectionDesignParams connParams = const ConnectionDesignParams();
    if (map['connParams'] is Map) {
      final cp = map['connParams'] as Map;
      connParams = ConnectionDesignParams(
        detailType: _enumByName(ConnectionDetailType.values, cp['detailType'], ConnectionDetailType.boltedGusset),
        steelGrade: _enumByName(SteelGrade.values, cp['steelGrade'], SteelGrade.s275),
        boltSpec: _enumByName(BoltSpec.values, cp['boltSpec'], BoltSpec.m20g88),
        gussetThicknessMm: _num(cp['gussetThicknessMm'], 16.0),
        boltsPerMember: _int(cp['boltsPerMember'], 4).clamp(1, 16),
        weldLegMm: _num(cp['weldLegMm'], 8.0),
        weldLengthMm: _num(cp['weldLengthMm'], 160.0),
        pinDiameterMm: _num(cp['pinDiameterMm'], 60.0),
        basePlateWidthMm: _num(cp['basePlateWidthMm'], 280.0),
        basePlateLengthMm: _num(cp['basePlateLengthMm'], 240.0),
        basePlateThickMm: _num(cp['basePlateThickMm'], 25.0),
        concreteFckMpa: _num(cp['concreteFckMpa'], 25.0),
      );
    }

    return ProjectSnapshot(
      preset: preset,
      method: method,
      lMm: lMm,
      eGpa: eGpa,
      aMm2: aMm2,
      pKn: pKn,
      fyMpa: fyMpa,
      materialNonlinear: matNL,
      hardeningRatio: hardRatio,
      loadFactor: loadFactor,
      nSteps: nSteps,
      customCoords: coords,
      customConn: conn,
      customNodalLoadsKn: nodalLoads,
      elemSections: elemSections,
      nodeSupports: nodeSupports,
      supportDirections: supportDirections,
      springStiffnessKnMm: springK,
      connParams: connParams,
    );
  }

  static ProjectSnapshot? tryFromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return fromJsonMap(decoded);
      }
      if (decoded is Map) {
        return fromJsonMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }
}
