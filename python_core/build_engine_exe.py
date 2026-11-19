# -*- coding: utf-8 -*-
"""
Script đóng gói lõi tính toán Python CALFEM (API Server + Report Exporter)
thành một tệp thực thi duy nhất `calfem_engine.exe` bằng PyInstaller để
nhúng cùng ứng dụng Flutter Windows chạy độc lập trên mọi máy tính Windows.
"""

from __future__ import annotations
import os
import subprocess
import sys


def build() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    entry_script = os.path.join(root, "python_core", "engine_entry.py")
    dist_dir = os.path.join(root, "python_core", "dist")
    work_dir = os.path.join(root, "python_core", "build_pyinstaller")

    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--onefile",
        "--console",
        "--name",
        "calfem_engine",
        "--distpath",
        dist_dir,
        "--workpath",
        work_dir,
        "--specpath",
        work_dir,
        "--paths",
        root,
        "--hidden-import",
        "scipy.linalg",
        "--hidden-import",
        "scipy._cyutility",
        "--hidden-import",
        "docx",
        "--hidden-import",
        "reportlab.platypus",
        entry_script,
    ]
    print("Đang đóng gói calfem_engine.exe bằng PyInstaller...")
    subprocess.run(cmd, check=True)
    print(f"Đóng gói thành công: {os.path.join(dist_dir, 'calfem_engine.exe')}")


if __name__ == "__main__":
    build()
