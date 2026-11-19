# -*- coding: utf-8 -*-
"""Điểm khởi chạy độc lập cho `calfem_engine.exe` (chạy API hoặc chạy kiểm chứng CLI)."""

import os
import sys

# Đảm bảo xuất tiếng Việt UTF-8 ổn định trên mọi máy tính Windows bất kể codepage hệ thống
os.environ.setdefault("PYTHONIOENCODING", "utf-8")
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from python_core.api_server import main as run_api_main
from python_core.test_verification import run_all_tests

if __name__ == "__main__":
    if "--test" in sys.argv:
        run_all_tests()
    else:
        run_api_main()
