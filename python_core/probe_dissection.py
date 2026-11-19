# -*- coding: utf-8 -*-
"""
================================================================================
MÔ-ĐUN 4: KHẢO SÁT TẠI VỊ TRÍ BẤT KỲ & "PHẪU THUẬT" MẶT CẮT NGANG / DỌC 3D
================================================================================
Mục đích:
  Đáp ứng yêu cầu chuyên sâu về mô phỏng kỹ thuật tương đương ANSYS Mechanical:
    1. `probe_member_at(...)`: Cho phép người dùng chọn BẤT KỲ thanh nào và
       BẤT KỲ tọa độ chuẩn hóa ξ ∈ [0, 1] dọc theo chiều dài thanh (kể cả tọa độ
       nội bộ (η, ζ) bên trong mặt cắt ngang) để truy xuất tức thì:
         - Tọa độ trước và sau biến dạng (X0, Y0) -> (x, y)
         - Chuyển vị nội suy tuyến tính u_x(ξ), u_y(ξ) và chuyển vị tổng ||u||
           (theo hàm dạng N1(ξ)=1-ξ, N2(ξ)=ξ trong NSA_2 Slides 26-29)
         - Biến dạng dọc trục ε_xx và biến dạng co/nở ngang do hiệu ứng Poisson:
           ε_yy = ε_zz = -ν * ε_xx (NSA_2 Slide 9; Hibbeler Mechanics Mục 3.6)
         - Ứng suất pháp σ_xx, ứng suất tương đương von Mises σ_vM = |σ_xx|,
           ứng suất chính (σ_1, σ_2, σ_3) và ứng suất cắt cực đại τ_max = |σ_xx|/2
           (vòng tròn Mohr cho trạng thái ứng suất đơn trục – Hibbeler Mục 9.3)
         - Mật độ năng lượng biến dạng đàn hồi u_0 = (1/2) * σ_xx * ε_xx (mJ/cm³)
         - Góc xoay vật rắn của thanh Δθ = θ_cur - θ_0 (độ & rad)
         - Độ sai khác giữa Phi tuyến hình học và Tuyến tính tại đúng điểm khảo sát!
    2. `dissect_cross_section(...)`: "Phẫu thuật" (Section Cut) tại vị trí ξ:
         - Cắt mở mặt cắt ngang 3D (I-Section, Ống tròn rỗng, Thanh đặc, Hộp vuông),
         - Tính lưới phân bố ứng suất – biến dạng bên trong tiết diện, kể cả chế độ
           mô phỏng thêm hiệu ứng sai lệch ban đầu bậc hai (P-δ Imperfection theo
           NSA_4 Slide 23-27: DAF = 1 / (1 - |N|/P_Euler)) để người học thấy rõ
           sự khác biệt giữa thanh dàn khớp lý tưởng (ứng suất đều σ = N/A) và
           thanh nén thực tế có độ cong ban đầu e0 (ứng suất lệch hai mép)!
    3. `compute_longitudinal_profile(...)`: "Mổ dọc thanh" dọc từ ξ=0 đến ξ=1.
================================================================================
"""

from __future__ import annotations
from typing import Dict, Any, List, Optional
import math
import numpy as np

from .truss_models import TrussModel
from .nonlinear_solvers import AnalysisResult


def probe_member_at(
    model: TrussModel,
    result_nl: AnalysisResult,
    result_lin: Optional[AnalysisResult],
    elem_index_0based: int,
    xi: float = 0.5,
    eta_norm: float = 0.0,
    zeta_norm: float = 0.0,
    imperfection_ratio: float = 0.0,
) -> Dict[str, Any]:
    """
    Khảo sát ứng xử cơ học đầy đủ tại một điểm bất kỳ bên trong phần tử thanh.

    Tham số:
      model             : mô hình dàn TrussModel.
      result_nl         : kết quả phân tích phi tuyến (hoặc kết quả hiện chọn).
      result_lin        : kết quả phân tích tuyến tính để so sánh trực tiếp tại điểm đó.
      elem_index_0based : chỉ số phần tử (0..n_elems-1).
      xi                : vị trí dọc thanh chuẩn hóa ξ = s / L0 ∈ [0, 1].
      eta_norm          : tọa độ thớ trong mặt cắt theo chiều cao chuẩn hóa ∈ [-1, 1]
                          (0 = trục trung hòa, ±1 = mép trên/dưới tiết diện).
      zeta_norm         : tọa độ thớ theo chiều rộng chuẩn hóa ∈ [-1, 1].
      imperfection_ratio: tỷ số độ lệch ban đầu e0/L (0 = dàn khớp lý tưởng,
                          ví dụ 0.001 = L/1000 để minh họa hiệu ứng P-δ trong phẫu thuật).
    """
    e = int(elem_index_0based)
    xi_c = float(np.clip(xi, 0.0, 1.0))
    eta = float(np.clip(eta_norm, -1.0, 1.0))
    zeta = float(np.clip(zeta_norm, -1.0, 1.0))

    ni, nj = int(model.conn[e, 0]) - 1, int(model.conn[e, 1]) - 1
    p1_0 = model.coords[ni]
    p2_0 = model.coords[nj]
    dx0, dy0 = float(p2_0[0] - p1_0[0]), float(p2_0[1] - p1_0[1])
    L0 = math.hypot(dx0, dy0)
    theta0_rad = math.atan2(dy0, dx0)

    # Chuyển vị 2 đầu thanh từ nghiệm phi tuyến
    u1 = result_nl.u[2 * ni : 2 * ni + 2]
    u2 = result_nl.u[2 * nj : 2 * nj + 2]
    p1_c = p1_0 + u1
    p2_c = p2_0 + u2
    dxc, dyc = float(p2_c[0] - p1_c[0]), float(p2_c[1] - p1_c[1])
    l_cur = math.hypot(dxc, dyc)
    theta_cur_rad = math.atan2(dyc, dxc)
    dtheta_rad = math.atan2(math.sin(theta_cur_rad - theta0_rad), math.cos(theta_cur_rad - theta0_rad))

    # Nội suy hàm dạng tuyến tính N1 = 1 - ξ, N2 = ξ (NSA_2 Slide 27-28)
    N1, N2 = 1.0 - xi_c, xi_c
    pos0 = N1 * p1_0 + N2 * p2_0
    disp = N1 * u1 + N2 * u2
    pos_cur = pos0 + disp
    disp_mag = float(np.hypot(disp[0], disp[1]))

    # Nội lực, ứng suất, biến dạng dọc trục & ngang Poisson
    N_e = float(result_nl.N[e])
    A_e = float(model.areas[e])
    sigma_axial = float(result_nl.stress[e])
    eps_axial = float(result_nl.strain[e])
    eps_transverse = -model.nu * eps_axial

    # Kích thước tiết diện 3D tương ứng diện tích A_e
    sec_dims = model.section_spec(e).dimensions()
    h_sec = sec_dims["height"]
    b_sec = sec_dims["width"]
    I_major = sec_dims["I_major"]
    P_euler = (math.pi ** 2) * model.E * sec_dims["I_minor"] / (L0 ** 2)

    # Ứng suất uốn phụ bậc hai (chỉ khác 0 khi người dùng bật chế độ khảo sát độ lệch e0 > 0)
    y_fiber = 0.5 * h_sec * eta
    sigma_bend = 0.0
    daf = 1.0
    if imperfection_ratio > 0.0 and abs(N_e) > 1e-6:
        e0 = imperfection_ratio * L0
        # Công thức khuếch đại bậc hai (NSA_4 Slide 26-27): DAF = 1 / (1 - |N|/P_cr) khi nén
        if N_e < 0.0:
            ratio_cr = min(0.95, abs(N_e) / max(1.0, P_euler))
            daf = 1.0 / (1.0 - ratio_cr)
        else:
            daf = 1.0 / (1.0 + abs(N_e) / max(1.0, P_euler))
        # Dạng võng hình sin dọc thanh: δ(ξ) = e0 * DAF * sin(π*ξ)
        M_sec = abs(N_e) * e0 * daf * math.sin(math.pi * xi_c)
        # Mép chịu nén thêm khi η > 0 (nếu N < 0)
        sign_bend = -1.0 if N_e < 0.0 else 1.0
        sigma_bend = sign_bend * (M_sec * y_fiber / max(1e-9, I_major))

    sigma_xx = sigma_axial + sigma_bend
    eps_xx_local = sigma_xx / model.E
    eps_yy_local = -model.nu * eps_xx_local
    sigma_vm = abs(sigma_xx)
    tau_max = 0.5 * abs(sigma_xx)
    sigma_p1 = max(sigma_xx, 0.0)
    sigma_p3 = min(sigma_xx, 0.0)
    strain_energy_density = 0.5 * sigma_xx * eps_xx_local  # N·mm / mm³ = MPa = mJ/mm³

    # So sánh trực tiếp với Tuyến tính tại đúng vị trí (e, ξ)
    comparison_lin = {}
    if result_lin is not None:
        u1_l = result_lin.u[2 * ni : 2 * ni + 2]
        u2_l = result_lin.u[2 * nj : 2 * nj + 2]
        disp_l = N1 * u1_l + N2 * u2_l
        disp_mag_l = float(np.hypot(disp_l[0], disp_l[1]))
        sigma_l = float(result_lin.stress[e])
        N_l = float(result_lin.N[e])
        comparison_lin = {
            "N_linear_kN": N_l / 1000.0,
            "delta_N_N": N_e - N_l,
            "stress_linear_MPa": sigma_l,
            "delta_stress_MPa": sigma_axial - sigma_l,
            "disp_linear_mm": [float(disp_l[0]), float(disp_l[1])],
            "disp_mag_linear_mm": disp_mag_l,
            "delta_disp_mag_mm": disp_mag - disp_mag_l,
            "pct_disp_diff": (100.0 * (disp_mag - disp_mag_l) / disp_mag_l) if abs(disp_mag_l) > 1e-12 else 0.0,
        }

    state_label = "KÉO (Tension)" if N_e > 1e-3 else ("NÉN (Compression)" if N_e < -1e-3 else "KHÔNG LỰC (Zero-force)")

    return {
        "element_1based": e + 1,
        "member_label": model.member_labels[e],
        "xi": xi_c,
        "s_along_bar_mm": xi_c * L0,
        "L0_mm": L0,
        "l_current_mm": l_cur,
        "elongation_mm": l_cur - L0,
        "theta0_deg": math.degrees(theta0_rad),
        "theta_cur_deg": math.degrees(theta_cur_rad),
        "rotation_delta_deg": math.degrees(dtheta_rad),
        "rotation_delta_mrad": dtheta_rad * 1000.0,
        "coords_initial_mm": [float(pos0[0]), float(pos0[1])],
        "coords_deformed_mm": [float(pos_cur[0]), float(pos_cur[1])],
        "displacement_mm": [float(disp[0]), float(disp[1])],
        "displacement_mag_mm": disp_mag,
        "axial_force_N": N_e,
        "axial_force_kN": N_e / 1000.0,
        "area_mm2": A_e,
        "state": state_label,
        "fiber_eta_norm": eta,
        "fiber_zeta_norm": zeta,
        "fiber_y_mm": y_fiber,
        "fiber_z_mm": 0.5 * b_sec * zeta,
        "sigma_axial_MPa": sigma_axial,
        "sigma_bending_second_order_MPa": sigma_bend,
        "sigma_xx_MPa": sigma_xx,
        "sigma_von_mises_MPa": sigma_vm,
        "tau_max_mohr_MPa": tau_max,
        "principal_stresses_MPa": [sigma_p1, 0.0, sigma_p3],
        "eps_xx_microstrain": eps_xx_local * 1e6,
        "eps_yy_poisson_microstrain": eps_yy_local * 1e6,
        "eps_zz_poisson_microstrain": eps_yy_local * 1e6,
        "strain_energy_density_kJ_per_m3": strain_energy_density * 1000.0,
        "utilization_vs_fy_pct": 100.0 * sigma_vm / model.fy_reference_mpa,
        "imperfection_DAF": daf,
        "P_euler_local_kN": P_euler / 1000.0,
        "section_shape": model.section_shape,
        "section_dimensions_mm": sec_dims,
        "comparison_linear": comparison_lin,
    }


def dissect_cross_section(
    model: TrussModel,
    result_nl: AnalysisResult,
    elem_index_0based: int,
    xi: float = 0.5,
    grid_n: int = 11,
    imperfection_ratio: float = 0.0,
) -> Dict[str, Any]:
    """
    Thực hiện "PHẪU THUẬT MẶT CẮT NGANG" tại vị trí ξ trên phần tử e:
    Tạo lưới điểm (η, ζ) bên trong mặt cắt ngang (có kiểm tra điểm thuộc phần thịt
    vật liệu của tiết diện chữ I, ống tròn, hộp vuông hay thanh đặc) cùng giá trị
    ứng suất σ_xx, biến dạng dọc ε_xx, co giãn ngang Poisson (Δy, Δz).
    """
    e = int(elem_index_0based)
    dims = model.section_spec(e).dimensions()
    shape = model.section_shape
    h = dims["height"]
    b = dims["width"]

    samples: List[Dict[str, float]] = []
    # Lùi biên nhẹ (0.94) để tâm các ô mẫu nằm gọn hoàn toàn bên trong đường viền vật liệu
    coords_1d = np.linspace(-0.94, 0.94, grid_n)
    for eta in coords_1d:
        for zeta in coords_1d:
            y = 0.5 * h * float(eta)
            z = 0.5 * b * float(zeta)
            inside = False
            if shape == "SOLID_ROD":
                inside = (eta ** 2 + zeta ** 2) <= 0.94 ** 2
            elif shape == "CIRC_TUBE":
                r2 = eta ** 2 + zeta ** 2
                inside = (0.85 ** 2) <= r2 <= (0.96 ** 2)
            elif shape == "BOX_SECTION":
                inside = (abs(eta) >= 0.78) or (abs(zeta) >= 0.78)
            else:  # I_SECTION
                in_flange = abs(eta) >= 0.78
                in_web = abs(zeta) <= 0.09
                inside = in_flange or in_web

            if not inside:
                continue

            p = probe_member_at(
                model,
                result_nl,
                None,
                elem_index_0based=e,
                xi=xi,
                eta_norm=float(eta),
                zeta_norm=float(zeta),
                imperfection_ratio=imperfection_ratio,
            )
            samples.append(
                {
                    "eta": float(eta),
                    "zeta": float(zeta),
                    "y_mm": y,
                    "z_mm": z,
                    "sigma_xx_MPa": p["sigma_xx_MPa"],
                    "eps_xx_microstrain": p["eps_xx_microstrain"],
                    "eps_poisson_microstrain": p["eps_yy_poisson_microstrain"],
                }
            )

    sigmas = [s["sigma_xx_MPa"] for s in samples] or [0.0]
    return {
        "element_1based": e + 1,
        "member_label": model.member_labels[e],
        "xi": float(xi),
        "section_shape": shape,
        "dimensions_mm": dims,
        "sigma_min_MPa": float(min(sigmas)),
        "sigma_max_MPa": float(max(sigmas)),
        "samples": samples,
    }


def compute_longitudinal_profile(
    model: TrussModel,
    result_nl: AnalysisResult,
    result_lin: Optional[AnalysisResult],
    elem_index_0based: int,
    n_stations: int = 21,
    imperfection_ratio: float = 0.0,
) -> List[Dict[str, Any]]:
    """
    "Mổ dọc thanh" (Longitudinal Cutaway): tính biến thiên chuyển vị, ứng suất mép
    trên/trục trung hòa/mép dưới dọc từ đầu thanh (ξ=0) tới cuối thanh (ξ=1).
    """
    stations = []
    for xi in np.linspace(0.0, 1.0, n_stations):
        p_center = probe_member_at(model, result_nl, result_lin, elem_index_0based, float(xi), 0.0, 0.0, imperfection_ratio)
        p_top = probe_member_at(model, result_nl, None, elem_index_0based, float(xi), 1.0, 0.0, imperfection_ratio)
        p_bot = probe_member_at(model, result_nl, None, elem_index_0based, float(xi), -1.0, 0.0, imperfection_ratio)
        stations.append(
            {
                "xi": float(xi),
                "s_mm": p_center["s_along_bar_mm"],
                "u_mag_mm": p_center["displacement_mag_mm"],
                "ux_mm": p_center["displacement_mm"][0],
                "uy_mm": p_center["displacement_mm"][1],
                "sigma_center_MPa": p_center["sigma_xx_MPa"],
                "sigma_top_MPa": p_top["sigma_xx_MPa"],
                "sigma_bottom_MPa": p_bot["sigma_xx_MPa"],
                "eps_microstrain": p_center["eps_xx_microstrain"],
            }
        )
    return stations
