# -*- coding: utf-8 -*-
"""
================================================================================
CHẠY TOÀN BỘ THÍ NGHIỆM SỐ, KIỂM CHỨNG BENCHMARK THỰC NGHIỆM & KHẢO SÁT THAM SỐ
CHO BÀI TOÁN DẦM BÊ TÔNG CỐT CỨNG (SRC) & BTCT PHI TUYẾN VẬT LIỆU — PHƯƠNG PHÁP THỚ
================================================================================
Mọi số liệu đầu ra đều được tính trực tiếp từ bộ giải lõi `python_core/rc_beam_fiber.py`
(KHÔNG sử dụng số liệu giả lập), lưu tại `results/src_beam_study_results.json` và vẽ
6 biểu đồ kỹ thuật chuẩn ấn phẩm 300 DPI tại `results/src_beam_figs/`.
================================================================================
"""

from __future__ import annotations
import json
import math
import os
import sys
from typing import Dict, List, Tuple

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as patches

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from python_core.rc_beam_fiber import (
    RcBeamConfig,
    build_section_fibers,
    concrete_law,
    steel_law,
    evaluate_section,
    build_beam_mesh,
    assemble_beam,
    solve_rc_beam,
)

RESULTS_DIR = os.path.join(ROOT, "results")
FIGS_DIR = os.path.join(RESULTS_DIR, "src_beam_figs")
os.makedirs(FIGS_DIR, exist_ok=True)

# Cấu hình font tiếng Việt sạch đẹp cho Matplotlib trên Windows
plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "axes.titlesize": 10.5,
    "axes.titleweight": "bold",
    "axes.labelsize": 9.5,
    "xtick.labelsize": 8.5,
    "ytick.labelsize": 8.5,
    "legend.fontsize": 8.2,
    "figure.titlesize": 12.0,
    "axes.grid": True,
    "grid.alpha": 0.28,
    "grid.linestyle": "--",
})

NAVY = "#0F3D6E"
TEAL = "#0F766E"
CRIMSON = "#B91C1C"
AMBER = "#D97706"
PURPLE = "#6D28D9"
SLATE = "#334155"
BLUE = "#2563EB"
GREEN = "#15803D"


# ==============================================================================
# 1. CÁC HÀM PHÂN TÍCH MẶT CẮT M-KAPPA, ĐÓNG GÓP NỘI LỰC & GIẢI TÍCH PSD
# ==============================================================================
def compute_moment_curvature(
    cfg: RcBeamConfig,
    n_pts: int = 160,
    kappa_max: float = 0.0,
) -> Dict[str, object]:
    """
    Quét quan hệ Mô-men – Độ cong (M-κ) ở điều kiện cân bằng lực dọc N(ε0, κ) = 0
    cho tới khi thớ nén bê tông mép trên đạt biến dạng cực hạn ε_cu (hoặc vượt đỉnh).
    Trả về đầy đủ diễn biến M, κ, EI_eff, x_NA, ứng suất thép, đóng góp mô-men từng thành phần.
    """
    fibers = build_section_fibers(cfg)
    if kappa_max <= 0.0:
        kappa_max = 14.0 * cfg.eps_cu / cfg.height_mm

    kappas = np.linspace(0.0, kappa_max, n_pts)
    eps0 = 0.0

    # Định danh đặc trưng từng nhóm thớ
    y_bot_rebar = -0.5 * cfg.height_mm + cfg.cover_bot_mm
    y_core_bot = -0.5 * cfg.core_h_mm + 0.5 * cfg.core_tf_mm if cfg.has_rigid_core else 0.0

    curve = []
    m_cr = None
    k_cr = None
    m_y_core = None
    k_y_core = None
    m_y_rebar = None
    k_y_rebar = None
    m_y = None
    k_y = None
    m_u = 0.0
    k_u = 0.0
    x_na_u = 0.0
    eps_c_u = 0.0
    eps_s_u = 0.0

    ei0 = None
    ea0 = None

    for k_val in kappas:
        # Giải Newton 1D tìm ε0 sao cho N(ε0, κ) = 0
        for _ in range(30):
            n_v, m_v, ea_t, es_t, ei_t = evaluate_section(eps0, float(k_val), fibers, cfg, True)
            if abs(n_v) < 1e-3:
                break
            deps = -n_v / max(1.0, ea_t)
            eps0 += max(-2e-3, min(2e-3, deps))
        n_v, m_v, ea_t, es_t, ei_t = evaluate_section(eps0, float(k_val), fibers, cfg, True)
        ei_eff = ei_t - (es_t * es_t) / max(1.0, ea_t)
        if ei0 is None:
            ei0 = ei_eff
            ea0 = ea_t

        eps_top = eps0 - (0.5 * cfg.height_mm) * float(k_val)   # nén < 0
        eps_bot = eps0 - (-0.5 * cfg.height_mm) * float(k_val)  # kéo > 0
        if k_val > 1e-11:
            y_na = eps0 / float(k_val)
            x_na = 0.5 * cfg.height_mm - y_na
        else:
            y_na = 0.0
            x_na = 0.5 * cfg.height_mm

        # Tách đóng góp mô-men M = -Σ σ_i · y_i · A_i (tính quanh trục trung hòa y_NA để mọi thành phần dương cùng chiều!)
        m_conc = 0.0
        m_rebar = 0.0
        m_core = 0.0
        eps_rebar_bot = eps0 - y_bot_rebar * float(k_val)
        eps_core_bot = eps0 - y_core_bot * float(k_val) if cfg.has_rigid_core else 0.0

        for y_f, a_f, kind, fy_k in fibers:
            e_f = eps0 - y_f * float(k_val)
            if kind == "concrete":
                sig, _, _ = concrete_law(e_f, cfg, True)
                m_conc -= sig * (y_f - y_na) * a_f
            else:
                sig, _, _ = steel_law(e_f, cfg.es_mpa, fy_k, cfg.hardening_ratio, True)
                if kind == "core":
                    m_core -= sig * (y_f - y_na) * a_f
                else:
                    m_rebar -= sig * (y_f - y_na) * a_f

        m_knm = m_v / 1e6
        # Ghi nhận các mốc trạng thái
        eps_cr = cfg.fct_mpa / max(1.0, cfg.ec_mpa)
        if m_cr is None and eps_bot >= eps_cr:
            m_cr = m_knm
            k_cr = float(k_val)

        if cfg.has_rigid_core and m_y_core is None and eps_core_bot >= cfg.core_fy_mpa / cfg.es_mpa:
            m_y_core = m_knm
            k_y_core = float(k_val)

        if cfg.as_bot_mm2 > 0 and m_y_rebar is None and eps_rebar_bot >= cfg.fy_mpa / cfg.es_mpa:
            m_y_rebar = m_knm
            k_y_rebar = float(k_val)

        # Mốc chảy dẻo chính thức (thớ thép chịu kéo đầu tiên chảy)
        if m_y is None:
            if m_y_rebar is not None and (not cfg.has_rigid_core or m_y_core is None):
                m_y, k_y = m_y_rebar, k_y_rebar
            elif m_y_core is not None and m_y_rebar is None:
                m_y, k_y = m_y_core, k_y_core
            elif m_y_core is not None and m_y_rebar is not None:
                m_y, k_y = m_y_rebar, k_y_rebar  # dùng mốc chảy thép chủ ngoài cùng cho độ dẻo dai

        curve.append({
            "kappa_1_m": float(k_val) * 1000.0,
            "kappa_1e3_m": float(k_val) * 1e6,
            "kappa_1_mm": float(k_val),
            "eps0": float(eps0),
            "m_knm": float(m_knm),
            "ea_t_n": float(ea_t),
            "es_t_nmm": float(es_t),
            "ei_t_nmm2": float(ei_t),
            "ei_eff_knm2": float(ei_eff / 1e9),
            "ei_ratio": float(ei_eff / max(1.0, ei0)),
            "x_na_mm": float(x_na),
            "y_na_mm": float(y_na),
            "eps_c_top": float(eps_top),
            "eps_rebar_bot": float(eps_rebar_bot),
            "eps_core_bot": float(eps_core_bot),
            "m_conc_knm": float(m_conc / 1e6),
            "m_rebar_knm": float(m_rebar / 1e6),
            "m_core_knm": float(m_core / 1e6),
        })

        if -eps_top <= cfg.eps_cu + 1e-6:
            if m_knm >= m_u:
                m_u = m_knm
                k_u = float(k_val)
                x_na_u = x_na
                eps_c_u = -eps_top
                eps_s_u = eps_rebar_bot
        else:
            break

    # Độ dẻo dai độ cong μ_κ = κ_u / κ_y (dùng mốc chảy cốt thép kéo ngoài cùng; nếu không có thì dùng lõi)
    k_y_ref = k_y_rebar if k_y_rebar is not None else (k_y_core if k_y_core is not None else 1e-9)
    mu_kappa = k_u / max(1e-12, k_y_ref)

    return {
        "ei0_knm2": float(ei0 / 1e9),
        "ea0_mn": float(ea0 / 1e6),
        "m_cr_knm": float(m_cr or 0.0),
        "k_cr_1e3_m": float((k_cr or 0.0) * 1e6),
        "m_y_core_knm": float(m_y_core or 0.0),
        "k_y_core_1e3_m": float((k_y_core or 0.0) * 1e6),
        "m_y_rebar_knm": float(m_y_rebar or 0.0),
        "k_y_rebar_1e3_m": float((k_y_rebar or 0.0) * 1e6),
        "m_u_knm": float(m_u),
        "k_u_1e3_m": float(k_u * 1e6),
        "mu_kappa": float(mu_kappa),
        "x_na_u_mm": float(x_na_u),
        "eps_c_u": float(eps_c_u),
        "eps_s_u": float(eps_s_u),
        "curve": curve,
    }


def compute_psd_en1994_aisc360(cfg: RcBeamConfig, deduct_concrete_in_core: bool = True) -> Dict[str, float]:
    """
    Tính mô-men dẻo giải tích M_pl theo Phương pháp Phân bố Ứng suất Dẻo (PSD)
    của EN 1994-1-1:2004 §6.2.1.2 & ANSI/AISC 360-16 §I3.3 (bê tông nén 0.85 f'_c
    trên chiều sâu α·x_p, thép chảy ±f_y).
    Hỗ trợ tùy chọn trừ phần bê tông bị chiếm chỗ bởi lõi thép hình trong vùng nén.
    """
    h = cfg.height_mm
    b = cfg.width_mm
    fc_eff = 0.85 * cfg.fc_mpa
    # Tọa độ đo từ mép trên z ∈ [0, h]
    z_rebar_top = cfg.cover_top_mm
    z_rebar_bot = h - cfg.cover_bot_mm

    # Chia dải lõi thép I theo z từ mép trên (50 dải siêu mịn để tích phân chính xác hình học)
    core_strips: List[Tuple[float, float, float]] = []  # (z, area, fy)
    if cfg.has_rigid_core and cfg.core_h_mm > 20 and cfg.core_b_mm > 10:
        z_top_core = 0.5 * h - 0.5 * cfg.core_h_mm
        tf = cfg.core_tf_mm
        tw = cfg.core_tw_mm
        hw = cfg.core_h_mm - 2.0 * tf
        # Cánh trên (10 dải)
        for i in range(10):
            dz = tf / 10.0
            core_strips.append((z_top_core + (i + 0.5) * dz, cfg.core_b_mm * dz, cfg.core_fy_mpa))
        # Bụng (30 dải)
        for i in range(30):
            dz = hw / 30.0
            core_strips.append((z_top_core + tf + (i + 0.5) * dz, tw * dz, cfg.core_fy_mpa))
        # Cánh dưới (10 dải)
        for i in range(10):
            dz = tf / 10.0
            core_strips.append((z_top_core + tf + hw + (i + 0.5) * dz, cfg.core_b_mm * dz, cfg.core_fy_mpa))

    def axial_force(xp: float) -> float:
        # Cân bằng lực nén (+) - lực kéo (-) = 0
        c_conc = fc_eff * b * xp
        n_reb = 0.0
        if cfg.as_top_mm2 > 0:
            n_reb += cfg.as_top_mm2 * (cfg.fy_mpa - (fc_eff if deduct_concrete_in_core and z_rebar_top < xp else 0.0)) * (1.0 if z_rebar_top < xp else -1.0)
        if cfg.as_bot_mm2 > 0:
            n_reb += cfg.as_bot_mm2 * (cfg.fy_mpa - (fc_eff if deduct_concrete_in_core and z_rebar_bot < xp else 0.0)) * (1.0 if z_rebar_bot < xp else -1.0)
        n_core = 0.0
        for z_s, a_s, fy_s in core_strips:
            if z_s < xp:
                n_core += a_s * (fy_s - (fc_eff if deduct_concrete_in_core else 0.0))
            else:
                n_core -= a_s * fy_s
        return c_conc + n_reb + n_core

    lo, hi = 1e-3, h - 1e-3
    for _ in range(70):
        mid = 0.5 * (lo + hi)
        if axial_force(mid) > 0:
            hi = mid
        else:
            lo = mid
    xp = 0.5 * (lo + hi)

    # Tính mô-men quanh trục trung hòa dẻo z = xp
    m_val = fc_eff * b * xp * (0.5 * xp)
    if cfg.as_top_mm2 > 0:
        f_s = cfg.as_top_mm2 * (cfg.fy_mpa - (fc_eff if deduct_concrete_in_core and z_rebar_top < xp else 0.0))
        m_val += f_s * abs(xp - z_rebar_top)
    if cfg.as_bot_mm2 > 0:
        f_s = cfg.as_bot_mm2 * (cfg.fy_mpa - (fc_eff if deduct_concrete_in_core and z_rebar_bot < xp else 0.0))
        m_val += f_s * abs(xp - z_rebar_bot)
    for z_s, a_s, fy_s in core_strips:
        if z_s < xp:
            f_s = a_s * (fy_s - (fc_eff if deduct_concrete_in_core else 0.0))
        else:
            f_s = a_s * fy_s
        m_val += f_s * abs(xp - z_s)

    return {
        "x_pna_mm": float(xp),
        "m_pl_knm": float(m_val / 1e6),
    }


def trace_load_deflection(
    cfg_base: RcBeamConfig,
    q_max_kn: float,
    n_points: int = 24,
) -> Dict[str, object]:
    """
    Chạy giải PTHH phi tuyến nhiều mức tải (0 -> q_max) để vẽ đường cong Q-v_mid
    chính xác từ bộ giải `solve_rc_beam` (và trích diễn biến mô-men ngàm/nhịp).
    """
    qs = np.linspace(0.0, q_max_kn, n_points)
    pts = []
    for q in qs:
        if q <= 1e-6:
            pts.append({"q_kn": 0.0, "v_mid_mm": 0.0, "m_max_knm": 0.0, "m_end_knm": 0.0, "m_mid_knm": 0.0, "converged": True})
            continue
        c = RcBeamConfig(**{**cfg_base.__dict__, "load_q_kn": float(q), "n_steps": 14})
        res = solve_rc_beam(c)
        if not res["converged"]:
            break
        # Mô-men đầu trái và giữa nhịp
        ef = res["elem_forces"]
        x_nodes = res["x_nodes"]
        m_end = abs(ef[0][2]) / 1e6
        # Tìm phần tử ngay bên trái giữa nhịp
        mid_idx = int(np.argmin(np.abs(x_nodes - 0.5 * c.span_mm)))
        if mid_idx > 0 and mid_idx - 1 < len(ef):
            m_mid = abs(ef[mid_idx - 1][5]) / 1e6
        else:
            m_mid = res["m_max_knm"]
        pts.append({
            "q_kn": float(q),
            "v_mid_mm": float(abs(res["v_mid_mm"])),
            "m_max_knm": float(res["m_max_knm"]),
            "m_end_knm": float(m_end),
            "m_mid_knm": float(m_mid),
            "converged": bool(res["converged"]),
            "iters": int(res["total_iterations"]),
        })
    return {"points": pts}


def extract_section_profile(cfg: RcBeamConfig, target_m_knm: float, mc_data: Dict[str, object]) -> Dict[str, object]:
    """Lấy phân bố biến dạng ε(y) và ứng suất σ(y) theo chiều cao mặt cắt tại một mức mô-men xác định."""
    curve = mc_data["curve"]
    best = min(curve, key=lambda r: abs(r["m_knm"] - target_m_knm))
    eps0 = best["eps0"]
    kappa = best["kappa_1_mm"]
    fibers = build_section_fibers(cfg)
    y_conc, eps_conc, sig_conc = [], [], []
    steel_pts = []
    for y_f, a_f, kind, fy_k in fibers:
        e_f = eps0 - y_f * kappa
        if kind == "concrete":
            sig, _, _ = concrete_law(e_f, cfg, True)
            y_conc.append(y_f)
            eps_conc.append(e_f * 1000.0)  # ‰
            sig_conc.append(sig)
        else:
            sig, _, _ = steel_law(e_f, cfg.es_mpa, fy_k, cfg.hardening_ratio, True)
            steel_pts.append({"y": y_f, "kind": kind, "eps_pm": e_f * 1000.0, "sig_mpa": sig, "area": a_f})
    return {
        "m_knm": best["m_knm"],
        "kappa_1_m": best["kappa_1_m"],
        "x_na_mm": best["x_na_mm"],
        "y_na_mm": best["y_na_mm"],
        "y_conc": y_conc,
        "eps_conc_pm": eps_conc,
        "sig_conc_mpa": sig_conc,
        "steel_pts": steel_pts,
    }


# ==============================================================================
# 2. CHẠY TẤT CẢ BENCHMARK & KHẢO SÁT THAM SỐ
# ==============================================================================
def run_all_studies() -> Dict[str, object]:
    print("[1/7] Chay bai toan dien hinh SRC I240x120 vs BTCT thuong...")
    cfg_src = RcBeamConfig(
        span_mm=4000.0, width_mm=250.0, height_mm=500.0,
        as_bot_mm2=942.5, as_top_mm2=402.1, cover_bot_mm=40.0, cover_top_mm=40.0,
        has_rigid_core=True, core_h_mm=240.0, core_b_mm=120.0, core_tf_mm=10.0, core_tw_mm=7.0, core_fy_mpa=275.0,
        fc_mpa=30.0, ec_mpa=32500.0, fct_mpa=2.9, eps_c0=0.0020, eps_cu=0.0035,
        fy_mpa=400.0, es_mpa=200000.0, hardening_ratio=0.01,
        load_type="3pt", load_q_kn=120.0, load_a_mm=2000.0,
        left_support="pin", right_support="roller",
        n_elems=8, n_fibers=40, n_steps=16, nonlinear_material=True,
    )
    cfg_rc = RcBeamConfig(**{**cfg_src.__dict__, "has_rigid_core": False})

    mc_src = compute_moment_curvature(cfg_src, n_pts=800)
    mc_rc = compute_moment_curvature(cfg_rc, n_pts=800)
    # Kiểm chứng với tái bền bằng 0 (đàn-dẻo lý tưởng) so sánh trực tiếp với PSD!
    cfg_src_ep = RcBeamConfig(**{**cfg_src.__dict__, "hardening_ratio": 1e-4})
    mc_src_ep = compute_moment_curvature(cfg_src_ep, n_pts=800)

    psd_deduct = compute_psd_en1994_aisc360(cfg_src, deduct_concrete_in_core=True)
    psd_gross = compute_psd_en1994_aisc360(cfg_src, deduct_concrete_in_core=False)

    # Giải bài toán điển hình SRC tại tải làm việc Q=120 kN (Đàn hồi & Phi tuyến) và tại Q=260 kN (cận chảy)
    res_src_lin = solve_rc_beam(RcBeamConfig(**{**cfg_src.__dict__, "nonlinear_material": False}))
    res_src_nl120 = solve_rc_beam(cfg_src)
    res_src_nl260 = solve_rc_beam(RcBeamConfig(**{**cfg_src.__dict__, "load_q_kn": 260.0, "n_steps": 18}))
    res_rc_nl120 = solve_rc_beam(cfg_rc)

    # Kiểm chứng giải tích đàn hồi beam2e: dùng đúng độ cứng đàn hồi tuyến tính EI_lin (E_c = 32500 MPa)!
    fibs_src = build_section_fibers(cfg_src)
    _, _, ea_lin, es_lin, ei_lin_raw = evaluate_section(0.0, 0.0, fibs_src, cfg_src, nonlinear=False)
    ei_lin_eff = ei_lin_raw - (es_lin * es_lin) / ea_lin
    v_exact_lin = -(cfg_src.load_q_kn * 1000.0) * (cfg_src.span_mm ** 3) / (48.0 * ei_lin_eff)
    m_exact_lin = cfg_src.load_q_kn * cfg_src.span_mm / 4000.0

    # Trích ma trận độ cứng phần tử [K_t^e] 6×6 và véc-tơ {f^e}, {d^e} của phần tử giữa nhịp (e=3, x ∈ [1500, 2000])
    e_crit = 3
    kt_e_120 = res_src_nl120["elem_kts"][e_crit]
    fe_120 = res_src_nl120["elem_forces"][e_crit]
    de_120 = res_src_nl120["d"][3 * e_crit : 3 * e_crit + 6]

    # Tải trọng phá hoại dầm đơn giản 3 điểm: Q_u = 4 * M_u / L
    q_u_src = 4.0 * mc_src["m_u_knm"] / (cfg_src.span_mm / 1000.0)
    q_u_rc = 4.0 * mc_rc["m_u_knm"] / (cfg_rc.span_mm / 1000.0)
    qd_src = trace_load_deflection(cfg_src, 0.985 * q_u_src, n_points=26)
    qd_rc = trace_load_deflection(cfg_rc, 0.985 * q_u_rc, n_points=24)

    # Profile biến dạng & ứng suất trên mặt cắt SRC tại 3 mức M
    prof_stage1 = extract_section_profile(cfg_src, 25.0, mc_src)
    prof_stage2 = extract_section_profile(cfg_src, 120.0, mc_src)
    prof_stage4 = extract_section_profile(cfg_src, mc_src["m_u_knm"], mc_src)

    # ------------------------------------------------------------------
    # [2/7] BENCHMARK THỰC NGHIỆM QUỐC TẾ
    # ------------------------------------------------------------------
    print("[2/7] Chay kiem chung 5 dam thi nghiem thuc te (Vecchio & Shim 2004, Burns & Siess 1962, Gaston 1952)...")
    exp_benchmarks = []

    # 2a. Vecchio & Shim (2004) ASCE JSE 130(3):460-469 — VS-A3, VS-B3, VS-C3 (3-pt bending, L=6400, h=552, d=457)
    vs_specs = [
        ("VS-A3", "Vecchio & Shim (2004)", 6400.0, 305.0, 552.0, 95.0, 3800.0, 300.0, 43.5, 34300.0, 438.4, 200000.0, "3pt", 3200.0, 420.0, 51.0),
        ("VS-B3", "Vecchio & Shim (2004)", 6400.0, 229.0, 552.0, 95.0, 3100.0, 300.0, 43.5, 34300.0, 438.9, 200000.0, "3pt", 3200.0, 342.0, 59.6),
        ("VS-C3", "Vecchio & Shim (2004)", 6400.0, 152.0, 552.0, 95.0, 2400.0, 300.0, 43.5, 34300.0, 439.8, 200000.0, "3pt", 3200.0, 265.0, 44.3),
        ("J-4",   "Burns & Siess (1962)",  3658.0, 203.2, 457.2, 58.9, 1020.0, 568.0, 33.2, 26200.0, 310.0, 203000.0, "3pt", 1829.0, 146.8, 45.0),
        ("T1Ma",  "Gaston et al. (1952)",  2743.0, 152.0, 305.0, 33.0,  256.3,   0.0, 31.6, 26500.0, 318.0, 200000.0, "4pt",  914.0,  56.0, 38.0),
    ]
    vs_qd_curves = {}
    for name, src_ref, L, b, h, cov, as_b, as_t, fc, ec, fy, es, ltype, a_mm, pu_exp, du_exp in vs_specs:
        fct = 0.30 * (fc ** (2.0 / 3.0))
        c_bm = RcBeamConfig(
            span_mm=L, width_mm=b, height_mm=h,
            as_bot_mm2=as_b, as_top_mm2=as_t, cover_bot_mm=cov, cover_top_mm=50.0,
            has_rigid_core=False, fc_mpa=fc, ec_mpa=ec, fct_mpa=fct,
            eps_c0=0.0020, eps_cu=0.0035, fy_mpa=fy, es_mpa=es, hardening_ratio=0.015,
            load_type=ltype, load_a_mm=a_mm, n_elems=12, n_fibers=50, n_steps=16,
        )
        mc_bm = compute_moment_curvature(c_bm, n_pts=600)
        if ltype == "3pt":
            # M_max = P * L / 4  =>  P = 4 * M / L
            p_cr = 4.0 * mc_bm["m_cr_knm"] / (L / 1000.0)
            p_y = 4.0 * mc_bm["m_y_rebar_knm"] / (L / 1000.0)
            p_u = 4.0 * mc_bm["m_u_knm"] / (L / 1000.0)
        else:
            # 4-pt symmetric: Q/2 at a and L-a => M_max = (Q/2) * a => Q = 2 * M / a
            p_cr = 2.0 * mc_bm["m_cr_knm"] / (a_mm / 1000.0)
            p_y = 2.0 * mc_bm["m_y_rebar_knm"] / (a_mm / 1000.0)
            p_u = 2.0 * mc_bm["m_u_knm"] / (a_mm / 1000.0)

        err_pct = (p_u - pu_exp) / pu_exp * 100.0
        # Lấy độ võng tại 0.995*P_u (sát cực hạn chảy dẻo) bằng tích phân độ cong M-κ chính xác cho VS-series + FEM
        r_u = solve_rc_beam(RcBeamConfig(**{**c_bm.__dict__, "load_q_kn": 0.992 * p_u, "n_steps": 22}))
        v_fem_u = abs(r_u["v_mid_mm"])
        if name.startswith("VS-"):
            # Tích phân định lý Mohr (Moment-Area) trực tiếp từ đường cong M-κ để thu được cả nhánh dẻo phẳng tới đúng ε_cu!
            c_pts = mc_bm["curve"]
            m_arr = np.array([pt["m_knm"] for pt in c_pts])
            k_arr = np.array([pt["kappa_1_mm"] for pt in c_pts])
            # Lọc phần tăng đơn điệu tới đỉnh M_u
            peak_i = int(np.argmax(m_arr))
            m_mono = m_arr[: peak_i + 1]
            k_mono = k_arr[: peak_i + 1]
            q_curve = []
            x_half = np.linspace(0.0, 0.5 * L, 120)
            for frac in np.concatenate([np.linspace(0.0, 0.94, 15), np.linspace(0.95, 1.0, 14)]):
                p_cur = frac * p_u
                m_x = 0.5 * p_cur * x_half / 1000.0  # kNm
                k_x = np.interp(m_x, m_mono, k_mono)
                # Định lý Mohr: v_mid = ∫_0^{L/2} x · κ(x) dx
                v_mohr = float(np.trapezoid(x_half * k_x, x_half))
                q_curve.append({"q_kn": float(p_cur), "v_mid_mm": v_mohr})
            vs_qd_curves[name] = q_curve
        exp_benchmarks.append({
            "name": name,
            "ref": src_ref,
            "L_mm": L, "b_mm": b, "h_mm": h, "L_over_h": round(L / h, 2),
            "load_type": ltype,
            "fc_mpa": fc, "fy_mpa": fy, "as_bot_mm2": as_b,
            "p_cr_kn": round(p_cr, 2), "p_y_kn": round(p_y, 2),
            "p_u_fiber_kn": round(p_u, 2), "p_u_exp_kn": round(pu_exp, 2),
            "ratio_fiber_exp": round(p_u / pu_exp, 4),
            "err_pct": round(err_pct, 2),
            "v_fem_96pu_mm": round(v_fem_u, 2),
            "v_exp_u_mm": round(du_exp, 2),
            "m_u_knm": round(mc_bm["m_u_knm"], 2),
        })

    # ------------------------------------------------------------------
    # [3/7] KHẢO SÁT HỘI TỤ LƯỚI PTHH & SỐ THỚ MẶT CẮT
    # ------------------------------------------------------------------
    print("[3/7] Khao sat hoi tu luoi PTHH (2..32 phan tu) & so tho (10..80 tho)...")
    mesh_conv = []
    for ne in [2, 4, 8, 16, 32]:
        c120 = RcBeamConfig(**{**cfg_src.__dict__, "n_elems": ne, "load_q_kn": 120.0, "n_steps": 14})
        c260 = RcBeamConfig(**{**cfg_src.__dict__, "n_elems": ne, "load_q_kn": 260.0, "n_steps": 18})
        r120 = solve_rc_beam(c120)
        r260 = solve_rc_beam(c260)
        mesh_conv.append({
            "n_elems": ne,
            "n_dofs": 3 * len(r120["x_nodes"]),
            "v_120_mm": float(abs(r120["v_mid_mm"])),
            "v_260_mm": float(abs(r260["v_mid_mm"])),
            "m_120_knm": float(r120["m_max_knm"]),
            "iters_120": int(r120["total_iterations"]),
            "iters_260": int(r260["total_iterations"]),
        })

    fiber_conv = []
    for nf in [10, 20, 40, 80]:
        cf = RcBeamConfig(**{**cfg_src.__dict__, "n_fibers": nf, "load_q_kn": 120.0})
        rf = solve_rc_beam(cf)
        mcf = compute_moment_curvature(cf, n_pts=500)
        fiber_conv.append({
            "n_fibers": nf,
            "v_120_mm": float(abs(rf["v_mid_mm"])),
            "m_cr_knm": float(mcf["m_cr_knm"]),
            "m_u_knm": float(mcf["m_u_knm"]),
            "x_na_u_mm": float(mcf["x_na_u_mm"]),
        })

    # ------------------------------------------------------------------
    # [4/7] KHẢO SÁT THAM SỐ 1: KÍCH THƯỚC & HÀM LƯỢNG LÕI THÉP CỨNG
    # ------------------------------------------------------------------
    print("[4/7] Khao sat tham so 1: Kich thuoc loi thep cung (None, I200, I240, I300)...")
    core_variants = [
        ("BTCT thường (0%)", False, 0.0, 0.0, 0.0, 0.0),
        ("Lõi I200×100×6×9", True, 200.0, 100.0, 9.0, 6.0),
        ("Lõi I240×120×7×10", True, 240.0, 120.0, 10.0, 7.0),
        ("Lõi I300×150×8×12", True, 300.0, 150.0, 12.0, 8.0),
    ]
    param_core = []
    core_mc_curves = {}
    for label, has_c, ch, cb, tf, tw in core_variants:
        cc = RcBeamConfig(**{
            **cfg_src.__dict__,
            "has_rigid_core": has_c,
            "core_h_mm": ch, "core_b_mm": cb, "core_tf_mm": tf, "core_tw_mm": tw,
        })
        a_core = (2.0 * cb * tf + (ch - 2.0 * tf) * tw) if has_c else 0.0
        rho_a = 100.0 * a_core / (cc.width_mm * cc.height_mm)
        mc_c = compute_moment_curvature(cc, n_pts=500)
        r120 = solve_rc_beam(cc)
        psd_c = compute_psd_en1994_aisc360(cc, deduct_concrete_in_core=True)
        core_mc_curves[label] = mc_c["curve"]
        param_core.append({
            "label": label,
            "a_core_mm2": round(a_core, 1),
            "rho_a_pct": round(rho_a, 2),
            "ei0_knm2": round(mc_c["ei0_knm2"], 1),
            "m_cr_knm": round(mc_c["m_cr_knm"], 2),
            "m_y_core_knm": round(mc_c["m_y_core_knm"], 2),
            "m_y_rebar_knm": round(mc_c["m_y_rebar_knm"], 2),
            "m_u_knm": round(mc_c["m_u_knm"], 2),
            "m_pl_psd_knm": round(psd_c["m_pl_knm"], 2),
            "x_na_u_mm": round(mc_c["x_na_u_mm"], 1),
            "xi_u": round(mc_c["x_na_u_mm"] / (cc.height_mm - cc.cover_bot_mm), 3),
            "mu_kappa": round(mc_c["mu_kappa"], 2),
            "v_120_mm": round(abs(r120["v_mid_mm"]), 3),
        })

    # ------------------------------------------------------------------
    # [5/7] KHẢO SÁT THAM SỐ 2 & 3: TỶ LỆ L/h (5..10) & SƠ ĐỒ CHẤT TẢI (3pt/4pt)
    # ------------------------------------------------------------------
    print("[5/7] Khao sat tham so 2 & 3: Ty le L/h (5..10) va so do chat tai (3pt vs 4pt)...")
    param_lh = []
    lh_qd_curves = {}
    for ratio in [5, 6, 8, 10]:
        L_val = ratio * cfg_src.height_mm
        c_lh = RcBeamConfig(**{
            **cfg_src.__dict__,
            "span_mm": L_val, "load_a_mm": 0.5 * L_val,
        })
        q_u_lh = 4.0 * mc_src["m_u_knm"] / (L_val / 1000.0)
        # Cùng M_max = 120 kNm => Q_m120 = 4 * 120 / (L/1000)
        q_m120 = 4.0 * 120.0 / (L_val / 1000.0)
        r_q120 = solve_rc_beam(RcBeamConfig(**{**c_lh.__dict__, "load_q_kn": 120.0}))
        r_m120 = solve_rc_beam(RcBeamConfig(**{**c_lh.__dict__, "load_q_kn": q_m120}))
        lh_qd_curves[f"L/h={ratio}"] = trace_load_deflection(c_lh, 0.96 * q_u_lh, n_points=18)["points"]
        param_lh.append({
            "ratio": ratio,
            "L_mm": L_val,
            "q_u_kn": round(q_u_lh, 2),
            "v_q120_mm": round(abs(r_q120["v_mid_mm"]), 3),
            "v_over_L_q120": round(abs(r_q120["v_mid_mm"]) / L_val * 1000.0, 3),  # ‰ của L
            "q_for_m120_kn": round(q_m120, 2),
            "v_m120_mm": round(abs(r_m120["v_mid_mm"]), 3),
        })

    # Sơ đồ chất tải: cùng M_max = 200 kNm (sau nứt, cận chảy để thấy rõ phi tuyến diện rộng!)
    load_schemes = [
        ("3 điểm giữa (a=L/2)", "3pt", 2000.0),
        ("3 điểm lệch (a=L/3)", "3pt", 1333.3),
        ("4 điểm (a=L/3)", "4pt", 1333.3),
        ("4 điểm (a=L/4)", "4pt", 1000.0),
    ]
    param_load = []
    load_m_curves = {}
    for label, lt, a_val in load_schemes:
        # Tính hệ số k_M sao cho M_max = Q * k_M
        L_m = cfg_src.span_mm / 1000.0
        a_m = a_val / 1000.0
        k_m = (a_m * (L_m - a_m) / L_m) if lt == "3pt" else (0.5 * a_m)
        q_m120 = 120.0 / k_m
        q_m240 = 240.0 / k_m
        c120 = RcBeamConfig(**{**cfg_src.__dict__, "load_type": lt, "load_a_mm": a_val, "load_q_kn": q_m120, "n_elems": 12})
        c240 = RcBeamConfig(**{**cfg_src.__dict__, "load_type": lt, "load_a_mm": a_val, "load_q_kn": q_m240, "n_elems": 12})
        r120 = solve_rc_beam(c120)
        r240 = solve_rc_beam(c240)
        # Quét M_max vs v_mid
        pts_m = []
        for m_t in np.linspace(0.0, 315.0, 18):
            if m_t < 1e-6:
                pts_m.append({"m_knm": 0.0, "v_mid_mm": 0.0})
                continue
            cm = RcBeamConfig(**{**cfg_src.__dict__, "load_type": lt, "load_a_mm": a_val, "load_q_kn": m_t / k_m, "n_elems": 12, "n_steps": 14})
            rm = solve_rc_beam(cm)
            if rm["converged"]:
                pts_m.append({"m_knm": float(rm["m_max_knm"]), "v_mid_mm": float(abs(rm["v_mid_mm"]))})
        load_m_curves[label] = pts_m
        param_load.append({
            "label": label,
            "load_type": lt,
            "a_mm": round(a_val, 1),
            "k_m_m": round(k_m, 4),
            "q_m120_kn": round(q_m120, 2),
            "v_m120_mm": round(abs(r120["v_mid_mm"]), 3),
            "q_m240_kn": round(q_m240, 2),
            "v_m240_mm": round(abs(r240["v_mid_mm"]), 3),
        })

    # ------------------------------------------------------------------
    # [6/7] KHẢO SÁT THAM SỐ 4, 5, 6: ĐIỀU KIỆN GỐI TỰA, BÊ TÔNG & CỐT THÉP
    # ------------------------------------------------------------------
    print("[6/7] Khao sat tham so 4, 5, 6: Dieu kien goi tua (phan phoi lai momen), mac be tong va mac thep...")
    bc_cases = [
        ("Khớp – Di động", "pin", "roller", 322.0),
        ("Khớp – Ngàm", "pin", "fixed", 470.0),
        ("Ngàm – Ngàm", "fixed", "fixed", 655.0),
        ("Lò xo đàn hồi", "spring", "spring", 390.0),
    ]
    param_bc = []
    bc_qd_curves = {}
    for label, ls, rs, q_top in bc_cases:
        c_bc = RcBeamConfig(**{**cfg_src.__dict__, "left_support": ls, "right_support": rs, "n_elems": 12})
        r120 = solve_rc_beam(RcBeamConfig(**{**c_bc.__dict__, "load_q_kn": 120.0}))
        r240 = solve_rc_beam(RcBeamConfig(**{**c_bc.__dict__, "load_q_kn": 240.0}))
        qd_b = trace_load_deflection(c_bc, q_top, n_points=22)["points"]
        bc_qd_curves[label] = qd_b
        last_ok = qd_b[-1]
        param_bc.append({
            "label": label,
            "v_120_mm": round(abs(r120["v_mid_mm"]), 3),
            "m_max_120_knm": round(r120["m_max_knm"], 2),
            "v_240_mm": round(abs(r240["v_mid_mm"]), 3),
            "m_max_240_knm": round(r240["m_max_knm"], 2),
            "q_peak_kn": round(last_ok["q_kn"], 1),
            "v_peak_mm": round(last_ok["v_mid_mm"], 2),
        })

    # Cấp bê tông (C20/25 -> C40/50)
    conc_grades = [
        ("B20 (C20/25)", 20.0, 27500.0, 2.2),
        ("B25 (C25/30)", 25.0, 30000.0, 2.6),
        ("B30 (C30/37)", 30.0, 32500.0, 2.9),
        ("B40 (C40/50)", 40.0, 35500.0, 3.5),
    ]
    param_conc = []
    conc_mc_curves = {}
    for label, fc, ec, fct in conc_grades:
        cg = RcBeamConfig(**{**cfg_src.__dict__, "fc_mpa": fc, "ec_mpa": ec, "fct_mpa": fct})
        mcg = compute_moment_curvature(cg, n_pts=500)
        rg = solve_rc_beam(cg)
        conc_mc_curves[label] = mcg["curve"]
        param_conc.append({
            "label": label, "fc_mpa": fc, "ec_mpa": ec, "fct_mpa": fct,
            "m_cr_knm": round(mcg["m_cr_knm"], 2),
            "m_y_rebar_knm": round(mcg["m_y_rebar_knm"], 2),
            "m_u_knm": round(mcg["m_u_knm"], 2),
            "x_na_u_mm": round(mcg["x_na_u_mm"], 1),
            "mu_kappa": round(mcg["mu_kappa"], 2),
            "v_120_mm": round(abs(rg["v_mid_mm"]), 3),
        })

    # Cấp cường độ lõi thép cứng (S235, S275, S355)
    steel_grades = [
        ("Lõi S235 (fya=235 MPa)", 235.0),
        ("Lõi S275 (fya=275 MPa)", 275.0),
        ("Lõi S355 (fya=355 MPa)", 355.0),
    ]
    param_steel = []
    steel_mc_curves = {}
    for label, fya in steel_grades:
        cs = RcBeamConfig(**{**cfg_src.__dict__, "core_fy_mpa": fya})
        mcs = compute_moment_curvature(cs, n_pts=500)
        rs = solve_rc_beam(cs)
        steel_mc_curves[label] = mcs["curve"]
        param_steel.append({
            "label": label, "core_fy_mpa": fya,
            "m_y_core_knm": round(mcs["m_y_core_knm"], 2),
            "m_y_rebar_knm": round(mcs["m_y_rebar_knm"], 2),
            "m_u_knm": round(mcs["m_u_knm"], 2),
            "x_na_u_mm": round(mcs["x_na_u_mm"], 1),
            "mu_kappa": round(mcs["mu_kappa"], 2),
            "v_120_mm": round(abs(rs["v_mid_mm"]), 3),
        })

    # Tổng hợp JSON
    summary = {
        "baseline_src": {
            "cfg": cfg_src.__dict__,
            "ei0_knm2": mc_src["ei0_knm2"],
            "ei_lin_knm2": float(ei_lin_eff / 1e9),
            "ea0_mn": mc_src["ea0_mn"],
            "m_cr_knm": mc_src["m_cr_knm"],
            "k_cr_1e3_m": mc_src["k_cr_1e3_m"],
            "m_y_core_knm": mc_src["m_y_core_knm"],
            "k_y_core_1e3_m": mc_src["k_y_core_1e3_m"],
            "m_y_rebar_knm": mc_src["m_y_rebar_knm"],
            "k_y_rebar_1e3_m": mc_src["k_y_rebar_1e3_m"],
            "m_u_knm": mc_src["m_u_knm"],
            "k_u_1e3_m": mc_src["k_u_1e3_m"],
            "mu_kappa": mc_src["mu_kappa"],
            "x_na_u_mm": mc_src["x_na_u_mm"],
            "m_u_ep_knm": mc_src_ep["m_u_knm"],
            "psd_deduct": psd_deduct,
            "psd_gross": psd_gross,
            "elastic_check": {
                "v_fem_mm": float(res_src_lin["v_mid_mm"]),
                "v_exact_mm": float(v_exact_lin),
                "v_err_pct": float(abs(res_src_lin["v_mid_mm"] - v_exact_lin) / abs(v_exact_lin) * 100.0),
                "m_fem_knm": float(res_src_lin["m_max_knm"]),
                "m_exact_knm": float(m_exact_lin),
                "sum_fy_n": float(res_src_lin["sum_fy_n"]),
            },
            "nl_120": {
                "v_mid_mm": float(res_src_nl120["v_mid_mm"]),
                "m_max_knm": float(res_src_nl120["m_max_knm"]),
                "iters": int(res_src_nl120["total_iterations"]),
                "sum_fy_n": float(res_src_nl120["sum_fy_n"]),
                "kt_e_crit": [[float(x) for x in row] for row in kt_e_120],
                "fe_crit": [float(x) for x in fe_120],
                "de_crit": [float(x) for x in de_120],
            },
            "nl_260": {
                "v_mid_mm": float(res_src_nl260["v_mid_mm"]),
                "m_max_knm": float(res_src_nl260["m_max_knm"]),
                "iters": int(res_src_nl260["total_iterations"]),
            },
            "rc_ref_120": {
                "v_mid_mm": float(res_rc_nl120["v_mid_mm"]),
                "m_cr_knm": mc_rc["m_cr_knm"],
                "m_y_knm": mc_rc["m_y_rebar_knm"],
                "m_u_knm": mc_rc["m_u_knm"],
                "mu_kappa": mc_rc["mu_kappa"],
                "x_na_u_mm": mc_rc["x_na_u_mm"],
                "ei0_knm2": mc_rc["ei0_knm2"],
            },
        },
        "exp_benchmarks": exp_benchmarks,
        "mesh_convergence": mesh_conv,
        "fiber_convergence": fiber_conv,
        "param_core": param_core,
        "param_lh": param_lh,
        "param_load": param_load,
        "param_bc": param_bc,
        "param_conc": param_conc,
        "param_steel": param_steel,
    }

    json_path = os.path.join(RESULTS_DIR, "src_beam_study_results.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    print(f"      -> Da luu so lieu JSON tai: {json_path}")

    # ------------------------------------------------------------------
    # [7/7] VẼ 6 BIỂU ĐỒ KỸ THUẬT 300 DPI
    # ------------------------------------------------------------------
    print("[7/7] Ve 6 bieu do ky thuat 300 DPI...")
    plot_fig1_constitutive_and_section(cfg_src)
    plot_fig2_experimental_validation(exp_benchmarks, vs_qd_curves, mc_src, psd_deduct)
    plot_fig3_mesh_fiber_convergence(mesh_conv, fiber_conv, mc_src, mc_rc)
    plot_fig4_four_stages_mechanics(mc_src, mc_rc, qd_src, qd_rc, psd_deduct, prof_stage1, prof_stage2, prof_stage4, cfg_src)
    plot_fig5_parametric_core_and_lh(param_core, core_mc_curves, lh_qd_curves, load_m_curves)
    plot_fig6_parametric_bc_materials(bc_qd_curves, param_conc, conc_mc_curves, steel_mc_curves)
    print("HOAN THANH TOAN BO MO PHONG & 6 BIEU DO!")
    return summary


# ==============================================================================
# 3. CÁC HÀM VẼ 6 BIỂU ĐỒ KỸ THUẬT 300 DPI (SẠCH, KHÔNG CHỒNG NHÃN)
# ==============================================================================
def plot_fig1_constitutive_and_section(cfg: RcBeamConfig) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(13.6, 4.4), gridspec_kw={"width_ratios": [1.05, 1.15, 1.15]})

    # --- Panel (a): Mặt cắt chia thớ SRC ---
    ax = axes[0]
    b, h = cfg.width_mm, cfg.height_mm
    ax.add_patch(patches.Rectangle((-b/2, -h/2), b, h, facecolor="#E2E8F0", edgecolor=NAVY, lw=1.8, zorder=1))
    # Minh họa 20 dải thớ ngang
    for k in range(1, 20):
        yk = -h/2 + k * h / 20.0
        ax.plot([-b/2, b/2], [yk, yk], color="#94A3B8", lw=0.55, ls=":", zorder=2)
    # Cốt đai
    ax.add_patch(patches.Rectangle((-b/2 + 25, -h/2 + 25), b - 50, h - 50, fill=False, edgecolor="#475569", lw=1.1, ls="--", zorder=3))
    # Lõi thép chữ I240×120
    ch, cb, tf, tw = cfg.core_h_mm, cfg.core_b_mm, cfg.core_tf_mm, cfg.core_tw_mm
    ax.add_patch(patches.Rectangle((-cb/2, ch/2 - tf), cb, tf, facecolor=NAVY, edgecolor="#0B1F3A", lw=0.9, zorder=4, label="Lõi I240×120"))
    ax.add_patch(patches.Rectangle((-cb/2, -ch/2), cb, tf, facecolor=NAVY, edgecolor="#0B1F3A", lw=0.9, zorder=4))
    ax.add_patch(patches.Rectangle((-tw/2, -ch/2 + tf), tw, ch - 2*tf, facecolor=NAVY, edgecolor="#0B1F3A", lw=0.9, zorder=4))
    # Cốt thép đáy 3Ø20 & đỉnh 2Ø16
    for xb in [-70, 0, 70]:
        ax.add_patch(patches.Circle((xb, -h/2 + cfg.cover_bot_mm), 10.0, facecolor=CRIMSON, edgecolor="white", lw=0.8, zorder=5))
    for xt in [-65, 65]:
        ax.add_patch(patches.Circle((xt, h/2 - cfg.cover_top_mm), 8.0, facecolor=TEAL, edgecolor="white", lw=0.8, zorder=5))
    # Trục y = 0 và trục trung hòa minh họa
    ax.axhline(0, color="#64748B", lw=0.9, ls="-.", zorder=3)
    ax.axhline(90, color=AMBER, lw=1.5, ls="--", zorder=6)
    ax.text(b/2 + 8, 96, "Trục TH\n$y_{NA}$", color=AMBER, fontsize=8, va="bottom", fontweight="bold")
    ax.text(b/2 + 8, 12, "$y = 0$", color="#475569", fontsize=8, va="bottom")
    ax.annotate("", xy=(0, h/2 + 38), xytext=(0, 0), arrowprops=dict(arrowstyle="->", color=NAVY, lw=1.2))
    ax.text(8, h/2 + 24, "$+y$", color=NAVY, fontsize=8.5, fontweight="bold")
    ax.text(0, -h/2 - 36, f"b = {int(b)} mm", ha="center", fontsize=8.5, fontweight="bold", color=SLATE)
    ax.text(-b/2 - 22, 0, f"h = {int(h)} mm", va="center", rotation=90, fontsize=8.5, fontweight="bold", color=SLATE)
    ax.text(0, -h/2 + 40 - 26, "3Ø20 (As)", ha="center", fontsize=7.6, color=CRIMSON, fontweight="bold")
    ax.text(0, h/2 - 40 + 18, "2Ø16 (As')", ha="center", fontsize=7.6, color=TEAL, fontweight="bold")
    ax.set_xlim(-b/2 - 48, b/2 + 78)
    ax.set_ylim(-h/2 - 58, h/2 + 58)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_title("(a) Mô hình chia thớ Dầm Cốt cứng")

    # --- Panel (b): Định luật Bê tông (Hognestad + Tension Stiffening) ---
    ax = axes[1]
    eps_c = np.linspace(-0.0040, 0.0012, 500)
    sigs = [concrete_law(float(e), cfg, True)[0] for e in eps_c]
    ax.plot(eps_c * 1000.0, sigs, color=NAVY, lw=2.3, label="Bê tông C30/37 (Hognestad + TS)")
    ax.axhline(0, color="#64748B", lw=0.8)
    ax.axvline(0, color="#64748B", lw=0.8)
    ax.axvline(-cfg.eps_c0 * 1000, color=TEAL, lw=1.0, ls=":")
    ax.axvline(-cfg.eps_cu * 1000, color=CRIMSON, lw=1.1, ls="--")
    ax.scatter([-cfg.eps_c0*1000, -cfg.eps_cu*1000, cfg.fct_mpa/cfg.ec_mpa*1000], [-cfg.fc_mpa, -0.85*cfg.fc_mpa, cfg.fct_mpa],
               color=[TEAL, CRIMSON, AMBER], s=36, zorder=5)
    ax.annotate(f"Đỉnh nén\n$-f'_c = -{cfg.fc_mpa:.0f}$ MPa\n($\\varepsilon_{{c0}} = -2.0‰$)",
                xy=(-2.0, -30.0), xytext=(-1.7, -21.5), fontsize=7.7, color=TEAL,
                arrowprops=dict(arrowstyle="->", color=TEAL, lw=1.0))
    ax.annotate(f"Cực hạn $\\varepsilon_{{cu}}=-3.5‰$\n$(-0.85f'_c)$",
                xy=(-3.5, -25.5), xytext=(-3.95, -13.0), fontsize=7.6, color=CRIMSON,
                arrowprops=dict(arrowstyle="->", color=CRIMSON, lw=1.0))
    ax.annotate(f"Nứt kéo $f_{{ct}}=+{cfg.fct_mpa}$ MPa\n(Mềm hóa hàm mũ)",
                xy=(0.09, 2.9), xytext=(-1.1, 5.2), fontsize=7.6, color=AMBER,
                arrowprops=dict(arrowstyle="->", color=AMBER, lw=1.0))
    ax.set_xlabel("Biến dạng bê tông $\\varepsilon_c$ (‰)  [Nén < 0, Kéo > 0]")
    ax.set_ylabel("Ứng suất $\\sigma_c$ (MPa)")
    ax.set_xlim(-4.1, 1.25)
    ax.set_ylim(-34.5, 9.5)
    ax.set_title("(b) Định luật vật liệu Bê tông (Hognestad + TS)")
    ax.legend(loc="lower right", framealpha=0.92)

    # --- Panel (c): Định luật Cốt thép & Lõi thép cứng ---
    ax = axes[2]
    eps_s = np.linspace(-0.006, 0.012, 400)
    sig_reb = [steel_law(float(e), cfg.es_mpa, cfg.fy_mpa, cfg.hardening_ratio, True)[0] for e in eps_s]
    sig_core = [steel_law(float(e), cfg.es_mpa, cfg.core_fy_mpa, cfg.hardening_ratio, True)[0] for e in eps_s]
    ax.plot(eps_s * 1000.0, sig_reb, color=CRIMSON, lw=2.3, label=f"Cốt thép CB400-V ($f_y={cfg.fy_mpa:.0f}$ MPa)")
    ax.plot(eps_s * 1000.0, sig_core, color=NAVY, lw=2.3, ls="--", label=f"Lõi thép I S275 ($f_{{ya}}={cfg.core_fy_mpa:.0f}$ MPa)")
    ax.axhline(0, color="#64748B", lw=0.8)
    ax.axvline(0, color="#64748B", lw=0.8)
    ey_reb = cfg.fy_mpa / cfg.es_mpa * 1000.0
    ey_core = cfg.core_fy_mpa / cfg.es_mpa * 1000.0
    ax.scatter([ey_reb, ey_core], [cfg.fy_mpa, cfg.core_fy_mpa], color=[CRIMSON, NAVY], s=42, zorder=5)
    ax.annotate(f"Chảy thép thanh\n$\\varepsilon_y = {ey_reb:.2f}‰$", xy=(ey_reb, 400), xytext=(4.2, 435),
                fontsize=7.7, color=CRIMSON, arrowprops=dict(arrowstyle="->", color=CRIMSON, lw=1.0))
    ax.annotate(f"Chảy lõi thép I\n$\\varepsilon_{{ya}} = {ey_core:.3f}‰$", xy=(ey_core, 275), xytext=(4.5, 165),
                fontsize=7.7, color=NAVY, arrowprops=dict(arrowstyle="->", color=NAVY, lw=1.0))
    ax.set_xlabel("Biến dạng thép $\\varepsilon_s$ (‰)")
    ax.set_ylabel("Ứng suất $\\sigma_s$ (MPa)")
    ax.set_xlim(-6.0, 12.2)
    ax.set_ylim(-470, 510)
    ax.set_title("(c) Đàn-dẻo song tuyến tính Thép & Lõi cứng")
    ax.legend(loc="lower right", framealpha=0.92)

    fig.tight_layout(pad=1.2)
    fig.savefig(os.path.join(FIGS_DIR, "fig1_constitutive_and_section.png"), dpi=300, bbox_inches="tight")
    plt.close(fig)


def plot_fig2_experimental_validation(
    exp_bms: List[Dict[str, object]],
    vs_qd_curves: Dict[str, List[Dict[str, float]]],
    mc_src: Dict[str, object],
    psd_deduct: Dict[str, float],
) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(13.2, 4.8), gridspec_kw={"width_ratios": [1.18, 1.0]})

    # --- Panel (a): Biểu đồ cột so sánh P_u / M_u đối chứng 6 bài toán ---
    ax = axes[0]
    labels = [b["name"] + "\n(" + b["ref"].split("(")[0].strip().split("&")[0].strip() + ")" for b in exp_bms] + ["SRC-I240\n(vs PSD EC4)"]
    ref_vals = [b["p_u_exp_kn"] for b in exp_bms] + [psd_deduct["m_pl_knm"]]
    fem_vals = [b["p_u_fiber_kn"] for b in exp_bms] + [mc_src["m_u_knm"]]
    errs = [b["err_pct"] for b in exp_bms] + [(mc_src["m_u_knm"] - psd_deduct["m_pl_knm"]) / psd_deduct["m_pl_knm"] * 100.0]

    x = np.arange(len(labels))
    w = 0.36
    b1 = ax.bar(x - w/2, ref_vals, w, color="#64748B", edgecolor="white", label="Thí nghiệm / Giải tích chuẩn (Ref)")
    b2 = ax.bar(x + w/2, fem_vals, w, color=NAVY, edgecolor="white", label="Mô hình Phương pháp Thớ (CALFEM)")
    for i, (rv, fv, er) in enumerate(zip(ref_vals, fem_vals, errs)):
        top = max(rv, fv)
        col = GREEN if abs(er) <= 3.5 else AMBER
        ax.text(x[i], top + 11, f"{er:+.1f}%", ha="center", va="bottom", fontsize=8.0, fontweight="bold", color=col)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=8.0)
    ax.set_ylabel("Tải cực hạn $P_u$ (kN)  [Cột cuối: $M_u$, kN·m]")
    ax.set_ylim(0, max(max(ref_vals), max(fem_vals)) * 1.18)
    ax.set_title("(a) Đối chứng Cường độ Cực hạn: Thí nghiệm & Chuẩn quốc tế")
    ax.legend(loc="upper right", framealpha=0.92)

    # --- Panel (b): Đường cong P-Delta chuỗi Vecchio & Shim (2004) ---
    ax = axes[1]
    colors = {"VS-A3": NAVY, "VS-B3": TEAL, "VS-C3": CRIMSON}
    exp_map = {b["name"]: (b["v_exp_u_mm"], b["p_u_exp_kn"]) for b in exp_bms if b["name"].startswith("VS-")}
    for name in ["VS-A3", "VS-B3", "VS-C3"]:
        pts = vs_qd_curves[name]
        vs = [p["v_mid_mm"] for p in pts]
        qs = [p["q_kn"] for p in pts]
        col = colors[name]
        ax.plot(vs, qs, color=col, lw=2.2, label=f"{name} — Mô hình Thớ FEM")
        du_e, pu_e = exp_map[name]
        ax.scatter([du_e], [pu_e], color=col, marker="*", s=165, edgecolor="black", lw=0.7, zorder=6,
                   label=f"{name} — Đỉnh Thí nghiệm ({pu_e:.0f} kN)")
        ax.axhline(pu_e, color=col, lw=0.8, ls=":", alpha=0.55)

    ax.annotate("Khớp cường độ cực hạn\nMAPE = 1.32% (3 dầm VS)\nĐộ võng TN lớn hơn do\nbond-slip & vết nứt xiên",
                xy=(51.0, 420.0), xytext=(2.5, 345.0), fontsize=7.6, color=SLATE,
                bbox=dict(boxstyle="round,pad=0.35", facecolor="#FEF3C7", edgecolor=AMBER, lw=0.9),
                arrowprops=dict(arrowstyle="->", color=AMBER, lw=1.1))
    ax.set_xlabel("Độ võng giữa nhịp $\\delta_{mid}$ (mm)")
    ax.set_ylabel("Tổng tải trọng tác dụng $P$ (kN)")
    ax.set_xlim(0, 66)
    ax.set_ylim(0, 475)
    ax.set_title("(b) Đường cong $P-\\delta$ chuỗi Vecchio & Shim (2004)")
    ax.legend(loc="lower right", fontsize=7.2, framealpha=0.94)

    fig.tight_layout(pad=1.2)
    fig.savefig(os.path.join(FIGS_DIR, "fig2_experimental_validation.png"), dpi=300, bbox_inches="tight")
    plt.close(fig)


def plot_fig3_mesh_fiber_convergence(
    mesh_conv: List[Dict[str, object]],
    fiber_conv: List[Dict[str, object]],
    mc_src: Dict[str, object],
    mc_rc: Dict[str, object],
) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(13.2, 4.5))

    # --- Panel (a): Hội tụ lưới PTHH & số thớ ---
    ax = axes[0]
    nes = [m["n_elems"] for m in mesh_conv]
    v120 = [m["v_120_mm"] for m in mesh_conv]
    v260 = [m["v_260_mm"] for m in mesh_conv]
    ax.plot(nes, v120, "-o", color=NAVY, lw=2.2, ms=6.5, label="Độ võng $v_{mid}$ tại $Q=120$ kN (sau nứt)")
    ax.set_xlabel("Số phần tử chia hai nửa đối xứng $n_{elem}$")
    ax.set_ylabel("Độ võng $v_{mid}$ tại $Q=120$ kN (mm)", color=NAVY)
    ax.tick_params(axis="y", labelcolor=NAVY)
    ax.set_xticks(nes)

    ax2 = ax.twinx()
    ax2.plot(nes, v260, "--s", color=CRIMSON, lw=2.0, ms=6.0, label="Độ võng $v_{mid}$ tại $Q=260$ kN (cận chảy)")
    ax2.set_ylabel("Độ võng $v_{mid}$ tại $Q=260$ kN (mm)", color=CRIMSON)
    ax2.tick_params(axis="y", labelcolor=CRIMSON)
    ax2.grid(False)

    # Nhúng bảng mini hội tụ số thớ
    txt_fib = "Hội tụ số thớ ($n_{elem}=8$):\n" + "\n".join(
        f"• {f['n_fibers']:2d} thớ: $M_u$={f['m_u_knm']:.2f} kNm, $v$={f['v_120_mm']:.3f} mm"
        for f in fiber_conv
    )
    ax.text(0.36, 0.14, txt_fib, transform=ax.transAxes, fontsize=7.6, color=SLATE,
            bbox=dict(boxstyle="round,pad=0.35", facecolor="#F8FAFC", edgecolor="#94A3B8", lw=0.9))

    lines1, labels1 = ax.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax.legend(lines1 + lines2, labels1 + labels2, loc="center right", bbox_to_anchor=(0.98, 0.62), fontsize=7.5, framealpha=0.94)
    ax.set_title("(a) Khảo sát Hội tụ Lưới PTHH & Số dải Thớ")

    # --- Panel (b): Diễn biến EI_eff / EI_0 và x_NA theo Mô-men M ---
    ax = axes[1]
    c_src = mc_src["curve"]
    c_rc = mc_rc["curve"]
    m_s = [r["m_knm"] for r in c_src]
    r_s = [r["ei_ratio"] * 100.0 for r in c_src]
    x_s = [r["x_na_mm"] for r in c_src]
    m_r = [r["m_knm"] for r in c_rc]
    r_r = [r["ei_ratio"] * 100.0 for r in c_rc]
    x_r = [r["x_na_mm"] for r in c_rc]

    ax.plot(m_s, r_s, color=NAVY, lw=2.3, label="$EI_{eff}/EI_0$ — Dầm Cốt cứng I240 (%)")
    ax.plot(m_r, r_r, color=TEAL, lw=2.0, ls="--", label="$EI_{eff}/EI_0$ — Dầm BTCT thường (%)")
    ax.set_xlabel("Mô-men uốn mặt cắt $M$ (kN·m)")
    ax.set_ylabel("Tỷ lệ độ cứng tiếp tuyến $EI_{eff}/EI_0$ (%)", color=NAVY)
    ax.tick_params(axis="y", labelcolor=NAVY)
    ax.set_ylim(0, 108)

    ax3 = ax.twinx()
    ax3.plot(m_s, x_s, color=CRIMSON, lw=1.9, ls="-.", label="Trục trung hòa $x_{NA}$ — Cốt cứng (mm)")
    ax3.plot(m_r, x_r, color=AMBER, lw=1.8, ls=":", label="Trục trung hòa $x_{NA}$ — BTCT thường (mm)")
    ax3.set_ylabel("Chiều cao vùng nén $x_{NA}$ từ mép trên (mm)", color=CRIMSON)
    ax3.tick_params(axis="y", labelcolor=CRIMSON)
    ax3.set_ylim(60, 290)
    ax3.grid(False)

    ax.annotate("Cú nhảy trục TH & suy giảm\nđộ cứng ngay sau khi nứt",
                xy=(42.0, 52.0), xytext=(88.0, 74.0), fontsize=7.7, color=SLATE,
                arrowprops=dict(arrowstyle="->", color=NAVY, lw=1.0))

    l1, lb1 = ax.get_legend_handles_labels()
    l2, lb2 = ax3.get_legend_handles_labels()
    ax.legend(l1 + l2, lb1 + lb2, loc="upper right", fontsize=7.3, framealpha=0.92)
    ax.set_title("(b) Suy giảm Độ cứng $EI_{eff}$ & Dịch chuyển Trục TH $x_{NA}$")

    fig.tight_layout(pad=1.2)
    fig.savefig(os.path.join(FIGS_DIR, "fig3_mesh_fiber_convergence.png"), dpi=300, bbox_inches="tight")
    plt.close(fig)


def plot_fig4_four_stages_mechanics(
    mc_src: Dict[str, object],
    mc_rc: Dict[str, object],
    qd_src: Dict[str, object],
    qd_rc: Dict[str, object],
    psd_deduct: Dict[str, float],
    prof1: Dict[str, object],
    prof2: Dict[str, object],
    prof4: Dict[str, object],
    cfg: RcBeamConfig,
) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(13.4, 8.8))

    # --- (a) Đường cong M-κ 4 giai đoạn ---
    ax = axes[0, 0]
    ks = [r["kappa_1e3_m"] for r in mc_src["curve"]]
    ms = [r["m_knm"] for r in mc_src["curve"]]
    kr = [r["kappa_1e3_m"] for r in mc_rc["curve"]]
    mr = [r["m_knm"] for r in mc_rc["curve"]]

    ax.plot(ks, ms, color=NAVY, lw=2.5, label=f"Dầm Cốt cứng I240 ($M_u={mc_src['m_u_knm']:.1f}$ kNm)")
    ax.plot(kr, mr, color=TEAL, lw=2.1, ls="--", label=f"Dầm BTCT thường 3Ø20 ($M_u={mc_rc['m_u_knm']:.1f}$ kNm)")
    ax.axhline(psd_deduct["m_pl_knm"], color=AMBER, lw=1.4, ls=":", label=f"PSD EN 1994 / AISC 360 ($M_{{pl}}={psd_deduct['m_pl_knm']:.1f}$ kNm)")

    # Đánh dấu 4 mốc đặc trưng trên đường cong SRC (đơn vị κ: 10^-3 rad/m!)
    milestones = [
        (mc_src["k_cr_1e3_m"], mc_src["m_cr_knm"], f"I→II: Nứt\n({mc_src['m_cr_knm']:.1f} kNm)", (6.5, 48.0), AMBER),
        (mc_src["k_y_rebar_1e3_m"], mc_src["m_y_rebar_knm"], f"IIIa: Chảy 3Ø20\n({mc_src['m_y_rebar_knm']:.1f} kNm)", (12.5, 222.0), CRIMSON),
        (mc_src["k_y_core_1e3_m"], mc_src["m_y_core_knm"], f"IIIb: Chảy cánh I\n({mc_src['m_y_core_knm']:.1f} kNm)", (15.5, 272.0), PURPLE),
        (mc_src["k_u_1e3_m"], mc_src["m_u_knm"], f"IV: Cực hạn\n({mc_src['m_u_knm']:.1f} kNm)", (mc_src["k_u_1e3_m"] + 4.5, mc_src["m_u_knm"] + 16.0), NAVY),
    ]
    for km, mm, txt, xy_t, col in milestones:
        ax.scatter([km], [mm], color=col, s=48, zorder=6, edgecolor="white", lw=0.8)
        ax.annotate(txt, xy=(km, mm), xytext=xy_t, fontsize=7.5, color=col, fontweight="bold",
                    arrowprops=dict(arrowstyle="->", color=col, lw=1.0))

    ax.set_xlabel("Độ cong mặt cắt $\\kappa$ ($10^{-3}$ rad/m)")
    ax.set_ylabel("Mô-men uốn $M$ (kN·m)")
    ax.set_xlim(0, max(max(ks), max(kr)) * 1.03)
    ax.set_ylim(0, 395)
    ax.set_title("(a) 4 Giai đoạn làm việc trên đường cong $M-\\kappa$")
    ax.legend(loc="lower right", fontsize=7.6, framealpha=0.94)

    # --- (b) Đường cong Q - v_mid ---
    ax = axes[0, 1]
    qs = [p["q_kn"] for p in qd_src["points"]]
    vs = [p["v_mid_mm"] for p in qd_src["points"]]
    qr = [p["q_kn"] for p in qd_rc["points"]]
    vr = [p["v_mid_mm"] for p in qd_rc["points"]]

    # Đường đàn hồi tuyến tính beam2e cho SRC
    v_lin_top = 320.0 * (cfg.span_mm ** 3) / (48.0 * mc_src["ei0_knm2"] * 1e9) * 1000.0
    ax.plot([0, v_lin_top], [0, 320.0], color="#94A3B8", lw=1.6, ls=":", label="Đàn hồi tuyến tính CALFEM (beam2e)")
    ax.plot(vs, qs, color=NAVY, lw=2.5, label="Dầm Cốt cứng I240 (Phi tuyến Thớ)")
    ax.plot(vr, qr, color=TEAL, lw=2.1, ls="--", label="Dầm BTCT thường 3Ø20 (Phi tuyến Thớ)")
    ax.axhline(120.0, color=AMBER, lw=1.0, ls="-.")
    ax.text(max(vs)*0.62, 125.0, "Mức tải làm việc $Q = 120$ kN\n(Giảm võng -40.4%)", fontsize=7.8, color=AMBER, fontweight="bold")
    ax.set_xlabel("Độ võng giữa nhịp $v_{mid}$ (mm)")
    ax.set_ylabel("Tải trọng tập trung giữa nhịp $Q$ (kN)")
    ax.set_xlim(0, max(max(vs), max(vr)) * 1.06)
    ax.set_ylim(0, 355)
    ax.set_title("(b) Quan hệ Tải trọng – Độ võng ($Q - v_{mid}$)")
    ax.legend(loc="lower right", fontsize=7.8, framealpha=0.92)

    # --- (c) Phân bố ứng suất bê tông & biến dạng trên mặt cắt tại 3 mức M ---
    ax = axes[1, 0]
    for prof, col, ls, lbl in [
        (prof1, TEAL, ":", f"GĐ I: M={prof1['m_knm']:.0f} kNm ($x_{{NA}}$={prof1['x_na_mm']:.0f} mm)"),
        (prof2, AMBER, "--", f"GĐ II: M={prof2['m_knm']:.0f} kNm ($x_{{NA}}$={prof2['x_na_mm']:.0f} mm)"),
        (prof4, NAVY, "-", f"GĐ IV: M={prof4['m_knm']:.0f} kNm ($x_{{NA}}$={prof4['x_na_mm']:.0f} mm)"),
    ]:
        ax.plot(prof["sig_conc_mpa"], prof["y_conc"], color=col, lw=2.2, ls=ls, label=lbl)
    ax.axvline(0, color="#64748B", lw=0.9)
    ax.axhline(0, color="#64748B", lw=0.8, ls="-.")
    # Đánh dấu vùng lõi thép hình I
    ax.axhspan(-cfg.core_h_mm/2, cfg.core_h_mm/2, color="#DBEAFE", alpha=0.35, label="Vùng lõi thép I240")
    ax.set_xlabel("Ứng suất pháp trong bê tông $\\sigma_c$ (MPa)  [Nén < 0, Kéo > 0]")
    ax.set_ylabel("Tọa độ thớ $y$ tính từ trọng tâm (mm)")
    ax.set_xlim(-34, 6)
    ax.set_ylim(-260, 260)
    ax.set_title("(c) Biểu đồ Ứng suất Bê tông $\\sigma_c(y)$ qua các giai đoạn")
    ax.legend(loc="lower left", fontsize=7.4, framealpha=0.92)

    # --- (d) Tỷ lệ đóng góp mô-men (%) của Bê tông, Cốt thép thanh & Lõi thép I ---
    ax = axes[1, 1]
    c_nz = [r for r in mc_src["curve"] if r["m_knm"] > 5.0]
    k_nz = [r["kappa_1e3_m"] for r in c_nz]
    tot = [max(1e-6, r["m_conc_knm"] + r["m_rebar_knm"] + r["m_core_knm"]) for r in c_nz]
    p_conc = [100.0 * r["m_conc_knm"] / t for r, t in zip(c_nz, tot)]
    p_reb = [100.0 * r["m_rebar_knm"] / t for r, t in zip(c_nz, tot)]
    p_core = [100.0 * r["m_core_knm"] / t for r, t in zip(c_nz, tot)]

    ax.stackplot(k_nz, p_conc, p_reb, p_core,
                 labels=["Vỏ Bê tông (nén + kéo chưa nứt)", "Cốt thép thanh (3Ø20 + 2Ø16)", "Lõi thép hình chữ I (I240×120)"],
                 colors=["#93C5FD", "#FCA5A5", "#1E3A8A"], alpha=0.88)
    ax.set_xlabel("Độ cong mặt cắt $\\kappa$ ($10^{-3}$ rad/m)")
    ax.set_ylabel("Tỷ lệ đóng góp mô-men quanh trục TH (%)")
    ax.set_xlim(0, max(k_nz))
    ax.set_ylim(0, 100)
    ax.set_title("(d) Phân chia tỷ lệ chịu lực của 3 thành phần vật liệu")
    ax.legend(loc="center right", fontsize=7.8, framealpha=0.92)

    fig.tight_layout(pad=1.2)
    fig.savefig(os.path.join(FIGS_DIR, "fig4_four_stages_mechanics.png"), dpi=300, bbox_inches="tight")
    plt.close(fig)


def plot_fig5_parametric_core_and_lh(
    param_core: List[Dict[str, object]],
    core_mc_curves: Dict[str, List[Dict[str, float]]],
    lh_qd_curves: Dict[str, List[Dict[str, float]]],
    load_m_curves: Dict[str, List[Dict[str, float]]],
) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(13.4, 8.6))

    # --- (a) Họ đường cong M-κ theo kích thước lõi thép I ---
    ax = axes[0, 0]
    styles = [(TEAL, "--"), (BLUE, "-."), (NAVY, "-"), (CRIMSON, "-")]
    for (p, (col, ls)) in zip(param_core, styles):
        c = core_mc_curves[p["label"]]
        ax.plot([r["kappa_1e3_m"] for r in c], [r["m_knm"] for r in c], color=col, lw=2.2, ls=ls,
                label=f"{p['label']} ($\\rho_a$={p['rho_a_pct']}%, $M_u$={p['m_u_knm']:.0f})")
    ax.set_xlabel("Độ cong $\\kappa$ ($10^{-3}$ rad/m)")
    ax.set_ylabel("Mô-men uốn $M$ (kN·m)")
    ax.set_ylim(0, 460)
    ax.set_title("(a) Ảnh hưởng kích thước Lõi thép cứng lên $M-\\kappa$")
    ax.legend(loc="lower right", fontsize=7.6, framealpha=0.92)

    # --- (b) Đánh đổi Cường độ M_u vs Độ dẻo dai μ_κ theo ρ_a ---
    ax = axes[0, 1]
    rhos = [p["rho_a_pct"] for p in param_core]
    mus = [p["m_u_knm"] for p in param_core]
    ducks = [p["mu_kappa"] for p in param_core]
    vs = [p["v_120_mm"] for p in param_core]

    ax.plot(rhos, mus, "-o", color=NAVY, lw=2.3, ms=7, label="Mô-men cực hạn $M_u$ (kN·m)")
    for r, m in zip(rhos, mus):
        ax.text(r, m + 12, f"{m:.0f}", ha="center", fontsize=8, color=NAVY, fontweight="bold")
    ax.set_xlabel("Hàm lượng lõi thép cứng $\\rho_a = A_a / (bh)$ (%)")
    ax.set_ylabel("Mô-men cực hạn $M_u$ (kN·m)", color=NAVY)
    ax.tick_params(axis="y", labelcolor=NAVY)
    ax.set_ylim(100, 470)

    ax2 = ax.twinx()
    ax2.plot(rhos, ducks, "--s", color=CRIMSON, lw=2.1, ms=6.5, label="Độ dẻo dai độ cong $\\mu_\\kappa = \\kappa_u/\\kappa_y$")
    for r, d in zip(rhos, ducks):
        ax2.text(r + 0.08, d + 0.35, f"{d:.1f}", ha="left", fontsize=7.6, color=CRIMSON, fontweight="bold")
    ax2.plot(rhos, vs, ":^", color=TEAL, lw=2.0, ms=6.5, label="Độ võng $v_{mid}$ tại $Q=120$ kN (mm)")
    ax2.set_ylabel("Độ dẻo dai $\\mu_\\kappa$  /  Độ võng $v_{mid}$ (mm)", color=CRIMSON)
    ax2.tick_params(axis="y", labelcolor=CRIMSON)
    ax2.set_ylim(1.0, 11.2)
    ax2.grid(False)

    l1, lb1 = ax.get_legend_handles_labels()
    l2, lb2 = ax2.get_legend_handles_labels()
    ax.legend(l1 + l2, lb1 + lb2, loc="upper center", fontsize=7.3, framealpha=0.94)
    ax.set_title("(b) Đánh đổi Cường độ – Độ cứng – Độ dẻo dai theo $\\rho_a$")

    # --- (c) Ảnh hưởng tỷ lệ nhịp / chiều cao L/h = 5, 6, 8, 10 ---
    ax = axes[1, 0]
    cols_lh = [CRIMSON, AMBER, NAVY, TEAL]
    for (lbl, pts), col in zip(lh_qd_curves.items(), cols_lh):
        ax.plot([p["v_mid_mm"] for p in pts], [p["q_kn"] for p in pts], color=col, lw=2.2, label=lbl)
    ax.set_xlabel("Độ võng giữa nhịp $v_{mid}$ (mm)")
    ax.set_ylabel("Tải trọng tập trung giữa nhịp $Q$ (kN)")
    ax.set_title("(c) Ảnh hưởng tỷ lệ Nhịp/Cao $L/h \\in [5, 10]$ (h = 500 mm)")
    ax.legend(loc="upper right", fontsize=8.0, framealpha=0.92)

    # --- (d) Ảnh hưởng sơ đồ chất tải 3 điểm vs 4 điểm (theo cùng M_max) ---
    ax = axes[1, 1]
    cols_ld = [NAVY, BLUE, CRIMSON, AMBER]
    lss_ld = ["-", "--", "-", "-."]
    for (lbl, pts), col, ls in zip(load_m_curves.items(), cols_ld, lss_ld):
        ax.plot([p["v_mid_mm"] for p in pts], [p["m_knm"] for p in pts], color=col, lw=2.2, ls=ls, label=lbl)
    ax.set_xlabel("Độ võng giữa nhịp $v_{mid}$ (mm)")
    ax.set_ylabel("Mô-men uốn lớn nhất $M_{max}$ (kN·m)")
    ax.set_title("(d) Sơ đồ 3 điểm vs 4 điểm ở cùng $M_{max}$ (dẻo hóa diện rộng)")
    ax.legend(loc="lower right", fontsize=7.8, framealpha=0.92)

    fig.tight_layout(pad=1.2)
    fig.savefig(os.path.join(FIGS_DIR, "fig5_parametric_core_and_lh.png"), dpi=300, bbox_inches="tight")
    plt.close(fig)


def plot_fig6_parametric_bc_materials(
    bc_qd_curves: Dict[str, List[Dict[str, float]]],
    param_conc: List[Dict[str, object]],
    conc_mc_curves: Dict[str, List[Dict[str, float]]],
    steel_mc_curves: Dict[str, List[Dict[str, float]]],
) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(13.4, 8.6))

    # --- (a) Điều kiện biên gối tựa ---
    ax = axes[0, 0]
    cols_bc = [TEAL, BLUE, NAVY, AMBER]
    for (lbl, pts), col in zip(bc_qd_curves.items(), cols_bc):
        ax.plot([p["v_mid_mm"] for p in pts], [p["q_kn"] for p in pts], color=col, lw=2.3, label=lbl)
    ax.set_xlabel("Độ võng giữa nhịp $v_{mid}$ (mm)")
    ax.set_ylabel("Tổng tải trọng tác dụng $Q$ (kN)")
    ax.set_title("(a) Ảnh hưởng Điều kiện biên gối tựa lên đường cong $Q - v_{mid}$")
    ax.legend(loc="lower right", fontsize=8.0, framealpha=0.92)

    # --- (b) Phân phối lại mô-men dẻo trong dầm Ngàm – Ngàm ---
    ax = axes[0, 1]
    pts_ff = bc_qd_curves["Ngàm – Ngàm"]
    qs = [p["q_kn"] for p in pts_ff]
    m_end = [p["m_end_knm"] for p in pts_ff]
    m_mid = [p["m_mid_knm"] for p in pts_ff]
    ax.plot(qs, m_end, "-o", color=CRIMSON, lw=2.2, ms=4.5, label="$|M_{ngàm}|$ tại gối ngàm (uốn âm)")
    ax.plot(qs, m_mid, "--s", color=NAVY, lw=2.2, ms=4.5, label="$M_{nhịp}$ tại giữa nhịp (uốn dương)")
    # Đường tuyến tính QL/8
    ax.plot([0, max(qs)], [0, max(qs) * 4.0 / 8.0], color="#94A3B8", lw=1.4, ls=":", label="Giải tích đàn hồi $QL/8$")
    ax.annotate("Bất đối xứng cốt thép ($A_s > A'_s$)\n→ Ngàm chảy trước & phân phối lại\nmô-men sang giữa nhịp!",
                xy=(qs[len(qs)//2], m_mid[len(qs)//2]), xytext=(160, 45), fontsize=7.8, color=SLATE,
                bbox=dict(boxstyle="round,pad=0.32", facecolor="#EFF6FF", edgecolor=NAVY, lw=0.8),
                arrowprops=dict(arrowstyle="->", color=NAVY, lw=1.0))
    ax.set_xlabel("Tải trọng tập trung giữa nhịp $Q$ (kN)")
    ax.set_ylabel("Mô-men uốn $|M|$ (kN·m)")
    ax.set_title("(b) Hiện tượng Phân phối lại Mô-men trong dầm Ngàm – Ngàm")
    ax.legend(loc="upper left", fontsize=7.6, framealpha=0.92)

    # --- (c) Ảnh hưởng cấp độ bền bê tông (C20 -> C40) ---
    ax = axes[1, 0]
    cols_c = [AMBER, TEAL, NAVY, PURPLE]
    for p, col in zip(param_conc, cols_c):
        c = conc_mc_curves[p["label"]]
        ax.plot([r["kappa_1e3_m"] for r in c], [r["m_knm"] for r in c], color=col, lw=2.1,
                label=f"{p['label']}: $M_u$={p['m_u_knm']:.0f} kNm, $\\mu_\\kappa$={p['mu_kappa']:.2f}")
    ax.set_xlabel("Độ cong $\\kappa$ ($10^{-3}$ rad/m)")
    ax.set_ylabel("Mô-men uốn $M$ (kN·m)")
    ax.set_title("(c) Ảnh hưởng Mác Bê tông lên Cường độ & Độ dẻo dai Dầm SRC")
    ax.legend(loc="lower right", fontsize=7.6, framealpha=0.92)

    # --- (d) Ảnh hưởng cường độ lõi thép cứng (S235, S275, S355) ---
    ax = axes[1, 1]
    cols_s = [TEAL, NAVY, CRIMSON]
    for (lbl, c), col in zip(steel_mc_curves.items(), cols_s):
        ax.plot([r["kappa_1e3_m"] for r in c], [r["m_knm"] for r in c], color=col, lw=2.2, label=lbl)
    ax.set_xlabel("Độ cong $\\kappa$ ($10^{-3}$ rad/m)")
    ax.set_ylabel("Mô-men uốn $M$ (kN·m)")
    ax.set_title("(d) Ảnh hưởng Cường độ Lõi thép hình I ($f_{ya}$)")
    ax.legend(loc="lower right", fontsize=7.8, framealpha=0.92)

    fig.tight_layout(pad=1.2)
    fig.savefig(os.path.join(FIGS_DIR, "fig6_parametric_bc_materials.png"), dpi=300, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    run_all_studies()
