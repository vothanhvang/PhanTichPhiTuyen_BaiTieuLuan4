# -*- coding: utf-8 -*-
"""
================================================================================
MÔ-ĐUN 3: CÁC THUẬT TOÁN GIẢI HỆ PHƯƠNG TRÌNH PHI TUYẾN & TẢI TỚI HẠN ĐÀN HỒI
================================================================================
Cài đặt đầy đủ hệ thống thuật toán trong Bài giảng NSA_4, NSA_6 (PGS.TS. Ngô Hữu
Cường) và Giáo trình McGuire, Gallagher & Ziemian (2000, Chương 9 & Chương 12),
Olsson & Dahlblom (2016, Chương 9):

  1. `solve_linear_calfem`                     : Tuyến tính bậc 1 (CALFEM `bar2e` + `bar2s`)
  2. `solve_calfem_bar2g_second_order`         : Phi tuyến bậc 2 CALFEM gốc (`bar2g` cố định
                                                 tọa độ gốc, lặp lực dọc theo Dahlblom PT 9.1-9.3)
  3. `solve_corotational_newton_raphson`       : Phi tuyến hình học chuyển vị lớn Corotational UL
                                                 + Newton-Raphson đầy đủ (NSA_6 Mục 6.3.1)
  4. `solve_corotational_modified_nr`          : Corotational UL + Newton-Raphson cải tiến
                                                 Modified NR giữ [K_i^0] (NSA_6 Mục 6.3.4)
  5. `solve_corotational_euler`                : Corotational UL + Euler bước đơn (NSA_6 Mục 6.2)
  6. `solve_corotational_rk2`                  : Corotational UL + Runge-Kutta bậc 2 điểm giữa
                                                 (NSA_6 Mục 6.2, McGuire Mục 12.2.2)
  7. `solve_corotational_displacement_control` : Corotational UL + Điều khiển chuyển vị
                                                 (NSA_6 Mục 6.3.2, vượt qua điểm giới hạn!)
  8. `solve_corotational_arc_length`           : Corotational UL + Chiều dài cung (Constant
                                                 Arc-Length Crisfield/Riks, NSA_6 Mục 6.3.3,
                                                 truy vết cả nhánh Snap-Through & Snap-Back!)
  9. `solve_total_lagrangian_nr`               : Total Lagrangian biến dạng Green-Lagrange
                                                 (NSA_4 Slides 6-12, McGuire PT 9.1-9.9)
 10. `solve_elastic_buckling_eigen`            : Bài toán trị riêng tìm tải tới hạn đàn hồi
                                                 (Ke + α_cr * Kg) φ = 0 (NSA_4 Mục 4.2,
                                                 Dahlblom PT 9.4-9.7, McGuire PT 12.36-12.37)
 11. `verify_tangent_finite_difference`        : Kiểm chứng độc lập ma trận độ cứng tiếp tuyến Kt
                                                 bằng đạo hàm sai phân trung tâm.
================================================================================
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import List, Dict, Any, Tuple
import math
import numpy as np
from scipy.linalg import eig

from .calfem_elements import (
    bar2e,
    bar2g,
    bar2g_split,
    bar2s,
    assem,
    solveq,
    extract,
    bar2g_corotational,
    bar2g_total_lagrangian,
)
from .truss_models import TrussModel


@dataclass
class AnalysisResult:
    """Cấu trúc chứa trọn vẹn kết quả của một lần phân tích kết cấu."""

    method_name: str
    formulation: str
    converged: bool
    u: np.ndarray                         # (ndof,) chuyển vị nút (mm)
    reactions: np.ndarray                 # (ndof,) phản lực gối & phần dư (N)
    N: np.ndarray                         # (nelem,) lực dọc trục từng thanh (N)
    stress: np.ndarray                    # (nelem,) ứng suất pháp trung bình σ = N/A (MPa)
    strain: np.ndarray                    # (nelem,) biến dạng dọc trục ε
    elongation: np.ndarray                # (nelem,) độ dãn dài ΔL = l - L0 (mm)
    current_lengths: np.ndarray           # (nelem,) chiều dài hiện tại l (mm)
    member_energy: np.ndarray             # (nelem,) năng lượng biến dạng từng thanh (N·mm)
    total_energy: float                   # Tổng năng lượng biến dạng U (N·mm)
    K_final: np.ndarray                   # Ma trận độ cứng tổng thể tại bước cuối (N/mm)
    Ke_final: np.ndarray                  # Thành phần độ cứng đàn hồi (N/mm)
    Kg_final: np.ndarray                  # Thành phần độ cứng hình học (N/mm)
    equilibrium_check: Dict[str, float]   # Kiểm tra ∑Fx, ∑Fy, ∑M trên cấu hình tương ứng
    history: List[Dict[str, Any]] = field(default_factory=list)
    extra: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Chuyển sang từ điển JSON-friendly để truyền sang Flutter hoặc lưu file."""
        return {
            "method_name": self.method_name,
            "formulation": self.formulation,
            "converged": bool(self.converged),
            "u_mm": self.u.tolist(),
            "reactions_N": self.reactions.tolist(),
            "N_N": self.N.tolist(),
            "stress_MPa": self.stress.tolist(),
            "strain": self.strain.tolist(),
            "elongation_mm": self.elongation.tolist(),
            "current_lengths_mm": self.current_lengths.tolist(),
            "member_energy_Nmm": self.member_energy.tolist(),
            "total_energy_Nmm": float(self.total_energy),
            "equilibrium_check": {k: float(v) for k, v in self.equilibrium_check.items()},
            "history": self.history,
            "extra": self.extra,
        }


def _compute_equilibrium_check(
    model: TrussModel,
    u: np.ndarray,
    reactions: np.ndarray,
    f_ext: np.ndarray,
    use_deformed_coords: bool,
) -> Dict[str, float]:
    """
    Kiểm tra 3 phương trình cân bằng tĩnh học toàn hệ (∑Fx = 0, ∑Fy = 0, ∑M_O = 0).
    Lưu ý bản chất cơ học:
      - Trong phân tích TUYẾN TÍNH (bậc 1): mô-men viết trên tọa độ BAN ĐẦU X.
      - Trong phân tích PHI TUYẾN HÌNH HỌC: mô-men PHẢI viết trên tọa độ BIẾN DẠNG x = X + u!
    """
    coords_eval = model.coords + u.reshape(-1, 2) if use_deformed_coords else model.coords
    # Tổng ngoại lực tác dụng lên các nút = tải ngoài f_ext + phản lực gối reactions
    total_nodal = (f_ext + reactions).reshape(-1, 2)
    sum_fx = float(np.sum(total_nodal[:, 0]))
    sum_fy = float(np.sum(total_nodal[:, 1]))
    sum_m = float(
        np.sum(coords_eval[:, 0] * total_nodal[:, 1] - coords_eval[:, 1] * total_nodal[:, 0])
    )
    free_res = float(np.max(np.abs(reactions[model.free_dofs_0based])))
    return {
        "sum_Fx_N": sum_fx,
        "sum_Fy_N": sum_fy,
        "sum_M_Nmm": sum_m,
        "max_free_residual_N": free_res,
    }


def assemble_nonlinear_state(
    model: TrussModel,
    u: np.ndarray,
    formulation: str = "corotational",
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    Hàm lắp ráp nội lực toàn cục f_int và ma trận độ cứng tiếp tuyến Kt = Ke + Kg
    tại véc-tơ chuyển vị hiện tại `u`.

    Tham số `formulation`:
      - "corotational"      : CALFEM đồng chuyển động (bar2g trên cấu hình biến dạng hiện tại,
                              biến dạng kỹ thuật ε = (l - L0)/L0).
      - "total_lagrangian"  : Total Lagrangian (biến dạng Green-Lagrange theo NSA_4 Slides 6-12).
    """
    nd = model.n_dofs
    ne = model.n_elems
    f_int = np.zeros(nd, dtype=float)
    Kt = np.zeros((nd, nd), dtype=float)
    Ke_glob = np.zeros((nd, nd), dtype=float)
    Kg_glob = np.zeros((nd, nd), dtype=float)
    N = np.zeros(ne, dtype=float)
    strains = np.zeros(ne, dtype=float)
    lengths = np.zeros(ne, dtype=float)
    energies = np.zeros(ne, dtype=float)

    ed_all = extract(model.edof, u)
    elem_fn = bar2g_corotational if formulation == "corotational" else bar2g_total_lagrangian

    for e in range(ne):
        ex0, ey0 = model.element_coords(e)
        fe_int, kt_e, ke_e, kg_e, N_e, eps_e, l_e, en_e = elem_fn(
            ex0, ey0, (model.E, model.areas[e]), ed_all[e]
        )
        idx = model.edof[e, 1:] - 1
        f_int[idx] += fe_int
        Kt[np.ix_(idx, idx)] += kt_e
        Ke_glob[np.ix_(idx, idx)] += ke_e
        Kg_glob[np.ix_(idx, idx)] += kg_e
        N[e] = N_e
        strains[e] = eps_e
        lengths[e] = l_e
        energies[e] = en_e

    return f_int, Kt, Ke_glob, Kg_glob, N, strains, lengths, energies


# ==============================================================================
# 1. PHÂN TÍCH ĐÀN HỒI TUYẾN TÍNH BẬC 1 (CALFEM bar2e + assem + solveq + bar2s)
# ==============================================================================
def solve_linear_calfem(model: TrussModel, load_factor: float = 1.0) -> AnalysisResult:
    """
    Giải bài toán dàn phẳng đàn hồi tuyến tính bậc 1 theo đúng quy trình chuẩn
    CALFEM 3.4: bar2e -> assem -> solveq -> extract -> bar2s.
    """
    nd = model.n_dofs
    ne = model.n_elems
    K = np.zeros((nd, nd), dtype=float)
    f = load_factor * model.f_ref.copy()

    for e in range(ne):
        ex, ey = model.element_coords(e)
        Ke = bar2e(ex, ey, (model.E, model.areas[e]))
        K = assem(model.edof[e], K, Ke)

    u, reactions = solveq(K, f, model.bc)
    ed = extract(model.edof, u)
    L0, _, _ = model.initial_lengths_and_cosines()

    N = np.zeros(ne, dtype=float)
    for e in range(ne):
        ex, ey = model.element_coords(e)
        N[e] = bar2s(ex, ey, (model.E, model.areas[e]), ed[e])

    stress = N / model.areas
    strain = stress / model.E
    elongation = strain * L0
    member_energy = 0.5 * (N ** 2) * L0 / (model.E * model.areas)
    U = float(np.sum(member_energy))

    eq = _compute_equilibrium_check(model, u, reactions, f, use_deformed_coords=False)
    Kff = K[np.ix_(model.free_dofs_0based, model.free_dofs_0based)]
    return AnalysisResult(
        method_name="Đàn hồi Tuyến tính Bậc 1 (CALFEM bar2e)",
        formulation="linear_first_order",
        converged=True,
        u=u,
        reactions=reactions,
        N=N,
        stress=stress,
        strain=strain,
        elongation=elongation,
        current_lengths=L0 + elongation,
        member_energy=member_energy,
        total_energy=U,
        K_final=K,
        Ke_final=K.copy(),
        Kg_final=np.zeros_like(K),
        equilibrium_check=eq,
        history=[{"step": 1, "lambda": float(load_factor), "iterations": 1, "u_max_mm": float(np.max(np.abs(u)))}],
        extra={
            "rank_Kff": int(np.linalg.matrix_rank(Kff)),
            "cond_Kff": float(np.linalg.cond(Kff)),
            "det_Kff": float(np.linalg.det(Kff)),
        },
    )


# ==============================================================================
# 2. PHÂN TÍCH PHI TUYẾN BẬC 2 CHUẨN CALFEM (bar2g CỐ ĐỊNH TỌA ĐỘ BAN ĐẦU)
# ==============================================================================
def solve_calfem_bar2g_second_order(
    model: TrussModel,
    load_factor: float = 1.0,
    tol_rel: float = 1e-10,
    max_iter: int = 50,
) -> AnalysisResult:
    """
    Giải bài toán phi tuyến hình học bậc 2 theo ĐÚNG quy trình gốc của sách
    Olsson & Dahlblom (2016, Chương 9, Mục 9.1 PT 9.1-9.3 & Example 9.1 tr. 260-261)
    và CALFEM 3.4 (`bar2g` + `assem` + `solveq` + `extract` + `bar2s`, tương tự `exn1.m`).

    Các bước lặp:
      - Khởi tạo lực dọc N^(0) = 0 -> giải bước 1 (chính là nghiệm tuyến tính).
      - Ở vòng lặp k = 1, 2, ...:
          1) Với mỗi thanh e, gọi bar2g(ex0, ey0, [E, A_e], N_e^(k-1)) tạo K_e = K_e0 + K_eσ.
          2) Lắp ráp K(N^(k-1)) bằng `assem`.
          3) Giải hệ K(N^(k-1)) * a^(k) = f bằng `solveq`.
          4) Tính lại lực dọc mới N^(k) bằng `bar2s`.
          5) Dừng khi sai số tương đối ||N^(k) - N^(k-1)|| / max(1, ||N^(k)||) < tol_rel.
    """
    nd = model.n_dofs
    ne = model.n_elems
    f = load_factor * model.f_ref.copy()
    L0, _, _ = model.initial_lengths_and_cosines()

    N_cur = np.zeros(ne, dtype=float)
    history: List[Dict[str, Any]] = []
    converged = False
    u = np.zeros(nd, dtype=float)
    reactions = np.zeros(nd, dtype=float)
    K_tot = np.zeros((nd, nd), dtype=float)
    Ke_tot = np.zeros((nd, nd), dtype=float)
    Kg_tot = np.zeros((nd, nd), dtype=float)

    for it in range(1, max_iter + 1):
        K_tot = np.zeros((nd, nd), dtype=float)
        Ke_tot = np.zeros((nd, nd), dtype=float)
        Kg_tot = np.zeros((nd, nd), dtype=float)
        for e in range(ne):
            ex, ey = model.element_coords(e)
            Ke0, Kg0 = bar2g_split(ex, ey, (model.E, model.areas[e]), N_cur[e])
            K_tot = assem(model.edof[e], K_tot, Ke0 + Kg0)
            Ke_tot = assem(model.edof[e], Ke_tot, Ke0)
            Kg_tot = assem(model.edof[e], Kg_tot, Kg0)

        u, reactions = solveq(K_tot, f, model.bc)
        ed = extract(model.edof, u)
        N_next = np.zeros(ne, dtype=float)
        for e in range(ne):
            ex, ey = model.element_coords(e)
            N_next[e] = bar2s(ex, ey, (model.E, model.areas[e]), ed[e])

        diff_N = float(np.linalg.norm(N_next - N_cur))
        denom = max(1.0, float(np.linalg.norm(N_next)))
        rel_err = diff_N / denom
        history.append(
            {
                "iteration": it,
                "u_mm": u.tolist(),
                "N_N": N_next.tolist(),
                "rel_err_N": rel_err,
            }
        )
        N_cur = N_next
        if it > 1 and rel_err < tol_rel:
            converged = True
            break

    # Lắp ráp lại K tại N hội tụ cuối cùng
    K_tot = np.zeros((nd, nd), dtype=float)
    Ke_tot = np.zeros((nd, nd), dtype=float)
    Kg_tot = np.zeros((nd, nd), dtype=float)
    for e in range(ne):
        ex, ey = model.element_coords(e)
        Ke0, Kg0 = bar2g_split(ex, ey, (model.E, model.areas[e]), N_cur[e])
        K_tot = assem(model.edof[e], K_tot, Ke0 + Kg0)
        Ke_tot = assem(model.edof[e], Ke_tot, Ke0)
        Kg_tot = assem(model.edof[e], Kg_tot, Kg0)
    reactions = K_tot @ u - f

    stress = N_cur / model.areas
    strain = stress / model.E
    elongation = strain * L0
    member_energy = 0.5 * (N_cur ** 2) * L0 / (model.E * model.areas)
    eq = _compute_equilibrium_check(model, u, reactions, f, use_deformed_coords=False)

    return AnalysisResult(
        method_name="Phi tuyến Bậc 2 CALFEM gốc (bar2g tọa độ ban đầu)",
        formulation="calfem_bar2g_second_order",
        converged=converged,
        u=u,
        reactions=reactions,
        N=N_cur,
        stress=stress,
        strain=strain,
        elongation=elongation,
        current_lengths=L0 + elongation,
        member_energy=member_energy,
        total_energy=float(np.sum(member_energy)),
        K_final=K_tot,
        Ke_final=Ke_tot,
        Kg_final=Kg_tot,
        equilibrium_check=eq,
        history=history,
        extra={"iterations": len(history)},
    )


# ==============================================================================
# 3. PHI TUYẾN HÌNH HỌC CHUYỂN VỊ LỚN: NEWTON-RAPHSON ĐẦY ĐỦ (ĐIỀU KHIỂN LỰC)
#    Nguồn: Bài giảng NSA_6, Mục 6.3.1 (Slides 10-14); McGuire Mục 12.3.1
# ==============================================================================
def _solve_full_nr_core(
    model: TrussModel,
    formulation: str,
    method_label: str,
    load_factor: float = 1.0,
    n_steps: int = 10,
    tol_force: float = 1e-7,
    tol_disp: float = 1e-10,
    max_iter: int = 40,
) -> AnalysisResult:
    """Hàm lõi Newton-Raphson điều khiển lực dùng chung cho Corotational UL và Total Lagrangian."""
    nd = model.n_dofs
    free = model.free_dofs_0based
    L0, _, _ = model.initial_lengths_and_cosines()

    u = np.zeros(nd, dtype=float)
    f_target = model.f_ref.copy()
    lambdas = np.linspace(load_factor / n_steps, load_factor, n_steps)
    history: List[Dict[str, Any]] = []
    # Ghi nhận trạng thái khởi đầu λ = 0
    history.append(
        {
            "step": 0,
            "lambda": 0.0,
            "iterations": 0,
            "residual_inf_N": 0.0,
            "disp_norm_rel": 0.0,
            "u_mm": u.tolist(),
            "N_N": [0.0] * model.n_elems,
            "iter_trace": [],
        }
    )

    all_converged = True
    f_int = np.zeros(nd)
    Kt = np.zeros((nd, nd))
    Ke_glob = np.zeros((nd, nd))
    Kg_glob = np.zeros((nd, nd))
    N = np.zeros(model.n_elems)
    strains = np.zeros(model.n_elems)
    lengths = L0.copy()
    energies = np.zeros(model.n_elems)

    for step_idx, lam in enumerate(lambdas, start=1):
        f_ext = lam * f_target
        step_converged = False
        iter_trace = []
        res_inf = 0.0
        disp_rel = 0.0
        n_it = 0

        for it in range(1, max_iter + 1):
            n_it = it
            f_int, Kt, Ke_glob, Kg_glob, N, strains, lengths, energies = assemble_nonlinear_state(
                model, u, formulation=formulation
            )
            R = f_ext - f_int
            res_inf = float(np.max(np.abs(R[free])))
            iter_trace.append({"iter": it, "residual_inf_N": res_inf})

            if res_inf < tol_force:
                step_converged = True
                break

            Kt_ff = Kt[np.ix_(free, free)]
            du_f = np.linalg.solve(Kt_ff, R[free])
            u[free] += du_f

            u_ref = max(1e-12, float(np.max(np.abs(u[free]))))
            disp_rel = float(np.max(np.abs(du_f)) / u_ref)
            # Kiểm tra lại phần dư sau khi cập nhật u
            f_int, Kt, Ke_glob, Kg_glob, N, strains, lengths, energies = assemble_nonlinear_state(
                model, u, formulation=formulation
            )
            R = f_ext - f_int
            res_inf = float(np.max(np.abs(R[free])))
            iter_trace[-1]["after_residual_inf_N"] = res_inf
            iter_trace[-1]["disp_norm_rel"] = disp_rel

            if res_inf < tol_force and disp_rel < tol_disp:
                step_converged = True
                break

        if not step_converged:
            all_converged = False
            break

        history.append(
            {
                "step": step_idx,
                "lambda": float(lam),
                "iterations": n_it,
                "residual_inf_N": float(res_inf),
                "disp_norm_rel": float(disp_rel),
                "u_mm": u.tolist(),
                "N_N": N.tolist(),
                "iter_trace": iter_trace,
            }
        )

    f_final = load_factor * f_target
    reactions = f_int - f_final
    stress = N / model.areas
    elongation = lengths - L0
    eq = _compute_equilibrium_check(model, u, reactions, f_final, use_deformed_coords=True)

    return AnalysisResult(
        method_name=method_label,
        formulation=formulation,
        converged=all_converged,
        u=u,
        reactions=reactions,
        N=N,
        stress=stress,
        strain=strains,
        elongation=elongation,
        current_lengths=lengths,
        member_energy=energies,
        total_energy=float(np.sum(energies)),
        K_final=Kt,
        Ke_final=Ke_glob,
        Kg_final=Kg_glob,
        equilibrium_check=eq,
        history=history,
        extra={
            "n_steps": n_steps,
            "total_iterations": int(sum(h["iterations"] for h in history)),
            "total_stiffness_factorizations": int(sum(h["iterations"] for h in history)),
        },
    )


def solve_corotational_newton_raphson(
    model: TrussModel,
    load_factor: float = 1.0,
    n_steps: int = 10,
    tol_force: float = 1e-7,
    tol_disp: float = 1e-10,
    max_iter: int = 40,
) -> AnalysisResult:
    """
    Phi tuyến hình học CALFEM Đồng chuyển động (bar2g trên cấu hình hiện tại)
    giải bằng thuật toán Full Newton-Raphson (Điều khiển lực – NSA_6 Mục 6.3.1).
    """
    return _solve_full_nr_core(
        model=model,
        formulation="corotational",
        method_label="Phi tuyến Hình học CALFEM-UL (Full Newton-Raphson)",
        load_factor=load_factor,
        n_steps=n_steps,
        tol_force=tol_force,
        tol_disp=tol_disp,
        max_iter=max_iter,
    )


def solve_total_lagrangian_nr(
    model: TrussModel,
    load_factor: float = 1.0,
    n_steps: int = 10,
    tol_force: float = 1e-7,
    tol_disp: float = 1e-10,
    max_iter: int = 40,
) -> AnalysisResult:
    """
    Phi tuyến hình học Total Lagrangian (biến dạng Green-Lagrange theo NSA_4
    Slides 6-12 & McGuire PT 9.1-9.9) giải bằng Full Newton-Raphson.
    """
    return _solve_full_nr_core(
        model=model,
        formulation="total_lagrangian",
        method_label="Phi tuyến Total Lagrangian (Green-Lagrange – NSA_4)",
        load_factor=load_factor,
        n_steps=n_steps,
        tol_force=tol_force,
        tol_disp=tol_disp,
        max_iter=max_iter,
    )


# ==============================================================================
# 4. NEWTON-RAPHSON CẢI TIẾN (MODIFIED NEWTON-RAPHSON – NSA_6 Mục 6.3.4, Slide 21)
# ==============================================================================
def solve_corotational_modified_nr(
    model: TrussModel,
    load_factor: float = 1.0,
    n_steps: int = 10,
    tol_force: float = 1e-7,
    max_iter: int = 100,
) -> AnalysisResult:
    """
    Thuật toán Newton-Raphson cải tiến (Modified Iterative Technique):
    Giữ nguyên ma trận độ cứng tiếp tuyến đầu bước [K_i^0] cho mọi vòng lặp con
    trong cùng một bước gia tải i (NSA_6, Slide 21; McGuire Mục 12.3.5).
    Ưu điểm: chỉ phân tích ma trận độ cứng 1 lần/bước tải; Nhược điểm: cần nhiều
    vòng lặp con hơn (hội tụ tuyến tính thay vì bậc hai).
    """
    nd = model.n_dofs
    free = model.free_dofs_0based
    L0, _, _ = model.initial_lengths_and_cosines()

    u = np.zeros(nd, dtype=float)
    f_target = model.f_ref.copy()
    lambdas = np.linspace(load_factor / n_steps, load_factor, n_steps)
    history: List[Dict[str, Any]] = [
        {"step": 0, "lambda": 0.0, "iterations": 0, "residual_inf_N": 0.0, "u_mm": u.tolist(), "N_N": [0.0] * model.n_elems}
    ]
    all_converged = True
    f_int = np.zeros(nd)
    Kt = np.zeros((nd, nd))
    Ke_glob = np.zeros((nd, nd))
    Kg_glob = np.zeros((nd, nd))
    N = np.zeros(model.n_elems)
    strains = np.zeros(model.n_elems)
    lengths = L0.copy()
    energies = np.zeros(model.n_elems)
    n_factorizations = 0

    for step_idx, lam in enumerate(lambdas, start=1):
        f_ext = lam * f_target
        # Thiết lập [K_i^0] MỘT LẦN DUY NHẤT ở đầu bước gia tải thứ i
        f_int, Kt_step0, Ke_glob, Kg_glob, N, strains, lengths, energies = assemble_nonlinear_state(
            model, u, formulation="corotational"
        )
        Kt_ff_0 = Kt_step0[np.ix_(free, free)]
        n_factorizations += 1

        step_converged = False
        res_inf = 0.0
        n_it = 0
        for it in range(1, max_iter + 1):
            n_it = it
            R = f_ext - f_int
            res_inf = float(np.max(np.abs(R[free])))
            if res_inf < tol_force:
                step_converged = True
                break
            du_f = np.linalg.solve(Kt_ff_0, R[free])
            u[free] += du_f
            f_int, Kt, Ke_glob, Kg_glob, N, strains, lengths, energies = assemble_nonlinear_state(
                model, u, formulation="corotational"
            )
            res_inf = float(np.max(np.abs((f_ext - f_int)[free])))
            if res_inf < tol_force:
                step_converged = True
                break

        if not step_converged:
            all_converged = False
            break
        history.append(
            {
                "step": step_idx,
                "lambda": float(lam),
                "iterations": n_it,
                "residual_inf_N": float(res_inf),
                "u_mm": u.tolist(),
                "N_N": N.tolist(),
            }
        )

    f_final = load_factor * f_target
    reactions = f_int - f_final
    eq = _compute_equilibrium_check(model, u, reactions, f_final, use_deformed_coords=True)
    return AnalysisResult(
        method_name="Phi tuyến CALFEM-UL (Modified Newton-Raphson – NSA_6 6.3.4)",
        formulation="corotational",
        converged=all_converged,
        u=u,
        reactions=reactions,
        N=N,
        stress=N / model.areas,
        strain=strains,
        elongation=lengths - L0,
        current_lengths=lengths,
        member_energy=energies,
        total_energy=float(np.sum(energies)),
        K_final=Kt,
        Ke_final=Ke_glob,
        Kg_final=Kg_glob,
        equilibrium_check=eq,
        history=history,
        extra={
            "n_steps": n_steps,
            "total_iterations": int(sum(h["iterations"] for h in history)),
            "total_stiffness_factorizations": n_factorizations,
        },
    )


# ==============================================================================
# 5. PHƯƠNG PHÁP GIA TĂNG BƯỚC ĐƠN EULER & RUNGE-KUTTA BẬC 2 (NSA_6 Mục 6.2)
# ==============================================================================
def solve_corotational_euler(
    model: TrussModel, load_factor: float = 1.0, n_steps: int = 10
) -> AnalysisResult:
    """
    Thuật toán gia tăng bước đơn Euler (không lặp khử lực dư):
      [K_i] {dΔ_i} = dλ_i {P_ref}
    Nguồn: Bài giảng NSA_6, Mục 6.2 (Slide 4, 8); McGuire Mục 12.2.1 (tr. 341).
    Minh họa rõ hiện tượng sai số tích lũy (drift error) do không hiệu chỉnh cân bằng.
    """
    nd = model.n_dofs
    free = model.free_dofs_0based
    L0, _, _ = model.initial_lengths_and_cosines()
    u = np.zeros(nd, dtype=float)
    dlam = load_factor / n_steps
    df = dlam * model.f_ref
    history = [{"step": 0, "lambda": 0.0, "residual_inf_N": 0.0, "u_mm": u.tolist(), "N_N": [0.0] * model.n_elems}]

    for step in range(1, n_steps + 1):
        _, Kt, _, _, _, _, _, _ = assemble_nonlinear_state(model, u, "corotational")
        du_f = np.linalg.solve(Kt[np.ix_(free, free)], df[free])
        u[free] += du_f
        f_int, Kt, Ke_glob, Kg_glob, N, strains, lengths, energies = assemble_nonlinear_state(
            model, u, "corotational"
        )
        lam = step * dlam
        res_inf = float(np.max(np.abs((lam * model.f_ref - f_int)[free])))
        history.append(
            {
                "step": step,
                "lambda": float(lam),
                "iterations": 1,
                "residual_inf_N": res_inf,
                "u_mm": u.tolist(),
                "N_N": N.tolist(),
            }
        )

    f_final = load_factor * model.f_ref
    reactions = f_int - f_final
    eq = _compute_equilibrium_check(model, u, reactions, f_final, use_deformed_coords=True)
    return AnalysisResult(
        method_name=f"Gia tăng bước đơn Euler ({n_steps} bước – NSA_6 6.2)",
        formulation="corotational",
        converged=True,
        u=u,
        reactions=reactions,
        N=N,
        stress=N / model.areas,
        strain=strains,
        elongation=lengths - L0,
        current_lengths=lengths,
        member_energy=energies,
        total_energy=float(np.sum(energies)),
        K_final=Kt,
        Ke_final=Ke_glob,
        Kg_final=Kg_glob,
        equilibrium_check=eq,
        history=history,
        extra={"n_steps": n_steps, "total_stiffness_factorizations": n_steps},
    )


def solve_corotational_rk2(
    model: TrussModel, load_factor: float = 1.0, n_steps: int = 10
) -> AnalysisResult:
    """
    Thuật toán gia tăng bước đơn Runge-Kutta bậc 2 điểm giữa (Midpoint RK2):
      Bước dự báo nửa bước: [K(u_i)] {du_1/2} = (1/2) dλ {P_ref}
      Bước chính dùng độ cứng tại điểm giữa: [K(u_i + du_1/2)] {du} = dλ {P_ref}
    Nguồn: Bài giảng NSA_6, Mục 6.2 (Slide 5); McGuire Mục 12.2.2 (tr. 341-344).
    """
    nd = model.n_dofs
    free = model.free_dofs_0based
    L0, _, _ = model.initial_lengths_and_cosines()
    u = np.zeros(nd, dtype=float)
    dlam = load_factor / n_steps
    df = dlam * model.f_ref
    history = [{"step": 0, "lambda": 0.0, "residual_inf_N": 0.0, "u_mm": u.tolist(), "N_N": [0.0] * model.n_elems}]

    for step in range(1, n_steps + 1):
        # 1. Nửa bước dự báo để tìm điểm giữa u_mid
        _, Kt0, _, _, _, _, _, _ = assemble_nonlinear_state(model, u, "corotational")
        du_half = np.linalg.solve(Kt0[np.ix_(free, free)], 0.5 * df[free])
        u_mid = u.copy()
        u_mid[free] += du_half
        # 2. Đánh giá độ cứng tiếp tuyến tại điểm giữa u_mid và tính bước chuyển vị chính
        _, Kt_mid, _, _, _, _, _, _ = assemble_nonlinear_state(model, u_mid, "corotational")
        du_full = np.linalg.solve(Kt_mid[np.ix_(free, free)], df[free])
        u[free] += du_full

        f_int, Kt, Ke_glob, Kg_glob, N, strains, lengths, energies = assemble_nonlinear_state(
            model, u, "corotational"
        )
        lam = step * dlam
        res_inf = float(np.max(np.abs((lam * model.f_ref - f_int)[free])))
        history.append(
            {
                "step": step,
                "lambda": float(lam),
                "iterations": 2,
                "residual_inf_N": res_inf,
                "u_mm": u.tolist(),
                "N_N": N.tolist(),
            }
        )

    f_final = load_factor * model.f_ref
    reactions = f_int - f_final
    eq = _compute_equilibrium_check(model, u, reactions, f_final, use_deformed_coords=True)
    return AnalysisResult(
        method_name=f"Runge-Kutta bậc 2 điểm giữa ({n_steps} bước – NSA_6 6.2)",
        formulation="corotational",
        converged=True,
        u=u,
        reactions=reactions,
        N=N,
        stress=N / model.areas,
        strain=strains,
        elongation=lengths - L0,
        current_lengths=lengths,
        member_energy=energies,
        total_energy=float(np.sum(energies)),
        K_final=Kt,
        Ke_final=Ke_glob,
        Kg_final=Kg_glob,
        equilibrium_check=eq,
        history=history,
        extra={"n_steps": n_steps, "total_stiffness_factorizations": 2 * n_steps},
    )


# ==============================================================================
# 6. PHƯƠNG PHÁP ĐIỀU KHIỂN CHUYỂN VỊ (DISPLACEMENT CONTROL – NSA_6 Mục 6.3.2)
# ==============================================================================
def solve_corotational_displacement_control(
    model: TrussModel,
    control_dof_1based: int = 4,
    target_disp_mm: float = 2200.0,
    n_steps: int = 110,
    tol_force: float = 1e-4,
    max_iter: int = 30,
) -> Dict[str, Any]:
    """
    Thuật toán Điều khiển Chuyển vị (Displacement Control – Batoz & Dhatt / NSA_6
    Mục 6.3.2, Slides 16-17; McGuire Mục 12.3.2, tr. 348).

    Công thức đúng theo Slide 16-17 Bài giảng NSA_6:
      - Giải hai véc-tơ thành phần tại mỗi vòng lặp con j:
          [K_t] {du_bar}    = {P_ref}
          [K_t] {du_double} = {R} = λ {P_ref} - {f_int}
      - Bước con đầu tiên (j=1): chọn dλ_1 = du_prescribed / du_bar[q]
      - Các bước con lặp (j >= 2): giữ chuyển vị tại bậc tự do điều khiển q không đổi:
          du[q] = dλ * du_bar[q] + du_double[q] = 0  =>  dλ = -du_double[q] / du_bar[q]
          {du}  = dλ * {du_bar} + {du_double}

    Ưu điểm: Vượt qua ĐIỂM GIỚI HẠN TẢI (Limit Point / Snap-Through) dễ dàng,
    truy vết được nhánh giảm tải (mất ổn định) và nhánh cứng hóa trở lại!
    """
    nd = model.n_dofs
    free = model.free_dofs_0based
    q_global = control_dof_1based - 1
    q_local = int(np.where(free == q_global)[0][0])

    u = np.zeros(nd, dtype=float)
    lam = 0.0
    du_step = target_disp_mm / n_steps
    f_ref = model.f_ref.copy()

    path: List[Dict[str, Any]] = [
        {
            "step": 0,
            "lambda": 0.0,
            "u_control_mm": 0.0,
            "u_mm": u.tolist(),
            "N_N": [0.0] * model.n_elems,
            "det_Kt": float(np.linalg.det(assemble_nonlinear_state(model, u, "corotational")[1][np.ix_(free, free)])),
            "min_eig_Kt": float(np.min(np.linalg.eigvalsh(assemble_nonlinear_state(model, u, "corotational")[1][np.ix_(free, free)]))),
            "iterations": 0,
        }
    ]

    for step in range(1, n_steps + 1):
        # Bước dự báo (j = 1)
        f_int, Kt, _, _, N, _, _, _ = assemble_nonlinear_state(model, u, "corotational")
        Kt_ff = Kt[np.ix_(free, free)]
        du_bar = np.linalg.solve(Kt_ff, f_ref[free])
        if abs(du_bar[q_local]) < 1e-14:
            break
        dlam = du_step / du_bar[q_local]
        lam += dlam
        u[free] += dlam * du_bar

        # Vòng lặp hiệu chỉnh cân bằng giữ u[q] = const (j >= 2)
        n_it = 1
        for it in range(2, max_iter + 1):
            n_it = it
            f_int, Kt, _, _, N, _, _, _ = assemble_nonlinear_state(model, u, "corotational")
            R = lam * f_ref - f_int
            if float(np.max(np.abs(R[free]))) < tol_force:
                break
            Kt_ff = Kt[np.ix_(free, free)]
            du_bar = np.linalg.solve(Kt_ff, f_ref[free])
            du_double = np.linalg.solve(Kt_ff, R[free])
            dlam_corr = -du_double[q_local] / du_bar[q_local]
            lam += dlam_corr
            u[free] += dlam_corr * du_bar + du_double

        f_int, Kt, _, _, N, _, _, _ = assemble_nonlinear_state(model, u, "corotational")
        Kt_ff = Kt[np.ix_(free, free)]
        eigs = np.linalg.eigvalsh(Kt_ff)
        path.append(
            {
                "step": step,
                "lambda": float(lam),
                "u_control_mm": float(u[q_global]),
                "u_mm": u.tolist(),
                "N_N": N.tolist(),
                "det_Kt": float(np.linalg.det(Kt_ff)),
                "min_eig_Kt": float(np.min(eigs)),
                "iterations": n_it,
            }
        )

    # Tìm điểm giới hạn tải cực đại ĐẦU TIÊN (Local Peak) và điểm thung lũng (Local Valley) sau đỉnh
    lam_vals = np.array([p["lambda"] for p in path])
    u_vals = np.array([p["u_control_mm"] for p in path])
    idx_peak = int(np.argmax(lam_vals))
    for k in range(1, len(lam_vals) - 1):
        if lam_vals[k] > lam_vals[k - 1] and lam_vals[k] >= lam_vals[k + 1] and lam_vals[k] > 0:
            idx_peak = k
            break
    idx_valley = idx_peak
    for k in range(idx_peak + 1, len(lam_vals) - 1):
        if lam_vals[k] <= lam_vals[k - 1] and lam_vals[k] < lam_vals[k + 1]:
            idx_valley = k
            break
    if idx_valley == idx_peak and idx_peak < len(lam_vals) - 1:
        idx_valley = int(idx_peak + np.argmin(lam_vals[idx_peak:]))

    return {
        "method": "Điều khiển chuyển vị (Displacement Control – NSA_6 6.3.2)",
        "control_dof_1based": control_dof_1based,
        "path": path,
        "limit_point_peak": {
            "lambda_limit": float(lam_vals[idx_peak]),
            "P_limit_kN": float(lam_vals[idx_peak] * np.max(np.abs(f_ref)) / 1000.0),
            "u_control_mm": float(u_vals[idx_peak]),
            "step": int(path[idx_peak]["step"]),
        },
        "limit_point_valley": {
            "lambda_valley": float(lam_vals[idx_valley]),
            "P_valley_kN": float(lam_vals[idx_valley] * np.max(np.abs(f_ref)) / 1000.0),
            "u_control_mm": float(u_vals[idx_valley]),
            "step": int(path[idx_valley]["step"]),
        },
    }


# ==============================================================================
# 7. PHƯƠNG PHÁP CHIỀU DÀI CUNG (CONSTANT ARC-LENGTH – NSA_6 Mục 6.3.3, Slides 19-20)
# ==============================================================================
def solve_corotational_arc_length(
    model: TrussModel,
    ds: float = 35.0,
    n_steps: int = 90,
    psi: float = 1.0,
    scale_lambda: float = 100.0,
    max_u_stop: float = 2300.0,
    tol_force: float = 1e-4,
    max_iter: int = 25,
) -> Dict[str, Any]:
    """
    Thuật toán Chiều dài cung (Updated Normal Plane Arc-Length – Ramm / Crisfield,
    Bài giảng NSA_6 Mục 6.3.3, Slides 19-20; McGuire Mục 12.3.4, tr. 349).

    Phương trình ràng buộc mặt phẳng pháp tuyến trực giao (đúng Slide 19-20 NSA_6):
      {dΔ_i^1}^T {dΔ_i^j} + ψ^2 * (s_λ)^2 * dλ_i^1 * dλ_i^j = 0  (j >= 2)
      => dλ_i^j = - ( {dΔ_i^1}^T {du_double} ) / ( {dΔ_i^1}^T {du_bar} + ψ^2 * s_λ^2 * dλ_i^1 )

    Ưu điểm tối thượng:
      Tự động vượt qua CẢ điểm giới hạn tải (Snap-Through) LẪN điểm ngoặt chuyển
      vị (Snap-Back), tự đảo chiều dλ dựa vào dấu tích vô hướng với bước trước!
    """
    nd = model.n_dofs
    free = model.free_dofs_0based
    f_ref = model.f_ref.copy()
    u = np.zeros(nd, dtype=float)
    lam = 0.0

    # Véc-tơ hướng bước trước để giữ tính liên tục chiều đi trên đường cong cân bằng
    prev_du = np.zeros(len(free), dtype=float)
    prev_dlam = 0.0

    # Tìm bậc tự do đặt tải chính để theo dõi
    main_dof = int(np.argmax(np.abs(f_ref)))

    path: List[Dict[str, Any]] = [
        {
            "step": 0,
            "lambda": 0.0,
            "u_main_mm": 0.0,
            "u_mm": u.tolist(),
            "N_N": [0.0] * model.n_elems,
            "min_eig_Kt": float(np.min(np.linalg.eigvalsh(assemble_nonlinear_state(model, u, "corotational")[1][np.ix_(free, free)]))),
            "iterations": 0,
        }
    ]

    for step in range(1, n_steps + 1):
        f_int, Kt, _, _, N, _, _, _ = assemble_nonlinear_state(model, u, "corotational")
        Kt_ff = Kt[np.ix_(free, free)]
        du_bar = np.linalg.solve(Kt_ff, f_ref[free])

        denom_pred = math.sqrt(float(np.dot(du_bar, du_bar)) + (psi * scale_lambda) ** 2)
        dlam_1 = ds / denom_pred

        # Chọn dấu dλ_1 đảm bảo đi tiếp (không quay ngược lại nhánh cũ)
        if step == 1:
            sign_dir = 1.0
        else:
            dot_prev = float(np.dot(prev_du, du_bar * dlam_1)) + (psi * scale_lambda) ** 2 * prev_dlam * dlam_1
            sign_dir = 1.0 if dot_prev >= 0.0 else -1.0

        dlam_1 *= sign_dir
        du_1 = dlam_1 * du_bar

        u_step = u.copy()
        u_step[free] += du_1
        lam_step = lam + dlam_1

        # Lưu tích lũy gia tăng của bước hiện tại (Δu_i, Δλ_i) cho Updated Normal Plane
        Delta_u = du_1.copy()
        Delta_lam = dlam_1

        n_it = 1
        converged_step = False
        for it in range(2, max_iter + 1):
            n_it = it
            f_int, Kt, _, _, N, _, _, _ = assemble_nonlinear_state(model, u_step, "corotational")
            R = lam_step * f_ref - f_int
            if float(np.max(np.abs(R[free]))) < tol_force:
                converged_step = True
                break
            Kt_ff = Kt[np.ix_(free, free)]
            du_bar_j = np.linalg.solve(Kt_ff, f_ref[free])
            du_double_j = np.linalg.solve(Kt_ff, R[free])

            # Phương trình ràng buộc chiều dài cung mặt phẳng pháp tuyến (NSA_6 Slide 19-20)
            num = -float(np.dot(Delta_u, du_double_j))
            den = float(np.dot(Delta_u, du_bar_j)) + (psi * scale_lambda) ** 2 * Delta_lam
            if abs(den) < 1e-14:
                break
            dlam_j = num / den
            du_j = dlam_j * du_bar_j + du_double_j

            u_step[free] += du_j
            lam_step += dlam_j
            Delta_u += du_j
            Delta_lam += dlam_j

        if not converged_step:
            # Nếu chưa hội tụ với ds lớn -> tự động giảm nửa ds và tiếp tục
            ds = max(2.0, 0.5 * ds)
            continue

        prev_du = Delta_u.copy()
        prev_dlam = Delta_lam
        u = u_step
        lam = lam_step

        f_int, Kt, _, _, N, _, _, _ = assemble_nonlinear_state(model, u, "corotational")
        min_eig = float(np.min(np.linalg.eigvalsh(Kt[np.ix_(free, free)])))
        path.append(
            {
                "step": step,
                "lambda": float(lam),
                "u_main_mm": float(u[main_dof]),
                "u_mm": u.tolist(),
                "N_N": N.tolist(),
                "min_eig_Kt": min_eig,
                "iterations": n_it,
            }
        )
        if abs(u[main_dof]) >= max_u_stop:
            break

    return {
        "method": "Chiều dài cung (Constant Arc-Length – NSA_6 6.3.3)",
        "path": path,
    }


# ==============================================================================
# 8. PHÂN TÍCH TẢI TỚI HẠN ĐÀN HỒI BẰNG BÀI TOÁN TRỊ RIÊNG (BUCKLING EIGENVALUE)
#    Nguồn: NSA_4 Mục 4.2; Dahlblom Mục 9.1 PT (9.4)-(9.7); McGuire Mục 12.8 PT (12.37)
# ==============================================================================
def solve_elastic_buckling_eigen(model: TrussModel) -> Dict[str, Any]:
    """
    Giải bài toán trị riêng tổng quát tìm tải tới hạn đàn hồi tổng thể (Linearized
    Buckling Analysis / Bifurcation Load) cho hệ dàn dùng CALFEM `bar2g`:

      (K_e,ff + α_cr * K_g,ff(N_ref)) * φ = 0
      <=> K_e,ff * φ = α_cr * (-K_g,ff(N_ref)) * φ

    trong đó N_ref là lực dọc tìm từ bài toán tuyến tính ứng với tải tham chiếu f_ref.
    Đồng thời tính thêm tải tới hạn Euler cục bộ của từng thanh nén (giả thiết tiết
    diện 3D quy đổi để cảnh báo kỹ thuật theo Hibbeler Mechanics PT 13-5 & Dahlblom tr. 262).
    """
    lin = solve_linear_calfem(model, load_factor=1.0)
    nd = model.n_dofs
    free = model.free_dofs_0based

    Ke = np.zeros((nd, nd), dtype=float)
    Kg_bar2g = np.zeros((nd, nd), dtype=float)
    Kg_mcguire = np.zeros((nd, nd), dtype=float)

    for e in range(model.n_elems):
        ex, ey = model.element_coords(e)
        Ke_e, Kg_e = bar2g_split(ex, ey, (model.E, model.areas[e]), lin.N[e])
        Ke = assem(model.edof[e], Ke, Ke_e)
        Kg_bar2g = assem(model.edof[e], Kg_bar2g, Kg_e)

        # So sánh thêm với Kg đầy đủ theo McGuire PT (9.9) / NSA_4 Slide 11-12
        L0 = math.hypot(ex[1] - ex[0], ey[1] - ey[0])
        k_mcg = (lin.N[e] / L0) * np.block([[np.eye(2), -np.eye(2)], [-np.eye(2), np.eye(2)]])
        Kg_mcguire = assem(model.edof[e], Kg_mcguire, k_mcg)

    def _solve_modes(Ke_mat: np.ndarray, Kg_mat: np.ndarray) -> List[Dict[str, Any]]:
        K_e_ff = Ke_mat[np.ix_(free, free)]
        K_g_ff = Kg_mat[np.ix_(free, free)]
        vals, vecs = eig(K_e_ff, -K_g_ff)
        modes = []
        for val, vec in zip(vals, vecs.T):
            if np.isfinite(val) and abs(val.imag) < 1e-6 and val.real > 0:
                v_real = vec.real
                v_norm = v_real / max(1e-12, np.max(np.abs(v_real)))
                full_mode = np.zeros(nd, dtype=float)
                full_mode[free] = v_norm
                modes.append({"alpha_cr": float(val.real), "mode_shape": full_mode.tolist()})
        modes.sort(key=lambda m: m["alpha_cr"])
        return modes

    modes_bar2g = _solve_modes(Ke, Kg_bar2g)
    modes_mcguire = _solve_modes(Ke, Kg_mcguire)

    # Khảo sát ổn định cục bộ Euler cho từng thanh nén (tham khảo theo tiết diện 3D)
    L0, _, _ = model.initial_lengths_and_cosines()
    local_euler = []
    for e in range(model.n_elems):
        spec = model.section_spec(e).dimensions()
        I_min = spec["I_minor"]
        P_euler = (math.pi ** 2) * model.E * I_min / (L0[e] ** 2)
        N_e = float(lin.N[e])
        is_comp = N_e < -1e-6
        alpha_local = abs(P_euler / N_e) if is_comp else float("inf")
        local_euler.append(
            {
                "element": e + 1,
                "label": model.member_labels[e],
                "L_mm": float(L0[e]),
                "I_minor_mm4": float(I_min),
                "N_linear_kN": N_e / 1000.0,
                "P_euler_kN": P_euler / 1000.0,
                "alpha_local_euler": float(alpha_local) if math.isfinite(alpha_local) else None,
            }
        )

    return {
        "modes_calfem_bar2g": modes_bar2g,
        "modes_mcguire_nsa4": modes_mcguire,
        "local_euler_reference": local_euler,
        "P_ref_kN": float(np.max(np.abs(model.f_ref)) / 1000.0),
    }


# ==============================================================================
# 9. KIỂM CHỨNG ĐỘC LẬP MA TRẬN ĐỘ CỨNG TIẾP TUYẾN BẰNG SAI PHÂN TRUNG TÂM
# ==============================================================================
def verify_tangent_finite_difference(
    model: TrussModel, u: np.ndarray, formulation: str = "corotational", h: float = 1e-4
) -> Dict[str, float]:
    """
    Kiểm tra tính nhất quán toán học của ma trận độ cứng tiếp tuyến giải tích Kt
    so với đạo hàm sai phân trung tâm của véc-tơ nội lực:
      Kt_FD[:, d] = ( f_int(u + h*e_d) - f_int(u - h*e_d) ) / (2*h)
    Nếu sai số chuẩn Frobenius tương đối < 1e-7 => ma trận tiếp tuyến chuẩn tuyệt đối!
    """
    nd = model.n_dofs
    _, Kt_ana, _, _, _, _, _, _ = assemble_nonlinear_state(model, u, formulation=formulation)
    Kt_fd = np.zeros((nd, nd), dtype=float)
    for d in range(nd):
        up = u.copy()
        um = u.copy()
        up[d] += h
        um[d] -= h
        fp = assemble_nonlinear_state(model, up, formulation=formulation)[0]
        fm = assemble_nonlinear_state(model, um, formulation=formulation)[0]
        Kt_fd[:, d] = (fp - fm) / (2.0 * h)

    frob_diff = float(np.linalg.norm(Kt_fd - Kt_ana, "fro"))
    frob_norm = max(1e-12, float(np.linalg.norm(Kt_ana, "fro")))
    max_abs = float(np.max(np.abs(Kt_fd - Kt_ana)))
    return {
        "relative_frobenius_error": frob_diff / frob_norm,
        "max_abs_error_N_per_mm": max_abs,
        "step_h_mm": h,
    }
