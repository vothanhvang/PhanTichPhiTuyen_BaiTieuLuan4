# -*- coding: utf-8 -*-
"""
Đóng gói toàn bộ ứng dụng Flutter Windows (EXE + DLL + data/) thành MỘT TỆP
DUY NHẤT `releases/PhanTichPhiTuyen_CALFEM_Windows_x64.exe` chạy trực tiếp
trên bất kỳ máy tính Windows 10/11 nào chỉ bằng một cú nhấp đúp chuột!
"""

from __future__ import annotations
import os
import subprocess
import sys
import zipfile


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    flutter_rel = os.path.join(root, "flutter_app", "build", "windows", "x64", "runner", "Release")
    build_tmp = os.path.join(root, "scripts", "_build_single_exe")
    os.makedirs(build_tmp, exist_ok=True)
    payload_zip = os.path.join(build_tmp, "flutter_payload.zip")

    print("1. Nén gói Flutter Windows Release thành payload nội bộ...")
    with zipfile.ZipFile(payload_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for dirpath, _, filenames in os.walk(flutter_rel):
            for fn in filenames:
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, flutter_rel)
                zf.write(full, rel)

    launcher_py = os.path.join(build_tmp, "portable_launcher.py")
    with open(launcher_py, "w", encoding="utf-8") as f:
        f.write(
            '''# -*- coding: utf-8 -*-
import os, sys, zipfile, subprocess, shutil

APP_DIR_NAME = "CALFEM_Nonlinear_Studio_v1_0"

def main():
    base_res = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    payload = os.path.join(base_res, "flutter_payload.zip")
    local_root = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    target = os.path.join(local_root, APP_DIR_NAME)
    exe_path = os.path.join(target, "calfem_nonlinear_truss.exe")
    marker = os.path.join(target, ".extracted_v1")

    if not os.path.exists(marker) or not os.path.exists(exe_path):
        os.makedirs(target, exist_ok=True)
        with zipfile.ZipFile(payload, "r") as zf:
            zf.extractall(target)
        with open(marker, "w", encoding="utf-8") as mf:
            mf.write("ok")

    # Nếu có đặt calfem_engine.exe nằm cạnh file .exe đơn lẻ thì tự động copy vào để kết nối Live Python!
    my_dir = os.path.dirname(os.path.abspath(sys.executable))
    near_py = os.path.join(my_dir, "calfem_engine.exe")
    dst_py = os.path.join(target, "calfem_engine.exe")
    if os.path.exists(near_py) and not os.path.exists(dst_py):
        try:
            shutil.copy2(near_py, dst_py)
        except Exception:
            pass

    subprocess.Popen([exe_path], cwd=target)

if __name__ == "__main__":
    main()
'''
        )

    out_dir = os.path.join(root, "releases")
    os.makedirs(out_dir, exist_ok=True)
    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--onefile",
        "--noconsole",
        "--name",
        "PhanTichPhiTuyen_CALFEM_Windows_x64",
        "--distpath",
        out_dir,
        "--workpath",
        os.path.join(build_tmp, "work"),
        "--specpath",
        build_tmp,
        "--add-data",
        f"{payload_zip};.",
        launcher_py,
    ]
    print("2. Đóng gói tệp đơn lẻ PhanTichPhiTuyen_CALFEM_Windows_x64.exe...")
    subprocess.run(cmd, check=True)
    out_exe = os.path.join(out_dir, "PhanTichPhiTuyen_CALFEM_Windows_x64.exe")
    sz_mb = os.path.getsize(out_exe) / (1024 * 1024)
    print(f"HOÀN TẤT: {out_exe} ({sz_mb:.2f} MB)")


if __name__ == "__main__":
    main()
