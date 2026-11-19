# -*- coding: utf-8 -*-
"""
================================================================================
GÓI PHẦN MỀM LÕI TÍNH TOÁN: CALFEM PHI TUYẾN HÌNH HỌC CHO KẾT CẤU DÀN PHẲNG
================================================================================
Học phần  : Phân tích Phi tuyến Kết cấu (Nonlinear Structural Analysis)
Trường    : Trường Đại học Bách Khoa – ĐHQG TP. Hồ Chí Minh
GVHD      : PGS.TS. Ngô Hữu Cường
Học viên  : Võ Thanh Vang (MSHV: 2670624)

Cấu trúc mô-đun (kiến trúc tách lớp rõ ràng, dễ đọc, dễ kiểm chứng):
  1. calfem_elements.py   : Các hàm phần tử & lắp ráp chuẩn CALFEM 3.4
                            (bar2e, bar2g, bar2s, assem, solveq, extract)
                            và mở rộng đồng chuyển động (Corotational UL)
                            + Total Lagrangian (Green-Lagrange theo NSA_4).
  2. truss_models.py      : Định nghĩa hình học, vật liệu, tiết diện, điều kiện
                            biên và tải trọng cho bài toán dàn 4 nút – 5 thanh
                            cùng các bài toán chuẩn kiểm chứng (Dahlblom Ex 9.1,
                            CALFEM exs3, Vòm bật nhảy Von Mises).
  3. nonlinear_solvers.py : 6 thuật toán giải hệ phương trình phi tuyến
                            (Euler, Runge-Kutta bậc 2, Newton-Raphson đầy đủ,
                            Newton-Raphson cải tiến, Điều khiển chuyển vị,
                            Chiều dài cung Arc-Length) + Bài toán trị riêng
                            tìm tải tới hạn đàn hồi (Buckling Eigenvalue).
  4. probe_dissection.py  : Khảo sát ứng suất – biến dạng tại vị trí bất kỳ
                            và mô-đun "Phẫu thuật" mặt cắt ngang/dọc 3D.
  5. report_exporter.py   : Tự động xuất thuyết minh định dạng Word (.docx)
                            và PDF (.pdf) từ bất kỳ kịch bản tính toán nào.
  6. api_server.py        : Cầu nối HTTP JSON cục bộ cho giao diện Flutter.
================================================================================
"""

from .calfem_elements import (
    bar2e,
    bar2g,
    bar2s,
    assem,
    solveq,
    extract,
    bar2g_corotational,
    bar2g_total_lagrangian,
)
from .truss_models import (
    TrussModel,
    CrossSectionSpec,
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

__all__ = [
    "bar2e",
    "bar2g",
    "bar2s",
    "assem",
    "solveq",
    "extract",
    "bar2g_corotational",
    "bar2g_total_lagrangian",
    "TrussModel",
    "CrossSectionSpec",
    "create_assignment_5bar_truss",
    "create_dahlblom_example_9_1",
    "create_calfem_exs3_truss",
    "create_von_mises_arch",
    "solve_linear_calfem",
    "solve_calfem_bar2g_second_order",
    "solve_corotational_newton_raphson",
    "solve_corotational_modified_nr",
    "solve_corotational_euler",
    "solve_corotational_rk2",
    "solve_corotational_displacement_control",
    "solve_corotational_arc_length",
    "solve_total_lagrangian_nr",
    "solve_elastic_buckling_eigen",
    "verify_tangent_finite_difference",
    "probe_member_at",
    "dissect_cross_section",
    "compute_longitudinal_profile",
]
