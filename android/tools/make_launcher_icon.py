#!/usr/bin/env python3 -I
"""从 iOS 版的应用图标（app/StrumCoach/Assets.xcassets/AppIcon.appiconset/icon-1024.png）生成安卓的自适应图标图层。

输出（都在 android/app/src/main/res/）：
  drawable-nodpi/ic_launcher_foreground.png   前景：把原图的纯渐变底去掉，只留三块图形，缩到安全区里（108dp 画布的中间约 59%）
  drawable-nodpi/ic_launcher_monochrome.png   单色图层（安卓 13 的主题图标用）：只留图里的白色部分
  drawable/ic_launcher_background.xml         背景：和原图一样的竖向橙色渐变（颜色从原图上下两端取）

用法：python3 -I android/tools/make_launcher_icon.py        需要 Pillow
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ANDROID = os.path.dirname(HERE)
REPO = os.path.dirname(ANDROID)
SRC = os.path.join(REPO, "app", "StrumCoach", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")
RES = os.path.join(ANDROID, "app", "src", "main", "res")

CANVAS = 648           # 108dp × 6
CONTENT = 384          # 图形占 64dp：圆形遮罩下四角不被切掉

src = Image.open(SRC).convert("RGB")
w, h = src.size
px = src.load()
bg = [px[2, y] for y in range(h)]            # 左边缘一列就是纯渐变底

fg = Image.new("RGBA", (w, h))
mono = Image.new("RGBA", (w, h))
fp, mp = fg.load(), mono.load()
for y in range(h):
    b = bg[y]
    for x in range(w):
        p = px[x, y]
        if max(abs(p[0] - b[0]), abs(p[1] - b[1]), abs(p[2] - b[2])) <= 3:
            fp[x, y] = (0, 0, 0, 0)
        else:
            fp[x, y] = (p[0], p[1], p[2], 255)
        # 单色：越接近白越不透明（节拍器身、音叉、指法图的横线和圆点）
        whiteness = min(p)
        mp[x, y] = (255, 255, 255, max(0, min(255, (whiteness - 200) * 255 // 55)))

def place(img, path):
    small = img.resize((CONTENT, CONTENT), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(small, ((CANVAS - CONTENT) // 2, (CANVAS - CONTENT) // 2), small)
    canvas.save(path, optimize=True)

os.makedirs(os.path.join(RES, "drawable-nodpi"), exist_ok=True)
place(fg, os.path.join(RES, "drawable-nodpi", "ic_launcher_foreground.png"))
place(mono, os.path.join(RES, "drawable-nodpi", "ic_launcher_monochrome.png"))

top, bottom = "#%02X%02X%02X" % bg[0], "#%02X%02X%02X" % bg[h - 1]
with open(os.path.join(RES, "drawable", "ic_launcher_background.xml"), "w") as f:
    f.write(f'''<?xml version="1.0" encoding="utf-8"?>
<!-- 自动生成（tools/make_launcher_icon.py）：和 iOS 图标同样的竖向橙色渐变 -->
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient android:angle="270" android:startColor="#FF{top[1:]}" android:endColor="#FF{bottom[1:]}" />
</shape>
''')
print("ok", top, bottom)
