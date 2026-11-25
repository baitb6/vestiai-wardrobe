"""生成 App 图标：番茄红底 + 奶油白衣架 + 柠檬绿点缀。

用法：python3 tools/make_icon.py（需要 Pillow）
会覆盖 android/app/src/main/res/mipmap-*/ 与 web/icons/ 下的图标。
"""
from PIL import Image, ImageDraw
import os

RED = (255, 59, 47, 255)
CREAM = (250, 246, 241, 255)
LEMON = (216, 246, 81, 255)
S = 1024


def capsule(draw, p1, p2, width, fill):
    draw.line([p1, p2], fill=fill, width=width)
    r = width / 2
    for p in (p1, p2):
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


def _art(scale=1.0, color=CREAM, accent=LEMON):
    """在透明大画布上画衣架，返回已裁剪居中的图形。"""
    W = 1600
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = W // 2, W // 2
    w = int(46 * scale)

    top_y = cy - int(250 * scale)
    stem_bot = cy - int(74 * scale)

    # 钩：圆心右偏，绕上再卷回右侧（真实衣架钩的走向）
    hr = int(72 * scale)
    hx = cx + hr
    d.arc([hx - hr, top_y - hr, hx + hr, top_y + hr], start=180, end=60,
          fill=color, width=w)

    # 竖杆
    capsule(d, (cx, top_y), (cx, stem_bot), w, color)

    # 三角肩
    dx, dy = int(268 * scale), int(206 * scale)
    left = (cx - dx, cy + dy)
    right = (cx + dx, cy + dy)
    capsule(d, left, (cx, stem_bot), w, color)
    capsule(d, (cx, stem_bot), right, w, color)
    capsule(d, left, (left[0], left[1] + int(36 * scale)), w, color)
    capsule(d, right, (right[0], right[1] + int(36 * scale)), w, color)

    # 底部横杆：贴着两条斜线
    bar_y = cy + int(150 * scale)
    t = (bar_y - stem_bot) / (cy + dy - stem_bot)
    half = int(dx * t)
    capsule(d, (cx - half, bar_y), (cx + half, bar_y), int(26 * scale), accent)

    bbox = img.getbbox()
    return img.crop(bbox)


def draw_hanger(img, scale=1.0, color=CREAM, accent=LEMON, bg=None):
    """把衣架按比例居中画到目标图上。"""
    if bg is not None:
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.225), fill=bg)

    art = _art(scale=1.0, color=color, accent=accent)
    target_w = int(S * 0.60 * scale)
    ratio = target_w / art.width
    art = art.resize((target_w, max(1, int(art.height * ratio))), Image.LANCZOS)
    img.alpha_composite(art, ((S - art.width) // 2, (S - art.height) // 2))


def make_full(size):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_hanger(img, scale=1.0, bg=RED)
    return img.resize((size, size), Image.LANCZOS)


def make_foreground(size):
    """自适应图标前景：内容压到中间 ~62%，给系统裁切留出安全区。"""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_hanger(img, scale=0.62)
    return img.resize((size, size), Image.LANCZOS)


def make_mono(size):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_hanger(img, scale=0.62, color=(255, 255, 255, 255),
                accent=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
res = f"{ROOT}/android/app/src/main/res"

# 传统图标
for density, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                      ("xxhdpi", 144), ("xxxhdpi", 192)]:
    make_full(size).save(f"{res}/mipmap-{density}/ic_launcher.png")

# 自适应图标图层（108dp 基准）
for density, size in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                      ("xxhdpi", 324), ("xxxhdpi", 432)]:
    make_foreground(size).save(f"{res}/mipmap-{density}/ic_launcher_foreground.png")
    make_mono(size).save(f"{res}/mipmap-{density}/ic_launcher_monochrome.png")

# Web 图标
web = f"{ROOT}/web/icons"
os.makedirs(web, exist_ok=True)
make_full(192).save(f"{web}/Icon-192.png")
make_full(512).save(f"{web}/Icon-512.png")
make_foreground(512).save(f"{web}/Icon-maskable-512.png")
make_foreground(192).save(f"{web}/Icon-maskable-192.png")
make_full(32).save(f"{web}/favicon.png")
# 商店/展示用大图
make_full(1024).save(f"{ROOT}/docs/icon-1024.png")
print("icons done")
