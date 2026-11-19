# -*- coding: utf-8 -*-
"""
================================================================================
MÔ-ĐUN 2: MÔ HÌNH HÌNH HỌC, VẬT LIỆU, TIẾT DIỆN 3D VÀ CÁC BÀI TOÁN CHUẨN
================================================================================
Chức năng:
  - Định nghĩa cấu trúc dữ liệu `TrussModel` cho mọi hệ dàn phẳng (tọa độ nút,
    bảng liên kết phần tử, bảng Edof chuẩn CALFEM 1-based, diện tích tiết diện,
    mô-đun đàn hồi E, hệ số Poisson ν, giới hạn chảy fy để tham khảo kỹ thuật,
    điều kiện biên bc và véc-tơ tải trọng tham chiếu f_ref).
  - Cung cấp sẵn 4 bài toán quan trọng:
      1. `create_assignment_5bar_truss(...)` : ĐỀ BÀI CHÍNH (1.jpg) – Dàn 4 nút,
         5 thanh: L = 1000 mm, E = 200.000 MPa, A = 2001 mm², P = 208.000 N hướng
         lên tại nút 2, diện tích thanh chéo = 2*sqrt(2)*A.
      2. `create_dahlblom_example_9_1()`     : BÀI TOÁN KIỂM CHỨNG PHI TUYẾN
         (Olsson & Dahlblom 2016, Chương 9, Example 9.1, tr. 260-261 / PDF 274-275)
         để xác minh hàm `bar2g` và vòng lặp bậc 2 khớp 100% Bảng 1 trong sách!
      3. `create_calfem_exs3_truss()`        : BÀI TOÁN KIỂM CHỨNG TUYẾN TÍNH
         (CALFEM 3.4 `examples/exs3.m`, calfem34.pdf tr. 9.3-9..9.3-12 / PDF 233-236).
      4. `create_von_mises_arch()`           : BÀI TOÁN VÒM 2 THANH VON MISES
         minh họa trực quan hiện tượng bật nhảy (Snap-Through) và mất ổn định
         điểm giới hạn (Limit Point) theo McGuire Example 8.2 & 9.2 (tr. 248).
================================================================================
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import List, Tuple, Dict, Any
import math
import numpy as np


@dataclass
class CrossSectionSpec:
    """
    Đặc trưng hình học mặt cắt ngang 3D của thanh dàn có diện tích đúng bằng `area_mm2`.
    Dùng để dựng hình khối 3D chuẩn ANSYS và thực hiện chức năng "Phẫu thuật"
    (mổ mặt cắt xem phân bố ứng suất, biến dạng dọc trục & co giãn ngang Poisson).

    Các dạng tiết diện hỗ trợ (tất cả được quy đổi chính xác về đúng diện tích A_e):
      - "I_SECTION"  : Thép chữ I / chữ H đối xứng (b = h, tf = 0.12*h, tw = 0.08*h).
      - "CIRC_TUBE"  : Ống thép tròn rỗng (tỷ số chiều dày thành t/R = 0.15).
      - "SOLID_ROD"  : Thanh tròn đặc (bán kính R = sqrt(A/pi)).
      - "BOX_SECTION": Thép hộp vuông rỗng (b = h, chiều dày thành t = 0.12*h).
    """

    shape: str = "I_SECTION"
    area_mm2: float = 2001.0

    def dimensions(self) -> Dict[str, float]:
        """Tính kích thước hình học (mm) và mô-men quán tính I (mm^4) từ diện tích A."""
        A = float(self.area_mm2)
        if self.shape == "SOLID_ROD":
            R = math.sqrt(A / math.pi)
            I = 0.25 * math.pi * (R ** 4)
            return {
                "height": 2.0 * R,
                "width": 2.0 * R,
                "radius_out": R,
                "radius_in": 0.0,
                "I_major": I,
                "I_minor": I,
                "r_gyration": 0.5 * R,
            }
        if self.shape == "CIRC_TUBE":
            # A = pi * (R^2 - (0.85*R)^2) = pi * 0.2775 * R^2
            alpha = 0.85
            R = math.sqrt(A / (math.pi * (1.0 - alpha ** 2)))
            r_in = alpha * R
            I = 0.25 * math.pi * (R ** 4 - r_in ** 4)
            return {
                "height": 2.0 * R,
                "width": 2.0 * R,
                "radius_out": R,
                "radius_in": r_in,
                "thickness": R - r_in,
                "I_major": I,
                "I_minor": I,
                "r_gyration": math.sqrt(I / A),
            }
        if self.shape == "BOX_SECTION":
            # A = h^2 - (h - 2*t)^2 với t = 0.12*h => A = (1 - 0.76^2)*h^2 = 0.4224*h^2
            c_in = 0.76
            h = math.sqrt(A / (1.0 - c_in ** 2))
            t = 0.12 * h
            I = (h ** 4 - (c_in * h) ** 4) / 12.0
            return {
                "height": h,
                "width": h,
                "thickness": t,
                "I_major": I,
                "I_minor": I,
                "r_gyration": math.sqrt(I / A),
            }
        # Mặc định: I_SECTION (b = 0.85*h, tf = 0.12*h, tw = 0.08*h)
        # A = 2*(b*tf) + (h - 2*tf)*tw = (2*0.85*0.12 + 0.76*0.08)*h^2 = 0.2648*h^2
        coeff = 2.0 * 0.85 * 0.12 + 0.76 * 0.08
        h = math.sqrt(A / coeff)
        b = 0.85 * h
        tf = 0.12 * h
        tw = 0.08 * h
        h_web = h - 2.0 * tf
        I_major = (b * (h ** 3) - (b - tw) * (h_web ** 3)) / 12.0
        I_minor = (2.0 * tf * (b ** 3) + h_web * (tw ** 3)) / 12.0
        return {
            "height": h,
            "width": b,
            "tf": tf,
            "tw": tw,
            "I_major": I_major,
            "I_minor": I_minor,
            "r_gyration": math.sqrt(I_minor / A),
        }


@dataclass
class TrussModel:
    """
    Mô hình tổng quát một hệ dàn phẳng 2D theo chuẩn dữ liệu CALFEM.
    """

    name: str
    description: str
    coords: np.ndarray               # (n_nodes, 2) tọa độ ban đầu [x, y] (mm)
    conn: np.ndarray                 # (n_elems, 2) chỉ số nút đầu/cuối 1-based
    areas: np.ndarray                # (n_elems,) diện tích tiết diện từng thanh (mm²)
    E: float                         # Mô-đun đàn hồi Young (MPa = N/mm²)
    nu: float                        # Hệ số Poisson (dùng cho biến dạng ngang 3D)
    bc: np.ndarray                   # (n_bc, 2) [DOF_1based, giá trị ràng buộc]
    f_ref: np.ndarray                # (2*n_nodes,) véc-tơ tải trọng tham chiếu (N)
    member_labels: List[str]         # Tên thanh: ['1-2', '1-3', ...]
    node_labels: List[str]           # Tên nút: ['Nút 1', 'Nút 2', ...]
    section_shape: str = "I_SECTION" # Hình dạng mặt cắt 3D để phẫu thuật
    fy_reference_mpa: float = 250.0  # Giới hạn chảy tham khảo (chỉ để đánh giá kỹ thuật)
    units: str = "N-mm-MPa"
    meta: Dict[str, Any] = field(default_factory=dict)

    @property
    def n_nodes(self) -> int:
        return int(self.coords.shape[0])

    @property
    def n_elems(self) -> int:
        return int(self.conn.shape[0])

    @property
    def n_dofs(self) -> int:
        return 2 * self.n_nodes

    @property
    def edof(self) -> np.ndarray:
        """
        Tạo bảng định vị bậc tự do Edof theo đúng chuẩn CALFEM 3.4:
        Mỗi hàng = [số_hiệu_phần_tử, dof_x_nút_i, dof_y_nút_i, dof_x_nút_j, dof_y_nút_j]
        với đánh số 1-based.
        """
        rows = []
        for e in range(self.n_elems):
            ni, nj = int(self.conn[e, 0]), int(self.conn[e, 1])
            rows.append([e + 1, 2 * ni - 1, 2 * ni, 2 * nj - 1, 2 * nj])
        return np.array(rows, dtype=int)

    @property
    def constrained_dofs_0based(self) -> np.ndarray:
        return self.bc[:, 0].astype(int) - 1

    @property
    def free_dofs_0based(self) -> np.ndarray:
        mask = np.ones(self.n_dofs, dtype=bool)
        mask[self.constrained_dofs_0based] = False
        return np.where(mask)[0]

    def element_coords(self, e: int) -> Tuple[np.ndarray, np.ndarray]:
        """Trả về (ex, ey) tọa độ ban đầu của phần tử thứ e (0-based)."""
        ni, nj = int(self.conn[e, 0]) - 1, int(self.conn[e, 1]) - 1
        ex = np.array([self.coords[ni, 0], self.coords[nj, 0]], dtype=float)
        ey = np.array([self.coords[ni, 1], self.coords[nj, 1]], dtype=float)
        return ex, ey

    def initial_lengths_and_cosines(self) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
        """Tính chiều dài ban đầu L0 và cosin chỉ phương (c0, s0) của mọi thanh."""
        L0 = np.zeros(self.n_elems, dtype=float)
        c0 = np.zeros(self.n_elems, dtype=float)
        s0 = np.zeros(self.n_elems, dtype=float)
        for e in range(self.n_elems):
            ex, ey = self.element_coords(e)
            dx, dy = ex[1] - ex[0], ey[1] - ey[0]
            L0[e] = math.hypot(dx, dy)
            c0[e] = dx / L0[e]
            s0[e] = dy / L0[e]
        return L0, c0, s0

    def section_spec(self, e: int) -> CrossSectionSpec:
        return CrossSectionSpec(shape=self.section_shape, area_mm2=float(self.areas[e]))


def create_assignment_5bar_truss(
    L_mm: float = 1000.0,
    E_mpa: float = 200000.0,
    A_mm2: float = 2001.0,
    P_n: float = 208000.0,
    nu: float = 0.3,
    section_shape: str = "I_SECTION",
) -> TrussModel:
    """
    Khởi tạo MÔ HÌNH ĐỀ BÀI CHÍNH (từ tệp `BaiTapNhom/DeBai/1.jpg`):
      - Hệ dàn phẳng gồm 4 nút, 5 thanh liên kết khớp lý tưởng:
          • Nút 1: (0, 0)       – Gối khớp cố định (cấm u1x = 0, u1y = 0)
          • Nút 2: (L, 0)       – Nút tự do, chịu tải tập trung P hướng LÊN (+Y)
          • Nút 3: (0, L)       – Nút tự do
          • Nút 4: (2L, L)      – Gối di động (con lăn ngang phía trên, cấm u4y = 0)
      - 5 thanh dàn:
          • Thanh 1 (1–2): ngang dưới, dài L,        diện tích A
          • Thanh 2 (1–3): đứng trái,  dài L,        diện tích A
          • Thanh 3 (3–4): ngang trên, dài 2L,       diện tích A
          • Thanh 4 (3–2): chéo trái,  dài √2·L,     diện tích 2√2·A
          • Thanh 5 (2–4): chéo phải,  dài √2·L,     diện tích 2√2·A
      - Số liệu mặc định theo đề bài 1.jpg:
          L = 1 m = 1000 mm; E = 200 GPa = 200.000 MPa;
          A = 2001 mm²; P = 208 kN = 208.000 N (hướng lên).
    """
    coords = np.array(
        [
            [0.0, 0.0],          # Nút 1
            [L_mm, 0.0],         # Nút 2
            [0.0, L_mm],         # Nút 3
            [2.0 * L_mm, L_mm],  # Nút 4
        ],
        dtype=float,
    )
    conn = np.array(
        [
            [1, 2],  # Thanh 1: 1-2
            [1, 3],  # Thanh 2: 1-3
            [3, 4],  # Thanh 3: 3-4
            [3, 2],  # Thanh 4: 3-2
            [2, 4],  # Thanh 5: 2-4
        ],
        dtype=int,
    )
    areas = np.array(
        [
            A_mm2,
            A_mm2,
            A_mm2,
            2.0 * math.sqrt(2.0) * A_mm2,
            2.0 * math.sqrt(2.0) * A_mm2,
        ],
        dtype=float,
    )
    # Điều kiện biên (DOF 1-based): ux1=1, uy1=2, uy4=8 bị khống chế bằng 0
    bc = np.array([[1, 0.0], [2, 0.0], [8, 0.0]], dtype=float)
    # Véc-tơ tải trọng nút: P tác dụng hướng LÊN tại nút 2 => DOF số 4 (chỉ số 3)
    f_ref = np.zeros(8, dtype=float)
    f_ref[3] = P_n

    return TrussModel(
        name="DeBai_Dan5Thanh",
        description=(
            "Hệ dàn phẳng 4 nút – 5 thanh theo Đề bài (1.jpg): "
            f"L={L_mm:.0f} mm, E={E_mpa/1000:.0f} GPa, A={A_mm2:.0f} mm², "
            f"P={P_n/1000:.1f} kN hướng lên tại Nút 2."
        ),
        coords=coords,
        conn=conn,
        areas=areas,
        E=E_mpa,
        nu=nu,
        bc=bc,
        f_ref=f_ref,
        member_labels=["1-2", "1-3", "3-4", "3-2", "2-4"],
        node_labels=["Nút 1 (Khớp cố định)", "Nút 2 (Đặt tải P)", "Nút 3 (Tự do)", "Nút 4 (Gối di động)"],
        section_shape=section_shape,
        fy_reference_mpa=250.0,
        units="N-mm-MPa",
        meta={"L_mm": L_mm, "E_mpa": E_mpa, "A_mm2": A_mm2, "P_n": P_n},
    )


def create_dahlblom_example_9_1() -> TrussModel:
    """
    BÀI TOÁN KIỂM CHỨNG PHI TUYẾN HÌNH HỌC CHUẨN: Example 9.1
    Nguồn: Olsson & Dahlblom (2016), Structural Mechanics: Modelling and Analysis
           of Frames and Trusses, Chương 9, Mục 9.2.3, tr. 260-261 (PDF tr. 274-275).

    Dữ liệu gốc trong sách (quy đổi thống nhất về hệ N - mm - MPa):
      - Nút 1 (A): (0, 0) mm – khớp cố định (DOF 1, 2 = 0)
      - Nút 2 (C): (0, 1200) mm – khớp cố định (DOF 3, 4 = 0)
      - Nút 3 (B): (1600, 0) mm – nút tự do (DOF 5, 6), chịu tải:
          P = -10 MN = -10e6 N (ngang sang trái), F = -0.2 MN = -0.2e6 N (đứng xuống)
      - Thanh 1 (A-B = 1-3): L = 1600 mm, EA = 400 MN = 400e6 N -> với E = 200.000 MPa => A1 = 2000 mm²
      - Thanh 2 (C-B = 2-3): L = 2000 mm, EA = 100 MN = 100e6 N -> với E = 200.000 MPa => A2 = 500 mm²

    Đáp số Bảng 1 của Dahlblom (tr. 261 / PDF tr. 275) sau 6 vòng lặp `bar2g`:
      a5 = -44.544 mm, a6 = -108.835 mm, Q1 = -11.1360 MN, Q2 = +1.4833 MN.
    """
    coords = np.array([[0.0, 0.0], [0.0, 1200.0], [1600.0, 0.0]], dtype=float)
    conn = np.array([[1, 3], [2, 3]], dtype=int)
    E_mpa = 200000.0
    areas = np.array([2000.0, 500.0], dtype=float)  # EA1 = 400 MN, EA2 = 100 MN
    bc = np.array([[1, 0.0], [2, 0.0], [3, 0.0], [4, 0.0]], dtype=float)
    f_ref = np.array([0.0, 0.0, 0.0, 0.0, -10.0e6, -0.2e6], dtype=float)
    return TrussModel(
        name="Benchmark_Dahlblom_Ex9_1",
        description="Ví dụ chuẩn 9.1 (Olsson & Dahlblom 2016, tr. 260-261) kiểm chứng CALFEM bar2g.",
        coords=coords,
        conn=conn,
        areas=areas,
        E=E_mpa,
        nu=0.3,
        bc=bc,
        f_ref=f_ref,
        member_labels=["1-3 (AB)", "2-3 (CB)"],
        node_labels=["Nút 1 (A)", "Nút 2 (C)", "Nút 3 (B)"],
        section_shape="SOLID_ROD",
        units="N-mm-MPa",
        meta={
            "book_expected": {
                "a5_mm": -44.544,
                "a6_mm": -108.835,
                "N1_MN": -11.1360,
                "N2_MN": 1.4833,
            }
        },
    )


def create_calfem_exs3_truss() -> TrussModel:
    """
    BÀI TOÁN KIỂM CHỨNG TUYẾN TÍNH CHUẨN CALFEM 3.4: `examples/exs3.m`
    Nguồn: calfem34.pdf Mục 9.3, tr. 9.3-9..9.3-12 (PDF tr. 233-236)
           và Olsson & Dahlblom (2016), Example 3.2, tr. 59-65 (PDF tr. 73-79).
    Quy đổi sang N - mm - MPa (tương đương chính xác hệ N - m - Pa trong sách).
    """
    coords = np.array(
        [
            [0.0, 0.0],       # Nút 1 (DOF 1,2)
            [0.0, 1200.0],    # Nút 2 (DOF 3,4)
            [1600.0, 0.0],    # Nút 3 (DOF 5,6 - tự do, chịu F_y = -80 kN)
            [1600.0, 1200.0], # Nút 4 (DOF 7,8)
        ],
        dtype=float,
    )
    conn = np.array([[1, 3], [3, 4], [2, 3]], dtype=int)
    areas = np.array([600.0, 300.0, 1000.0], dtype=float)
    bc = np.array(
        [[1, 0.0], [2, 0.0], [3, 0.0], [4, 0.0], [7, 0.0], [8, 0.0]], dtype=float
    )
    f_ref = np.zeros(8, dtype=float)
    f_ref[5] = -80000.0  # -80 kN hướng xuống tại DOF 6
    return TrussModel(
        name="Benchmark_CALFEM_exs3",
        description="Ví dụ chuẩn CALFEM 3.4 exs3.m (calfem34.pdf tr. 9.3-9..12).",
        coords=coords,
        conn=conn,
        areas=areas,
        E=200000.0,
        nu=0.3,
        bc=bc,
        f_ref=f_ref,
        member_labels=["1-3", "3-4", "2-3"],
        node_labels=["Nút 1", "Nút 2", "Nút 3 (Tự do)", "Nút 4"],
        section_shape="CIRC_TUBE",
        units="N-mm-MPa",
        meta={
            "manual_expected": {
                "u5_mm": -0.398,
                "u6_mm": -1.152,
                "N_N": [-29845.0, 57617.0, 37306.0],
            }
        },
    )


def create_von_mises_arch(
    span_half_mm: float = 1000.0,
    rise_mm: float = 200.0,
    E_mpa: float = 200000.0,
    A_mm2: float = 1000.0,
    P_n: float = 1000000.0,
) -> TrussModel:
    """
    Mô hình Vòm dàn 2 thanh đối xứng Von Mises (minh họa trực quan Snap-Through
    theo McGuire Example 8.2 & Example 9.2, tr. 248).
    """
    coords = np.array(
        [
            [0.0, 0.0],
            [span_half_mm, rise_mm],
            [2.0 * span_half_mm, 0.0],
        ],
        dtype=float,
    )
    conn = np.array([[1, 2], [2, 3]], dtype=int)
    areas = np.array([A_mm2, A_mm2], dtype=float)
    bc = np.array([[1, 0.0], [2, 0.0], [5, 0.0], [6, 0.0]], dtype=float)
    f_ref = np.array([0.0, 0.0, 0.0, -P_n, 0.0, 0.0], dtype=float)
    return TrussModel(
        name="VonMises_SnapThrough",
        description="Vòm dàn 2 thanh Von Mises minh họa hiện tượng bật nhảy (Snap-Through).",
        coords=coords,
        conn=conn,
        areas=areas,
        E=E_mpa,
        nu=0.3,
        bc=bc,
        f_ref=f_ref,
        member_labels=["1-2", "2-3"],
        node_labels=["Nút 1 (Gối trái)", "Nút 2 (Đỉnh vòm)", "Nút 3 (Gối phải)"],
        section_shape="BOX_SECTION",
        units="N-mm-MPa",
    )
