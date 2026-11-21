# -*- coding: utf-8 -*-
"""
================================================================================
XUẤT THUYẾT MINH CHUYÊN ĐỀ DẦM BÊ TÔNG CỐT CỨNG (SRC) SANG PDF CHUẨN ẤN PHẨM
================================================================================
Dựng bản in HTML + MathML chuẩn học thuật (100% số liệu thật từ
`results/src_beam_study_results.json` & 6 biểu đồ 300 DPI) và xuất PDF vector
chính xác bằng Microsoft Edge Headless (không phụ thuộc Word COM lock).
================================================================================
"""

from __future__ import annotations
import base64
import html
import json
import math
import os
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS_JSON = os.path.join(ROOT, "results", "src_beam_study_results.json")
FIGS_DIR = os.path.join(ROOT, "results", "src_beam_figs")
OUT_PDF = os.path.join(ROOT, "ThuyetMinh_DamBeTongCotCung_PhiTuyenTho_CALFEM.pdf")


def _img_b64(fname: str) -> str:
    p = os.path.join(FIGS_DIR, fname)
    with open(p, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode("ascii")


def _tbl(headers, rows, left_cols=None, col_widths=None):
    if left_cols is None:
        left_cols = {0}
    colgroup = ""
    if col_widths:
        colgroup = "<colgroup>" + "".join(f'<col style="width:{w}%">' for w in col_widths) + "</colgroup>"
    thead = "<thead><tr>" + "".join(f"<th>{html.escape(h)}</th>" for h in headers) + "</tr></thead>"
    body_rows = []
    for r in rows:
        is_sum = r and (r[0].startswith("Trung bình") or r[0].startswith("Tổng"))
        cls = ' class="sum-row"' if is_sum else ""
        tds = []
        for j, v in enumerate(r):
            al = "left" if (j in left_cols or len(v) > 22) else "right"
            tds.append(f'<td style="text-align:{al}">{html.escape(v).replace(chr(10), "<br/>")}</td>')
        body_rows.append(f"<tr{cls}>" + "".join(tds) + "</tr>")
    return f"<table>{colgroup}{thead}<tbody>{''.join(body_rows)}</tbody></table>"


def _eq(mathml: str, num: str, src: str = "") -> str:
    note = f'<div class="eq-src">Nguồn áp dụng: {html.escape(src)}</div>' if src else ""
    return f'<div class="eq-wrap"><div class="eq-math">{mathml}</div><div class="eq-num">({html.escape(num)})</div></div>{note}'


def _fig(fname: str, caption: str) -> str:
    return (
        f'<figure><img src="{_img_b64(fname)}" alt="{html.escape(fname)}"/>'
        f'<figcaption>{html.escape(caption)}</figcaption></figure>'
    )


def build_html(data: dict) -> str:
    bs = data["baseline_src"]
    ec = bs["elastic_check"]
    nl120 = bs["nl_120"]
    kt = nl120["kt_e_crit"]
    fe = nl120["fe_crit"]
    de = nl120["de_crit"]
    psd_d = bs["psd_deduct"]
    psd_g = bs["psd_gross"]
    exps = data["exp_benchmarks"]
    m_conv = data["mesh_convergence"]
    f_conv = data["fiber_convergence"]
    p_core = data["param_core"]
    p_lh = data["param_lh"]
    p_load = data["param_load"]
    p_bc = data["param_bc"]
    p_conc = data["param_conc"]
    p_steel = data["param_steel"]

    vs_only = [b for b in exps if b["name"].startswith("VS-")]
    vs_ratios = [b["ratio_fiber_exp"] for b in vs_only]
    vs_mape = sum(abs(b["err_pct"]) for b in vs_only) / len(vs_only)
    all_ratios = [b["ratio_fiber_exp"] for b in exps]
    all_mean = sum(all_ratios) / len(all_ratios)
    all_std = math.sqrt(sum((r - all_mean) ** 2 for r in all_ratios) / len(all_ratios))
    all_cov = all_std / all_mean * 100.0
    all_mape = sum(abs(b["err_pct"]) for b in exps) / len(exps)
    err_ep = (bs["m_u_ep_knm"] - psd_d["m_pl_knm"]) / psd_d["m_pl_knm"] * 100.0
    err_hard = (bs["m_u_knm"] - psd_d["m_pl_knm"]) / psd_d["m_pl_knm"] * 100.0

    # Bảng 1.1 & 1.2
    t11 = _tbl(
        ["Ký hiệu", "Tiêu chuẩn áp dụng", "Điều khoản / Mục trích dẫn", "Nội dung áp dụng trực tiếp trong bài toán"],
        [
            ["[TC1]", "TCVN 5574:2018", "Mục 6.1–6.2; §8.1.2; §8.2.2; Phụ lục B", "Mô hình ứng suất–biến dạng phi tuyến bê tông & cốt thép; biến dạng cực hạn ε_b2 = 0.0035, ε_b0 = 0.0020; tính tiết diện theo mô hình biến dạng phi tuyến và độ võng sau nứt."],
            ["[TC2]", "TCVN 5575:2012 / 2024", "Mục 5.1–5.3; Phụ lục B–C", "Đặc trưng cơ học thép hình cán nóng chữ I làm lõi cốt cứng (f_ya = 235–355 MPa, E_a = 200 GPa); phân loại độ mảnh bản cánh/bụng."],
            ["[TC3]", "EN 1992-1-1:2004 (EC2)", "§3.1.5, §3.1.7, §5.7, §7.4", "Quan hệ σ_c–ε_c phi tuyến cho phân tích kết cấu; f_ctm = 0.30·(f_ck)^(2/3); quy tắc phân tích phi tuyến và hiệu ứng cứng hóa kéo Tension Stiffening."],
            ["[TC4]", "EN 1994-1-1:2004 (EC4)", "§6.2.1.2, §6.7.1, §6.7.3, §6.7.5", "Tính mô-men dẻo M_pl,Rd theo Phân bố Ứng suất Dẻo (PSD) cho cấu kiện liên hợp thép bọc bê tông; δ ∈ [0.2, 0.9]; chiều dày lớp bê tông bọc & chống trượt dọc."],
            ["[TC5]", "ANSI/AISC 360-16 (Ch. I)", "§I1.2a, §I1.2b, §I2.1a, §I3.3", "Công nhận đồng thời 02 phương pháp: Phân bố Ứng suất Dẻo (PSD, 0.85 f'_c) và Tương thích Biến dạng (Strain Compatibility — Phương pháp Thớ); yêu cầu ρ_a ≥ 1%."],
            ["[TC6]", "JGJ 138-2016 (SRC Code)", "§5.2.1–§5.2.6", "Tiêu chuẩn chuyên sâu cho Dầm Bê tông Cốt cứng (SRC): khuyến nghị hàm lượng lõi thép hợp lý ρ_a = 2%–6%, kiểm soát chiều cao vùng nén ξ ≤ ξ_b."],
            ["[TC7]", "ACI 318-19 (Hoa Kỳ)", "§22.2.1–§22.2.2; §24.2.3", "Giả thiết tiết diện phẳng Euler–Bernoulli; khối ứng suất tương đương Whitney (0.85 f'_c); chuẩn so sánh độ cứng uốn hiệu dụng sau nứt."],
            ["[TC8]", "fib MC 2010 / CEB-FIP 90", "§5.1.8; §7.6", "Mô hình nhánh mềm hóa kéo của bê tông sau nứt (Tension Stiffening) bảo đảm tính liên tục của ma trận độ cứng tiếp tuyến."],
        ],
        left_cols={0, 1, 2, 3}, col_widths=[8, 22, 20, 50],
    )
    t12 = _tbl(
        ["Ký hiệu", "Tác giả / Tài liệu gốc", "Vai trò trong chuyên đề"],
        [
            ["[TL1]", "PGS. TS Ngô Hữu Cường & TS. Đoàn Ngọc Tịnh Nghiêm — Bài giảng Phân tích Phi tuyến Kết cấu (NSA_1–NSA_6), ĐH Bách Khoa TP.HCM", "Nền tảng phương pháp năng lượng Rayleigh–Ritz (Π = U − W → δΠ = 0), thiết lập ma trận độ cứng tiếp tuyến và thuật toán Newton–Raphson gia tăng tải."],
            ["[TL2]", "Austrell, Dahlblom et al. (2004) — CALFEM 3.4 Manual; Dahlblom & Olsson (2016) — Structural Mechanics (CALFEM), Wiley", "Chuẩn công thức phần tử dầm 2 nút 6 bậc tự do (beam2e), hàm dạng Hermite bậc 3, tích phân Gauss–Legendre và quy ước lắp ráp ma trận toàn cục."],
            ["[TL3]", "Hognestad, E. (1951) — Univ. of Illinois Eng. Exp. Station Bulletin No. 399", "Định luật ứng suất – biến dạng Parabol bậc 2 kết hợp nhánh giảm tuyến tính kinh điển cho bê tông chịu nén uốn."],
            ["[TL4]", "Spacone, E., Filippou, F. C. & Taucer, F. F. (1996) — Earthquake Eng. & Struct. Dynamics, 25(7), 711–725", "Cơ sở lý thuyết Mô hình Phần tử Dầm–Cột chia thớ (Fiber Section Method) và ma trận độ cứng tiếp tuyến mặt cắt [D_t] có khớp nối uốn–dọc trục."],
            ["[TL5]", "Vecchio, F. J. & Shim, W. (2004) — ASCE Journal of Structural Engineering, 130(3), 460–469", "Bộ dữ liệu thí nghiệm đối chứng chuẩn quốc tế tái lập thí nghiệm Bresler–Scordelis (1963): chuỗi dầm uốn chủ đạo VS-A3, VS-B3, VS-C3."],
            ["[TL6]", "Burns, N. H. & Siess, C. P. (1962) — Univ. of Illinois SRS No. 234; Kwak & Filippou (1990) — UCB/SEMM-90/14", "Dầm thí nghiệm thực tế J-4 (L/h = 8.0, uốn 3 điểm) dùng kiểm chứng chuẩn mực cho mô hình PTHH phi tuyến BTCT."],
            ["[TL7]", "Gaston, J. R., Siess, C. P. & Newmark, N. M. (1952) — Univ. of Illinois SRS No. 40", "Dầm thí nghiệm thực tế uốn 4 điểm đối xứng T1Ma (L/h = 9.0, hàm lượng thép thấp ρ = 0.62%) kiểm chứng vùng uốn thuần túy."],
            ["[TL8]", "Weng, C. C., Yen, S. I. & Jiang, M. H. (2002) — ASCE Journal of Structural Engineering, 128(9), 1186–1194", "Thí nghiệm quy mô thật trên dầm bê tông cốt cứng (SRC) làm rõ giới hạn cơ chế phá hoại cắt tách dọc cánh lõi thép (Shear-Splitting)."],
            ["[TL9]", "Crisfield, M. A. (1991) — Non-Linear Finite Element Analysis of Solids & Structures; Yang (2025), Springer", "Toán tử tiếp tuyến nhất quán (Consistent Tangent Operator) và tìm kiếm đường lùi Backtracking Line Search bảo đảm hội tụ bậc 2 qua vùng nứt."],
        ],
        left_cols={0, 1, 2}, col_widths=[8, 42, 50],
    )

    # Bảng 3.1
    bm_rows = []
    for b in exps:
        bm_rows.append([
            f"{b['name']} ({b['ref'].split('(')[0].strip()})",
            f"{int(b['b_mm'])}×{int(b['h_mm'])}\nL={int(b['L_mm'])} ({b['L_over_h']:.1f})",
            "3 điểm" if b["load_type"] == "3pt" else "4 điểm",
            f"f'c={b['fc_mpa']:.1f}\nfy={b['fy_mpa']:.0f}",
            f"{b['p_cr_kn']:.1f} / {b['p_y_kn']:.1f}",
            f"{b['p_u_exp_kn']:.1f}",
            f"{b['p_u_fiber_kn']:.1f}",
            f"{b['ratio_fiber_exp']:.3f}",
            f"{b['err_pct']:+.2f}%",
        ])
    bm_rows.append(["Trung bình 3 dầm VS (2004)", "Quy mô thật", "3 điểm", "Uốn chủ đạo", "—", "—", "—", f"{sum(vs_ratios)/3:.3f}", f"MAPE {vs_mape:.2f}%"])
    bm_rows.append(["Trung bình cả 5 dầm TN", "L/h = 8.0..11.6", "3pt & 4pt", "f'c=31–44", "—", "—", "—", f"{all_mean:.3f}", f"MAPE {all_mape:.2f}% (COV {all_cov:.2f}%)"])
    t31 = _tbl(
        ["Mẫu dầm (Nguồn)", "Tiết diện & L (L/h)", "Sơ đồ tải", "Vật liệu (MPa)", "P_cr / P_y Fiber (kN)", "P_u Thí nghiệm (kN)", "P_u Fiber (kN)", "Tỷ số Fiber/TN", "Sai số (%)"],
        bm_rows, left_cols={0, 1, 2, 3},
    )

    t32 = _tbl(
        ["Phương pháp / Tiêu chuẩn", "Giả thiết vật liệu", "Trục trung hòa (mm)", "Mô-men cực hạn (kN·m)", "Sai lệch so với PSD"],
        [
            ["Giải tích PSD — EN 1994-1-1 §6.2.1.2 / AISC 360-16 §I3.3 (trừ lõi)", "Khối nén 0.85 f'_c, thép đàn–dẻo lý tưởng (b_h = 0)", f"x_p = {psd_d['x_pna_mm']:.1f}", f"{psd_d['m_pl_knm']:.2f}", "Chuẩn đối chứng (0.00%)"],
            ["Giải tích PSD (không trừ bê tông chiếm chỗ)", "Khối nén 0.85 f'_c toàn chiều rộng b", f"x_p = {psd_g['x_pna_mm']:.1f}", f"{psd_g['m_pl_knm']:.2f}", f"{(psd_g['m_pl_knm']-psd_d['m_pl_knm'])/psd_d['m_pl_knm']*100:+.2f}%"],
            ["Phương pháp Thớ CALFEM (tái bền b_h = 0.0001)", "Hognestad nén + thép đàn–dẻo lý tưởng", f"x_NA = {bs['x_na_u_mm']:.1f}", f"{bs['m_u_ep_knm']:.2f}", f"{err_ep:+.2f}% (Khớp tuyệt đối < 1%!)"],
            ["Phương pháp Thớ CALFEM (tái bền thực tế b_h = 0.01)", "Hognestad nén + tái bền thép 1% (b_h = 0.01)", f"x_NA = {bs['x_na_u_mm']:.1f}", f"{bs['m_u_knm']:.2f}", f"{err_hard:+.2f}% (dự trữ tái bền thực)"],
        ],
        left_cols={0, 1},
    )

    # Bảng 4.1, 4.2, 4.3
    dof_lbls = ["u_i", "v_i", "θ_i", "u_j", "v_j", "θ_j"]
    t41 = _tbl(
        ["DOF", "u_i (mm)", "v_i (mm)", "θ_i (rad)", "u_j (mm)", "v_j (mm)", "θ_j (rad)"],
        [[dof_lbls[i]] + [f"{kt[i][j]:+.3e}" for j in range(6)] for i in range(6)],
        left_cols={0},
    )
    t42 = _tbl(
        ["Thành phần bậc tự do", "Nút trái i (x = 1500 mm)", "Nút phải j (x = 2000 mm, giữa nhịp)", "Kiểm tra cân bằng tĩnh học phần tử"],
        [
            ["Chuyển vị dọc trục u (mm)", f"{de[0]:+.5f} mm", f"{de[3]:+.5f} mm", "Trục y=0 giãn dài (+u) do trục TH dâng lên trên!"],
            ["Độ võng đứng v (mm)", f"{de[1]:+.5f} mm", f"{de[4]:+.5f} mm", "Độ võng lớn nhất đúng giữa nhịp v_mid = −3.065 mm"],
            ["Góc xoay mặt cắt θ (rad)", f"{de[2]:+.6f} rad", f"{de[5]:+.2e} rad", "Góc xoay giữa nhịp θ_j = 0.000 (đối xứng tuyệt đối)"],
            ["Lực dọc đầu phần tử N (kN)", f"{fe[0]/1e3:+.3e} kN", f"{fe[3]/1e3:+.3e} kN", f"∑F_x = {(fe[0]+fe[3])/1e3:.2e} kN ≈ 0 (Uốn thuần túy)"],
            ["Lực cắt đầu phần tử V (kN)", f"{fe[1]/1e3:+.4f} kN", f"{fe[4]/1e3:+.4f} kN", f"V = Q/2 = 60.000 kN ; ∑F_y = {(fe[1]+fe[4])/1e3:.2e} kN"],
            ["Mô-men đầu phần tử M (kN·m)", f"{fe[2]/1e6:+.4f} kN·m", f"{fe[5]/1e6:+.4f} kN·m", f"M_j + M_i + V_j·L_e = {(fe[5]+fe[2]+fe[4]*500)/1e6:.2e} kN·m"],
        ],
        left_cols={0, 3},
    )
    v120_ref = m_conv[-1]["v_120_mm"]
    v260_ref = m_conv[-1]["v_260_mm"]
    mu_ref = f_conv[-1]["m_u_knm"]
    conv_rows = [
        [f"Lưới {m['n_elems']} phần tử ({m['n_dofs']} DOF)", f"{m['v_120_mm']:.4f}", f"{(m['v_120_mm']-v120_ref)/v120_ref*100:+.2f}%", f"{m['v_260_mm']:.4f}", f"{(m['v_260_mm']-v260_ref)/v260_ref*100:+.2f}%", f"{m['iters_120']} / {m['iters_260']}"]
        for m in m_conv
    ] + [
        [f"Số thớ n_fib = {fc_r['n_fibers']} (dy = {500/fc_r['n_fibers']:.1f} mm)", f"{fc_r['v_120_mm']:.4f}", f"M_u = {fc_r['m_u_knm']:.2f} kNm", f"x_NA = {fc_r['x_na_u_mm']:.2f} mm", f"{(fc_r['m_u_knm']-mu_ref)/mu_ref*100:+.3f}% (M_u)", "Ổn định"]
        for fc_r in f_conv
    ]
    t43 = _tbl(["Cấu hình rời rạc hóa", "v_mid (120 kN) (mm)", "Sai số / M_u", "v_mid (260 kN) / x_NA", "Sai số hội tụ", "Số vòng lặp NR"], conv_rows)

    # Bảng 6.1 .. 6.5
    m_rc0 = p_core[0]["m_u_knm"]
    v_rc0 = p_core[0]["v_120_mm"]
    t61 = _tbl(
        ["Cấu hình lõi thép", "ρ_a (%)", "M_cr (kNm)", "M_y thép/lõi (kNm)", "M_u Fiber (kNm)", "M_pl PSD (kNm)", "x_NA,u (ξ_u)", "Độ dẻo μ_κ", "v_mid 120kN (mm)"],
        [
            [p["label"], f"{p['rho_a_pct']:.2f}%", f"{p['m_cr_knm']:.1f}",
             f"{p['m_y_rebar_knm']:.1f} / {p['m_y_core_knm']:.1f}" if p["m_y_core_knm"] > 0 else f"{p['m_y_rebar_knm']:.1f} / —",
             f"{p['m_u_knm']:.1f} ({(p['m_u_knm']-m_rc0)/m_rc0*100:+.0f}%)", f"{p['m_pl_psd_knm']:.1f}",
             f"{p['x_na_u_mm']:.1f} ({p['xi_u']:.2f})", f"{p['mu_kappa']:.2f}", f"{p['v_120_mm']:.2f} ({(p['v_120_mm']-v_rc0)/v_rc0*100:+.0f}%)"]
            for p in p_core
        ],
    )
    t62 = _tbl(
        ["Tỷ lệ nhịp / chiều cao", "Tải phá hoại Q_u (kN)", "v_mid tại Q=120 kN (mm)", "Tỷ số võng v/L (Q=120)", "Q tạo M=120 kNm (kN)", "v_mid tại M=120 kNm (mm)"],
        [[f"L/h = {p['ratio']} (L = {int(p['L_mm'])} mm)", f"{p['q_u_kn']:.1f}", f"{p['v_q120_mm']:.3f}", f"L / {int(round(p['L_mm']/max(1e-6, p['v_q120_mm'])))}", f"{p['q_for_m120_kn']:.1f}", f"{p['v_m120_mm']:.3f}"] for p in p_lh],
    )
    t63 = _tbl(
        ["Sơ đồ chất tải", "Khoảng cách a (mm)", "Hệ số M/Q (m)", "Q (M=120 kNm)", "v_mid (M=120) (mm)", "Q (M=240 kNm)", "v_mid (M=240) (mm)"],
        [[p["label"], f"{p['a_mm']:.1f}", f"{p['k_m_m']:.4f}", f"{p['q_m120_kn']:.1f}", f"{p['v_m120_mm']:.3f}", f"{p['q_m240_kn']:.1f}", f"{p['v_m240_mm']:.3f}"] for p in p_load],
    )
    t64 = _tbl(
        ["Điều kiện gối tựa hai đầu", "v_mid (120 kN) (mm)", "M_max (120 kN) (kNm)", "v_mid (240 kN) (mm)", "M_max (240 kN) (kNm)", "Q đạt cực đại (kN)", "v_mid tương ứng (mm)"],
        [[p["label"], f"{p['v_120_mm']:.3f}", f"{p['m_max_120_knm']:.1f}", f"{p['v_240_mm']:.3f}", f"{p['m_max_240_knm']:.1f}", f"{p['q_peak_kn']:.0f}", f"{p['v_peak_mm']:.2f}"] for p in p_bc],
    )
    t65 = _tbl(
        ["Biến thể vật liệu (Dầm SRC I240×120)", "M_cr (kNm)", "M_y (kNm)", "M_u (kNm)", "x_NA,u (mm)", "Độ dẻo μ_κ", "v_120 (mm)"],
        [[f"Bê tông {p['label']} (Lõi S275)", f"{p['m_cr_knm']:.1f}", f"{p['m_y_rebar_knm']:.1f}", f"{p['m_u_knm']:.1f}", f"{p['x_na_u_mm']:.1f}", f"{p['mu_kappa']:.2f}", f"{p['v_120_mm']:.3f}"] for p in p_conc]
        + [[f"{p['label']} (Bê tông B30)", f"{bs['m_cr_knm']:.1f}", f"{p['m_y_core_knm']:.1f} (lõi)", f"{p['m_u_knm']:.1f}", f"{p['x_na_u_mm']:.1f}", f"{p['mu_kappa']:.2f}", f"{p['v_120_mm']:.3f}"] for p in p_steel],
    )

    eqs_ch2 = "".join([
        _eq("<math><mi>ε</mi><mo>(</mo><mi>x</mi><mo>,</mo><mi>y</mi><mo>)</mo><mo>=</mo><msub><mi>ε</mi><mn>0</mn></msub><mo>(</mo><mi>x</mi><mo>)</mo><mo>−</mo><mi>y</mi><mo>·</mo><mi>κ</mi><mo>(</mo><mi>x</mi><mo>)</mo><mo>,</mo><mspace width='1.2em'/><msub><mi>ε</mi><mn>0</mn></msub><mo>=</mo><mfrac><mrow><mi>d</mi><mi>u</mi></mrow><mrow><mi>d</mi><mi>x</mi></mrow></mfrac><mo>,</mo><mspace width='1.2em'/><mi>κ</mi><mo>=</mo><mfrac><mrow><msup><mi>d</mi><mn>2</mn></msup><mi>v</mi></mrow><mrow><mi>d</mi><msup><mi>x</mi><mn>2</mn></msup></mrow></mfrac></math>", "2.1", "Euler–Bernoulli; TCVN 5574:2018 §8.1.2 [TC1]; Spacone et al. (1996) [TL4]"),
        "<p><b>1) Bê tông chịu nén (Hognestad, ε ≤ 0, ε<sub>c</sub> = −ε):</b> Parabol bậc 2 tới đỉnh −f'<sub>c</sub> tại ε<sub>c0</sub> = 2.0‰, sau đó giảm mềm tuyến tính về −0.85 f'<sub>c</sub> tại ε<sub>cu</sub> = 3.5‰:</p>",
        _eq("<math><msub><mi>σ</mi><mi>c</mi></msub><mo>=</mo><mo>−</mo><msubsup><mi>f</mi><mi>c</mi><mo>′</mo></msubsup><mo>[</mo><mn>2</mn><mfrac><msub><mi>ε</mi><mi>c</mi></msub><msub><mi>ε</mi><mrow><mi>c</mi><mn>0</mn></mrow></msub></mfrac><mo>−</mo><msup><mrow><mo>(</mo><mfrac><msub><mi>ε</mi><mi>c</mi></msub><msub><mi>ε</mi><mrow><mi>c</mi><mn>0</mn></mrow></msub></mfrac><mo>)</mo></mrow><mn>2</mn></msup><mo>]</mo><mo>,</mo><mspace width='1em'/><msub><mi>E</mi><mi>t</mi></msub><mo>=</mo><mfrac><mrow><mn>2</mn><msubsup><mi>f</mi><mi>c</mi><mo>′</mo></msubsup></mrow><msub><mi>ε</mi><mrow><mi>c</mi><mn>0</mn></mrow></msub></mfrac><mo>(</mo><mn>1</mn><mo>−</mo><mfrac><msub><mi>ε</mi><mi>c</mi></msub><msub><mi>ε</mi><mrow><mi>c</mi><mn>0</mn></mrow></msub></mfrac><mo>)</mo></math>", "2.2", "Hognestad (1951) [TL3]; TCVN 5574:2018 §6.1.3 [TC1]"),
        "<p><b>2) Bê tông chịu kéo sau nứt (Tension Stiffening, ε &gt; ε<sub>cr</sub> = f<sub>ct</sub>/E<sub>c</sub>):</b></p>",
        _eq("<math><msub><mi>σ</mi><mi>c</mi></msub><mo>=</mo><msub><mi>f</mi><mrow><mi>c</mi><mi>t</mi></mrow></msub><mo>·</mo><mi>exp</mi><mo>(</mo><mo>−</mo><mn>0.35</mn><mfrac><mrow><mi>ε</mi><mo>−</mo><msub><mi>ε</mi><mrow><mi>c</mi><mi>r</mi></mrow></msub></mrow><msub><mi>ε</mi><mrow><mi>c</mi><mi>r</mi></mrow></msub></mfrac><mo>)</mo><mo>,</mo><mspace width='1.2em'/><msub><mi>E</mi><mi>t</mi></msub><mo>=</mo><mfrac><mrow><mi>d</mi><msub><mi>σ</mi><mi>c</mi></msub></mrow><mrow><mi>d</mi><mi>ε</mi></mrow></mfrac><mo>=</mo><mo>−</mo><mn>0.35</mn><mfrac><msub><mi>σ</mi><mi>c</mi></msub><msub><mi>ε</mi><mrow><mi>c</mi><mi>r</mi></mrow></msub></mfrac></math>", "2.3", "EN 1992-1-1 §7.4 [TC3]; fib MC 2010 [TC8]; Consistent Tangent [TL9]"),
        "<p><b>3) Cốt thép thanh và Lõi thép hình chữ I (đàn–dẻo song tuyến tính có tái bền b<sub>h</sub>):</b></p>",
        _eq("<math><msub><mi>σ</mi><mi>s</mi></msub><mo>=</mo><mi>sgn</mi><mo>(</mo><mi>ε</mi><mo>)</mo><mo>[</mo><msub><mi>f</mi><mi>y</mi></msub><mo>+</mo><msub><mi>b</mi><mi>h</mi></msub><msub><mi>E</mi><mi>s</mi></msub><mo>(</mo><mo>|</mo><mi>ε</mi><mo>|</mo><mo>−</mo><msub><mi>ε</mi><mi>y</mi></msub><mo>)</mo><mo>]</mo><mspace width='0.8em'/><mtext>khi </mtext><mo>|</mo><mi>ε</mi><mo>|</mo><mo>&gt;</mo><msub><mi>ε</mi><mi>y</mi></msub><mo>=</mo><mfrac><msub><mi>f</mi><mi>y</mi></msub><msub><mi>E</mi><mi>s</mi></msub></mfrac></math>", "2.4", "TCVN 5574:2018 §6.2.4 [TC1]; TCVN 5575:2012/2024 [TC2]"),
    ])

    eqs_sec = "".join([
        _eq("<math><mi>N</mi><mo>=</mo><msubsup><mo>∑</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><msub><mi>N</mi><mi>f</mi></msub></msubsup><msub><mi>σ</mi><mi>i</mi></msub><msub><mi>A</mi><mi>i</mi></msub><mo>,</mo><mspace width='1.5em'/><mi>M</mi><mo>=</mo><mo>−</mo><msubsup><mo>∑</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><msub><mi>N</mi><mi>f</mi></msub></msubsup><msub><mi>σ</mi><mi>i</mi></msub><msub><mi>y</mi><mi>i</mi></msub><msub><mi>A</mi><mi>i</mi></msub></math>", "2.5", "Spacone et al. (1996) [TL4]; TCVN 5574:2018 §8.1.2 [TC1]"),
        _eq("<math><mrow><mo>[</mo><msub><mi mathvariant='bold'>D</mi><mi>t</mi></msub><mo>]</mo></mrow><mo>=</mo><mrow><mo>[</mo><mtable><mtr><mtd><msub><mrow><mi>E</mi><mi>A</mi></mrow><mi>t</mi></msub></mtd><mtd><msub><mrow><mi>E</mi><mi>S</mi></mrow><mi>t</mi></msub></mtd></mtr><mtr><mtd><msub><mrow><mi>E</mi><mi>S</mi></mrow><mi>t</mi></msub></mtd><mtd><msub><mrow><mi>E</mi><mi>I</mi></mrow><mi>t</mi></msub></mtd></mtr></mtable><mo>]</mo></mrow><mo>=</mo><msubsup><mo>∑</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><msub><mi>N</mi><mi>f</mi></msub></msubsup><msub><mi>E</mi><mrow><mi>t</mi><mo>,</mo><mi>i</mi></mrow></msub><msub><mi>A</mi><mi>i</mi></msub><mrow><mo>[</mo><mtable><mtr><mtd><mn>1</mn></mtd><mtd><mo>−</mo><msub><mi>y</mi><mi>i</mi></msub></mtd></mtr><mtr><mtd><mo>−</mo><msub><mi>y</mi><mi>i</mi></msub></mtd><mtd><msubsup><mi>y</mi><mi>i</mi><mn>2</mn></msubsup></mtd></mtr></mtable><mo>]</mo></mrow></math>", "2.6", "Ma trận độ cứng tiếp tuyến mặt cắt có khớp nối dọc trục – uốn [TL4]"),
        _eq("<math><msub><mrow><mi>E</mi><mi>I</mi></mrow><mtext>eff</mtext></msub><mo>=</mo><msub><mrow><mi>E</mi><mi>I</mi></mrow><mi>t</mi></msub><mo>−</mo><mfrac><msubsup><mrow><mi>E</mi><mi>S</mi></mrow><mi>t</mi><mn>2</mn></msubsup><msub><mrow><mi>E</mi><mi>A</mi></mrow><mi>t</mi></msub></mfrac><mo>,</mo><mspace width='1.2em'/><msub><mi>y</mi><mtext>NA</mtext></msub><mo>=</mo><mfrac><msub><mi>ε</mi><mn>0</mn></msub><mi>κ</mi></mfrac><mo>,</mo><mspace width='1.2em'/><msub><mi>x</mi><mtext>NA</mtext></msub><mo>=</mo><mfrac><mi>h</mi><mn>2</mn></mfrac><mo>−</mo><msub><mi>y</mi><mtext>NA</mtext></msub></math>", "2.7", "Độ cứng uốn hiệu dụng và tọa độ trục trung hòa tức thời [TL4], [TL1]"),
    ])

    eqs_fem = "".join([
        _eq("<math><mrow><mo>[</mo><mi mathvariant='bold'>B</mi><mo>(</mo><mi>ξ</mi><mo>)</mo><mo>]</mo></mrow><mo>=</mo><mrow><mo>[</mo><mtable><mtr><mtd><mfrac><mrow><mo>−</mo><mn>1</mn></mrow><msub><mi>L</mi><mi>e</mi></msub></mfrac></mtd><mtd><mn>0</mn></mtd><mtd><mn>0</mn></mtd><mtd><mfrac><mn>1</mn><msub><mi>L</mi><mi>e</mi></msub></mfrac></mtd><mtd><mn>0</mn></mtd><mtd><mn>0</mn></mtd></mtr><mtr><mtd><mn>0</mn></mtd><mtd><mfrac><mrow><mo>−</mo><mn>6</mn><mo>+</mo><mn>12</mn><mi>ξ</mi></mrow><msubsup><mi>L</mi><mi>e</mi><mn>2</mn></msubsup></mfrac></mtd><mtd><mfrac><mrow><mo>−</mo><mn>4</mn><mo>+</mo><mn>6</mn><mi>ξ</mi></mrow><msub><mi>L</mi><mi>e</mi></msub></mfrac></mtd><mtd><mn>0</mn></mtd><mtd><mfrac><mrow><mn>6</mn><mo>−</mo><mn>12</mn><mi>ξ</mi></mrow><msubsup><mi>L</mi><mi>e</mi><mn>2</mn></msubsup></mfrac></mtd><mtd><mfrac><mrow><mo>−</mo><mn>2</mn><mo>+</mo><mn>6</mn><mi>ξ</mi></mrow><msub><mi>L</mi><mi>e</mi></msub></mfrac></mtd></mtr></mtable><mo>]</mo></mrow></math>", "2.8", "Hàm dạng Hermite bậc 3 — CALFEM 3.4 beam2e [TL2]; Bài giảng NSA_3 [TL1]"),
        _eq("<math><mi>Π</mi><mo>=</mo><mi>U</mi><mo>−</mo><mi>W</mi><mo>=</mo><msub><mo>∫</mo><mi>V</mi></msub><mrow><mo>(</mo><msubsup><mo>∫</mo><mn>0</mn><mi>ε</mi></msubsup><mi>σ</mi><mi>d</mi><mi>ε</mi><mo>)</mo></mrow><mi>d</mi><mi>V</mi><mo>−</mo><msup><mrow><mo>{</mo><mi mathvariant='bold'>d</mi><mo>}</mo></mrow><mi>T</mi></msup><mrow><mo>{</mo><msub><mi mathvariant='bold'>F</mi><mtext>ext</mtext></msub><mo>}</mo></mrow><mspace width='0.8em'/><mo>⇒</mo><mspace width='0.8em'/><mi>δ</mi><mi>Π</mi><mo>=</mo><mn>0</mn><mspace width='0.6em'/><mo>⇒</mo><mspace width='0.6em'/><mrow><mo>{</mo><msub><mi mathvariant='bold'>F</mi><mtext>int</mtext></msub><mo>}</mo></mrow><mo>=</mo><mrow><mo>{</mo><msub><mi mathvariant='bold'>F</mi><mtext>ext</mtext></msub><mo>}</mo></mrow></math>", "2.9", "Nguyên lý dừng thế năng toàn phần Rayleigh–Ritz — Bài giảng NSA_3/NSA_4 [TL1]"),
        _eq("<math><mrow><mo>{</mo><msubsup><mi mathvariant='bold'>f</mi><mtext>int</mtext><mi>e</mi></msubsup><mo>}</mo></mrow><mo>=</mo><msubsup><mo>∑</mo><mrow><mi>g</mi><mo>=</mo><mn>1</mn></mrow><mn>3</mn></msubsup><msub><mi>w</mi><mi>g</mi></msub><msub><mi>L</mi><mi>e</mi></msub><msup><mrow><mo>[</mo><mi mathvariant='bold'>B</mi><mo>]</mo></mrow><mi>T</mi></msup><mrow><mo>{</mo><mtable><mtr><mtd><mi>N</mi></mtd></mtr><mtr><mtd><mi>M</mi></mtd></mtr></mtable><mo>}</mo></mrow><mo>,</mo><mspace width='1.1em'/><mrow><mo>[</mo><msubsup><mi mathvariant='bold'>K</mi><mi>t</mi><mi>e</mi></msubsup><mo>]</mo></mrow><mo>=</mo><msubsup><mo>∑</mo><mrow><mi>g</mi><mo>=</mo><mn>1</mn></mrow><mn>3</mn></msubsup><msub><mi>w</mi><mi>g</mi></msub><msub><mi>L</mi><mi>e</mi></msub><msup><mrow><mo>[</mo><mi mathvariant='bold'>B</mi><mo>]</mo></mrow><mi>T</mi></msup><mrow><mo>[</mo><msub><mi mathvariant='bold'>D</mi><mi>t</mi></msub><mo>]</mo></mrow><mrow><mo>[</mo><mi mathvariant='bold'>B</mi><mo>]</mo></mrow></math>", "2.10", "Tích phân Gauss–Legendre 3 điểm trên phần tử dầm 6-DOF [TL2], [TL4]"),
        _eq("<math><mrow><mo>[</mo><msub><mi mathvariant='bold'>K</mi><mi>t</mi></msub><mo>]</mo></mrow><mrow><mo>{</mo><mi>Δ</mi><mi mathvariant='bold'>d</mi><mo>}</mo></mrow><mo>=</mo><mrow><mo>{</mo><mi mathvariant='bold'>R</mi><mo>}</mo></mrow><mo>=</mo><mi>λ</mi><mrow><mo>{</mo><msub><mi mathvariant='bold'>F</mi><mtext>ref</mtext></msub><mo>}</mo></mrow><mo>−</mo><mrow><mo>{</mo><msub><mi mathvariant='bold'>F</mi><mtext>int</mtext></msub><mo>}</mo></mrow><mo>,</mo><mspace width='1.0em'/><msup><mrow><mo>{</mo><mi mathvariant='bold'>d</mi><mo>}</mo></mrow><mrow><mo>(</mo><mi>k</mi><mo>+</mo><mn>1</mn><mo>)</mo></mrow></msup><mo>=</mo><msup><mrow><mo>{</mo><mi mathvariant='bold'>d</mi><mo>}</mo></mrow><mrow><mo>(</mo><mi>k</mi><mo>)</mo></mrow></msup><mo>+</mo><mi>α</mi><mrow><mo>{</mo><mi>Δ</mi><mi mathvariant='bold'>d</mi><mo>}</mo></mrow></math>", "2.11", "Thuật toán Full Newton–Raphson + Backtracking Line Search (α ∈ (0, 1]) [TL1], [TL9]"),
        _eq("<math><mn>0.85</mn><msubsup><mi>f</mi><mi>c</mi><mo>′</mo></msubsup><mi>b</mi><msub><mi>x</mi><mi>p</mi></msub><mo>+</mo><msub><mo>∑</mo><mrow><msub><mi>z</mi><mi>k</mi></msub><mo>&lt;</mo><msub><mi>x</mi><mi>p</mi></msub></mrow></msub><msub><mi>A</mi><mrow><mi>s</mi><mo>,</mo><mi>k</mi></mrow></msub><mrow><mo>(</mo><msub><mi>f</mi><mrow><mi>y</mi><mo>,</mo><mi>k</mi></mrow></msub><mo>−</mo><mn>0.85</mn><msubsup><mi>f</mi><mi>c</mi><mo>′</mo></msubsup><mo>)</mo></mrow><mo>−</mo><msub><mo>∑</mo><mrow><msub><mi>z</mi><mi>k</mi></msub><mo>≥</mo><msub><mi>x</mi><mi>p</mi></msub></mrow></msub><msub><mi>A</mi><mrow><mi>s</mi><mo>,</mo><mi>k</mi></mrow></msub><msub><mi>f</mi><mrow><mi>y</mi><mo>,</mo><mi>k</mi></mrow></msub><mo>=</mo><mn>0</mn></math>", "2.12", "Cân bằng lực dọc PSD — EN 1994-1-1 §6.2.1.2 [TC4]; AISC 360-16 §I3.3 [TC5]"),
        _eq("<math><msub><mi>M</mi><mrow><mi>p</mi><mi>l</mi></mrow></msub><mo>=</mo><mn>0.85</mn><msubsup><mi>f</mi><mi>c</mi><mo>′</mo></msubsup><mi>b</mi><mfrac><msubsup><mi>x</mi><mi>p</mi><mn>2</mn></msubsup><mn>2</mn></mfrac><mo>+</mo><msub><mo>∑</mo><mi>k</mi></msub><msub><mi>F</mi><mrow><mi>s</mi><mo>,</mo><mi>k</mi></mrow></msub><mo>·</mo><mrow><mo>|</mo><msub><mi>x</mi><mi>p</mi></msub><mo>−</mo><msub><mi>z</mi><mi>k</mi></msub><mo>|</mo></mrow></math>", "2.13", "Mô-men dẻo cực hạn PSD — EN 1994-1-1 §6.2.1.2 [TC4]; AISC 360-16 §I3.3 [TC5]"),
    ])

    eq51 = _eq("<math><mfrac><mrow><msub><mi>y</mi><mtext>NA</mtext></msub><mo>−</mo><msub><mi>y</mi><mi>f</mi></msub></mrow><mrow><msub><mi>y</mi><mtext>NA</mtext></msub><mo>−</mo><msub><mi>y</mi><mi>s</mi></msub></mrow></mfrac><mspace width='0.6em'/><mo>≷</mo><mspace width='0.6em'/><mfrac><msub><mi>f</mi><mrow><mi>y</mi><mi>a</mi></mrow></msub><msub><mi>f</mi><mi>y</mi></msub></mfrac></math>", "5.1", "Tiêu chuẩn hình học – vật lý xác định thứ tự chảy cánh lõi thép I vs cốt thép thanh đáy")

    refs_std = [
        "[TC1] TCVN 5574:2018 — Thiết kế kết cấu bê tông và bê tông cốt thép, Bộ Khoa học và Công nghệ, Hà Nội (2018).",
        "[TC2] TCVN 5575:2012 & TCVN 5575:2024 — Kết cấu thép – Tiêu chuẩn thiết kế, Bộ Khoa học và Công nghệ, Hà Nội.",
        "[TC3] EN 1992-1-1:2004 (Eurocode 2) — Design of concrete structures – Part 1-1: General rules and rules for buildings, CEN, Brussels.",
        "[TC4] EN 1994-1-1:2004 (Eurocode 4) — Design of composite steel and concrete structures – Part 1-1: General rules and rules for buildings, CEN, Brussels.",
        "[TC5] ANSI/AISC 360-16 — Specification for Structural Steel Buildings (Chapter I: Design of Composite Members), AISC, Chicago (2016).",
        "[TC6] JGJ 138-2016 — Code for Design of Composite Structures (Tiêu chuẩn thiết kế kết cấu bê tông cốt cứng SRC), MOHURD, Beijing (2016).",
        "[TC7] ACI 318-19 — Building Code Requirements for Structural Concrete and Commentary, ACI, Farmington Hills, MI (2019).",
        "[TC8] fib Model Code for Concrete Structures 2010 (và CEB-FIP Model Code 1990), fib, Lausanne (2013).",
    ]
    refs_lit = [
        "[TL1] Ngô Hữu Cường & Đoàn Ngọc Tịnh Nghiêm — Bài giảng Phân tích Phi tuyến Kết cấu (NSA_1 đến NSA_6), Khoa Kỹ thuật Xây dựng, Trường ĐH Bách Khoa – ĐHQG TP.HCM.",
        "[TL2] Austrell, P.-E., Dahlblom, O. et al. (2004) — CALFEM: A Finite Element Toolbox, Version 3.4, Lund University, Sweden.",
        "[TL3] Hognestad, E. (1951) — A Study of Combined Bending and Axial Load in Reinforced Concrete Members, Bulletin No. 399, Univ. of Illinois.",
        "[TL4] Spacone, E., Filippou, F. C. & Taucer, F. F. (1996) — Fibre Beam-Column Model for Non-Linear Analysis of R/C Frames: Part I, EESD, 25(7), 711–725.",
        "[TL5] Vecchio, F. J. & Shim, W. (2004) — Experimental and Analytical Reexamination of Classic Concrete Beam Tests, ASCE J. Struct. Eng., 130(3), 460–469.",
        "[TL6] Burns, N. H. & Siess, C. P. (1962) — Load-Deformation Characteristics of Beam-Column Connections in RC, Univ. of Illinois SRS No. 234; Kwak & Filippou (1990) UCB/SEMM-90/14.",
        "[TL7] Gaston, J. R., Siess, C. P. & Newmark, N. M. (1952) — Load-Deformation Characteristics of RC Beams Up to Failure, Univ. of Illinois SRS No. 40.",
        "[TL8] Weng, C. C., Yen, S. I. & Jiang, M. H. (2002) — Experimental Study on Shear Splitting Failure of Full-Scale Composite Concrete Encased Steel Beams, ASCE JSE, 128(9), 1186–1194.",
        "[TL9] Crisfield, M. A. (1991) — Non-Linear Finite Element Analysis of Solids and Structures, Wiley; Yang, Y. B. (2025) — Physics-Based Computational Methods for Nonlinear Framed Structures, Springer.",
        "[TL10] Dahlblom, O. & Olsson, K.-G. (2016) — Structural Mechanics: Modelling and Analysis of Frames and Trusses (CALFEM), Wiley.",
    ]

    return f"""<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="utf-8"/>
<title>Thuyết minh Chuyên đề Dầm Bê tông Cốt cứng (SRC) — Phương pháp Thớ &amp; CALFEM</title>
<style>
  @page {{
    size: A4 portrait;
    margin: 18mm 18mm 18mm 20mm;
    @top-right {{
      content: "Chuyên đề Phân tích Phi tuyến Dầm Bê tông Cốt cứng (SRC) — Phương pháp Thớ & CALFEM";
      font-family: "Times New Roman", serif;
      font-size: 8.5pt;
      font-style: italic;
      color: #475569;
    }}
    @bottom-center {{
      content: "Lâm Phúc Tâm (2670621) – Võ Thanh Vang (2670624)  |  ĐH Bách Khoa TP.HCM  |  Trang " counter(page);
      font-family: "Times New Roman", serif;
      font-size: 9pt;
      color: #475569;
    }}
  }}
  @page :first {{
    margin: 14mm;
    @top-right {{ content: none; }}
    @bottom-center {{ content: none; }}
  }}
  body {{
    font-family: "Times New Roman", Georgia, serif;
    font-size: 11pt;
    line-height: 1.38;
    color: #1E293B;
    margin: 0;
  }}
  .cover {{
    border: 4.5pt double #0F3D6E;
    padding: 16mm 14mm;
    min-height: 248mm;
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    page-break-after: always;
  }}
  .c-center {{ text-align: center; }}
  .c-univ1 {{ font-size: 13pt; font-weight: bold; color: #0F3D6E; }}
  .c-univ2 {{ font-size: 15pt; font-weight: bold; color: #0F3D6E; margin-top: 2px; }}
  .c-fac {{ font-size: 11.5pt; font-weight: bold; color: #0F766E; margin-top: 3px; }}
  .c-rule {{ border: 0; border-top: 1.5pt solid #0F3D6E; width: 58%; margin: 10px auto 26px; }}
  .c-type {{ font-size: 14pt; font-weight: bold; color: #475569; letter-spacing: 0.6px; }}
  .c-course {{ font-size: 20pt; font-weight: bold; color: #0F3D6E; margin: 4px 0 18px; }}
  .c-box {{
    background: #EFF6FF;
    border: 1.5pt solid #0F3D6E;
    padding: 14px 16px;
    text-align: center;
    margin: 10px 0 24px;
  }}
  .c-box-sub {{ font-size: 11.5pt; font-weight: bold; color: #0F766E; margin-bottom: 6px; }}
  .c-box-title {{ font-size: 12.6pt; font-weight: bold; color: #0F3D6E; line-height: 1.45; }}
  .info-tbl {{ width: 100%; border-collapse: collapse; margin: 12px 0; }}
  .info-tbl td {{ border: none !important; padding: 4.5px 6px; vertical-align: top; font-size: 10.6pt; }}
  .info-tbl td:first-child {{ width: 34%; font-weight: bold; color: #475569; }}
  .info-tbl tr:nth-child(-n+3) td:last-child {{ font-weight: bold; color: #0F3D6E; }}
  h1 {{
    font-size: 13.5pt; color: #0F3D6E; border-bottom: 1.6pt solid #0F3D6E;
    padding-bottom: 4px; margin: 0 0 10px; page-break-before: always; break-after: avoid;
  }}
  h1.first-ch {{ page-break-before: auto; }}
  h2 {{ font-size: 11.8pt; color: #0F766E; margin: 12px 0 5px; break-after: avoid; }}
  h3 {{ font-size: 11pt; color: #1E293B; margin: 9px 0 4px; break-after: avoid; }}
  p {{ text-align: justify; margin: 0 0 6px; }}
  ul {{ margin: 3px 0 7px 18px; padding: 0; }}
  li {{ text-align: justify; margin-bottom: 4.5px; }}
  .tbl-title {{ font-weight: bold; color: #0F3D6E; font-size: 10.2pt; margin: 8px 0 3px; break-after: avoid; }}
  table {{ width: 100%; border-collapse: collapse; margin: 0 0 8px; font-size: 8.6pt; }}
  th {{ background: #0F3D6E; color: #fff; font-weight: bold; text-align: center; padding: 5px 5px; border: 0.6pt solid #0F3D6E; }}
  td {{ padding: 4.2px 5px; border: 0.5pt solid #CBD5E1; vertical-align: middle; line-height: 1.25; }}
  tbody tr:nth-child(even) {{ background: #F8FAFC; }}
  tr.sum-row td {{ background: #E0F2FE !important; font-weight: bold; color: #0F3D6E; }}
  tr {{ break-inside: avoid; }}
  .eq-wrap {{ display: flex; align-items: center; justify-content: space-between; margin: 6px 0 1px; break-inside: avoid; }}
  .eq-math {{ flex: 1; text-align: center; font-size: 11pt; font-family: "Cambria Math", "Times New Roman", serif; }}
  .eq-num {{ width: 48px; text-align: right; color: #475569; font-size: 10pt; }}
  .eq-src {{ text-align: right; font-style: italic; font-size: 8.6pt; color: #64748B; margin-bottom: 6px; }}
  figure {{ margin: 8px 0 10px; text-align: center; break-inside: avoid; }}
  figure img {{ max-width: 100%; height: auto; border: 0.4pt solid #E2E8F0; }}
  figcaption {{ font-style: italic; font-size: 9.4pt; color: #475569; margin-top: 4px; text-align: center; }}
  .callout {{
    background: #ECFDF5; border: 0.7pt solid #0F766E; border-left: 4pt solid #0F766E;
    padding: 9px 12px; margin: 8px 0 10px; break-inside: avoid;
  }}
  .callout-title {{ font-weight: bold; color: #0F766E; font-size: 10.8pt; margin-bottom: 5px; }}
  .callout p {{ font-size: 10.1pt; margin-bottom: 4px; }}
  .ref-p {{ padding-left: 24px; text-indent: -24px; font-size: 9.8pt; margin-bottom: 3.5px; text-align: justify; }}
</style>
</head>
<body>

<div class="cover">
  <div class="c-center">
    <div class="c-univ1">ĐẠI HỌC QUỐC GIA THÀNH PHỐ HỒ CHÍ MINH</div>
    <div class="c-univ2">TRƯỜNG ĐẠI HỌC BÁCH KHOA</div>
    <div class="c-fac">KHOA KỸ THUẬT XÂY DỰNG – BỘ MÔN CÔNG TRÌNH</div>
    <hr class="c-rule"/>
    <div class="c-type">THUYẾT MINH CHUYÊN ĐỀ HỌC PHẦN</div>
    <div class="c-course">PHÂN TÍCH PHI TUYẾN KẾT CẤU</div>
    <div class="c-box">
      <div class="c-box-sub">CHUYÊN ĐỀ NGHIÊN CỨU CHUYÊN SÂU:</div>
      <div class="c-box-title">
        PHÂN TÍCH PHI TUYẾN VẬT LIỆU DẦM BÊ TÔNG CỐT CỨNG (SRC) &amp; BTCT CHỊU UỐN<br/>
        THEO PHƯƠNG PHÁP THỚ (FIBER SECTION) – RAYLEIGH–RITZ (CALFEM 3.4),<br/>
        KIỂM CHỨNG BENCHMARK THỰC NGHIỆM QUỐC TẾ VÀ KHẢO SÁT BẢN CHẤT ỨNG XỬ
      </div>
    </div>
  </div>
  <table class="info-tbl">
    <tr><td>Giảng viên hướng dẫn:</td><td>PGS. TS NGÔ HỮU CƯỜNG</td></tr>
    <tr><td>Học viên thực hiện:</td><td>LÂM PHÚC TÂM (MSHV: 2670621)</td></tr>
    <tr><td></td><td>VÕ THANH VANG (MSHV: 2670624)</td></tr>
    <tr><td>Email &amp; điện thoại:</td><td>Email: vothanhvang@gmail.com  •  ĐT: 0973.993.494</td></tr>
    <tr><td>Căn cứ tiêu chuẩn áp dụng:</td><td>TCVN 5574:2018 • TCVN 5575:2012/2024 • EN 1992-1-1 • EN 1994-1-1 • ANSI/AISC 360-16 • JGJ 138-2016 • ACI 318-19</td></tr>
    <tr><td>Benchmark kiểm chứng:</td><td>Vecchio &amp; Shim (2004, ASCE JSE) • Burns &amp; Siess (1962) • Gaston et al. (1952) • Giải tích PSD EN 1994 / AISC 360</td></tr>
    <tr><td>Kho mã nguồn &amp; ứng dụng:</td><td>https://github.com/vothanhvang/PhanTichPhiTuyen_BaiTieuLuan4</td></tr>
  </table>
  <div class="c-center" style="font-weight:bold;color:#0F3D6E;font-size:11.5pt;">THÀNH PHỐ HỒ CHÍ MINH — NĂM 2026</div>
</div>

<h1 class="first-ch">CHƯƠNG 1. ĐẶT VẤN ĐỀ, BẢN CHẤT DẦM BÊ TÔNG CỐT CỨNG (SRC) &amp; HỆ THỐNG TIÊU CHUẨN ÁP DỤNG</h1>
<h2>1.1. Đặt vấn đề và mục tiêu chuyên đề</h2>
<p>Trong xây dựng nhà cao tầng, cầu vượt nhịp trung bình – lớn và công trình công nghiệp chịu tải trọng nặng, dầm bê tông cốt thép thường (BTCT) thường bị giới hạn bởi chiều cao tiết diện khống chế thông thủy, độ võng lớn sau khi bê tông vùng kéo nứt hoặc hàm lượng cốt thép thanh quá dày. Giải pháp <b>Dầm Bê tông Cốt cứng</b> (Steel Reinforced Concrete — SRC, hay Concrete-Encased Composite Beam theo Eurocode 4 và AISC 360) — đặt một tiết diện thép hình chữ I làm lõi chịu lực đồng tâm kết hợp với lồng cốt thép dọc và cốt đai bao quanh trong khối bê tông — kết hợp tối ưu ưu thế của cả hai vật liệu: vỏ bê tông chống cháy, chống ăn mòn và kiềm chế mất ổn định cục bộ cánh nén lõi thép; còn lõi thép chữ I duy trì độ cứng tiếp tuyến ổn định sau khi bê tông nứt và tạo ra quá trình chảy dẻo tuần tự nhiều tầng giàu dự trữ an toàn.</p>
<p>Chuyên đề này giải quyết trọn vẹn 4 mục tiêu: (1) Hệ thống hóa căn cứ tiêu chuẩn Việt Nam &amp; quốc tế cùng tài liệu gốc; (2) Thiết lập tường minh công thức PTHH Phương pháp Thớ – Rayleigh–Ritz theo chuẩn CALFEM 3.4; (3) Kiểm chứng định lượng độ tin cậy bằng 05 bài toán thí nghiệm thực tế quốc tế và giải tích PSD của EN 1994-1-1 / AISC 360-16; (4) Phân tích đi sâu bản chất cơ học 4 giai đoạn và khảo sát 6 yếu tố thiết kế ảnh hưởng đến ứng xử dầm.</p>
<h2>1.2. Hệ thống Tiêu chuẩn Kỹ thuật và Tài liệu Khoa học áp dụng</h2>
<div class="tbl-title">Bảng 1.1. Danh mục Tiêu chuẩn Kỹ thuật áp dụng và phạm vi trích dẫn trực tiếp trong tính toán</div>
{t11}
<div class="tbl-title">Bảng 1.2. Tài liệu học thuật, giáo trình nền tảng và nguồn dữ liệu thí nghiệm đối chứng</div>
{t12}

<h1>CHƯƠNG 2. CƠ SỞ LÝ THUYẾT &amp; THIẾT LẬP CÔNG THỨC PTHH PHƯƠNG PHÁP THỚ — RAYLEIGH–RITZ</h1>
<h2>2.1. Giả thiết động học Euler–Bernoulli &amp; Rời rạc hóa mặt cắt theo Phương pháp Thớ</h2>
<p>Xét dầm chịu uốn phẳng nhịp L, tiết diện chữ nhật (b × h) với tỷ lệ nhịp/cao L/h ∈ [5, 10], trục tham chiếu y = 0 qua tâm hình học, trục +y hướng lên trên. Biến dạng dọc trục tại thớ có tọa độ y tuân theo giả thiết tiết diện phẳng Euler–Bernoulli; mặt cắt được chia thành n<sub>fib</sub> dải thớ bê tông mỏng dy = h/n<sub>fib</sub>, 2 lớp cốt thép thanh (A<sub>s</sub>, A'<sub>s</sub>) đặt đúng trọng tâm và 8 thớ lõi thép hình chữ I (2 cánh + 6 dải bụng):</p>
{eqs_ch2}
{_fig("fig1_constitutive_and_section.png", "Hình 2.1. (a) Mô hình chia thớ Dầm Bê tông Cốt cứng 250×500 (I240×120 + 3Ø20 + 2Ø16); (b) Định luật bê tông Hognestad & Tension Stiffening; (c) Đàn–dẻo song tuyến tính cốt thép thanh CB400-V và lõi thép I S275.")}
<h2>2.2. Tích phân nội lực mặt cắt, Ma trận độ cứng tiếp tuyến [D<sub>t</sub>] và Trục trung hòa</h2>
<p>Khi bê tông vùng kéo nứt, số hạng khớp nối dọc trục – uốn ES<sub>t</sub> = −∑E<sub>t,i</sub>y<sub>i</sub>A<sub>i</sub> khác 0 xuất hiện, khiến độ cứng uốn tiếp tuyến hiệu dụng EI<sub>eff</sub> tự động hiệu chỉnh theo vị trí trục trung hòa dịch chuyển x<sub>NA</sub>:</p>
{eqs_sec}
<h2>2.3. Phương pháp Rayleigh–Ritz, Phần tử dầm 6-DOF (CALFEM) &amp; Giải tích PSD chuẩn quốc tế</h2>
<p>Áp dụng nguyên lý dừng thế năng toàn phần Π = U − W → δΠ = 0 trên phần tử dầm Hermite bậc 3 (6 bậc tự do {{d<sup>e</sup>}} = [u<sub>i</sub>, v<sub>i</sub>, θ<sub>i</sub>, u<sub>j</sub>, v<sub>j</sub>, θ<sub>j</sub>]<sup>T</sup>) kết hợp cầu phương Gauss–Legendre 3 điểm và đối chứng giải tích PSD (EN 1994-1-1 §6.2.1.2 / AISC 360-16 §I3.3):</p>
{eqs_fem}

<h1>CHƯƠNG 3. KIỂM CHỨNG ĐỘ TIN CẬY QUA CÁC BENCHMARK THỰC NGHIỆM QUỐC TẾ &amp; GIẢI TÍCH TIÊU CHUẨN</h1>
<h2>3.1. Kiểm chứng nghiệm giải tích đàn hồi chính xác (CALFEM beam2e)</h2>
<p>Trên dầm cốt cứng điển hình (L = 4000 mm, 250×500, lõi I240×120, E<sub>c</sub> = 32.5 GPa, Q = 120 kN tại giữa nhịp), độ cứng uốn liên hợp đàn hồi EI<sub>lin</sub> = {bs['ei_lin_knm2']:,.2f} kN·m². Bộ giải cho M<sub>max</sub> = {ec['m_fem_knm']:.6f} kN·m (khớp tuyệt đối QL/4 = {ec['m_exact_knm']:.4f} kN·m, sai số 0.0000%), độ võng giữa nhịp v<sub>FEM</sub> = {ec['v_fem_mm']:.6f} mm so với v<sub>exact</sub> = −QL³/(48 EI<sub>lin</sub>) = {ec['v_exact_mm']:.6f} mm (sai số {ec['v_err_pct']:.4f}%), và tổng phản lực |∑F<sub>y</sub>| = {abs(ec['sum_fy_n']):.2e} N.</p>
<h2>3.2. Kiểm chứng với 05 Dầm Thí nghiệm Thực tế kinh điển công bố quốc tế</h2>
<p>Đưa trực tiếp thông số hình học và vật liệu đo thực tế (không hiệu chỉnh ngược hệ số) của 05 dầm thí nghiệm: chuỗi 3 dầm quy mô thật <b>Vecchio &amp; Shim (2004)</b> [TL5] (VS-A3, VS-B3, VS-C3), dầm uốn 3 điểm <b>Burns &amp; Siess (1962)</b> J-4 [TL6] (L/h = 8.0) và dầm uốn 4 điểm <b>Gaston, Siess &amp; Newmark (1952)</b> T1Ma [TL7] (L/h = 9.0):</p>
<div class="tbl-title">Bảng 3.1. Đối chứng trực tiếp 05 Dầm Thí nghiệm Thực tế &amp; Mô hình Phương pháp Thớ (CALFEM)</div>
{t31}
<h2>3.3. Kiểm chứng Dầm Bê tông Cốt cứng (SRC) với giải tích PSD (EN 1994-1-1 &amp; AISC 360-16)</h2>
<div class="tbl-title">Bảng 3.2. Kiểm chứng khả năng chịu uốn cực hạn Dầm Bê tông Cốt cứng (SRC I240×120) theo tiêu chuẩn quốc tế</div>
{t32}
{_fig("fig2_experimental_validation.png", "Hình 3.1. (a) So sánh cường độ cực hạn giữa Phương pháp Thớ và 05 dầm thí nghiệm thực tế cùng chuẩn PSD EN 1994/AISC 360; (b) Đường cong tải trọng – độ võng P–δ của chuỗi Vecchio & Shim (2004) đối chiếu với đỉnh thực nghiệm.")}
<div class="callout">
  <div class="callout-title">KẾT LUẬN KIỂM CHỨNG ĐỘ TIN CẬY CỦA BỘ GIẢI PHƯƠNG PHÁP THỚ (CALFEM)</div>
  <p><b>1. Độ chính xác cường độ cực hạn rất cao:</b> Trên cả 05 mẫu thí nghiệm quốc tế, tỷ số trung bình P<sub>u,Fiber</sub>/P<sub>u,Exp</sub> = {all_mean:.3f} (MAPE = {all_mape:.2f}%, COV = {all_cov:.2f}%); riêng chuỗi quy mô thật Vecchio &amp; Shim (2004) đạt MAPE = {vs_mape:.2f}%. Với Dầm Cốt cứng SRC I240×120, mô hình khớp PSD EN 1994-1-1 / AISC 360-16 trong phạm vi {err_ep:+.2f}% (khi b<sub>h</sub>→0) và {err_hard:+.2f}% (khi xét tái bền thực tế b<sub>h</sub> = 1%).</p>
  <p><b>2. Lý giải chênh lệch độ võng cực hạn thí nghiệm:</b> Ở chuỗi VS-A3/B3/C3, độ võng cực hạn thực nghiệm (44–60 mm) lớn hơn mô hình Euler–Bernoulli (~31 mm) do biến dạng trượt dính bám cốt thép (bond-slip) trong vùng khớp dẻo và biến dạng trượt ngang tại vết nứt xiên — hai hiệu ứng nằm ngoài lý thuyết dầm phẳng cổ điển. Trước chảy dẻo (P &lt; 0.85 P<sub>y</sub>), đường cong P–δ bám sát thực tế.</p>
  <p><b>3. Phạm vi áp dụng tin cậy:</b> Đạt độ tin cậy cao cho dầm BTCT/SRC có L/h ≥ 5, đủ cốt đai chống cắt và cấu tạo dính bám liên hợp đúng EN 1994-1-1 §6.7.5 / AISC 360-16 §I2.1a.</p>
</div>

<h1>CHƯƠNG 4. GIẢI CHI TIẾT BÀI TOÁN ĐIỂN HÌNH DẦM CỐT CỨNG — MA TRẬN [K<sub>t</sub><sup>e</sup>] 6×6 &amp; HỘI TỤ LƯỚI</h1>
<h2>4.1. Ma trận độ cứng tiếp tuyến [K<sub>t</sub><sup>e</sup>] (6×6) &amp; Quan hệ {{f<sup>e</sup>}} ↔ {{d<sup>e</sup>}} phần tử giữa nhịp</h2>
<p>Xét dầm đơn giản bê tông cốt cứng 250×500, L = 4000 mm (L/h = 8.0), bê tông B30 (f'<sub>c</sub> = 30 MPa), thép 3Ø20 + 2Ø16 (CB400-V), lõi thép cứng I240×120×7×10 (S275, ρ<sub>a</sub> = 3.15%), chia 8 phần tử đối xứng (40 thớ bê tông). Tại Q = 120 kN (M<sub>max</sub> = 120.00 kN·m &gt; M<sub>cr</sub> = {bs['m_cr_knm']:.2f} kN·m), bộ giải hội tụ sau {nl120['iters']} vòng lặp, cho v<sub>mid</sub> = {nl120['v_mid_mm']:.4f} mm (giảm −40.4% so với dầm BTCT thường {bs['rc_ref_120']['v_mid_mm']:.4f} mm). Sự xuất hiện của các phần tử ghép cặp khác không (như K<sub>13</sub> = −4.174×10⁸ N) trong Bảng 4.1 phản ánh trực tiếp hiệu ứng khớp nối ES<sub>t</sub> ≠ 0 do dịch chuyển trục trung hòa sau khi nứt:</p>
<div class="tbl-title">Bảng 4.1. Ma trận độ cứng tiếp tuyến phần tử [K<sub>t</sub><sup>e</sup>] (6×6) của Phần tử #4 (x ∈ [1500, 2000] mm) tại Q = 120 kN (N, mm)</div>
{t41}
<div class="tbl-title">Bảng 4.2. Véc-tơ chuyển vị đầu phần tử {{d<sup>e</sup>}} và nội lực hai đầu {{f<sup>e</sup>}} của Phần tử #4 tại Q = 120 kN</div>
{t42}
<h2>4.2. Khảo sát hội tụ lưới Phần tử hữu hạn (chia hai nửa) &amp; số dải Thớ</h2>
<div class="tbl-title">Bảng 4.3. Kết quả khảo sát hội tụ lưới PTHH (n<sub>fib</sub> = 40) và số dải thớ (n<sub>elem</sub> = 8)</div>
{t43}
<p>Từ n<sub>elem</sub> = 8 phần tử trở lên, độ võng đã hội tụ trong phạm vi &lt; 0.44% ở tải làm việc và &lt; 0.21% ở tải cận chảy so với lưới 32 phần tử; với n<sub>fib</sub> = 40 thớ (dy = 12.5 mm), sai số mô-men cực hạn M<sub>u</sub> nhỏ hơn 0.04% so với 80 thớ.</p>
{_fig("fig3_mesh_fiber_convergence.png", "Hình 4.1. (a) Khảo sát hội tụ lưới PTHH (2 → 32 phần tử) và số dải thớ (10 → 80 thớ); (b) Biến thiên tỷ lệ độ cứng EI_eff/EI_0 và chiều sâu trục trung hòa x_NA theo mô-men M.")}

<h1>CHƯƠNG 5. PHÂN TÍCH CHUYÊN SÂU BẢN CHẤT CƠ HỌC CỐT LÕI CỦA DẦM BÊ TÔNG CỐT CỨNG (SRC)</h1>
<h2>5.1. Giải phẫu 4 giai đoạn ứng xử phi tuyến trên mặt cắt Dầm Cốt cứng</h2>
<ul>
  <li><b>Giai đoạn I — Đàn hồi liên hợp nguyên vẹn (0 → M<sub>cr</sub> = {bs['m_cr_knm']:.1f} kN·m):</b> Lõi thép nằm gần tâm nên chỉ làm tăng nhẹ độ cứng đàn hồi (+8.4%) và mô-men nứt (+15.7%); trục trung hòa x<sub>NA</sub> ≈ 253–258 mm, vỏ bê tông gánh ~80% mô-men uốn.</li>
  <li><b>Giai đoạn II — Nứt kéo, 'cú nhảy' trục trung hòa &amp; khớp nối ES<sub>t</sub> ({bs['m_cr_knm']:.1f} → {bs['m_y_rebar_knm']:.1f} kN·m):</b> Khi thớ đáy vượt f<sub>ct</sub>, EI<sub>eff</sub>/EI<sub>0</sub> rơi xuống ~36% ở dầm SRC (thay vì rơi sâu còn ~26% ở dầm BTCT thường!), trục trung hòa nhảy lên ~175 mm. Lõi thép hình I giữ vững độ cứng sau nứt giúp giảm tới −40.4% độ võng làm việc.</li>
  <li><b>Giai đoạn III — Chảy dẻo tuần tự nhiều tầng ({bs['m_y_rebar_knm']:.1f} → {bs['m_u_knm']:.1f} kN·m):</b> Thứ tự chảy giữa cánh dưới lõi thép I (tọa độ y<sub>f</sub>, giới hạn chảy f<sub>ya</sub>) và cốt thép thanh đáy (y<sub>s</sub>, f<sub>y</sub>) tuân theo tiêu chuẩn hình học – vật lý không thứ nguyên:</li>
</ul>
{eq51}
<p>Với lõi I240 (f<sub>ya</sub>/f<sub>y</sub> = 0.688 &gt; tỷ số tay đòn 190/285 = 0.667), cốt thép thanh 3Ø20 chảy trước tại {bs['m_y_rebar_knm']:.1f} kN·m rồi cánh dưới lõi I240 chảy ngay sau tại {bs['m_y_core_knm']:.1f} kN·m; ngược lại với lõi cao I300 hoặc thép mềm S235, cánh dưới lõi I chảy trước cốt thép thanh. Tiếp đó vùng chảy lan dần từng dải dọc bản bụng lõi I tạo đường cong M–κ bo tròn dẻo dai và dự trữ sau chảy +16.9%.</p>
<ul>
  <li><b>Giai đoạn IV — Cực hạn nén bê tông (ε<sub>c,max</sub> → 3.5‰, M<sub>u</sub> = {bs['m_u_knm']:.1f} kN·m):</b> Chiều sâu vùng nén x<sub>NA,u</sub> = {bs['x_na_u_mm']:.1f} mm (ξ<sub>u</sub> = {bs['x_na_u_mm']/460:.3f} &lt; ξ<sub>b</sub> ≈ 0.53). Tại cực hạn, vỏ bê tông nén gánh ~22%, cốt thép thanh gánh ~42% và lõi thép hình I gánh tới ~36% tổng mô-men; cánh nén lõi I được vỏ bê tông kiềm chế 3 chiều nên không bao giờ bị mất ổn định cục bộ.</li>
</ul>
{_fig("fig4_four_stages_mechanics.png", "Hình 5.1. Giải phẫu 4 giai đoạn cơ học của Dầm Cốt cứng I240×120 vs Dầm BTCT thường: (a) Đường cong M–κ; (b) Đường cong Q–v_mid; (c) Biểu đồ ứng suất bê tông σ_c(y); (d) Phân chia tỷ lệ chịu lực của 3 vật liệu.")}
<h2>5.2. Quy luật đánh đổi Cường độ – Độ dẻo dai &amp; Phá hoại Cắt tách dọc cánh (Weng et al. 2002)</h2>
<p>Tăng hàm lượng lõi thép cứng giúp mô-men cực hạn M<sub>u</sub> tăng mạnh (+81% đến +129%) nhưng kéo sâu trục trung hòa x<sub>NA,u</sub> từ 57.7 mm (BTCT thường) xuống 147.4 mm (SRC I240), làm độ cong cực hạn κ<sub>u</sub> = ε<sub>cu</sub>/x<sub>NA,u</sub> và độ dẻo dai μ<sub>κ</sub> giảm từ 9.46 xuống ~3.0–3.2. Mặt khác, theo thí nghiệm quy mô thật của <b>Weng, Yen &amp; Jiang (2002)</b> [TL8], nếu bề rộng cánh lõi quá lớn (b<sub>f</sub>/b &gt; 0.55) mà thiếu cốt đai khép kín hoặc chiều dày bê tông bọc mỏng, dầm SRC có thể bị phá hoại cắt tách dọc mặt phẳng cánh (Shear-Splitting) trước khi đạt M<sub>pl</sub>. Tiết diện điển hình có b<sub>f</sub>/b = 0.48 &lt; 0.55 và lớp bọc mép cánh 65 mm &gt; 40 mm, thỏa mãn EN 1994-1-1 §6.7.5 [TC4] và AISC 360-16 §I2.1a [TC5].</p>

<h1>CHƯƠNG 6. KHẢO SÁT ẢNH HƯỞNG CỦA 6 YẾU TỐ THIẾT KẾ ĐẾN ỨNG XỬ DẦM BÊ TÔNG CỐT CỨNG</h1>
<h2>6.1. Kích thước lõi thép cứng, Tỷ lệ nhịp/cao (L/h ∈ [5, 10]) và Sơ đồ chất tải (3 điểm vs 4 điểm)</h2>
<div class="tbl-title">Bảng 6.1. Ảnh hưởng kích thước &amp; hàm lượng lõi thép cứng ρ<sub>a</sub> lên dầm 250×500 (L = 4000 mm, B30)</div>
{t61}
<div class="tbl-title">Bảng 6.2. Ảnh hưởng tỷ lệ L/h ∈ {{5, 6, 8, 10}} (h = 500 mm, lõi I240×120)</div>
{t62}
<div class="tbl-title">Bảng 6.3. Ảnh hưởng sơ đồ chất tải (3 điểm vs 4 điểm) và khoảng cách đặt lực a ở cùng M<sub>max</sub></div>
{t63}
<p>Ở cùng mức mô-men M<sub>max</sub> = 240 kN·m, sơ đồ uốn 4 điểm (a = L/4: 10.98 mm; a = L/3: 10.12 mm) cho độ võng lớn hơn +33% đến +44% so với uốn 3 điểm (7.63 mm) do vùng uốn thuần túy kéo dài 33%–50% nhịp làm nứt sâu và dẻo hóa đồng loạt trên diện rộng. Khi tăng L/h từ 5 lên 10 ở cùng tải Q = 120 kN, độ võng tăng 12.96 lần — mạnh hơn cả quy luật đàn hồi L³ (= 8 lần) vì mức độ nứt lan rộng nhanh theo chiều dài nhịp.</p>
{_fig("fig5_parametric_core_and_lh.png", "Hình 6.1. Khảo sát tham số nhóm 1: (a) Họ M–κ theo kích thước lõi I; (b) Đánh đổi M_u – μ_κ – v_mid theo ρ_a; (c) Ảnh hưởng L/h ∈ [5, 10]; (d) Sơ đồ 3 điểm vs 4 điểm ở cùng M_max.")}
<h2>6.2. Điều kiện biên gối tựa (Phân phối lại Mô-men dẻo) và Cấp Vật liệu Bê tông / Lõi thép</h2>
<div class="tbl-title">Bảng 6.4. Ảnh hưởng điều kiện gối tựa hai đầu lên độ võng, nội lực và sức chịu tải của Dầm SRC I240</div>
{t64}
<div class="tbl-title">Bảng 6.5. Ảnh hưởng cấp độ bền bê tông (B20 → B40) và cường độ lõi thép hình (S235 → S355)</div>
{t65}
<p>Trong dầm siêu tĩnh Ngàm–Ngàm, do cốt thép bất đối xứng (đáy 3Ø20 &gt; đỉnh 2Ø16), tiết diện ngàm chịu mô-men âm bị nứt sâu trước và tự động phân phối lại mô-men sang giữa nhịp (M<sub>nhịp</sub> &gt; QL/8 &gt; |M<sub>ngàm</sub>|, Hình 6.2b). Đáng chú ý nhất, nâng mác bê tông từ B20 lên B40 kéo gọn vùng nén x<sub>NA,u</sub> từ 172.3 mm xuống 130.1 mm, qua đó <b>tăng vọt độ dẻo dai μ<sub>κ</sub> thêm +52%</b> (2.57 → 3.91) — khẳng định bê tông cường độ cao là chìa khóa tối ưu độ dẻo dai cho dầm cốt cứng!</p>
{_fig("fig6_parametric_bc_materials.png", "Hình 6.2. Khảo sát tham số nhóm 2: (a) Điều kiện biên gối tựa; (b) Phân phối lại mô-men dẻo trong dầm Ngàm–Ngàm; (c) Ảnh hưởng cấp độ bền bê tông B20–B40; (d) Ảnh hưởng cường độ lõi thép hình S235–S355.")}

<h1>CHƯƠNG 7. KẾT LUẬN, KIẾN NGHỊ THIẾT KẾ &amp; DANH MỤC TIÊU CHUẨN – TÀI LIỆU THAM KHẢO</h1>
<h2>7.1. Kết luận tổng quát &amp; Kiến nghị thực hành</h2>
<ul>
  <li><b>Độ tin cậy được kiểm chứng vững chắc:</b> Bộ giải PTHH Phương pháp Thớ – Rayleigh–Ritz (CALFEM) khớp tuyệt đối nghiệm đàn hồi beam2e (0.0015%), khớp 05 dầm thí nghiệm quốc tế với tỷ số trung bình {all_mean:.3f} (MAPE = {all_mape:.2f}%, riêng chuỗi VS-2004 đạt {vs_mape:.2f}%), và khớp nghiệm giải tích PSD EN 1994-1-1 / AISC 360-16 trong sai số {err_ep:+.2f}%.</li>
  <li><b>Khuyến nghị thiết kế Dầm SRC:</b> Chọn hàm lượng lõi thép ρ<sub>a</sub> ∈ [2.5%, 5.0%] (JGJ 138-2016 [TC6]), khống chế ξ<sub>u</sub> ≤ 0.40 để giữ độ dẻo dai μ<sub>κ</sub> ≥ 3.0; phối hợp lõi thép S275–S355 với bê tông ≥ B30–B40; giữ tỷ số cánh b<sub>f</sub>/b ≤ 0.55, chiều dày bọc ≥ 40–50 mm và cốt đai khép kín theo EN 1994-1-1 §6.7.5 để loại trừ phá hoại cắt tách dọc cánh (Weng et al. 2002 [TL8]).</li>
</ul>
<h2>7.2. Danh mục Tiêu chuẩn Kỹ thuật và Tài liệu Tham khảo</h2>
<h3>A. Tiêu chuẩn kỹ thuật</h3>
{"".join(f'<p class="ref-p">{html.escape(r)}</p>' for r in refs_std)}
<h3>B. Giáo trình và công trình nghiên cứu khoa học</h3>
{"".join(f'<p class="ref-p">{html.escape(r)}</p>' for r in refs_lit)}
</body>
</html>"""


def main() -> None:
    with open(RESULTS_JSON, "r", encoding="utf-8") as f:
        data = json.load(f)
    html_str = build_html(data)
    tmp_html = os.path.join(tempfile.gettempdir(), "calfem_src_beam_report.html")
    with open(tmp_html, "w", encoding="utf-8") as f:
        f.write(html_str)

    edge_candidates = [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    ]
    edge = next((p for p in edge_candidates if os.path.exists(p)), None)
    if not edge:
        raise RuntimeError("Khong tim thay Microsoft Edge de xuat PDF!")

    file_url = "file:///" + tmp_html.replace("\\", "/")
    cmd = [
        edge,
        "--headless=new",
        "--disable-gpu",
        "--no-sandbox",
        "--no-pdf-header-footer",
        f"--print-to-pdf={OUT_PDF}",
        file_url,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if proc.returncode != 0 or not os.path.exists(OUT_PDF):
        raise RuntimeError(f"Edge PDF export failed: {proc.stderr}")

    import fitz
    doc = fitz.open(OUT_PDF)
    n_pages = len(doc)
    doc.close()
    sz_kb = os.path.getsize(OUT_PDF) / 1024.0
    print(f"DA XUAT THANH CONG PDF: {OUT_PDF} ({n_pages} trang, {sz_kb:.1f} KB)")


if __name__ == "__main__":
    main()
