# -*- coding: utf-8 -*-
"""
================================================================================
MÔ-ĐUN 6: MÁY CHỦ API CỤC BỘ (HTTP JSON) KẾT NỐI LÕI PYTHON VỚI FLUTTER WINDOWS
================================================================================
Chức năng:
  Cung cấp dịch vụ HTTP nhẹ trên `127.0.0.1:<port>` (dùng hoàn toàn thư viện
  chuẩn `http.server` của Python để đóng gói PyInstaller nhỏ gọn, siêu ổn định):
    - GET  /api/health          : Kiểm tra trạng thái lõi Python CALFEM.
    - POST /api/analyze         : Chạy phân tích đầy đủ (Tuyến tính, CALFEM bar2g
                                  bậc 2, Corotational UL NR, Modified NR, Euler,
                                  RK2, Total Lagrangian, Buckling trị riêng,
                                  đường cong Snap-Through Arc-Length).
    - POST /api/probe           : Khảo sát bất kỳ vị trí (e, ξ, η, ζ) & phẫu thuật
                                  mặt cắt ngang/dọc.
    - POST /api/export_report   : Xuất báo cáo Word (.docx) hoặc PDF (.pdf) và trả
                                  về đường dẫn tệp hoặc dữ liệu base64.
================================================================================
"""

from __future__ import annotations
import argparse
import base64
import json
import os
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, Any

from .truss_models import (
    create_assignment_5bar_truss,
    create_dahlblom_example_9_1,
    create_calfem_exs3_truss,
    create_von_mises_arch,
)
from .nonlinear_solvers import (
    solve_linear_calfem,
    solve_calfem_bar2g_second_order,
    solve_corotational_newton_raphson,
    solve_corotational_modified_nr,
    solve_corotational_euler,
    solve_corotational_rk2,
    solve_corotational_displacement_control,
    solve_corotational_arc_length,
    solve_total_lagrangian_nr,
    solve_elastic_buckling_eigen,
    verify_tangent_finite_difference,
)
from .probe_dissection import (
    probe_member_at,
    dissect_cross_section,
    compute_longitudinal_profile,
)
from .report_exporter import export_quick_docx_report, export_quick_pdf_report


def _build_model_from_payload(payload: Dict[str, Any]):
    import numpy as np

    preset = payload.get("preset", "assignment_5bar")
    if preset == "dahlblom_ex9_1":
        model = create_dahlblom_example_9_1()
    elif preset == "calfem_exs3":
        model = create_calfem_exs3_truss()
    elif preset == "von_mises":
        model = create_von_mises_arch(
            span_half_mm=float(payload.get("L_mm", 1000.0)),
            rise_mm=float(payload.get("rise_mm", 200.0)),
            E_mpa=float(payload.get("E_mpa", 200000.0)),
            A_mm2=float(payload.get("A_mm2", 1000.0)),
            P_n=float(payload.get("P_kN", 1000.0)) * 1000.0,
        )
    else:
        model = create_assignment_5bar_truss(
            L_mm=float(payload.get("L_mm", 1000.0)),
            E_mpa=float(payload.get("E_mpa", 200000.0)),
            A_mm2=float(payload.get("A_mm2", 2001.0)),
            P_n=float(payload.get("P_kN", 208.0)) * 1000.0,
            nu=float(payload.get("nu", 0.3)),
            section_shape=str(payload.get("section_shape", "I_SECTION")),
        )

    if "fixed_dofs_0" in payload and isinstance(payload["fixed_dofs_0"], list):
        fd = [int(d) for d in payload["fixed_dofs_0"] if 0 <= int(d) < model.n_dofs]
        if fd:
            model.bc = np.array([[d + 1, 0.0] for d in sorted(set(fd))], dtype=float)
        else:
            model.bc = np.zeros((0, 2), dtype=float)
    if "spring_k_nmm" in payload and isinstance(payload["spring_k_nmm"], list):
        sk = [float(v) for v in payload["spring_k_nmm"]]
        if len(sk) == model.n_dofs:
            model.spring_k = np.array(sk, dtype=float)
    return model


def run_analysis_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Chạy trọn bộ phân tích từ gói tham số JSON của giao diện."""
    model = _build_model_from_payload(payload)
    n_steps = int(payload.get("n_steps", 10))
    load_factor = float(payload.get("load_factor", 1.0))

    res_lin = solve_linear_calfem(model, load_factor=load_factor)
    res_bar2g = solve_calfem_bar2g_second_order(model, load_factor=load_factor)
    res_nr = solve_corotational_newton_raphson(model, load_factor=load_factor, n_steps=n_steps)
    res_mod = solve_corotational_modified_nr(model, load_factor=load_factor, n_steps=n_steps)
    res_euler = solve_corotational_euler(model, load_factor=load_factor, n_steps=n_steps)
    res_rk2 = solve_corotational_rk2(model, load_factor=load_factor, n_steps=n_steps)
    res_tl = solve_total_lagrangian_nr(model, load_factor=load_factor, n_steps=n_steps)
    buckling = solve_elastic_buckling_eigen(model)
    fd_check = verify_tangent_finite_difference(model, res_nr.u, "corotational")

    include_snap = bool(payload.get("include_snap_through", False))
    snap_data = None
    if include_snap and model.name == "DeBai_Dan5Thanh":
        snap_data = solve_corotational_displacement_control(
            model, control_dof_1based=4, target_disp_mm=2.1 * float(payload.get("L_mm", 1000.0)), n_steps=70
        )

    return {
        "engine": "Python CALFEM Nonlinear Core v1.0",
        "model": {
            "name": model.name,
            "description": model.description,
            "coords_mm": model.coords.tolist(),
            "conn": model.conn.tolist(),
            "areas_mm2": model.areas.tolist(),
            "E_mpa": model.E,
            "nu": model.nu,
            "member_labels": model.member_labels,
            "node_labels": model.node_labels,
            "section_shape": model.section_shape,
        },
        "linear": res_lin.to_dict(),
        "bar2g_second_order": res_bar2g.to_dict(),
        "corotational_nr": res_nr.to_dict(),
        "modified_nr": res_mod.to_dict(),
        "euler": res_euler.to_dict(),
        "rk2": res_rk2.to_dict(),
        "total_lagrangian": res_tl.to_dict(),
        "buckling": buckling,
        "tangent_fd_check": fd_check,
        "snap_through": snap_data,
    }


class CalfemAPIHandler(BaseHTTPRequestHandler):
    """Bộ xử lý HTTP JSON cục bộ cho ứng dụng Flutter Desktop."""

    def _send_json(self, code: int, data: Dict[str, Any]) -> None:
        raw = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_OPTIONS(self) -> None:
        self._send_json(200, {"ok": True})

    def do_GET(self) -> None:
        if self.path == "/api/health":
            self._send_json(200, {"status": "ok", "engine": "Python CALFEM Nonlinear Core"})
            return
        self._send_json(404, {"error": "Endpoint không tồn tại"})

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8") if length > 0 else "{}"
        try:
            payload = json.loads(body)
            if self.path == "/api/analyze":
                self._send_json(200, run_analysis_payload(payload))
                return
            if self.path == "/api/probe":
                model = _build_model_from_payload(payload)
                lf = float(payload.get("load_factor", 1.0))
                res_lin = solve_linear_calfem(model, load_factor=lf)
                res_nl = solve_corotational_newton_raphson(model, load_factor=lf, n_steps=int(payload.get("n_steps", 10)))
                e_idx = int(payload.get("element_index", 0))
                xi = float(payload.get("xi", 0.5))
                eta = float(payload.get("eta", 0.0))
                zeta = float(payload.get("zeta", 0.0))
                imp = float(payload.get("imperfection_ratio", 0.0))
                probe = probe_member_at(model, res_nl, res_lin, e_idx, xi, eta, zeta, imp)
                dissect = dissect_cross_section(model, res_nl, e_idx, xi, grid_n=11, imperfection_ratio=imp)
                profile = compute_longitudinal_profile(model, res_nl, res_lin, e_idx, n_stations=21, imperfection_ratio=imp)
                self._send_json(200, {"probe": probe, "dissection": dissect, "longitudinal": profile})
                return
            if self.path == "/api/export_report":
                model = _build_model_from_payload(payload)
                lf = float(payload.get("load_factor", 1.0))
                fmt = str(payload.get("format", "docx")).lower()
                out_path = payload.get("output_path")
                if not out_path:
                    out_path = os.path.join(tempfile.gettempdir(), f"BaoCao_CALFEM_PhiTuyen.{fmt}")
                res_lin = solve_linear_calfem(model, load_factor=lf)
                res_nl = solve_corotational_newton_raphson(model, load_factor=lf, n_steps=int(payload.get("n_steps", 10)))
                buck = solve_elastic_buckling_eigen(model)
                probe = None
                if "element_index" in payload:
                    probe = probe_member_at(
                        model, res_nl, res_lin,
                        int(payload.get("element_index", 0)),
                        float(payload.get("xi", 0.5)),
                        float(payload.get("eta", 0.0)),
                        float(payload.get("zeta", 0.0)),
                        float(payload.get("imperfection_ratio", 0.0)),
                    )
                if fmt == "pdf":
                    saved = export_quick_pdf_report(out_path, model, res_lin, res_nl, buck, probe)
                else:
                    saved = export_quick_docx_report(out_path, model, res_lin, res_nl, None, buck, probe)
                with open(saved, "rb") as f:
                    b64 = base64.b64encode(f.read()).decode("ascii")
                self._send_json(200, {"status": "ok", "path": saved, "format": fmt, "base64": b64})
                return
            if self.path == "/api/shutdown":
                self._send_json(200, {"status": "shutting_down"})
                import threading
                threading.Thread(target=self.server.shutdown, daemon=True).start()
                return
            self._send_json(404, {"error": "Endpoint không tồn tại"})
        except Exception as exc:
            self._send_json(500, {"error": str(exc)})

    def log_message(self, format: str, *args) -> None:
        return  # Tắt log thừa trên console


def main() -> None:
    parser = argparse.ArgumentParser(description="Khởi chạy máy chủ lõi tính toán Python CALFEM.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18765)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), CalfemAPIHandler)
    print(f"CALFEM Python Nonlinear Core API đang chạy tại http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
