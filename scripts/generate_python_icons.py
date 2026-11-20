# -*- coding: utf-8 -*-
"""
Tạo bộ biểu tượng (Icon) chuẩn Python cho toàn bộ nền tảng:
  - Windows Desktop (.ico đa độ phân giải 16..256px)
  - Android Launcher (mipmap mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi)
  - Web Favicon & PWA Icons (favicon.png, Icon-192, Icon-512, maskable)
"""

from __future__ import annotations
import os
from PIL import Image, ImageDraw


def _draw_snake_half(mask: Image.Image, S: int, scale: float, flip: bool = False) -> None:
    """Vẽ chuẩn xác 1 nửa biểu tượng Python (trên-trái nếu flip=False, xoay 180° nếu flip=True)."""
    d = ImageDraw.Draw(mask)
    cx, cy = S / 2.0, S / 2.0
    u = S * scale / 100.0  # hệ tọa độ chuẩn hóa [-50..+50]

    def pt(x, y):
        if flip:
            x, y = -x, -y
        return (cx + x * u, cy + y * u)

    def rrect(x0, y0, x1, y1, r, val=255):
        p0, p1 = pt(x0, y0), pt(x1, y1)
        bx0, bx1 = min(p0[0], p1[0]), max(p0[0], p1[0])
        by0, by1 = min(p0[1], p1[1]), max(p0[1], p1[1])
        d.rounded_rectangle([bx0, by0, bx1, by1], radius=max(1, int(r * u)), fill=val)

    # 1. Khối đầu trên (x: -22..+22, y: -42..-2) bo tròn mạnh
    rrect(-22, -42, 22, -1, 14, 255)
    # 2. Khối thân trái (x: -42..-1, y: -19..+21) bo tròn mạnh
    rrect(-42, -19, 12, 18, 14, 255)
    # 3. Phần eo uốn vào giữa nối giữa đầu trên và thân trái
    rrect(-22, -22, 22, -1, 10, 255)
    # 4. Khoét rãnh miệng chữ C bên trái trên (x: -23..+1, y: -22..-17) — đường cắt đặc trưng Python!
    rrect(-23, -22, 1, -17.5, 2, 0)
    # 5. Khoét rãnh ngăn cách uốn lượn với mảnh thứ hai ở góc dưới-phải
    rrect(-22, 0.5, 23, 25, 13, 0)
    # 6. Khoét mắt tròn trắng
    ex, ey = pt(-11, -30)
    er = 4.3 * u
    d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=0)


def render_python_icon(size: int = 512, maskable: bool = False) -> Image.Image:
    S = size * 4
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    bg = (11, 22, 44, 255)
    rim = (56, 189, 248, 230)
    if maskable:
        d.rectangle([0, 0, S, S], fill=bg)
    else:
        pad = int(S * 0.04)
        rad = int(S * 0.22)
        d.rounded_rectangle([pad, pad, S - pad, S - pad], radius=rad, fill=bg, outline=rim, width=max(2, S // 64))

    scale = 0.72 if maskable else 0.80

    # Tạo mặt nạ cho mảnh Xanh (trên-trái) và mảnh Vàng (dưới-phải)
    m_blue = Image.new("L", (S, S), 0)
    _draw_snake_half(m_blue, S, scale, flip=False)

    m_gold = Image.new("L", (S, S), 0)
    _draw_snake_half(m_gold, S, scale, flip=True)

    # Tô gradient mượt cho mảnh Xanh (#4B8BBE -> #306998) và mảnh Vàng (#FFE873 -> #FFD43B)
    blue_layer = Image.new("RGBA", (S, S), (55, 118, 171, 255))
    gold_layer = Image.new("RGBA", (S, S), (255, 212, 59, 255))
    img.paste(blue_layer, (0, 0), m_blue)
    img.paste(gold_layer, (0, 0), m_gold)

    # Vẽ 2 tròng mắt trắng sáng rõ nét
    d = ImageDraw.Draw(img)
    cx, cy = S / 2.0, S / 2.0
    u = S * scale / 100.0
    er = 4.2 * u
    for sx, sy in [(-11, -30), (11, 30)]:
        ex, ey = cx + sx * u, cy + sy * u
        d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=(248, 250, 252, 255))

    return img.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    gui = os.path.join(root, "python_gui")

    ico_path = os.path.join(gui, "windows", "runner", "resources", "app_icon.ico")
    base_256 = render_python_icon(256, maskable=False)
    base_256.save(ico_path, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print(f"Đã tạo Windows ICO: {ico_path}")

    android_res = os.path.join(gui, "android", "app", "src", "main", "res")
    for folder, sz in [("mipmap-mdpi", 48), ("mipmap-hdpi", 72), ("mipmap-xhdpi", 96), ("mipmap-xxhdpi", 144), ("mipmap-xxxhdpi", 192)]:
        render_python_icon(sz, maskable=False).save(os.path.join(android_res, folder, "ic_launcher.png"), format="PNG")
    print("Đã tạo bộ Android ic_launcher.png (5 mật độ màn hình)")

    web_dir = os.path.join(gui, "web")
    render_python_icon(64, maskable=False).save(os.path.join(web_dir, "favicon.png"), format="PNG")
    render_python_icon(192, maskable=False).save(os.path.join(web_dir, "icons", "Icon-192.png"), format="PNG")
    render_python_icon(512, maskable=False).save(os.path.join(web_dir, "icons", "Icon-512.png"), format="PNG")
    render_python_icon(192, maskable=True).save(os.path.join(web_dir, "icons", "Icon-maskable-192.png"), format="PNG")
    render_python_icon(512, maskable=True).save(os.path.join(web_dir, "icons", "Icon-maskable-512.png"), format="PNG")
    print("Đã tạo bộ Web favicon & PWA icons!")


if __name__ == "__main__":
    main()
