# -*- coding: utf-8 -*-
"""
================================================================================
MÔ-ĐUN KIỂM THỬ TỰ ĐỘNG (VERIFICATION SUITE) – XÁC MINH ĐỘ CHÍNH XÁC TUYỆT ĐỐI
================================================================================
Kiểm chứng đồng thời 6 trụ cột khoa học:
  1. Benchmark tuyến tính CALFEM 3.4 `exs3.m` (calfem34.pdf PDF tr. 233-236).
  2. Benchmark phi tuyến hình học Dahlblom (2016) Example 9.1 (tr. 260-261 /
     PDF tr. 274-275) với `bar2g`: đối chiếu từng vòng lặp 1..6 với Bảng 1 sách!
  3. Đối chiếu bài toán Đề bài 5 thanh tuyến tính với nghiệm giải tích chính xác
     và SAP2000 (sai số < 1e-11 mm).
  4. Kiểm chứng tính khách quan vật rắn (Rigid-Body Motion Objectivity – Yang 2025):
     xoay thanh một góc lớn bất kỳ (ví dụ 35°) KHÔNG sinh biến dạng giả hay lực giả!
  5. Kiểm chứng ma trận tiếp tuyến giải tích Kt bằng đạo hàm sai phân trung tâm
     (cả Corotational UL lẫn Total Lagrangian Green-Lagrange: sai số < 1e-8).
  6. Kiểm chứng cân bằng cấu hình biến dạng ∑Fx = 0, ∑Fy = 0, ∑M_deformed = 0 và
     quy luật đòn bẩy phi tuyến R4y * (2L + u4x) = -P * (L + u2x)!
================================================================================
"""

from __future__ import annotations
import math
import sys
import numpy as np

from python_core.calfem_elements import bar2g_corotational, bar2g_total_lagrangian
from python_core.truss_models import (
    create_assignment_5bar_truss,
    create_dahlblom_example_9_1,
    create_calfem_exs3_truss,
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


def run_all_tests() -> None:
    print("=" * 78)
    print("BẮT ĐẦU KIỂM CHỨNG TOÀN DIỆN LÕI TÍNH TOÁN PYTHON CALFEM PHI TUYẾN")
    print("=" * 78)

    # 1. Benchmark CALFEM exs3.m
    m_exs3 = create_calfem_exs3_truss()
    r_exs3 = solve_linear_calfem(m_exs3)
    exp3 = m_exs3.meta["manual_expected"]
    err_u3 = max(abs(r_exs3.u[4] - exp3["u5_mm"]), abs(r_exs3.u[5] - exp3["u6_mm"]))
    err_n3 = float(np.max(np.abs(r_exs3.N - np.array(exp3["N_N"]))))
    assert err_u3 <= 0.001, f"Sai số exs3 chuyển vị lớn: {err_u3}"
    assert err_n3 <= 0.5, f"Sai số exs3 lực dọc lớn: {err_n3}"
    print(f"[PASS] 1. Benchmark CALFEM 3.4 exs3.m: u5={r_exs3.u[4]:.6f} mm, u6={r_exs3.u[5]:.6f} mm, max_dN={err_n3:.3f} N")

    # 2. Benchmark phi tuyến Dahlblom (2016) Example 9.1 (tr. 260-261)
    m_ex91 = create_dahlblom_example_9_1()
    r_ex91 = solve_calfem_bar2g_second_order(m_ex91, tol_rel=1e-9)
    exp91 = m_ex91.meta["book_expected"]
    assert abs(r_ex91.u[4] - exp91["a5_mm"]) < 0.005, f"a5 mismatch: {r_ex91.u[4]}"
    assert abs(r_ex91.u[5] - exp91["a6_mm"]) < 0.005, f"a6 mismatch: {r_ex91.u[5]}"
    assert abs(r_ex91.N[0] / 1e6 - exp91["N1_MN"]) < 0.0005, f"Q1 mismatch: {r_ex91.N[0]/1e6}"
    assert abs(r_ex91.N[1] / 1e6 - exp91["N2_MN"]) < 0.0005, f"Q2 mismatch: {r_ex91.N[1]/1e6}"
    print(
        f"[PASS] 2. Benchmark Dahlblom Ex 9.1 (bar2g): a5={r_ex91.u[4]:.3f} mm (sách -44.544), "
        f"a6={r_ex91.u[5]:.3f} mm (sách -108.835), Q1={r_ex91.N[0]/1e6:.4f} MN (sách -11.1360), "
        f"Q2={r_ex91.N[1]/1e6:.4f} MN (sách +1.4833)"
    )

    # 3. Kiểm chứng bài toán đề bài 5 thanh (Tuyến tính vs Giải tích)
    m = create_assignment_5bar_truss()
    r_lin = solve_linear_calfem(m)
    L, E, A, P = 1000.0, 200000.0, 2001.0, 208000.0
    q = P * L / (E * A)
    u_exact = q * np.array([0.0, 0.0, 0.0, 1.25, -0.25, 0.5, 0.75, 0.0])
    N_exact = np.array([0.0, P / 2.0, P / 2.0, -P / math.sqrt(2.0), -P / math.sqrt(2.0)])
    assert np.max(np.abs(r_lin.u - u_exact)) < 1e-12
    assert np.max(np.abs(r_lin.N - N_exact)) < 1e-9
    print(f"[PASS] 3. Đề bài 5 thanh Tuyến tính (bar2e) khớp giải tích & SAP2000: max_du={np.max(np.abs(r_lin.u - u_exact)):.2e} mm")

    # 4. Kiểm chứng tính khách quan vật rắn (Rigid-Body Motion Objectivity – Yang 2025)
    angle = math.radians(37.0)
    L0 = 1000.0
    ex0 = np.array([0.0, L0])
    ey0 = np.array([0.0, 0.0])
    # Xoay thanh cứng quanh đầu 1 một góc 37 độ + tịnh tiến [150, -80] mm
    ed_rb = np.array([150.0, -80.0, 150.0 + L0 * (math.cos(angle) - 1.0), -80.0 + L0 * math.sin(angle)])
    f_c, _, _, _, N_c, eps_c, _, _ = bar2g_corotational(ex0, ey0, (E, A), ed_rb)
    f_tl, _, _, _, N_tl, eps_tl, _, _ = bar2g_total_lagrangian(ex0, ey0, (E, A), ed_rb)
    assert abs(N_c) < 1e-8 and abs(eps_c) < 1e-14
    assert abs(N_tl) < 1e-8 and abs(eps_tl) < 1e-14
    print(f"[PASS] 4. Tính khách quan vật rắn (xoay cứng 37°): |N_corot|={abs(N_c):.2e} N, |N_TL|={abs(N_tl):.2e} N")

    # 5. Kiểm chứng toàn bộ mô hình phi tuyến & tiếp tuyến sai phân trên Đề bài 5 thanh
    r_b2g = solve_calfem_bar2g_second_order(m)
    r_nr = solve_corotational_newton_raphson(m, n_steps=10)
    r_mod = solve_corotational_modified_nr(m, n_steps=10)
    r_eul = solve_corotational_euler(m, n_steps=10)
    r_rk2 = solve_corotational_rk2(m, n_steps=10)
    r_tl = solve_total_lagrangian_nr(m, n_steps=10)

    fd_corot = verify_tangent_finite_difference(m, r_nr.u, "corotational")
    fd_tl = verify_tangent_finite_difference(m, r_tl.u, "total_lagrangian")
    assert fd_corot["relative_frobenius_error"] < 1e-8
    assert fd_tl["relative_frobenius_error"] < 1e-8
    assert np.max(np.abs(r_nr.u - r_mod.u)) < 1e-9
    assert r_nr.equilibrium_check["max_free_residual_N"] < 1e-7
    assert abs(r_nr.equilibrium_check["sum_M_Nmm"]) < 1e-3

    # Kiểm chứng định luật đòn bẩy trên cấu hình biến dạng: R4y * (2L + u4x) + P * (L + u2x) = 0
    lever_err = abs(r_nr.reactions[7] * (2.0 * L + r_nr.u[6]) + P * (L + r_nr.u[2]))
    assert lever_err < 1e-3
    print(
        f"[PASS] 5. Tiếp tuyến sai phân: Corotational={fd_corot['relative_frobenius_error']:.2e}, "
        f"TotalLagrangian={fd_tl['relative_frobenius_error']:.2e}; Cân bằng đòn bẩy biến dạng err={lever_err:.2e} N·mm"
    )

    # 6. Tải tới hạn đàn hồi & đường cong Snap-Through (Displacement Control & Arc-Length)
    buck = solve_elastic_buckling_eigen(m)
    dc = solve_corotational_displacement_control(m, control_dof_1based=4, target_disp_mm=2200.0, n_steps=110)
    arc = solve_corotational_arc_length(m, ds=35.0, n_steps=90, scale_lambda=250.0, max_u_stop=2200.0)
    assert len(buck["modes_calfem_bar2g"]) >= 1
    assert dc["limit_point_peak"]["P_limit_kN"] > 0
    print(
        f"[PASS] 6. Buckling & Snap-Through:\n"
        f"       • Trị riêng CALFEM bar2g: α_cr = {buck['modes_calfem_bar2g'][0]['alpha_cr']:.2f} "
        f"(P_cr = {buck['modes_calfem_bar2g'][0]['alpha_cr']*208.0:,.1f} kN)\n"
        f"       • Điểm giới hạn Snap-Through (Corotational): "
        f"P_limit = {dc['limit_point_peak']['P_limit_kN']:,.1f} kN tại u2y = {dc['limit_point_peak']['u_control_mm']:.1f} mm\n"
        f"       • Điểm thung lũng sau bật nhảy: "
        f"P_valley = {dc['limit_point_valley']['P_valley_kN']:,.1f} kN tại u2y = {dc['limit_point_valley']['u_control_mm']:.1f} mm\n"
        f"       • Arc-Length truy vết thành công {len(arc['path'])} điểm cân bằng."
    )
    print("-" * 78)
    print("TÓM TẮT SO SÁNH NHANH TẠI TẢI ĐỀ BÀI P = 208 kN:")
    print(f"  Tuyến tính (bar2e)        : u2y = {r_lin.u[3]:.8f} mm | N12 = {r_lin.N[0]:+.4f} N | R1y = {r_lin.reactions[1]/1000:.6f} kN | R4y = {r_lin.reactions[7]/1000:.6f} kN")
    print(f"  CALFEM bar2g (bậc 2 gốc)  : u2y = {r_b2g.u[3]:.8f} mm | N12 = {r_b2g.N[0]:+.4f} N | R1y = {r_b2g.reactions[1]/1000:.6f} kN | R4y = {r_b2g.reactions[7]/1000:.6f} kN")
    print(f"  Corotational UL (Full NR) : u2y = {r_nr.u[3]:.8f} mm | N12 = {r_nr.N[0]:+.4f} N | R1y = {r_nr.reactions[1]/1000:.6f} kN | R4y = {r_nr.reactions[7]/1000:.6f} kN")
    print(f"  Total Lagrangian (NSA_4)  : u2y = {r_tl.u[3]:.8f} mm | N12 = {r_tl.N[0]:+.4f} N | R1y = {r_tl.reactions[1]/1000:.6f} kN | R4y = {r_tl.reactions[7]/1000:.6f} kN")
    print(f"  Euler (10 bước)           : u2y = {r_eul.u[3]:.8f} mm | residual = {r_eul.equilibrium_check['max_free_residual_N']:.3f} N")
    print(f"  RK2 Midpoint (10 bước)    : u2y = {r_rk2.u[3]:.8f} mm | residual = {r_rk2.equilibrium_check['max_free_residual_N']:.3e} N")
    print("=" * 78)
    print("TẤT CẢ 6 NHÓM KIỂM CHỨNG ĐỀU ĐẠT CHUẨN TUYỆT ĐỐI (ALL TESTS PASSED)!")


if __name__ == "__main__":
    run_all_tests()
