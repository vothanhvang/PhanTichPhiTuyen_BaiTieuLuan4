# -*- coding: utf-8 -*-
"""
================================================================================
CHƯƠNG TRÌNH CHÍNH: CHẠY TOÀN BỘ PHÂN TÍCH, KIỂM CHỨNG & SINH BIỂU ĐỒ 300 DPI
================================================================================
Chức năng:
  1. Giải đề bài dàn 4 nút – 5 thanh (L=1000 mm, E=200 GPa, A=2001 mm², P=208 kN)
     bằng đầy đủ 4 mô hình cơ học và 6 thuật toán giải phi tuyến:
       - Tuyến tính bậc 1 (CALFEM bar2e) – đối chiếu giải tích & SAP2000
       - Phi tuyến bậc 2 CALFEM gốc (bar2g tọa độ ban đầu, Dahlblom Ch. 9)
       - Phi tuyến hình học Đồng chuyển động Corotational UL (Full NR, Modified NR,
         Euler 10 bước, RK2 Midpoint 10 bước, Displacement Control, Constant Arc-Length)
       - Phi tuyến Total Lagrangian (biến dạng Green-Lagrange theo NSA_4 Slides 6-12)
  2. Khảo sát độ nhạy theo mức tải (1P, 10P, 100P, 500P) và đảo chiều tải
     (+P hướng lên gây MỀM HÓA vs -P hướng xuống gây CỨNG HÓA!).
  3. Phân tích tải tới hạn đàn hồi (Eigenvalue Buckling) & đường cong cân bằng
     toàn phần tải lớn (Large-Displacement / Snap-Through Path).
  4. Tái lập kiểm chứng 2 ví dụ chuẩn: CALFEM `exs3.m` & Dahlblom Example 9.1.
  5. Xuất toàn bộ dữ liệu CSV/JSON và 10 biểu đồ kỹ thuật 300 DPI sắc nét vào `results/`.
================================================================================
"""

from __future__ import annotations
import csv
import json
import math
import os
import sys
from typing import Dict, Any, List
import numpy as np

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.patches import Polygon, Rectangle, Circle, FancyArrowPatch

from python_core.truss_models import (
    create_assignment_5bar_truss,
    create_dahlblom_example_9_1,
    create_calfem_exs3_truss,
    create_von_mises_arch,
)
from python_core.nonlinear_solvers import (
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
from python_core.probe_dissection import (
    probe_member_at,
    dissect_cross_section,
    compute_longitudinal_profile,
)
from python_core.report_exporter import export_quick_docx_report, export_quick_pdf_report


def _setup_matplotlib_style() -> None:
    """Thiết lập phong cách đồ họa kỹ thuật chuyên nghiệp hỗ trợ tiếng Việt có dấu."""
    plt.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Segoe UI", "Arial", "DejaVu Sans"],
            "axes.unicode_minus": False,
            "axes.edgecolor": "#334155",
            "axes.linewidth": 0.9,
            "grid.color": "#CBD5E1",
            "grid.linestyle": "--",
            "grid.linewidth": 0.6,
            "figure.facecolor": "white",
            "axes.facecolor": "#F8FAFC",
            "savefig.dpi": 300,
            "savefig.bbox": "tight",
        }
    )


def run_all(base_dir: str) -> Dict[str, Any]:
    _setup_matplotlib_style()
    res_dir = os.path.join(base_dir, "results")
    fig_dir = os.path.join(res_dir, "figures")
    os.makedirs(fig_dir, exist_ok=True)

    # ==========================================================================
    # PHẦN 1: CHẠY CÁC MÔ HÌNH & THUẬT TOÁN TRÊN ĐỀ BÀI CHÍNH (P = 208 kN)
    # ==========================================================================
    model = create_assignment_5bar_truss(L_mm=1000.0, E_mpa=200000.0, A_mm2=2001.0, P_n=208000.0)

    r_lin = solve_linear_calfem(model, load_factor=1.0)
    r_b2g = solve_calfem_bar2g_second_order(model, load_factor=1.0)
    r_nr = solve_corotational_newton_raphson(model, load_factor=1.0, n_steps=10)
    r_mod = solve_corotational_modified_nr(model, load_factor=1.0, n_steps=10)
    r_eul = solve_corotational_euler(model, load_factor=1.0, n_steps=10)
    r_rk2 = solve_corotational_rk2(model, load_factor=1.0, n_steps=10)
    r_tl = solve_total_lagrangian_nr(model, load_factor=1.0, n_steps=10)

    # Kiểm chứng tiếp tuyến sai phân trung tâm
    fd_corot = verify_tangent_finite_difference(model, r_nr.u, "corotational")
    fd_tl = verify_tangent_finite_difference(model, r_tl.u, "total_lagrangian")

    # Phân tích trị riêng tải tới hạn đàn hồi (Buckling Eigenvalue)
    buckling = solve_elastic_buckling_eigen(model)

    # ==========================================================================
    # PHẦN 2: KHẢO SÁT ĐỘ NHẠY TẢI LỚN & ĐẢO CHIỀU TẢI (+P MỀM HÓA vs -P CỨNG HÓA)
    # ==========================================================================
    load_multipliers = [1.0, 10.0, 50.0, 100.0, 250.0, 500.0]
    load_scale_study: List[Dict[str, Any]] = []
    for mult in load_multipliers:
        rl_m = solve_linear_calfem(model, load_factor=mult)
        rb_m = solve_calfem_bar2g_second_order(model, load_factor=mult)
        rc_m = solve_corotational_newton_raphson(model, load_factor=mult, n_steps=20)
        rt_m = solve_total_lagrangian_nr(model, load_factor=mult, n_steps=20)
        re_m = solve_corotational_euler(model, load_factor=mult, n_steps=10)
        rrk_m = solve_corotational_rk2(model, load_factor=mult, n_steps=10)
        load_scale_study.append(
            {
                "multiplier": mult,
                "P_kN": mult * 208.0,
                "u2y_lin_mm": float(rl_m.u[3]),
                "u2y_bar2g_mm": float(rb_m.u[3]),
                "u2y_corot_mm": float(rc_m.u[3]),
                "u2y_tl_mm": float(rt_m.u[3]),
                "u2y_euler10_mm": float(re_m.u[3]),
                "u2y_rk2_10_mm": float(rrk_m.u[3]),
                "pct_diff_corot_vs_lin": float(100.0 * (rc_m.u[3] - rl_m.u[3]) / rl_m.u[3]),
                "pct_diff_bar2g_vs_lin": float(100.0 * (rb_m.u[3] - rl_m.u[3]) / rl_m.u[3]),
                "N12_corot_kN": float(rc_m.N[0] / 1000.0),
                "N23_corot_kN": float(rc_m.N[3] / 1000.0),
                "R1y_corot_kN": float(rc_m.reactions[1] / 1000.0),
                "R4y_corot_kN": float(rc_m.reactions[7] / 1000.0),
                "euler_residual_N": float(re_m.equilibrium_check["max_free_residual_N"]),
                "rk2_residual_N": float(rrk_m.equilibrium_check["max_free_residual_N"]),
            }
        )

    # Khảo sát so sánh ĐẢO CHIỀU TẢI: +P hướng lên (Mềm hóa) vs -P hướng xuống (Cứng hóa)
    dir_sweep_lambdas = np.linspace(-300.0, 300.0, 61)
    direction_study: List[Dict[str, Any]] = []
    for lam in dir_sweep_lambdas:
        if abs(lam) < 1e-9:
            direction_study.append(
                {
                    "lambda": 0.0,
                    "P_kN": 0.0,
                    "u2y_lin_mm": 0.0,
                    "u2y_corot_mm": 0.0,
                    "u2y_bar2g_mm": 0.0,
                    "N12_corot_kN": 0.0,
                }
            )
            continue
        rl_d = solve_linear_calfem(model, load_factor=float(lam))
        rc_d = solve_corotational_newton_raphson(model, load_factor=float(lam), n_steps=15)
        rb_d = solve_calfem_bar2g_second_order(model, load_factor=float(lam))
        direction_study.append(
            {
                "lambda": float(lam),
                "P_kN": float(lam * 208.0),
                "u2y_lin_mm": float(rl_d.u[3]),
                "u2y_corot_mm": float(rc_d.u[3]),
                "u2y_bar2g_mm": float(rb_d.u[3]),
                "N12_corot_kN": float(rc_d.N[0] / 1000.0),
            }
        )

    # ==========================================================================
    # PHẦN 3: ĐƯỜNG CONG CÂN BẰNG TOÀN PHẦN (LARGE DISPLACEMENT & SNAP-THROUGH)
    # ==========================================================================
    dc_5bar = solve_corotational_displacement_control(model, control_dof_1based=4, target_disp_mm=2400.0, n_steps=120)
    arc_5bar = solve_corotational_arc_length(model, ds=35.0, n_steps=120, scale_lambda=250.0, max_u_stop=2400.0)

    # Minh họa thêm Vòm Von Mises 2 thanh có Snap-Through cổ điển rõ rệt
    vm_model = create_von_mises_arch(span_half_mm=1000.0, rise_mm=200.0, E_mpa=200000.0, A_mm2=1000.0, P_n=1000000.0)
    dc_vm = solve_corotational_displacement_control(vm_model, control_dof_1based=4, target_disp_mm=-460.0, n_steps=92)
    arc_vm = solve_corotational_arc_length(vm_model, ds=12.0, n_steps=95, scale_lambda=40.0, max_u_stop=460.0)

    # ==========================================================================
    # PHẦN 4: KIỂM CHỨNG BENCHMARK (DAHLBLOM EX 9.1 & CALFEM EXS3)
    # ==========================================================================
    m_ex91 = create_dahlblom_example_9_1()
    r_ex91 = solve_calfem_bar2g_second_order(m_ex91, tol_rel=1e-9)
    m_exs3 = create_calfem_exs3_truss()
    r_exs3 = solve_linear_calfem(m_exs3)

    # ==========================================================================
    # PHẦN 5: KHẢO SÁT & PHẪU THUẬT MẶT CẮT MẪU (THANH 1-2 VÀ THANH CHÉO 3-2)
    # ==========================================================================
    probe_bar12 = probe_member_at(model, r_nr, r_lin, elem_index_0based=0, xi=0.5)
    probe_bar32 = probe_member_at(model, r_nr, r_lin, elem_index_0based=3, xi=0.5, imperfection_ratio=0.001)
    dissect_bar32 = dissect_cross_section(model, r_nr, elem_index_0based=3, xi=0.5, grid_n=15, imperfection_ratio=0.001)

    # ==========================================================================
    # PHẦN 6: LƯU DỮ LIỆU CSV & JSON
    # ==========================================================================
    # Bảng so sánh nút
    with open(os.path.join(res_dir, "nodal_comparison.csv"), "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "Node", "DOF",
                "Linear_bar2e_mm", "CALFEM_bar2g_2ndOrder_mm", "Corotational_UL_NR_mm",
                "Total_Lagrangian_NSA4_mm", "Diff_Corot_vs_Lin_mm", "Diff_Corot_vs_Lin_pct",
                "Reaction_Linear_kN", "Reaction_Corot_kN", "Diff_Reaction_N",
            ]
        )
        dof_labels = ["ux1", "uy1", "ux2", "uy2", "ux3", "uy3", "ux4", "uy4"]
        for k, dname in enumerate(dof_labels):
            du = r_nr.u[k] - r_lin.u[k]
            pct = (100.0 * du / r_lin.u[k]) if abs(r_lin.u[k]) > 1e-12 else 0.0
            w.writerow(
                [
                    k // 2 + 1,
                    dname,
                    f"{r_lin.u[k]:.10f}",
                    f"{r_b2g.u[k]:.10f}",
                    f"{r_nr.u[k]:.10f}",
                    f"{r_tl.u[k]:.10f}",
                    f"{du:.10f}",
                    f"{pct:.6f}",
                    f"{r_lin.reactions[k]/1000.0:.8f}",
                    f"{r_nr.reactions[k]/1000.0:.8f}",
                    f"{r_nr.reactions[k] - r_lin.reactions[k]:.6f}",
                ]
            )

    # Bảng so sánh thanh
    with open(os.path.join(res_dir, "member_comparison.csv"), "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "Element", "Label", "Area_mm2", "L0_mm",
                "N_Linear_kN", "N_bar2g_kN", "N_Corot_kN", "N_TL_kN",
                "Delta_N_Corot_vs_Lin_N", "Stress_Linear_MPa", "Stress_Corot_MPa",
                "Strain_Corot_microstrain", "Elongation_Corot_mm", "Energy_Corot_Nmm",
            ]
        )
        L0, _, _ = model.initial_lengths_and_cosines()
        for e in range(model.n_elems):
            w.writerow(
                [
                    e + 1,
                    model.member_labels[e],
                    f"{model.areas[e]:.4f}",
                    f"{L0[e]:.4f}",
                    f"{r_lin.N[e]/1000.0:.8f}",
                    f"{r_b2g.N[e]/1000.0:.8f}",
                    f"{r_nr.N[e]/1000.0:.8f}",
                    f"{r_tl.N[e]/1000.0:.8f}",
                    f"{r_nr.N[e] - r_lin.N[e]:.6f}",
                    f"{r_lin.stress[e]:.6f}",
                    f"{r_nr.stress[e]:.6f}",
                    f"{r_nr.strain[e]*1e6:.4f}",
                    f"{r_nr.elongation[e]:.8f}",
                    f"{r_nr.member_energy[e]:.6f}",
                ]
            )

    # Bảng kiểm chứng Dahlblom Example 9.1 từng vòng lặp
    with open(os.path.join(res_dir, "dahlblom_ex9_1_iterations.csv"), "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["Iteration", "a5_mm", "a6_mm", "Q1_MN", "Q2_MN", "RelErr_N"])
        for h in r_ex91.history:
            w.writerow(
                [
                    h["iteration"],
                    f"{h['u_mm'][4]:.4f}",
                    f"{h['u_mm'][5]:.4f}",
                    f"{h['N_N'][0]/1e6:.5f}",
                    f"{h['N_N'][1]/1e6:.5f}",
                    f"{h['rel_err_N']:.3e}",
                ]
            )

    # Bảng so sánh 6 thuật toán giải phi tuyến
    algo_rows = [
        ("Full Newton-Raphson (10 bước)", r_nr.u[3], r_nr.N[0], r_nr.equilibrium_check["max_free_residual_N"], r_nr.extra["total_iterations"], r_nr.extra["total_stiffness_factorizations"]),
        ("Modified Newton-Raphson (10 bước)", r_mod.u[3], r_mod.N[0], r_mod.equilibrium_check["max_free_residual_N"], r_mod.extra["total_iterations"], r_mod.extra["total_stiffness_factorizations"]),
        ("Euler bước đơn (10 bước)", r_eul.u[3], r_eul.N[0], r_eul.equilibrium_check["max_free_residual_N"], 10, 10),
        ("Runge-Kutta bậc 2 RK2 (10 bước)", r_rk2.u[3], r_rk2.N[0], r_rk2.equilibrium_check["max_free_residual_N"], 20, 20),
        ("CALFEM bar2g bậc 2 cố định tọa độ", r_b2g.u[3], r_b2g.N[0], r_b2g.equilibrium_check["max_free_residual_N"], r_b2g.extra["iterations"], r_b2g.extra["iterations"]),
        ("Total Lagrangian Green-Lagrange NR", r_tl.u[3], r_tl.N[0], r_tl.equilibrium_check["max_free_residual_N"], r_tl.extra["total_iterations"], r_tl.extra["total_stiffness_factorizations"]),
    ]
    with open(os.path.join(res_dir, "algorithms_comparison.csv"), "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["Algorithm", "u2y_mm", "N12_N", "MaxResidual_N", "TotalIterations", "MatrixFactorizations"])
        for row in algo_rows:
            w.writerow(row)

    # ==========================================================================
    # PHẦN 7: SINH 8 BIỂU ĐỒ KỸ THUẬT CHUYÊN NGHIỆP 300 DPI
    # ==========================================================================
    _plot_fig1_truss_geometry_and_deformation(model, r_lin, r_nr, os.path.join(fig_dir, "fig01_mo_hinh_va_bien_dang.png"))
    _plot_fig2_stress_force_comparison(model, r_lin, r_b2g, r_nr, r_tl, os.path.join(fig_dir, "fig02_so_sanh_noi_luc_ung_suat.png"))
    _plot_fig3_direction_softening_stiffening(direction_study, os.path.join(fig_dir, "fig03_mem_hoa_va_cung_hoa.png"))
    _plot_fig4_load_scale_nonlinearity(load_scale_study, os.path.join(fig_dir, "fig04_do_nhay_phi_tuyen_theo_tai.png"))
    _plot_fig5_algorithms_convergence(model, r_nr, r_mod, r_eul, r_rk2, os.path.join(fig_dir, "fig05_so_sanh_thuat_toan_NSA6.png"))
    _plot_fig6_large_displacement_snap_through(dc_5bar, dc_vm, os.path.join(fig_dir, "fig06_duong_cong_can_bang_snap_through.png"))
    _plot_fig7_buckling_modes(model, buckling, os.path.join(fig_dir, "fig07_dang_mat_on_dinh_buckling.png"))
    _plot_fig8_surgical_dissection_ansys(model, r_nr, probe_bar32, dissect_bar32, os.path.join(fig_dir, "fig08_phau_thuat_mat_cat_ANSYS.png"))

    summary = {
        "model_inputs": model.meta,
        "linear": r_lin.to_dict(),
        "bar2g_second_order": r_b2g.to_dict(),
        "corotational_nr": r_nr.to_dict(),
        "modified_nr": r_mod.to_dict(),
        "euler": r_eul.to_dict(),
        "rk2": r_rk2.to_dict(),
        "total_lagrangian": r_tl.to_dict(),
        "tangent_fd_check": {"corotational": fd_corot, "total_lagrangian": fd_tl},
        "buckling": buckling,
        "load_scale_study": load_scale_study,
        "direction_study": direction_study,
        "large_disp_5bar_summary": {
            "max_u2y_mm": float(dc_5bar["path"][-1]["u_control_mm"]),
            "peak": dc_5bar["limit_point_peak"],
            "n_points": len(dc_5bar["path"]),
        },
        "von_mises_snap_through": {
            "peak": dc_vm["limit_point_peak"],
            "valley": dc_vm["limit_point_valley"],
        },
        "benchmark_dahlblom_ex9_1": {
            "iterations": r_ex91.history,
            "final_u_mm": r_ex91.u.tolist(),
            "final_N_MN": (r_ex91.N / 1e6).tolist(),
        },
        "benchmark_calfem_exs3": {
            "u_mm": r_exs3.u.tolist(),
            "N_N": r_exs3.N.tolist(),
        },
        "probe_bar12": probe_bar12,
        "probe_bar32": probe_bar32,
    }
    with open(os.path.join(res_dir, "full_analysis_results.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    print("HOÀN TẤT CHẠY TOÀN BỘ PHÂN TÍCH VÀ SINH 8 BIỂU ĐỒ 300 DPI!")
    print(f"Thư mục kết quả: {res_dir}")
    print("\n--- TÓM TẮT KẾT QUẢ CHÍNH (ĐỀ BÀI P = 208 kN) ---")
    print(f"u2y Tuyến tính (bar2e)      = {r_lin.u[3]:.8f} mm")
    print(f"u2y CALFEM bar2g (bậc 2)    = {r_b2g.u[3]:.8f} mm ({100*(r_b2g.u[3]-r_lin.u[3])/r_lin.u[3]:+.5f}%)")
    print(f"u2y Corotational UL (NR)    = {r_nr.u[3]:.8f} mm ({100*(r_nr.u[3]-r_lin.u[3])/r_lin.u[3]:+.5f}%)")
    print(f"u2y Total Lagrangian (NSA4) = {r_tl.u[3]:.8f} mm ({100*(r_tl.u[3]-r_lin.u[3])/r_lin.u[3]:+.5f}%)")
    print(f"Thanh 1-2 hồi sinh: N12_lin = 0.0000 N -> N12_bar2g = {r_b2g.N[0]:+.4f} N -> N12_corot = {r_nr.N[0]:+.4f} N")
    print(f"Phản lực bất đối xứng biến dạng: R1y = {r_nr.reactions[1]/1000:.6f} kN | R4y = {r_nr.reactions[7]/1000:.6f} kN (ΔR = {(r_nr.reactions[7]-r_nr.reactions[1]):+.3f} N)")
    print(f"Tải tới hạn đàn hồi (bar2g): α_cr = {buckling['modes_calfem_bar2g'][0]['alpha_cr']:.2f} => P_cr = {buckling['modes_calfem_bar2g'][0]['alpha_cr']*208:,.1f} kN")
    print(f"Tải tới hạn đàn hồi (NSA_4): α_cr = {buckling['modes_mcguire_nsa4'][0]['alpha_cr']:.2f} => P_cr = {buckling['modes_mcguire_nsa4'][0]['alpha_cr']*208:,.1f} kN")
    print("\n--- KHẢO SÁT TẢI LỚN ---")
    for row in load_scale_study:
        print(
            f"  {row['multiplier']:5.0f}P ({row['P_kN']:9.0f} kN): "
            f"u2y_lin={row['u2y_lin_mm']:7.2f} mm | u2y_corot={row['u2y_corot_mm']:7.2f} mm "
            f"({row['pct_diff_corot_vs_lin']:+6.2f}%) | N12={row['N12_corot_kN']:+8.2f} kN"
        )
    return summary


# ==============================================================================
# CÁC HÀM VẼ BIỂU ĐỒ KỸ THUẬT 300 DPI (PHONG CÁCH ANSYS / HỌC THUẬT CAO CẤP)
# ==============================================================================
def _plot_fig1_truss_geometry_and_deformation(model, r_lin, r_nr, out_path: str) -> None:
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.5, 5.4))

    # --- Panel A: Sơ đồ cơ học chuẩn đề bài ---
    coords = model.coords
    for e in range(model.n_elems):
        ni, nj = int(model.conn[e, 0]) - 1, int(model.conn[e, 1]) - 1
        x0, y0 = coords[ni]
        x1, y1 = coords[nj]
        lw = 3.6 if e >= 3 else 2.2
        col = "#1D4ED8" if e >= 3 else "#0F766E"
        ax1.plot([x0, x1], [y0, y1], color=col, lw=lw, solid_capstyle="round", zorder=3)
        mx, my = 0.5 * (x0 + x1), 0.5 * (y0 + y1)
        area_lbl = r"$2\sqrt{2}A$" if e >= 3 else r"$A$"
        off_x, off_y = (0, -70) if e == 0 else ((-130, 0) if e == 1 else ((0, 55) if e == 2 else ((-145, -25) if e == 3 else (145, -25))))
        ax1.text(
            mx + off_x, my + off_y,
            f"Thanh {e+1} ({model.member_labels[e]})\n{area_lbl}",
            ha="center", va="center", fontsize=8.5, fontweight="bold",
            color="#0F172A", bbox=dict(boxstyle="round,pad=0.22", fc="white", ec=col, alpha=0.92),
        )

    # Nút & gối tựa
    for i, (x, y) in enumerate(coords):
        ax1.scatter([x], [y], s=95, facecolor="white", edgecolor="#0F172A", linewidth=2.2, zorder=5)
        dx_t, dy_t = (-185, -35) if i == 0 else ((115, -110) if i == 1 else ((-145, 95) if i == 2 else (140, -115)))
        ax1.text(x + dx_t, y + dy_t, f"Nút {i+1}\n({int(x)}, {int(y)})", fontsize=8.5, fontweight="bold", ha="center", color="#0F172A")

    # Gối khớp Nút 1
    ax1.add_patch(Polygon([[0, 0], [-65, -90], [65, -90]], closed=True, fc="#CBD5E1", ec="#334155", lw=1.4, zorder=4))
    ax1.plot([-95, 95], [-90, -90], color="#0F172A", lw=2.2)
    # Gối con lăn trên Nút 4
    ax1.add_patch(Polygon([[2000, 1000], [1935, 1085], [2065, 1085]], closed=True, fc="#CBD5E1", ec="#334155", lw=1.4, zorder=4))
    ax1.add_patch(Circle((1965, 1105), 18, fc="white", ec="#334155", lw=1.4, zorder=4))
    ax1.add_patch(Circle((2035, 1105), 18, fc="white", ec="#334155", lw=1.4, zorder=4))
    ax1.plot([1900, 2100], [1125, 1125], color="#0F172A", lw=2.4)

    # Lực P hướng lên tại Nút 2
    ax1.annotate(
        "", xy=(1000, 320), xytext=(1000, 20),
        arrowprops=dict(arrowstyle="-|>,head_width=0.45,head_length=0.7", color="#DC2626", lw=2.8),
        zorder=6,
    )
    ax1.text(1000, 365, "P = 208 kN\n(hướng lên +Y)", color="#DC2626", fontsize=9.5, fontweight="bold", ha="center")
    ax1.set_title("(a) Sơ đồ tính toán dàn 4 nút – 5 thanh (Đề bài 1.jpg)", fontsize=11, fontweight="bold", color="#0F172A")
    ax1.set_xlabel("Tọa độ X (mm)")
    ax1.set_ylabel("Tọa độ Y (mm)")
    ax1.set_xlim(-320, 2320)
    ax1.set_ylim(-260, 1300)
    ax1.set_aspect("equal")
    ax1.grid(True)

    # --- Panel B: Bản đồ ứng suất kiểu ANSYS & chuyển vị phóng đại 250x ---
    scale = 250.0
    cmap = plt.get_cmap("turbo")
    s_min, s_max = float(np.min(r_nr.stress)), float(np.max(r_nr.stress))
    norm = plt.Normalize(vmin=s_min, vmax=s_max)

    # Khung ban đầu nét đứt
    for e in range(model.n_elems):
        ni, nj = int(model.conn[e, 0]) - 1, int(model.conn[e, 1]) - 1
        ax2.plot(
            [coords[ni, 0], coords[nj, 0]],
            [coords[ni, 1], coords[nj, 1]],
            color="#94A3B8", ls="--", lw=1.3, label="Cấu hình ban đầu" if e == 0 else None,
        )

    # Khung biến dạng tô màu theo ứng suất σ_xx (MPa)
    c_def = coords + scale * r_nr.u.reshape(-1, 2)
    for e in range(model.n_elems):
        ni, nj = int(model.conn[e, 0]) - 1, int(model.conn[e, 1]) - 1
        col = cmap(norm(r_nr.stress[e]))
        ax2.plot([c_def[ni, 0], c_def[nj, 0]], [c_def[ni, 1], c_def[nj, 1]], color=col, lw=6.0, solid_capstyle="round", zorder=4)
        mx, my = 0.5 * (c_def[ni, 0] + c_def[nj, 0]), 0.5 * (c_def[ni, 1] + c_def[nj, 1])
        ax2.text(
            mx, my + (55 if e == 2 else (-75 if e == 0 else 0)),
            f"σ={r_nr.stress[e]:+.2f} MPa\nN={r_nr.N[e]/1e3:+.3f} kN",
            ha="center", va="center", fontsize=7.8, fontweight="bold", color="#0F172A",
            bbox=dict(boxstyle="round,pad=0.18", fc="white", ec=col, alpha=0.92), zorder=6,
        )

    ax2.scatter(c_def[:, 0], c_def[:, 1], s=70, fc="white", ec="#0F172A", lw=2.0, zorder=5)
    sm = plt.cm.ScalarMappable(cmap=cmap, norm=norm)
    sm.set_array([])
    cbar = fig.colorbar(sm, ax=ax2, fraction=0.042, pad=0.03)
    cbar.set_label("Ứng suất pháp σ (MPa)  [+ Kéo / - Nén]", fontsize=9)
    ax2.set_title(f"(b) Mô phỏng ứng suất kiểu ANSYS & biến dạng (×{int(scale)})", fontsize=11, fontweight="bold", color="#0F172A")
    ax2.set_xlabel("Tọa độ X (mm)")
    ax2.set_ylabel("Tọa độ Y (mm)")
    ax2.set_xlim(-320, 2380)
    ax2.set_ylim(-220, 1320)
    ax2.set_aspect("equal")
    ax2.legend(loc="lower right", fontsize=8.5)
    ax2.grid(True)

    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def _plot_fig2_stress_force_comparison(model, r_lin, r_b2g, r_nr, r_tl, out_path: str) -> None:
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.2, 5.0))

    # Panel A: Chênh lệch lực dọc ΔN = N_NL - N_Lin (N) của 5 thanh
    x = np.arange(model.n_elems)
    w = 0.26
    dN_b2g = r_b2g.N - r_lin.N
    dN_nr = r_nr.N - r_lin.N
    dN_tl = r_tl.N - r_lin.N

    ax1.bar(x - w, dN_b2g, width=w, label="CALFEM bar2g (Bậc 2 gốc)", color="#0284C7")
    ax1.bar(x, dN_nr, width=w, label="Corotational UL (CALFEM cập nhật)", color="#DC2626")
    ax1.bar(x + w, dN_tl, width=w, label="Total Lagrangian (NSA_4 Green-Lagrange)", color="#0F766E")
    ax1.axhline(0, color="#0F172A", lw=0.9)
    ax1.set_xticks(x)
    ax1.set_xticklabels([f"Thanh {i+1}\n({lbl})" for i, lbl in enumerate(model.member_labels)], fontsize=9)
    ax1.set_ylabel("Độ lệch nội lực ΔN = N_PT − N_TT (N)")
    ax1.set_title("(a) Hiệu ứng phi tuyến làm thay đổi nội lực từng thanh (P = 208 kN)", fontsize=10.5, fontweight="bold")
    ax1.legend(fontsize=8.2, loc="best")
    ax1.grid(True, axis="y")
    for xi, val in zip(x, dN_nr):
        ax1.text(xi, val + (3.0 if val >= 0 else -5.5), f"{val:+.1f} N", ha="center", fontsize=8, fontweight="bold", color="#991B1B")

    # Panel B: Chênh lệch chuyển vị các DOF tự do (%) so với tuyến tính
    free_idx = [2, 3, 4, 5, 6]
    free_lbls = ["ux2\n(TT=0)", "uy2", "ux3", "uy3", "ux4"]
    x2 = np.arange(len(free_idx))
    du_b2g = [(r_b2g.u[k] - r_lin.u[k]) * 1e3 for k in free_idx]  # micromet (μm)
    du_nr = [(r_nr.u[k] - r_lin.u[k]) * 1e3 for k in free_idx]
    du_tl = [(r_tl.u[k] - r_lin.u[k]) * 1e3 for k in free_idx]

    ax2.bar(x2 - w, du_b2g, width=w, label="CALFEM bar2g (Bậc 2 gốc)", color="#0284C7")
    ax2.bar(x2, du_nr, width=w, label="Corotational UL (Full NR)", color="#DC2626")
    ax2.bar(x2 + w, du_tl, width=w, label="Total Lagrangian (NSA_4)", color="#0F766E")
    ax2.axhline(0, color="#0F172A", lw=0.9)
    ax2.set_xticks(x2)
    ax2.set_xticklabels(free_lbls, fontsize=9)
    ax2.set_ylabel("Độ lệch chuyển vị Δu = u_PT − u_TT (μm = 10⁻³ mm)")
    ax2.set_title("(b) Chênh lệch chuyển vị nút phi tuyến so với tuyến tính (μm)", fontsize=10.5, fontweight="bold")
    ax2.set_ylim(-0.48, 0.56)
    ax2.legend(fontsize=8.2, loc="upper right")
    ax2.grid(True, axis="y")
    for xi, val in zip(x2, du_nr):
        ax2.text(xi, val + (0.025 if val >= 0 else -0.055), f"{val:+.3f}", ha="center", fontsize=8, fontweight="bold", color="#991B1B")

    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def _plot_fig3_direction_softening_stiffening(direction_study: List[Dict[str, Any]], out_path: str) -> None:
    P_MN = np.array([d["P_kN"] / 1000.0 for d in direction_study])
    u_lin = np.array([d["u2y_lin_mm"] for d in direction_study])
    u_cor = np.array([d["u2y_corot_mm"] for d in direction_study])
    u_b2g = np.array([d["u2y_bar2g_mm"] for d in direction_study])
    N12 = np.array([d["N12_corot_kN"] for d in direction_study])

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.2, 5.1))
    ax1.plot(u_lin, P_MN, "--", color="#64748B", lw=1.8, label="Đàn hồi tuyến tính (bar2e)")
    ax1.plot(u_b2g, P_MN, "-.", color="#0284C7", lw=2.0, label="CALFEM bar2g (Bậc 2 tọa độ gốc)")
    ax1.plot(u_cor, P_MN, "-", color="#DC2626", lw=2.5, label="Corotational UL (Phi tuyến đầy đủ)")
    ax1.axhline(0, color="#334155", lw=0.8)
    ax1.axvline(0, color="#334155", lw=0.8)
    ax1.annotate("Tải +P hướng LÊN:\nHai thanh chéo NÉN → MỀM HÓA\n(|u_PT| > |u_TT|)", xy=(165, 42), xytext=(30, 52),
                 arrowprops=dict(arrowstyle="->", color="#B91C1C", lw=1.4), fontsize=8.5, fontweight="bold", color="#991B1B",
                 bbox=dict(boxstyle="round,pad=0.3", fc="#FEF2F2", ec="#DC2626"))
    ax1.annotate("Tải −P hướng XUỐNG:\nHai thanh chéo KÉO → CỨNG HÓA\n(|u_PT| < |u_TT|)", xy=(-110, -45), xytext=(-220, -25),
                 arrowprops=dict(arrowstyle="->", color="#0F766E", lw=1.4), fontsize=8.5, fontweight="bold", color="#115E59",
                 bbox=dict(boxstyle="round,pad=0.3", fc="#F0FDFA", ec="#0F766E"))
    ax1.set_xlabel("Chuyển vị đứng nút 2, u₂y (mm)")
    ax1.set_ylabel("Tải trọng P (MN)")
    ax1.set_title("(a) Bản chất bất đối xứng: Mềm hóa (+P) vs Cứng hóa (−P)", fontsize=10.5, fontweight="bold")
    ax1.legend(fontsize=8.3, loc="lower right")
    ax1.grid(True)

    # Panel B: Thanh 1-2 thức tỉnh từ 0 lên hàng nghìn kN khi tải tăng
    ax2.plot(P_MN, np.zeros_like(P_MN), "--", color="#64748B", lw=1.6, label="Tuyến tính: N₁₂ ≡ 0 (Thanh không lực)")
    ax2.plot(P_MN, N12, "-", color="#7C3AED", lw=2.5, label="Phi tuyến hình học: N₁₂ > 0 (Chịu KÉO ở cả hai chiều!)")
    ax2.fill_between(P_MN, 0, N12, color="#DDD6FE", alpha=0.45)
    ax2.set_xlabel("Tải trọng P (MN)  [−P hướng xuống | +P hướng lên]")
    ax2.set_ylabel("Lực dọc thanh 1–2, N₁₂ (kN)")
    ax2.set_title("(b) Hiện tượng 'hồi sinh' thanh không lực 1–2 (Hiệu ứng dây căng)", fontsize=10.5, fontweight="bold")
    ax2.legend(fontsize=8.5, loc="upper center")
    ax2.grid(True)

    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def _plot_fig4_load_scale_nonlinearity(load_scale_study: List[Dict[str, Any]], out_path: str) -> None:
    mults = [r["multiplier"] for r in load_scale_study]
    pct_cor = [r["pct_diff_corot_vs_lin"] for r in load_scale_study]
    pct_b2g = [r["pct_diff_bar2g_vs_lin"] for r in load_scale_study]
    r1y = [abs(r["R1y_corot_kN"]) for r in load_scale_study]
    r4y = [abs(r["R4y_corot_kN"]) for r in load_scale_study]
    asym_pct = [100.0 * (a - b) / (0.5 * (a + b)) for a, b in zip(r1y, r4y)]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.0, 4.8))
    ax1.plot(mults, pct_cor, "o-", color="#DC2626", lw=2.4, ms=7, label="Corotational UL (CALFEM cập nhật)")
    ax1.plot(mults, pct_b2g, "s--", color="#0284C7", lw=2.0, ms=6, label="CALFEM bar2g (Bậc 2 tọa độ gốc)")
    ax1.set_xscale("log")
    ax1.set_yscale("log")
    for m_v, p_v in zip(mults, pct_cor):
        ax1.annotate(f"{p_v:.2f}%", (m_v, p_v), textcoords="offset points", xytext=(0, 8), ha="center", fontsize=8.2, fontweight="bold", color="#991B1B")
    ax1.set_xlabel("Bội số tải trọng so với đề bài λ = P / 208 kN (thang log)")
    ax1.set_ylabel("Sai lệch chuyển vị (u₂y_PT − u₂y_TT)/u₂y_TT (%)")
    ax1.set_title("(a) Sự bùng nổ hiệu ứng phi tuyến hình học khi tăng tải", fontsize=10.5, fontweight="bold")
    ax1.set_ylim(0.03, 900.0)
    ax1.legend(fontsize=8.5, loc="upper left")
    ax1.grid(True, which="both")

    ax2.plot(mults, asym_pct, "D-", color="#D97706", lw=2.4, ms=7, label="(|R₁y| − |R₄y|) / (P/2)  (%)")
    ax2.set_xscale("log")
    ax2.set_yscale("log")
    for m_v, a_v in zip(mults, asym_pct):
        ax2.annotate(f"{a_v:.3f}%", (m_v, a_v), textcoords="offset points", xytext=(-6 if m_v >= 400 else 0, 8), ha="center", fontsize=8.2, fontweight="bold", color="#92400E")
    ax2.set_xlabel("Bội số tải trọng λ = P / 208 kN (thang log)")
    ax2.set_ylabel("Độ lệch phản lực hai gối |R₁y| − |R₄y| (%)")
    ax2.set_title("(b) Bất đối xứng phản lực gối do thay đổi tay đòn biến dạng", fontsize=10.5, fontweight="bold")
    ax2.set_ylim(0.02, 420.0)
    ax2.legend(fontsize=8.5, loc="upper left")
    ax2.grid(True, which="both")

    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def _plot_fig5_algorithms_convergence(model, r_nr, r_mod, r_eul, r_rk2, out_path: str) -> None:
    # Khảo sát so sánh 4 thuật toán tại mức tải phi tuyến mạnh λ = 250 (P = 52 MN) để thấy cực rõ sự khác biệt!
    lam_demo = 250.0
    nr_d = solve_corotational_newton_raphson(model, load_factor=lam_demo, n_steps=10)
    mod_d = solve_corotational_modified_nr(model, load_factor=lam_demo, n_steps=10)
    eul_d = solve_corotational_euler(model, load_factor=lam_demo, n_steps=10)
    rk2_d = solve_corotational_rk2(model, load_factor=lam_demo, n_steps=10)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.2, 5.0))

    steps_e = [h["lambda"] * 0.208 for h in eul_d.history[1:]]
    res_e = [max(1e-12, h["residual_inf_N"]) for h in eul_d.history[1:]]
    res_rk = [max(1e-12, h["residual_inf_N"]) for h in rk2_d.history[1:]]
    res_nr = [max(1e-12, h["residual_inf_N"]) for h in nr_d.history[1:]]
    res_mod = [max(1e-12, h["residual_inf_N"]) for h in mod_d.history[1:]]

    ax1.semilogy(steps_e, res_e, "o-", color="#DC2626", lw=2.2, label="Euler bước đơn (sai số tích lũy lớn)")
    ax1.semilogy(steps_e, res_rk, "s-", color="#D97706", lw=2.2, label="Runge-Kutta bậc 2 RK2 (giảm sai số mạnh)")
    ax1.semilogy(steps_e, res_mod, "^--", color="#0284C7", lw=2.0, label="Modified Newton-Raphson (hội tụ cân bằng)")
    ax1.semilogy(steps_e, res_nr, "D-", color="#0F766E", lw=2.2, label="Full Newton-Raphson (hội tụ bậc 2)")
    ax1.axhline(1e-7, color="#334155", ls=":", lw=1.2, label="Ngưỡng dung sai 10⁻⁷ N")
    ax1.set_xlabel("Tải trọng tích lũy P (MN)  [10 bước gia tải tới λ = 250]")
    ax1.set_ylabel("Phần dư lực cân bằng lớn nhất ||R_f||∞ (N) [log]")
    ax1.set_title("(a) Sai số mất cân bằng của 4 thuật toán (NSA_6, 10 bước)", fontsize=10.5, fontweight="bold")
    ax1.legend(fontsize=8.0, loc="center right")
    ax1.grid(True, which="both")

    # Panel B: Số vòng lặp con mỗi bước của Full NR vs Modified NR tại λ = 250
    st = [h["step"] for h in nr_d.history[1:]]
    it_nr = [h["iterations"] for h in nr_d.history[1:]]
    it_mod = [h["iterations"] for h in mod_d.history[1:]]
    x = np.arange(len(st))
    ax2.bar(x - 0.18, it_nr, width=0.36, color="#0F766E", label=f"Full NR (Tổng {sum(it_nr)} lặp / {sum(it_nr)} lần lập Kt)")
    ax2.bar(x + 0.18, it_mod, width=0.36, color="#0284C7", label=f"Modified NR (Tổng {sum(it_mod)} lặp / 10 lần lập Kt)")
    ax2.set_xticks(x)
    ax2.set_xticklabels([f"B{s}" for s in st])
    ax2.set_xlabel("Bước gia tải i = 1..10")
    ax2.set_ylabel("Số vòng lặp con để đạt ||R||∞ < 10⁻⁷ N")
    ax2.set_title("(b) Đánh đổi tốc độ hội tụ: Full NR vs Modified NR (NSA_6 6.3.4)", fontsize=10.5, fontweight="bold")
    ax2.legend(fontsize=8.2, loc="upper left")
    ax2.grid(True, axis="y")

    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def _plot_fig6_large_displacement_snap_through(dc_5bar: Dict[str, Any], dc_vm: Dict[str, Any], out_path: str) -> None:
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.4, 5.2))

    # Panel A: Đường cong cân bằng chuyển vị cực lớn của hệ dàn 5 thanh đề bài (zoom vùng bật nhảy 0..1500 mm)
    u5 = np.array([p["u_control_mm"] for p in dc_5bar["path"]])
    P5 = np.array([p["lambda"] * 0.208 for p in dc_5bar["path"]])  # MN
    eig5 = np.array([p["min_eig_Kt"] for p in dc_5bar["path"]])

    mask_zoom = u5 <= 1520.0
    u5z, P5z, eig5z = u5[mask_zoom], P5[mask_zoom], eig5[mask_zoom]
    ax1.plot(u5z, P5z, "-", color="#1D4ED8", lw=2.6, label="Đường cân bằng P(u₂y) – Dàn 5 thanh")
    unst5 = np.where(eig5z < 0)[0]
    if len(unst5) > 1:
        ax1.plot(u5z[unst5], P5z[unst5], "-", color="#DC2626", lw=3.2, label="Nhánh mất ổn định Snap-Through (det Kt < 0)")

    # Đường tiếp tuyến tuyến tính ban đầu
    u_lin_line = np.linspace(0, 420, 50)
    k_init = 208.0 / 0.6496751624187906
    ax1.plot(u_lin_line, u_lin_line * (k_init / 1000.0), "--", color="#64748B", lw=1.6, label="Đường tuyến tính ban đầu (bar2e)")
    ax1.axvline(1000.0, color="#94A3B8", ls=":", lw=1.3, label="Mốc y₂ = L = 1000 mm")

    pk5 = dc_5bar["limit_point_peak"]
    vl5 = dc_5bar["limit_point_valley"]
    ax1.scatter([pk5["u_control_mm"]], [pk5["P_limit_kN"] / 1000.0], s=85, color="#DC2626", zorder=6)
    ax1.scatter([vl5["u_control_mm"]], [vl5["P_valley_kN"] / 1000.0], s=85, color="#D97706", zorder=6)
    ax1.annotate(
        f"Điểm giới hạn A (Snap-Through)\nP_lim = {pk5['P_limit_kN']/1000:.2f} MN tại u₂y = {pk5['u_control_mm']:.0f} mm",
        xy=(pk5["u_control_mm"], pk5["P_limit_kN"] / 1000.0),
        xytext=(380, 118),
        arrowprops=dict(arrowstyle="->", color="#DC2626", lw=1.4),
        fontsize=8.2, fontweight="bold", color="#991B1B",
        bbox=dict(boxstyle="round,pad=0.28", fc="#FEF2F2", ec="#DC2626"),
    )
    ax1.annotate(
        f"Điểm thung lũng B\nP_min = {vl5['P_valley_kN']/1000:.2f} MN\n(u₂y = {vl5['u_control_mm']:.0f} mm)",
        xy=(vl5["u_control_mm"], vl5["P_valley_kN"] / 1000.0),
        xytext=(920, 12),
        arrowprops=dict(arrowstyle="->", color="#D97706", lw=1.4),
        fontsize=8.0, fontweight="bold", color="#92400E",
        bbox=dict(boxstyle="round,pad=0.25", fc="#FFFBEB", ec="#D97706"),
    )
    ax1.set_xlabel("Chuyển vị đứng nút 2, u₂y (mm)")
    ax1.set_ylabel("Tải trọng P (MN)")
    ax1.set_title("(a) Bật nhảy Snap-Through thực sự của Dàn 5 thanh đề bài", fontsize=10.5, fontweight="bold")
    ax1.set_xlim(0, 1520)
    ax1.set_ylim(-8, 155)
    ax1.legend(fontsize=7.8, loc="upper left")
    ax1.grid(True)

    # Panel B: Đối chiếu Vòm 2 thanh Von Mises (có rõ đỉnh Limit Point & nhánh âm mất ổn định như NSA_6 Slide 15!)
    u_vm = np.array([-p["u_control_mm"] for p in dc_vm["path"]])
    P_vm = np.array([p["lambda"] * 1.0 for p in dc_vm["path"]])  # MN (f_ref = 1 MN)
    eig_vm = np.array([p["min_eig_Kt"] for p in dc_vm["path"]])
    stable_mask = eig_vm >= 0

    ax2.plot(u_vm, P_vm, "-", color="#0F766E", lw=2.5, label="Đường cân bằng toàn phần (Arc-Length / Disp. Control)")
    # Tô đậm nhánh mất ổn định (min_eig < 0)
    unstable_idx = np.where(~stable_mask)[0]
    if len(unstable_idx) > 1:
        ax2.plot(u_vm[unstable_idx], P_vm[unstable_idx], "-", color="#DC2626", lw=3.2, label="Nhánh mất ổn định (det Kt < 0 – Snap-Through)")
    peak = dc_vm["limit_point_peak"]
    val = dc_vm["limit_point_valley"]
    ax2.scatter([-peak["u_control_mm"]], [peak["P_limit_kN"] / 1000.0], s=80, color="#DC2626", zorder=6)
    ax2.scatter([-val["u_control_mm"]], [val["P_valley_kN"] / 1000.0], s=80, color="#D97706", zorder=6)
    ax2.annotate(f"Điểm giới hạn A (Limit Point)\nP_max = {peak['P_limit_kN']/1000:.2f} MN",
                 xy=(-peak["u_control_mm"], peak["P_limit_kN"]/1000.0),
                 xytext=(-peak["u_control_mm"] + 65, peak["P_limit_kN"]/1000.0 + 0.12),
                 arrowprops=dict(arrowstyle="->", color="#DC2626", lw=1.4), fontsize=8.3, fontweight="bold", color="#991B1B")
    ax2.axhline(0, color="#334155", lw=0.9)
    ax2.set_xlabel("Độ võng đỉnh vòm |u_y| (mm)")
    ax2.set_ylabel("Tải trọng P (MN)")
    ax2.set_title("(b) So sánh trực quan với Vòm Von Mises có bật nhảy (NSA_6 Slide 15)", fontsize=10.5, fontweight="bold")
    ax2.legend(fontsize=8.0, loc="lower right")
    ax2.grid(True)

    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def _plot_fig7_buckling_modes(model, buckling: Dict[str, Any], out_path: str) -> None:
    modes = buckling["modes_calfem_bar2g"]
    n_show = min(2, len(modes))
    fig, axes = plt.subplots(1, n_show, figsize=(13.0, 5.0))
    if n_show == 1:
        axes = [axes]
    coords = model.coords
    for idx in range(n_show):
        ax = axes[idx]
        md = modes[idx]
        alpha_cr = md["alpha_cr"]
        p_cr = alpha_cr * buckling["P_ref_kN"]
        vec = np.array(md["mode_shape"]).reshape(-1, 2)
        if vec[1, 1] < 0:
            vec = -vec
        c_def = coords + 280.0 * vec

        for e in range(model.n_elems):
            ni, nj = int(model.conn[e, 0]) - 1, int(model.conn[e, 1]) - 1
            ax.plot([coords[ni, 0], coords[nj, 0]], [coords[ni, 1], coords[nj, 1]], "--", color="#94A3B8", lw=1.5, label="Chưa biến dạng" if e == 0 else None)
            ax.plot([c_def[ni, 0], c_def[nj, 0]], [c_def[ni, 1], c_def[nj, 1]], "-", color="#DC2626" if idx == 0 else "#7C3AED", lw=3.2, label="Dạng mất ổn định φ" if e == 0 else None)
        ax.scatter(c_def[:, 0], c_def[:, 1], s=75, fc="white", ec="#0F172A", lw=2.0, zorder=5)
        for i in range(model.n_nodes):
            ax.text(c_def[i, 0] + 45, c_def[i, 1] + 45, f"N{i+1}", fontsize=9, fontweight="bold")
        ax.set_title(f"Mode {idx+1}: α_cr = {alpha_cr:,.2f}  →  P_cr = {p_cr:,.1f} kN", fontsize=10.5, fontweight="bold", color="#0F172A")
        ax.set_xlabel("X (mm)")
        ax.set_ylabel("Y (mm)")
        ax.set_xlim(-350, 2450)
        ax.set_ylim(-350, 1450)
        ax.set_aspect("equal")
        ax.legend(fontsize=8.5, loc="lower right")
        ax.grid(True)

    fig.suptitle("Phân tích trị riêng tải tới hạn đàn hồi tổng thể: (Ke + α_cr·Kg)·φ = 0 (CALFEM bar2g)", fontsize=11.5, fontweight="bold", y=1.01)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def _plot_fig8_surgical_dissection_ansys(model, r_nr, probe_info: Dict[str, Any], dissect_info: Dict[str, Any], out_path: str) -> None:
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.2, 5.2))
    fig.patch.set_facecolor("#0F172A")
    for ax in (ax1, ax2):
        ax.set_facecolor("#1E293B")
        ax.tick_params(colors="#E2E8F0")
        ax.xaxis.label.set_color("#E2E8F0")
        ax.yaxis.label.set_color("#E2E8F0")
        ax.title.set_color("#38BDF8")
        for sp in ax.spines.values():
            sp.set_color("#475569")

    # Panel A: Phẫu thuật mặt cắt ngang chữ I tại ξ = 0.5 của thanh chéo nén 3-2
    samples = dissect_info["samples"]
    ys = np.array([s["y_mm"] for s in samples])
    zs = np.array([s["z_mm"] for s in samples])
    sigs = np.array([s["sigma_xx_MPa"] for s in samples])
    sc = ax1.scatter(zs, ys, c=sigs, cmap="turbo", s=165, marker="s", edgecolors="#0F172A", linewidths=0.4)
    dims = dissect_info["dimensions_mm"]
    h, b, tf, tw = dims["height"], dims["width"], dims["tf"], dims["tw"]
    # Vẽ đường viền tiết diện chữ I chuẩn
    i_poly = [
        (-b/2, -h/2), (b/2, -h/2), (b/2, -h/2+tf), (tw/2, -h/2+tf),
        (tw/2, h/2-tf), (b/2, h/2-tf), (b/2, h/2), (-b/2, h/2),
        (-b/2, h/2-tf), (-tw/2, h/2-tf), (-tw/2, -h/2+tf), (-b/2, -h/2+tf),
    ]
    ax1.add_patch(Polygon(i_poly, closed=True, fill=False, ec="#F8FAFC", lw=1.8, zorder=5))
    cbar = fig.colorbar(sc, ax=ax1, fraction=0.045, pad=0.03)
    cbar.set_label("Ứng suất pháp nội bộ σ_xx (MPa)", color="#E2E8F0", fontsize=9)
    cbar.ax.yaxis.set_tick_params(color="#E2E8F0")
    plt.setp(cbar.ax.yaxis.get_ticklabels(), color="#E2E8F0")
    ax1.set_title(f"(a) Phẫu thuật mặt cắt ngang Thanh {dissect_info['member_label']} tại ξ=0.5 (e₀=L/1000)", fontsize=10, fontweight="bold")
    ax1.set_xlabel("Tọa độ ngang mặt cắt z (mm)")
    ax1.set_ylabel("Tọa độ đứng mặt cắt y (mm)")
    ax1.set_aspect("equal")
    ax1.grid(True, color="#334155", alpha=0.6)

    # Panel B: Mổ dọc thanh (Longitudinal Cutaway) so sánh mép trên, trục trung hòa, mép dưới
    prof = compute_longitudinal_profile(model, r_nr, None, elem_index_0based=3, n_stations=31, imperfection_ratio=0.001)
    s_mm = [p["s_mm"] for p in prof]
    sig_c = [p["sigma_center_MPa"] for p in prof]
    sig_t = [p["sigma_top_MPa"] for p in prof]
    sig_b = [p["sigma_bottom_MPa"] for p in prof]
    ax2.plot(s_mm, sig_c, "--", color="#38BDF8", lw=2.2, label="Trục trung hòa (dàn khớp lý tưởng σ = N/A)")
    ax2.plot(s_mm, sig_t, "-", color="#F43F5E", lw=2.5, label="Mép nén cực đại (y = +h/2, xét P-δ bậc hai)")
    ax2.plot(s_mm, sig_b, "-", color="#22C55E", lw=2.5, label="Mép giảm nén (y = −h/2, xét P-δ bậc hai)")
    ax2.fill_between(s_mm, sig_t, sig_b, color="#38BDF8", alpha=0.14)
    ax2.set_title("(b) Mổ dọc thanh 3–2: Ứng suất dọc trục & khuếch đại P-δ (NSA_4 Slide 27)", fontsize=10, fontweight="bold")
    ax2.set_xlabel("Tọa độ dọc trục thanh s (mm)")
    ax2.set_ylabel("Ứng suất pháp σ_xx (MPa)")
    leg = ax2.legend(fontsize=8.2, facecolor="#0F172A", edgecolor="#475569")
    for text in leg.get_texts():
        text.set_color("#E2E8F0")
    ax2.grid(True, color="#334155", alpha=0.6)

    fig.tight_layout()
    fig.savefig(out_path, facecolor=fig.get_facecolor())
    plt.close(fig)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    run_all(root)
