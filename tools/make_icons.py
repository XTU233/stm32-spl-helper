"""生成 App 图标与启动图。

需求：离线 App，不引入图标生成插件（flutter_launcher_icons 要联网拉包），
所以直接在这里用 Pillow 画出各密度的 PNG。

图标设计：方形圆角底 + 蓝色渐变 + 白色芯片轮廓（方框 + 四边引脚 + 中心方块）。
寓意"芯片 / 嵌入式"，与 App 的功能（查 STM32 标准库）对应。
不用文字，缩到 48px 时文字会糊成一团。

用法：
    python tools/make_icons.py
"""

from __future__ import annotations

import io
import os

from PIL import Image, ImageDraw

# Android mipmap 密度 → 图标边长（px）
# 48dp 的启动图标在各密度下的实际像素
ICON_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# 自适应图标的前景层（108dp 画布，中间 72dp 是安全区）
ADAPTIVE_SIZES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

# 配色：与 App 主题种子色一致（lib/utils/theme.dart 的 seed）
BLUE_TOP = (44, 107, 237)
BLUE_BOTTOM = (23, 62, 158)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    """生成竖直渐变底图。"""
    img = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        img.putpixel(
            (0, y),
            (
                int(top[0] + (bottom[0] - top[0]) * t),
                int(top[1] + (bottom[1] - top[1]) * t),
                int(top[2] + (bottom[2] - top[2]) * t),
            ),
        )
    return img.resize((size, size), Image.NEAREST)


def draw_chip(draw: ImageDraw.ImageDraw, size: int, scale: float = 1.0) -> None:
    """在画布中心画一个芯片轮廓（方框 + 四边引脚 + 中心小方块）。

    scale 用来控制芯片占画布的比例：普通图标占 0.62，
    自适应图标的前景层要更小（占 0.42），因为系统会裁掉外圈。
    """
    cx = cy = size / 2
    body = size * scale          # 芯片本体边长
    half = body / 2
    corner = max(1, int(size * 0.022))
    line_w = max(2, int(size * 0.045))

    # 本体方框
    box = [cx - half, cy - half, cx + half, cy + half]
    draw.rounded_rectangle(box, radius=corner, outline=(255, 255, 255), width=line_w)

    # 中心小方块（代表内核）
    inner = body * 0.30
    ih = inner / 2
    draw.rounded_rectangle(
        [cx - ih, cy - ih, cx + ih, cy + ih],
        radius=max(1, int(corner * 0.6)),
        fill=(255, 255, 255),
    )

    # 四边引脚：每边 3 根
    pin_len = body * 0.17
    pin_w = line_w
    gap = body * 0.26
    for i in (-1, 0, 1):
        offset = i * gap
        # 上
        draw.rectangle(
            [cx + offset - pin_w / 2, cy - half - pin_len,
             cx + offset + pin_w / 2, cy - half + line_w / 2],
            fill=(255, 255, 255),
        )
        # 下
        draw.rectangle(
            [cx + offset - pin_w / 2, cy + half - line_w / 2,
             cx + offset + pin_w / 2, cy + half + pin_len],
            fill=(255, 255, 255),
        )
        # 左
        draw.rectangle(
            [cx - half - pin_len, cy + offset - pin_w / 2,
             cx - half + line_w / 2, cy + offset + pin_w / 2],
            fill=(255, 255, 255),
        )
        # 右
        draw.rectangle(
            [cx + half - line_w / 2, cy + offset - pin_w / 2,
             cx + half + pin_len, cy + offset + pin_w / 2],
            fill=(255, 255, 255),
        )


def make_icon(size: int, rounded: bool = True) -> Image.Image:
    """生成一个图标（带圆角与渐变底）。"""
    base = vertical_gradient(size, BLUE_TOP, BLUE_BOTTOM).convert("RGBA")

    # 圆角遮罩
    if rounded:
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, size - 1, size - 1],
            radius=int(size * 0.22),
            fill=255,
        )
        base.putalpha(mask)

    draw = ImageDraw.Draw(base)
    draw_chip(draw, size, scale=0.54)
    return base


def make_adaptive_foreground(size: int) -> Image.Image:
    """自适应图标的前景层（透明底 + 偏小的芯片图案）。"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw_chip(draw, size, scale=0.38)
    return img


def make_splash(size: int = 512) -> Image.Image:
    """启动图：透明底上一个白蓝配色的芯片（由 launch_background 居中显示）。"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # 启动图用主题蓝而不是白色，这样浅色/深色背景上都看得见
    cx = cy = size / 2
    body = size * 0.46
    half = body / 2
    line_w = max(3, int(size * 0.030))
    box = [cx - half, cy - half, cx + half, cy + half]
    draw.rounded_rectangle(
        box, radius=int(size * 0.035), outline=BLUE_TOP, width=line_w
    )
    inner = body * 0.30
    ih = inner / 2
    draw.rounded_rectangle(
        [cx - ih, cy - ih, cx + ih, cy + ih],
        radius=int(size * 0.02),
        fill=BLUE_TOP,
    )
    pin_len = body * 0.17
    gap = body * 0.26
    for i in (-1, 0, 1):
        offset = i * gap
        draw.rectangle(
            [cx + offset - line_w / 2, cy - half - pin_len,
             cx + offset + line_w / 2, cy - half + line_w / 2],
            fill=BLUE_TOP,
        )
        draw.rectangle(
            [cx + offset - line_w / 2, cy + half - line_w / 2,
             cx + offset + line_w / 2, cy + half + pin_len],
            fill=BLUE_TOP,
        )
        draw.rectangle(
            [cx - half - pin_len, cy + offset - line_w / 2,
             cx - half + line_w / 2, cy + offset + line_w / 2],
            fill=BLUE_TOP,
        )
        draw.rectangle(
            [cx + half - line_w / 2, cy + offset - line_w / 2,
             cx + half + pin_len, cy + offset + line_w / 2],
            fill=BLUE_TOP,
        )
    return img


def main() -> int:
    written = []

    # 传统启动图标（各密度）
    for density, size in ICON_SIZES.items():
        d = os.path.join(RES, f"mipmap-{density}")
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, "ic_launcher.png")
        make_icon(size).save(p, "PNG", optimize=True)
        written.append(p)

    # 自适应图标：前景（透明）+ 背景（纯渐变，无圆角）
    for density, size in ADAPTIVE_SIZES.items():
        d = os.path.join(RES, f"mipmap-{density}")
        os.makedirs(d, exist_ok=True)

        pf = os.path.join(d, "ic_launcher_foreground.png")
        make_adaptive_foreground(size).save(pf, "PNG", optimize=True)
        written.append(pf)

        pb = os.path.join(d, "ic_launcher_background.png")
        vertical_gradient(size, BLUE_TOP, BLUE_BOTTOM).save(
            pb, "PNG", optimize=True
        )
        written.append(pb)

    # 启动图（放在 drawable-nodpi，由 launch_background.xml 引用）
    d = os.path.join(RES, "drawable-nodpi")
    os.makedirs(d, exist_ok=True)
    ps = os.path.join(d, "splash_logo.png")
    make_splash().save(ps, "PNG", optimize=True)
    written.append(ps)

    for p in written:
        rel = os.path.relpath(p, ROOT)
        print(f"  {rel}  {os.path.getsize(p)} B")
    print(f"\n[make_icons] 共写入 {len(written)} 个文件")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
