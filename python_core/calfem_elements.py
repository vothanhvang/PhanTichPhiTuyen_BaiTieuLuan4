# -*- coding: utf-8 -*-
"""
================================================================================
MÔ-ĐUN 1: CÁC HÀM PHẦN TỬ & LẮP RÁP CHUẨN CALFEM 3.4 VÀ MỞ RỘNG PHI TUYẾN
================================================================================
Mục đích:
  Cài đặt nguyên bản thuật toán của thư viện CALFEM 3.4 (Lund University) sang
  Python/NumPy, đồng thời mở rộng sang hai công thức phi tuyến hình học chuyển
  vị lớn nhất quán về mặt cơ học:
    (A) CALFEM chuẩn tuyến tính (bar2e, bar2s, assem, solveq, extract)
        Nguồn: calfem34.pdf (Mục 5.3 tr. 5.3-2..5.3-5 / PDF tr. 60-63;
               Mục 6.2 tr. 6.2-2..6.2-7 / PDF tr. 160-165).
    (B) CALFEM chuẩn bậc hai (bar2g) – Lý thuyết bậc 2 trên tọa độ ban đầu
        Nguồn: calfem34.pdf (Mục 5.3 tr. 5.3-3..5.3-4 / PDF tr. 61-62);
               Olsson & Dahlblom (2016), Chương 9, Mục 9.2.2, PT (9.34)-(9.38),
               Sách tr. 258-260 / PDF tr. 272-274.
    (C) CALFEM Đồng chuyển động / Updated Lagrangian (bar2g_corotational)
        Áp dụng chính công thức bar2g trên CẤU HÌNH BIẾN DẠNG HIỆN TẠI x = X + u
        với biến dạng kỹ thuật chính xác ε = (l - L0)/L0.
        Nguồn: Jeffers (2026), Mục 8.3 (tr. 186); Yang (2025), Chương 4 (tr. 117-138).
    (D) Total Lagrangian với biến dạng hữu hạn Green-Lagrange (bar2g_total_lagrangian)
        Đúng nguyên bản công thức ma trận độ cứng hình học [k_g] trong Bài giảng
        NSA_4 (PGS.TS. Ngô Hữu Cường), Mục 4.1.1, Slides 6-12 (PDF tr. 2-3) và
        McGuire, Gallagher & Ziemian (2000), Mục 9.1.1, PT (9.1)-(9.9), tr. 243-245.

Quy ước đơn vị thống nhất xuyên suốt hệ thống:
  - Chiều dài & tọa độ & chuyển vị : mm
  - Lực & phản lực                 : N  (khi hiển thị bảng quy đổi 1 kN = 1000 N)
  - Mô-đun đàn hồi E & ứng suất σ  : MPa = N/mm²  (1 GPa = 1000 MPa)
  - Diện tích tiết diện A          : mm²
  - Năng lượng biến dạng U         : N·mm (1 J = 1000 N·mm)
Quy ước dấu:
  - Trục X hướng sang phải, trục Y hướng lên trên.
  - Lực dọc N > 0 là KÉO (tension), N < 0 là NÉN (compression).
================================================================================
"""

from __future__ import annotations
from typing import Tuple, Optional
import numpy as np


def bar2e(ex: np.ndarray, ey: np.ndarray, ep: Tuple[float, float]) -> np.ndarray:
    """
    Tính ma trận độ cứng đàn hồi tuyến tính Ke (4x4) của phần tử thanh dàn 2D
    trong hệ tọa độ tổng thể (Global Coordinate System).

    Nguồn:
      - CALFEM 3.4: fem/bar2e.m & calfem34.pdf Mục 5.3, tr. 5.3-2 (PDF tr. 60).
      - Olsson & Dahlblom (2016), Chương 3, PT (3.86)-(3.87), tr. 54 (PDF tr. 68).
      - Hibbeler Structural Analysis 10E (2019), Chương 14, PT (14-15)-(14-16), tr. 580.

    Công thức cơ học:
      L  = sqrt((x2 - x1)^2 + (y2 - y1)^2)
      c  = (x2 - x1) / L,   s = (y2 - y1) / L
      Kle = (E*A/L) * [[1, -1], [-1, 1]]
      G   = [[c, s, 0, 0], [0, 0, c, s]]
      Ke  = G^T * Kle * G

    Tham số đầu vào:
      ex : mảng [x1, x2] tọa độ X hai đầu thanh (mm).
      ey : mảng [y1, y2] tọa độ Y hai đầu thanh (mm).
      ep : bộ (E, A) gồm mô-đun đàn hồi E (MPa) và diện tích A (mm²).

    Giá trị trả về:
      Ke : ma trận đối xứng kích thước (4, 4), đơn vị N/mm, ứng với bậc tự do
           [u1x, u1y, u2x, u2y]^T.
    """
    E, A = float(ep[0]), float(ep[1])
    dx = float(ex[1]) - float(ex[0])
    dy = float(ey[1]) - float(ey[0])
    L = float(np.hypot(dx, dy))
    if L <= 0.0:
        raise ValueError("Chiều dài phần tử thanh L phải lớn hơn 0.")

    # Véc-tơ đơn vị chỉ phương trục thanh n = [c, s]
    c, s = dx / L, dy / L
    # Ma trận chuyển đổi tọa độ G (2x4) chiếu chuyển vị tổng thể lên trục thanh
    G = np.array([[c, s, 0.0, 0.0], [0.0, 0.0, c, s]], dtype=float)
    # Ma trận độ cứng dọc trục trong hệ tọa độ địa phương
    Kle = (E * A / L) * np.array([[1.0, -1.0], [-1.0, 1.0]], dtype=float)
    # Biến đổi về hệ tổng thể bảo toàn công ảo: Ke = G^T * Kle * G
    return G.T @ Kle @ G


def bar2g(
    ex: np.ndarray, ey: np.ndarray, ep: Tuple[float, float], N: float
) -> np.ndarray:
    """
    Tính ma trận độ cứng phần tử thanh dàn 2D PHI TUYẾN HÌNH HỌC Ke (4x4)
    theo đúng định nghĩa nguyên bản của hàm `bar2g` trong CALFEM 3.4.

    Nguồn:
      - CALFEM 3.4: fem/bar2g.m & calfem34.pdf Mục 5.3, tr. 5.3-3..5.3-4 (PDF tr. 61-62).
      - Olsson & Dahlblom (2016), Chương 9, Mục 9.2.2, PT (9.35)-(9.38),
        tr. 259-260 (PDF tr. 273-274).

    Bản chất vật lý (dễ hiểu cho học sinh cấp 3):
      Khi thanh đang có lực dọc N và hai đầu thanh dịch chuyển lệch nhau theo
      phương vuông góc trục thanh một góc nhỏ θ = (v2 - v1)/L, lực dọc N tạo ra
      thành phần lực ngang Qy = N * sin(θ) ≈ N * (v2 - v1)/L.
        • Nếu thanh chịu KÉO (N > 0): lực ngang kéo thanh về vị trí thẳng ->
          LÀM TĂNG độ cứng ngang (hiệu ứng dây đàn căng / Stress Stiffening).
        • Nếu thanh chịu NÉN (N < 0): lực ngang đẩy thanh lệch thêm ->
          LÀM GIẢM độ cứng ngang (hiệu ứng P-Δ / Geometric Softening).

    Công thức ma trận địa phương (4x4 ứng với [u1, v1, u2, v2]^T):
      Kle = (EA/L) * [[1,0,-1,0],[0,0,0,0],[-1,0,1,0],[0,0,0,0]]
          + (N/L)  * [[0,0,0,0],[0,1,0,-1],[0,0,0,0],[0,-1,0,1]]
      Ke  = G^T * Kle * G

    Tham số đầu vào:
      ex : [x1, x2] tọa độ X hai đầu thanh (mm).
      ey : [y1, y2] tọa độ Y hai đầu thanh (mm).
      ep : (E, A) gồm E (MPa) và A (mm²).
      N  : lực dọc hiện tại trong thanh (N), quy ước N > 0 là KÉO, N < 0 là NÉN.

    Giá trị trả về:
      Ke : ma trận độ cứng tổng (Ke_0 + Ke_sigma) kích thước (4, 4), đơn vị N/mm.
    """
    E, A = float(ep[0]), float(ep[1])
    N_val = float(N)
    dx = float(ex[1]) - float(ex[0])
    dy = float(ey[1]) - float(ey[0])
    L = float(np.hypot(dx, dy))
    if L <= 0.0:
        raise ValueError("Chiều dài phần tử thanh L phải lớn hơn 0.")

    c, s = dx / L, dy / L
    # Ma trận xoay trực giao 4x4 chuyển từ hệ tổng thể (X, Y) sang hệ địa phương (x̄, ȳ)
    G = np.array(
        [
            [c, s, 0.0, 0.0],
            [-s, c, 0.0, 0.0],
            [0.0, 0.0, c, s],
            [0.0, 0.0, -s, c],
        ],
        dtype=float,
    )

    # Thành phần 1: Độ cứng đàn hồi dọc trục K_e0
    Ke_elastic_local = (E * A / L) * np.array(
        [
            [1.0, 0.0, -1.0, 0.0],
            [0.0, 0.0, 0.0, 0.0],
            [-1.0, 0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0, 0.0],
        ],
        dtype=float,
    )
    # Thành phần 2: Độ cứng hình học ứng suất ban đầu K_eσ (chỉ tác động phương ngang)
    Ke_geom_local = (N_val / L) * np.array(
        [
            [0.0, 0.0, 0.0, 0.0],
            [0.0, 1.0, 0.0, -1.0],
            [0.0, 0.0, 0.0, 0.0],
            [0.0, -1.0, 0.0, 1.0],
        ],
        dtype=float,
    )
    Kle = Ke_elastic_local + Ke_geom_local
    return G.T @ Kle @ G


def bar2g_split(
    ex: np.ndarray, ey: np.ndarray, ep: Tuple[float, float], N: float
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Tách riêng ma trận độ cứng đàn hồi Ke0 (4x4) và ma trận độ cứng hình học Kg (4x4)
    của phần tử `bar2g` trong hệ tọa độ tổng thể.
    Rất hữu ích cho:
      1) Minh họa sư phạm trong báo cáo (thấy rõ đóng góp của [ke] và [kg]).
      2) Giải bài toán trị riêng tải tới hạn đàn hồi: (Ke + α_cr * Kg) φ = 0.
    """
    Ke0 = bar2e(ex, ey, ep)
    Ke_total = bar2g(ex, ey, ep, N)
    Kg = Ke_total - Ke0
    return Ke0, Kg


def bar2s(
    ex: np.ndarray, ey: np.ndarray, ep: Tuple[float, float], ed: np.ndarray
) -> float:
    """
    Tính lực dọc trục tuyến tính N (N) trong phần tử thanh dàn 2D từ chuyển vị nút ed.

    Nguồn:
      - CALFEM 3.4: fem/bar2s.m & calfem34.pdf Mục 5.3, tr. 5.3-5 (PDF tr. 63).
      - Hibbeler Structural Analysis 10E (2019), PT (14-23), tr. 587.

    Công thức:
      N = (E*A/L) * [-c, -s, c, s] * [u1x, u1y, u2x, u2y]^T

    Lưu ý quan trọng:
      Hàm trả về LỰC DỌC N (đơn vị N), KHÔNG phải ứng suất. Để tính ứng suất pháp
      trung bình trên tiết diện cần chia tiếp cho diện tích: σ = N / A (MPa).
    """
    E, A = float(ep[0]), float(ep[1])
    dx = float(ex[1]) - float(ex[0])
    dy = float(ey[1]) - float(ey[0])
    L = float(np.hypot(dx, dy))
    c, s = dx / L, dy / L
    ed_vec = np.asarray(ed, dtype=float).reshape(4)
    # Độ giãn dài dọc trục tuyến tính = chiếu hiệu chuyển vị 2 đầu lên trục thanh
    delta_L = c * (ed_vec[2] - ed_vec[0]) + s * (ed_vec[3] - ed_vec[1])
    return float((E * A / L) * delta_L)


def assem(
    edof_row: np.ndarray,
    K: np.ndarray,
    Ke: np.ndarray,
    f: Optional[np.ndarray] = None,
    fe: Optional[np.ndarray] = None,
) -> np.ndarray | Tuple[np.ndarray, np.ndarray]:
    """
    Lắp ráp (cộng dồn) ma trận độ cứng phần tử Ke vào ma trận độ cứng tổng thể K
    theo đúng bảng định vị bậc tự do `edof` (chuẩn 1-based giống CALFEM 3.4).

    Nguồn:
      - CALFEM 3.4: fem/assem.m & calfem34.pdf Mục 6.2, tr. 6.2-2 (PDF tr. 160).
      - Olsson & Dahlblom (2016), Mục 3.4.3, PT (3.93)-(3.103), tr. 56-59.

    Bản chất vật lý:
      Cộng dồn (KHÔNG ghi đè) các hệ số độ cứng tại bậc tự do dùng chung thể hiện
      đồng thời hai nguyên lý nền tảng:
        1. Tương thích chuyển vị: các thanh nối chung một khớp có cùng chuyển vị nút.
        2. Cân bằng nút: tổng nội lực các thanh quy tụ vào nút cân bằng ngoại lực nút.

    Tham số đầu vào:
      edof_row : hàng hoặc ma trận Edof có cột 0 là số hiệu phần tử, các cột sau
                 là chỉ số bậc tự do đánh số từ 1 (1-based giống MATLAB/CALFEM).
      K        : ma trận độ cứng tổng thể hiện tại (ndof x ndof).
      Ke       : ma trận độ cứng phần tử (ne x ne).
      f, fe    : (tùy chọn) véc-tơ tải tổng thể và phần tử.
    """
    edof_arr = np.atleast_2d(np.asarray(edof_row, dtype=int))
    for row in edof_arr:
        # Chuyển chỉ số DOF từ chuẩn 1-based (CALFEM) sang 0-based (Python)
        idx = row[1:] - 1
        K[np.ix_(idx, idx)] += Ke
        if f is not None and fe is not None:
            f[idx] += np.asarray(fe, dtype=float)
    if f is not None and fe is not None:
        return K, f
    return K


def solveq(
    K: np.ndarray, f: np.ndarray, bc: Optional[np.ndarray] = None
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Giải hệ phương trình cân bằng tĩnh K * a = f có xét điều kiện biên gối tựa `bc`,
    sau đó thu hồi véc-tơ phản lực gối Q = K * a - f (chuẩn CALFEM 3.4).

    Nguồn:
      - CALFEM 3.4: fem/solveq.m & calfem34.pdf Mục 6.2, tr. 6.2-7 (PDF tr. 165).
      - Hibbeler Structural Analysis 10E (2019), PT (14-17)-(14-22), tr. 586.

    Phân hoạch bậc tự do:
      - fdof (free DOFs)      : các bậc tự do chưa biết chuyển vị.
      - pdof (prescribed DOFs): các bậc tự do bị ràng buộc tại gối tựa (dp).
      Giải hệ rút gọn:  K_ff * a_f = f_f - K_fp * d_p
      Tính phản lực:    Q = K * a - f  (tại fdof phải ≈ 0; tại pdof là phản lực gối).

    Tham số đầu vào:
      K  : ma trận độ cứng tổng thể (ndof x ndof).
      f  : véc-tơ ngoại lực nút (ndof,).
      bc : mảng (nbc x 2), mỗi hàng [DOF_1based, gia_tri_chuyen_vi_goi].

    Giá trị trả về:
      (a, Q) : véc-tơ chuyển vị toàn hệ a và véc-tơ phản lực/phần dư Q.
    """
    nd = K.shape[0]
    f_vec = np.asarray(f, dtype=float).reshape(nd)
    if bc is None or len(bc) == 0:
        a = np.linalg.solve(K, f_vec)
        Q = K @ a - f_vec
        return a, Q

    bc_arr = np.atleast_2d(np.asarray(bc, dtype=float))
    pdof = bc_arr[:, 0].astype(int) - 1  # Chuyển về chỉ số 0-based
    dp = bc_arr[:, 1]
    all_dofs = np.arange(nd)
    mask = np.ones(nd, dtype=bool)
    mask[pdof] = False
    fdof = all_dofs[mask]

    a = np.zeros(nd, dtype=float)
    a[pdof] = dp
    rhs = f_vec[fdof] - K[np.ix_(fdof, pdof)] @ dp
    a[fdof] = np.linalg.solve(K[np.ix_(fdof, fdof)], rhs)
    Q = K @ a - f_vec
    return a, Q


def extract(edof: np.ndarray, a: np.ndarray) -> np.ndarray:
    """
    Tách véc-tơ chuyển vị phần tử `ed` từ véc-tơ chuyển vị toàn hệ `a`
    theo bảng định vị `edof` (chuẩn CALFEM 3.4).

    Nguồn:
      - CALFEM 3.4: fem/extract.m & calfem34.pdf Mục 6.2, tr. 6.2-6 (PDF tr. 164).
    """
    edof_arr = np.atleast_2d(np.asarray(edof, dtype=int))
    a_vec = np.asarray(a, dtype=float).reshape(-1)
    idx = edof_arr[:, 1:] - 1
    ed = a_vec[idx]
    return ed[0] if np.asarray(edof).ndim == 1 else ed


def bar2g_corotational(
    ex0: np.ndarray,
    ey0: np.ndarray,
    ep: Tuple[float, float],
    ed: np.ndarray,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, float, float, float, float]:
    """
    Phần tử thanh dàn 2D PHI TUYẾN HÌNH HỌC ĐỒNG CHUYỂN ĐỘNG (Corotational /
    Updated Lagrangian) dựa trên cấu trúc ma trận CALFEM `bar2g` đánh giá tại
    cấu hình biến dạng hiện tại.

    Nguồn đối chiếu:
      - Jeffers (2026), Mục 8.3 (Corotational Formulation), Sách tr. 186-189.
      - Yang et al. (2025), Chương 4 (Truss: A Perfect Example for Rigid Body Rule),
        Mục 4.2-4.3, Sách tr. 119-130.
      - CALFEM 3.4 `bar2g` đánh giá trên tọa độ hiện tại x = X + u.

    Giải thích trực quan (dành cho học sinh cấp 3):
      1. Ban đầu thanh dài L0 = sqrt((x2-x1)^2 + (y2-y1)^2).
      2. Sau khi hai đầu dịch chuyển ed = [u1x, u1y, u2x, u2y], tọa độ mới là:
           x1' = x1 + u1x,  y1' = y1 + u1y
           x2' = x2 + u2x,  y2' = y2 + u2y
      3. Theo định lý Py-ta-go chính xác, chiều dài MỚI của thanh là:
           l = sqrt((x2' - x1')^2 + (y2' - y1')^2)
      4. Độ biến dạng kỹ thuật dọc trục (Engineering strain):
           ε_eng = (l - L0) / L0
         -> Đặc tính vàng (Rigid-Body Objectivity): nếu xoay thanh như vật cứng
            (không co giãn), l = L0 nên ε_eng = 0 tuyệt đối -> không sinh lực giả!
      5. Lực dọc thực theo định luật Hooke:
           N = E * A * ε_eng = E * A * (l - L0) / L0
      6. Véc-tơ nội lực tác dụng tại hai đầu thanh theo hướng MỚI n = [c', s']:
           f_int = N * [-c', -s', c', s']^T
      7. Ma trận độ cứng tiếp tuyến nhất quán Kt = d(f_int)/d(ed):
           Kt = (EA/L0) * B_n^T * B_n  +  (N/l) * B_t^T * B_t
         trong đó B_n = [-c', -s', c', s'] (phương dọc trục mới) và
                  B_t = [ s', -c', -s', c'] (phương vuông góc trục mới).
         NHẬN XÉT CỰC KỲ ĐẸP: Trong hệ trục cục bộ hiện tại, Kt có dạng ĐÚNG BẰNG
         công thức `bar2g` của CALFEM với độ cứng dọc EA/L0 và độ cứng ngang N/l!

    Giá trị trả về:
      (f_int, Kt, Ke_mat, Kg_mat, N, strain_eng, l_cur, energy)
    """
    E, A = float(ep[0]), float(ep[1])
    ed_vec = np.asarray(ed, dtype=float).reshape(4)

    # Hình học ban đầu
    dx0 = float(ex0[1]) - float(ex0[0])
    dy0 = float(ey0[1]) - float(ey0[0])
    L0 = float(np.hypot(dx0, dy0))

    # Hình học hiện tại sau biến dạng x = X + u
    dux = ed_vec[2] - ed_vec[0]
    duy = ed_vec[3] - ed_vec[1]
    dxc = dx0 + dux
    dyc = dy0 + duy
    l_cur = float(np.hypot(dxc, dyc))
    if l_cur <= 1e-12:
        raise ValueError("Chiều dài hiện tại của thanh suy biến về 0.")

    # Cosin chỉ phương hiện tại n = [c_cur, s_cur]
    c_cur, s_cur = dxc / l_cur, dyc / l_cur
    n = np.array([c_cur, s_cur], dtype=float)

    # Biến dạng kỹ thuật chính xác (khử mất chữ số có nghĩa bằng hằng đẳng thức a - b = (a^2 - b^2)/(a + b))
    # l^2 - L0^2 = dux*(2*dx0 + dux) + duy*(2*dy0 + duy)
    dl_exact = (dux * (2.0 * dx0 + dux) + duy * (2.0 * dy0 + duy)) / (l_cur + L0)
    strain_eng = dl_exact / L0
    N = E * A * strain_eng
    energy = 0.5 * E * A * L0 * (strain_eng ** 2)

    # Véc-tơ nội lực phần tử trong hệ tổng thể
    f_int = N * np.array([-c_cur, -s_cur, c_cur, s_cur], dtype=float)

    # Tách ma trận tiếp tuyến thành phần vật liệu Ke_mat và hình học Kg_mat
    nnT = np.outer(n, n)
    I_minus_nnT = np.eye(2) - nnT
    k_mat_2 = (E * A / L0) * nnT
    k_geo_2 = (N / l_cur) * I_minus_nnT

    Ke_mat = np.block([[k_mat_2, -k_mat_2], [-k_mat_2, k_mat_2]])
    Kg_mat = np.block([[k_geo_2, -k_geo_2], [-k_geo_2, k_geo_2]])
    Kt = Ke_mat + Kg_mat

    return f_int, Kt, Ke_mat, Kg_mat, float(N), float(strain_eng), float(l_cur), float(energy)


def bar2g_total_lagrangian(
    ex0: np.ndarray,
    ey0: np.ndarray,
    ep: Tuple[float, float],
    ed: np.ndarray,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, float, float, float, float]:
    """
    Phần tử thanh dàn 2D PHI TUYẾN HÌNH HỌC TOTAL LAGRANGIAN sử dụng biến dạng
    hữu hạn Green-Lagrange theo đúng Bài giảng NSA_4 (PGS.TS. Ngô Hữu Cường)
    và giáo trình McGuire, Gallagher & Ziemian (2000).

    Nguồn đối chiếu:
      - Bài giảng NSA_4.pdf, Mục 4.1.1, Slides 6-12 (PDF tr. 2-3):
          ε_fin = du/dx + (1/2)*(du/dx)^2 + (1/2)*(dv/dx)^2 = (l^2 - L0^2) / (2*L0^2)
          [k_g] = (F_x2 / L0) * [[1,0,-1,0],[0,1,0,-1],[-1,0,1,0],[0,-1,0,1]]
      - McGuire, Gallagher & Ziemian (2000), Mục 9.1.1, PT (9.1)-(9.9), tr. 243-245.
      - Jeffers (2026), Mục 8.1 (Total Lagrangian Formulation), tr. 172-180.

    Điểm khác biệt học thuật sâu sắc so với CALFEM `bar2g` (đã giải thích trong thuyết minh):
      1. Biến dạng Green-Lagrange ε_GL = (l^2 - L0^2) / (2*L0^2) = ε_eng * (1 + ε_eng/2).
      2. Ứng suất Piola-Kirchhoff loại 2: S = E * ε_GL -> lực dọc PK2: S_N = E * A * ε_GL.
      3. Nội lực tổng thể f_int = S_N * (l/L0) * [-c', -s', c', s']^T.
      4. Ma trận độ cứng hình học Kg = (S_N / L0) * [[I, -I], [-I, I]] có ĐẦY ĐỦ cả
         thành phần dọc trục (1, -1) lẫn ngang trục (1, -1), khớp 100% PT (9.9) McGuire
         và Slide 11-12 Bài giảng NSA_4!
      5. Khi biến dạng nhỏ (ε << 1), ε_GL ≈ ε_eng và (l/L0) ≈ 1 nên Total Lagrangian
         và Corotational UL cho kết quả gần như trùng khít.

    Giá trị trả về:
      (f_int, Kt, Ke_mat, Kg_mat, N_cauchy_equiv, strain_gl, l_cur, energy)
    """
    E, A = float(ep[0]), float(ep[1])
    ed_vec = np.asarray(ed, dtype=float).reshape(4)

    dx0 = float(ex0[1]) - float(ex0[0])
    dy0 = float(ey0[1]) - float(ey0[0])
    L0 = float(np.hypot(dx0, dy0))

    dux = ed_vec[2] - ed_vec[0]
    duy = ed_vec[3] - ed_vec[1]
    dxc = dx0 + dux
    dyc = dy0 + duy
    l_cur = float(np.hypot(dxc, dyc))
    if l_cur <= 1e-12:
        raise ValueError("Chiều dài hiện tại của thanh suy biến về 0.")

    # Biến dạng hữu hạn Green-Lagrange chính xác (khử hoàn toàn sai số triệt tiêu số học)
    strain_gl = (dux * (2.0 * dx0 + dux) + duy * (2.0 * dy0 + duy)) / (2.0 * L0 * L0)
    # Lực dọc theo ứng suất Piola-Kirchhoff loại 2 (2nd PK)
    S_N = E * A * strain_gl
    # Năng lượng biến dạng St. Venant-Kirchhoff: U = (1/2) * E * A * L0 * ε_GL^2
    energy = 0.5 * E * A * L0 * (strain_gl ** 2)

    # Véc-tơ hiệu tọa độ hiện tại d = [dxc, dyc]
    d_cur = np.array([dxc, dyc], dtype=float)
    # Đạo hàm d(ε_GL)/d(ed) = (1/L0^2) * [-dxc, -dyc, dxc, dyc]
    # f_int = dU/d(ed) = (S_N / L0) * [-dxc, -dyc, dxc, dyc]
    f_int = (S_N / L0) * np.array([-dxc, -dyc, dxc, dyc], dtype=float)

    # Thành phần độ cứng vật liệu (tuyến tính + chuyển vị ban đầu K_0 + K_L)
    k_mat_2 = (E * A / (L0 ** 3)) * np.outer(d_cur, d_cur)
    # Thành phần độ cứng hình học ứng suất ban đầu K_g (KHỚP 100% NSA_4 Slide 11-12!)
    k_geo_2 = (S_N / L0) * np.eye(2)

    Ke_mat = np.block([[k_mat_2, -k_mat_2], [-k_mat_2, k_mat_2]])
    Kg_mat = np.block([[k_geo_2, -k_geo_2], [-k_geo_2, k_geo_2]])
    Kt = Ke_mat + Kg_mat

    # Lực dọc thực theo phương thanh biến dạng: N_phys = ||f_int_node2|| * sign(S_N) = S_N * (l / L0)
    N_phys = S_N * (l_cur / L0)
    return f_int, Kt, Ke_mat, Kg_mat, float(N_phys), float(strain_gl), float(l_cur), float(energy)
