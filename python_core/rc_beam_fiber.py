# -*- coding: utf-8 -*-
"""
===============================================================================
MÔ-ĐUN PHÂN TÍCH PHI TUYẾN VẬT LIỆU DẦM BÊ TÔNG CỐT THÉP (PHƯƠNG PHÁP THỚ)
===============================================================================
Tác giả: Lâm Phúc Tâm (2670621) - Võ Thanh Vang (2670624)
Giảng viên hướng dẫn: PGS. TS Ngô Hữu Cường — ĐH Bách Khoa TP.HCM

Cơ sở lý thuyết & công thức Phần tử hữu hạn (PTHH) theo chuẩn CALFEM:
  1. Giả thiết tiết diện phẳng Euler-Bernoulli:
       ε(x, y) = ε₀(x) − y · κ(x)
     với ε₀ = du/dx (biến dạng trục tham chiếu y = 0), κ = d²v/dx² (độ cong).
  2. Phương pháp Thớ (Fiber Section Method):
     - Chia mặt cắt chữ nhật (b × h) thành n_fib dải thớ bê tông mỏng dy = h/n_fib.
     - Cốt thép kéo As, nén As' và tùy chọn Cốt cứng thép hình I đặt đúng trọng tâm y_k.
     - Bê tông: Parabol Hognestad (nén) + nứt kéo tuyến tính mềm hóa (Tension Stiffening).
     - Cốt thép / Cốt cứng: Đàn-dẻo song tuyến tính có tái bền.
  3. Xác định độ cứng tiếp tuyến mặt cắt & Trục trung hòa:
       EA_t = ∑ E_t,i · A_i ;  ES_t = −∑ E_t,i · y_i · A_i ;  EI_t = ∑ E_t,i · y_i² · A_i
       EI_eff = EI_t − ES_t² / EA_t  ;  y_NA = ε₀ / κ  ;  x_NA = h/2 − y_NA
  4. Phương pháp Rayleigh-Ritz (Nguyên lý dừng thế năng toàn phần Π = U − W → δΠ = 0):
       {f_int^e} = ∫ [B(x)]ᵀ {N(x), M(x)}ᵀ dx
       [K_t^e]   = ∫ [B(x)]ᵀ [D_t(x)] [B(x)] dx   (Tích phân số Gauss-Legendre 3 điểm)
     Thiết lập quan hệ lực gia tăng – chuyển vị gia tăng: [K_t]{Δd} = {ΔF}.
===============================================================================
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Dict, List, Tuple
import math
import numpy as np


@dataclass
class RcBeamConfig:
    """Thông số hình học, vật liệu, tải trọng và chia lưới của Dầm BTCT."""
    span_mm: float = 4000.0          # Nhịp dầm L (mm), tỷ lệ L/h khuyến nghị 5..10
    width_mm: float = 250.0          # Bề rộng tiết diện b (mm)
    height_mm: float = 500.0         # Chiều cao tiết diện h (mm)
    as_bot_mm2: float = 942.5        # Cốt thép chịu kéo đáy As (vd 3Ø20 = 942.5 mm²)
    as_top_mm2: float = 402.1        # Cốt thép chịu nén đỉnh As' (vd 2Ø16 = 402.1 mm²)
    cover_bot_mm: float = 40.0       # Khoảng cách trọng tâm cốt thép đáy tới mép dưới a_s (mm)
    cover_top_mm: float = 40.0       # Khoảng cách trọng tâm cốt thép đỉnh tới mép trên a_s' (mm)
    # Tùy chọn Dầm cốt cứng (thép hình chữ I đặt đồng tâm trong lõi dầm BTCT)
    has_rigid_core: bool = False
    core_h_mm: float = 240.0
    core_b_mm: float = 120.0
    core_tf_mm: float = 10.0
    core_tw_mm: float = 7.0
    core_fy_mpa: float = 275.0
    # Thông số vật liệu Bê tông (EN 1992-1-1 / Hognestad)
    fc_mpa: float = 30.0
    ec_mpa: float = 32500.0
    fct_mpa: float = 2.9
    eps_c0: float = 0.0020
    eps_cu: float = 0.0035
    # Thông số vật liệu Cốt thép
    fy_mpa: float = 400.0
    es_mpa: float = 200000.0
    hardening_ratio: float = 0.01
    # Sơ đồ chất tải: '3pt' (3 điểm: 2 gối + 1 lực Q tại a) hoặc '4pt' (4 điểm: 2 gối + 2 lực Q/2 tại a & L-a)
    load_type: str = "3pt"
    load_q_kn: float = 120.0
    load_a_mm: float = 2000.0        # Khoảng cách lực từ gối trái a (mm)
    # Liên kết hai đầu: 'pin', 'roller', 'fixed', 'spring', 'free'
    left_support: str = "pin"
    right_support: str = "roller"
    spring_kv_kn_mm: float = 200.0
    spring_kth_knm_rad: float = 50000.0
    # Tham số chia lưới PTHH & Thớ
    n_elems: int = 8                 # Số phần tử (chẵn để chia hai nửa đối xứng)
    n_fibers: int = 40               # Số dải thớ bê tông theo chiều cao h
    n_steps: int = 12                # Số bước tăng tải
    nonlinear_material: bool = True  # True = Phi tuyến vật liệu thớ, False = Đàn hồi tuyến tính beam2e


def concrete_law(eps: float, cfg: RcBeamConfig, nonlinear: bool) -> Tuple[float, float, str]:
    """Định luật ứng suất – biến dạng bê tông (Hognestad nén + nứt kéo tension stiffening)."""
    if not nonlinear:
        return cfg.ec_mpa * eps, cfg.ec_mpa, ("Nén ĐH" if eps < 0 else "Kéo ĐH")
    if eps <= 0.0:
        ec = -eps
        e0 = max(1e-4, cfg.eps_c0)
        eu = max(e0 + 5e-4, cfg.eps_cu)
        if ec <= e0:
            r = ec / e0
            sig = -cfg.fc_mpa * (2.0 * r - r * r)
            et = (2.0 * cfg.fc_mpa / e0) * (1.0 - r)
            et = max(et, 0.005 * cfg.ec_mpa)
            st = "Nén ĐH" if r < 0.4 else "Nén PT"
            return sig, et, st
        if ec <= eu:
            frac = (ec - e0) / (eu - e0)
            sig = -cfg.fc_mpa * (1.0 - 0.15 * frac)
            return sig, 0.004 * cfg.ec_mpa, "Nén đỉnh"
        sig = -0.20 * cfg.fc_mpa
        return sig, 0.002 * cfg.ec_mpa, "Vỡ nén"
    # Miền kéo bê tông (mềm hóa hàm mũ mượt Tension Stiffening + mô-đun tiếp tuyến nhất quán chính xác!)
    eps_cr = cfg.fct_mpa / max(1.0, cfg.ec_mpa)
    if eps <= eps_cr:
        return cfg.ec_mpa * eps, cfg.ec_mpa, "Kéo chưa nứt"
    ratio = (eps - eps_cr) / max(1e-8, eps_cr)
    sig = cfg.fct_mpa * math.exp(-0.35 * ratio)
    et_exact = -0.35 * sig / max(1e-8, eps_cr)
    st = "Nứt kéo (mềm hóa)" if sig > 0.08 * cfg.fct_mpa else "Nứt hoàn toàn"
    return sig, et_exact, st


def steel_law(eps: float, es: float, fy: float, b_hard: float, nonlinear: bool) -> Tuple[float, float, str]:
    """Định luật ứng suất – biến dạng đàn-dẻo song tuyến tính cho cốt thép & cốt cứng."""
    if not nonlinear:
        return es * eps, es, "Đàn hồi"
    ey = fy / max(1.0, es)
    et_h = max(1e-4, b_hard) * es
    if abs(eps) <= ey:
        return es * eps, es, "Đàn hồi"
    sgn = 1.0 if eps >= 0.0 else -1.0
    sig = sgn * (fy + et_h * (abs(eps) - ey))
    return sig, et_h, "Chảy dẻo"


def build_section_fibers(cfg: RcBeamConfig) -> List[Tuple[float, float, str, float]]:
    """
    Khởi tạo danh sách thớ mặt cắt: [(y_mm, area_mm2, kind, fy_mpa), ...]
    Hệ trục y hướng lên từ trọng tâm hình học y = 0 (y ∈ [-h/2, +h/2]).
    """
    fibers: List[Tuple[float, float, str, float]] = []
    nf = max(6, cfg.n_fibers)
    dy = cfg.height_mm / nf
    # 1. Các dải thớ bê tông
    for k in range(nf):
        yk = -0.5 * cfg.height_mm + (k + 0.5) * dy
        fibers.append((yk, cfg.width_mm * dy, "concrete", 0.0))
    # 2. Cốt thép chịu kéo (đáy) & chịu nén (đỉnh) lấy đúng trọng tâm làm chuẩn
    if cfg.as_bot_mm2 > 0:
        y_bot = -0.5 * cfg.height_mm + cfg.cover_bot_mm
        fibers.append((y_bot, cfg.as_bot_mm2, "rebar_bot", cfg.fy_mpa))
    if cfg.as_top_mm2 > 0:
        y_top = 0.5 * cfg.height_mm - cfg.cover_top_mm
        fibers.append((y_top, cfg.as_top_mm2, "rebar_top", cfg.fy_mpa))
    # 3. Tùy chọn cốt cứng thép hình chữ I đồng tâm (chia thành cánh trên, cánh dưới + 6 thớ bụng)
    if cfg.has_rigid_core and cfg.core_h_mm > 20 and cfg.core_b_mm > 10:
        hh = 0.5 * cfg.core_h_mm
        tf = min(cfg.core_tf_mm, 0.35 * cfg.core_h_mm)
        tw = min(cfg.core_tw_mm, cfg.core_b_mm)
        a_fl = cfg.core_b_mm * tf
        fibers.append((-hh + 0.5 * tf, a_fl, "core", cfg.core_fy_mpa))
        fibers.append((hh - 0.5 * tf, a_fl, "core", cfg.core_fy_mpa))
        hw = cfg.core_h_mm - 2.0 * tf
        if hw > 1.0:
            n_w = 6
            dw = hw / n_w
            for j in range(n_w):
                yw = -0.5 * hw + (j + 0.5) * dw
                fibers.append((yw, tw * dw, "core", cfg.core_fy_mpa))
    return fibers


def evaluate_section(
    eps0: float,
    kappa: float,
    fibers: List[Tuple[float, float, str, float]],
    cfg: RcBeamConfig,
    nonlinear: bool,
) -> Tuple[float, float, float, float, float]:
    """Tính nội lực mặt cắt (N, M) và ma trận độ cứng tiếp tuyến (EA_t, ES_t, EI_t)."""
    n_val = 0.0
    m_val = 0.0
    ea_t = 0.0
    es_t = 0.0
    ei_t = 0.0
    for y, area, kind, fy_k in fibers:
        eps = eps0 - y * kappa
        if kind == "concrete":
            sig, et, _ = concrete_law(eps, cfg, nonlinear)
        else:
            sig, et, _ = steel_law(eps, cfg.es_mpa, fy_k, cfg.hardening_ratio, nonlinear)
        n_val += sig * area
        m_val -= sig * y * area
        ea_t += et * area
        es_t -= et * y * area
        ei_t += et * y * y * area
    # Bảo đảm ma trận độ cứng mặt cắt 2×2 [D_t] luôn xác định dương kể cả khi bê tông vỡ nén/không cốt thép
    ea_min = 0.005 * cfg.ec_mpa * cfg.width_mm * cfg.height_mm
    ei_min = 0.005 * cfg.ec_mpa * cfg.width_mm * (cfg.height_mm ** 3) / 12.0
    if ea_t < ea_min:
        ea_t = ea_min
    if ei_t - (es_t * es_t) / ea_t < ei_min:
        ei_t = (es_t * es_t) / ea_t + ei_min
    return n_val, m_val, ea_t, es_t, ei_t


def build_beam_mesh(cfg: RcBeamConfig) -> np.ndarray:
    """Sinh tọa độ nút x ∈ [0, L] luôn chia đối xứng 2 nửa và bám chính xác điểm đặt lực a, L-a."""
    n_half = max(1, cfg.n_elems // 2)
    L = cfg.span_mm
    pts = set(round(L * i / (2 * n_half), 3) for i in range(2 * n_half + 1))
    a = min(max(cfg.load_a_mm, 0.05 * L), 0.95 * L)
    if cfg.load_type == "3pt":
        pts.add(round(a, 3))
    else:
        a4 = min(max(cfg.load_a_mm, 0.05 * L), 0.49 * L)
        pts.add(round(a4, 3))
        pts.add(round(L - a4, 3))
    arr = sorted(pts)
    # Hợp nhất các nút quá sát nhau (< 1e-2 mm)
    cleaned = [arr[0]]
    for x in arr[1:]:
        if x - cleaned[-1] > 1.0:
            cleaned.append(x)
    if abs(cleaned[-1] - L) > 1e-2:
        cleaned[-1] = L
    return np.array(cleaned, dtype=float)


def assemble_beam(
    x_nodes: np.ndarray,
    d_vec: np.ndarray,
    fibers: List[Tuple[float, float, str, float]],
    cfg: RcBeamConfig,
    nonlinear: bool,
) -> Tuple[np.ndarray, np.ndarray, List[np.ndarray], List[np.ndarray]]:
    """
    Lắp ráp véc-tơ nội lực {F_int} và ma trận độ cứng tiếp tuyến toàn cục [K_t]
    theo phương pháp Rayleigh-Ritz (tích phân Gauss-Legendre 3 điểm trên từng phần tử).
    """
    n_nodes = len(x_nodes)
    n_dofs = 3 * n_nodes
    f_int = np.zeros(n_dofs, dtype=float)
    kt_glob = np.zeros((n_dofs, n_dofs), dtype=float)
    elem_kts: List[np.ndarray] = []
    elem_forces: List[np.ndarray] = []

    # Điểm & trọng số Gauss-Legendre 3 điểm trên [0, 1]
    gp_xi = [0.5 * (1.0 - math.sqrt(3.0 / 5.0)), 0.5, 0.5 * (1.0 + math.sqrt(3.0 / 5.0))]
    gp_w = [5.0 / 18.0, 8.0 / 18.0, 5.0 / 18.0]

    for e in range(n_nodes - 1):
        le = x_nodes[e + 1] - x_nodes[e]
        dofs = [3 * e, 3 * e + 1, 3 * e + 2, 3 * (e + 1), 3 * (e + 1) + 1, 3 * (e + 1) + 2]
        de = d_vec[dofs]
        fe = np.zeros(6, dtype=float)
        ke = np.zeros((6, 6), dtype=float)

        for xi, wi in zip(gp_xi, gp_w):
            bu = np.array([-1.0 / le, 0.0, 0.0, 1.0 / le, 0.0, 0.0])
            bk = np.array([
                0.0,
                (-6.0 + 12.0 * xi) / (le * le),
                (-4.0 + 6.0 * xi) / le,
                0.0,
                (6.0 - 12.0 * xi) / (le * le),
                (-2.0 + 6.0 * xi) / le,
            ])
            bmat = np.vstack([bu, bk])  # 2x6
            eps0 = float(bu @ de)
            kappa = float(bk @ de)
            n_sec, m_sec, ea_t, es_t, ei_t = evaluate_section(eps0, kappa, fibers, cfg, nonlinear)
            dmat = np.array([[ea_t, es_t], [es_t, ei_t]], dtype=float)
            w_dx = wi * le
            fe += (bmat.T @ np.array([n_sec, m_sec])) * w_dx
            ke += (bmat.T @ dmat @ bmat) * w_dx

        elem_forces.append(fe)
        elem_kts.append(ke)
        for a_i in range(6):
            f_int[dofs[a_i]] += fe[a_i]
            for b_i in range(6):
                kt_glob[dofs[a_i], dofs[b_i]] += ke[a_i, b_i]

    # Bổ sung lò xo đàn hồi đầu mút nếu chọn 'spring'
    for node_idx, sup in ((0, cfg.left_support), (n_nodes - 1, cfg.right_support)):
        if sup == "spring":
            kv = cfg.spring_kv_kn_mm * 1000.0
            kth = cfg.spring_kth_knm_rad * 1e6
            f_int[3 * node_idx + 1] += kv * d_vec[3 * node_idx + 1]
            kt_glob[3 * node_idx + 1, 3 * node_idx + 1] += kv
            f_int[3 * node_idx + 2] += kth * d_vec[3 * node_idx + 2]
            kt_glob[3 * node_idx + 2, 3 * node_idx + 2] += kth

    return f_int, kt_glob, elem_kts, elem_forces


def solve_rc_beam(cfg: RcBeamConfig) -> Dict[str, object]:
    """Giải bài toán dầm BTCT phi tuyến bằng Full Newton-Raphson gia tăng tải."""
    x_nodes = build_beam_mesh(cfg)
    n_nodes = len(x_nodes)
    n_dofs = 3 * n_nodes
    fibers = build_section_fibers(cfg)

    # Xác định bậc tự do bị khóa
    fixed = set()
    for node_idx, sup in ((0, cfg.left_support), (n_nodes - 1, cfg.right_support)):
        if sup == "pin":
            fixed.update([3 * node_idx, 3 * node_idx + 1])
        elif sup == "roller":
            fixed.add(3 * node_idx + 1)
        elif sup == "fixed":
            fixed.update([3 * node_idx, 3 * node_idx + 1, 3 * node_idx + 2])
    if 0 not in fixed and 3 * (n_nodes - 1) not in fixed:
        fixed.add(0)  # Khử chuyển vị cứng dọc trục nếu cả 2 gối đều di động
    free = [i for i in range(n_dofs) if i not in fixed]

    # Véc-tơ ngoại lực tham chiếu {F_ref} (N, N·mm)
    f_ref = np.zeros(n_dofs, dtype=float)
    q_n = cfg.load_q_kn * 1000.0
    if cfg.load_type == "3pt":
        idx = int(np.argmin(np.abs(x_nodes - cfg.load_a_mm)))
        f_ref[3 * idx + 1] -= q_n
    else:
        a4 = min(max(cfg.load_a_mm, 0.05 * cfg.span_mm), 0.49 * cfg.span_mm)
        i1 = int(np.argmin(np.abs(x_nodes - a4)))
        i2 = int(np.argmin(np.abs(x_nodes - (cfg.span_mm - a4))))
        f_ref[3 * i1 + 1] -= 0.5 * q_n
        f_ref[3 * i2 + 1] -= 0.5 * q_n

    d = np.zeros(n_dofs, dtype=float)
    steps = max(1, cfg.n_steps) if cfg.nonlinear_material else 1
    total_it = 0
    converged = True
    f_int, kt, elem_kts, elem_forces = assemble_beam(x_nodes, d, fibers, cfg, cfg.nonlinear_material)

    # Chuẩn hóa sai số riêng theo bậc tự do lực (u, v: N) và bậc tự do mô-men (θ: N·mm)
    f_scale = max(1e4, abs(q_n))
    m_scale = max(1e7, abs(q_n) * cfg.span_mm * 0.25)
    dof_scales = np.array([m_scale if (idx % 3 == 2) else f_scale for idx in free], dtype=float)
    tol_rel = 1e-5

    for s in range(1, steps + 1):
        lam = s / steps
        step_ok = False
        f_int, kt, elem_kts, elem_forces = assemble_beam(x_nodes, d, fibers, cfg, cfg.nonlinear_material)
        for _ in range(45):
            res = lam * f_ref[free] - f_int[free]
            err = float(np.max(np.abs(res) / dof_scales)) if len(res) else 0.0
            if err < tol_rel:
                step_ok = True
                break
            kt_ff = kt[np.ix_(free, free)]
            du = np.linalg.solve(kt_ff, res)
            # Tìm kiếm đường lùi (Backtracking Line Search) bảo đảm hội tụ toàn cục qua vùng nứt bê tông!
            alpha = 1.0
            best_d = d.copy()
            best_err = err
            for _ls in range(6):
                d_try = d.copy()
                d_try[free] += alpha * du
                fi_try, _, _, _ = assemble_beam(x_nodes, d_try, fibers, cfg, cfg.nonlinear_material)
                e_try = float(np.max(np.abs(lam * f_ref[free] - fi_try[free]) / dof_scales))
                if e_try < best_err:
                    best_err = e_try
                    best_d = d_try
                    if e_try < 0.85 * err:
                        break
                alpha *= 0.5
            if best_err < err:
                d = best_d
            else:
                d[free] += 0.25 * du
            total_it += 1
            f_int, kt, elem_kts, elem_forces = assemble_beam(x_nodes, d, fibers, cfg, cfg.nonlinear_material)
        if not step_ok:
            converged = False
            break

    f_int, kt, elem_kts, elem_forces = assemble_beam(x_nodes, d, fibers, cfg, cfg.nonlinear_material)
    reactions = f_int - f_ref
    mid_idx = int(np.argmin(np.abs(x_nodes - 0.5 * cfg.span_mm)))
    return {
        "converged": converged,
        "total_iterations": total_it,
        "x_nodes": x_nodes,
        "d": d,
        "reactions": reactions,
        "v_mid_mm": float(d[3 * mid_idx + 1]),
        "m_max_knm": float(max(max(abs(fe[2]), abs(fe[5])) for fe in elem_forces) / 1e6),
        "sum_fy_n": float(np.sum(reactions[1::3]) + np.sum(f_ref[1::3])),
        "elem_kts": elem_kts,
        "elem_forces": elem_forces,
    }


if __name__ == "__main__":
    # Kiểm chứng nhanh Dầm BTCT đơn giản 3 điểm (L=4000, b=250, h=500 -> L/h=8, Q=120 kN -> QL/4 = 120 kNm)
    cfg_lin = RcBeamConfig(nonlinear_material=False, load_type="3pt", load_q_kn=120.0, load_a_mm=2000.0)
    res_lin = solve_rc_beam(cfg_lin)
    cfg_nl = RcBeamConfig(nonlinear_material=True, load_type="3pt", load_q_kn=120.0, load_a_mm=2000.0)
    res_nl = solve_rc_beam(cfg_nl)
    print(f"[LIN] v_mid = {res_lin['v_mid_mm']:.4f} mm | M_max = {res_lin['m_max_knm']:.4f} kNm (QL/4 = 120.0000) | sumFy = {res_lin['sum_fy_n']:.2e} N")
    print(f"[NL ] v_mid = {res_nl['v_mid_mm']:.4f} mm | M_max = {res_nl['m_max_knm']:.4f} kNm | iters = {res_nl['total_iterations']} | sumFy = {res_nl['sum_fy_n']:.2e} N")
