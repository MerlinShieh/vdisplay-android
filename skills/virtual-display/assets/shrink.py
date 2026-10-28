#!/usr/bin/env python3
"""把截图压成适合塞进上下文的缩略图。

用法: python3 shrink.py <源图> [输出路径] [最大宽度] [JPEG 质量]
默认: 输出到 /var/minis/attachments/<原名>.jpg，最大宽度 360，质量 55
"""
import sys
import os
from PIL import Image

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else "/var/minis/attachments/" + os.path.splitext(os.path.basename(src))[0] + ".jpg"
max_w = int(sys.argv[3]) if len(sys.argv) > 3 else 360
quality = int(sys.argv[4]) if len(sys.argv) > 4 else 55

os.makedirs(os.path.dirname(dst), exist_ok=True)
im = Image.open(src).convert("RGB")
w, h = im.size
if w > max_w:
    im = im.resize((max_w, int(h * max_w / w)), Image.LANCZOS)
im.save(dst, "JPEG", quality=quality, optimize=True)

before = os.path.getsize(src)
after = os.path.getsize(dst)
print(f"{dst} {im.size[0]}x{im.size[1]} {before//1024}KB -> {after//1024}KB")
