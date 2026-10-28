#!/usr/bin/env python3
"""把多张截图横向拼成一张长图（会话里就能并排显示）。

用法: python3 montage.py <输出.jpg> <图1> <图2> [图3] [--step N]
      可选 --step 3：每次取 3 张拼一条（默认全部拼一条）
"""
import sys
import os
from PIL import Image, ImageDraw

args = sys.argv[1:]
step = 0
if "--step" in args:
    i = args.index("--step")
    step = int(args[i + 1])
    del args[i:i + 2]

out = args[0]
files = args[1:]
if step and step > 0:
    files = files[:step]

ims = []
for f in files:
    im = Image.open(f).convert("RGB")
    ims.append(im)

GAP = 10
PAD = 10
h = max(i.height for i in ims)
w = sum(i.width for i in ims) + GAP * (len(ims) - 1) + PAD * 2
canvas = Image.new("RGB", (w, h + PAD * 2), (238, 238, 238))
d = ImageDraw.Draw(canvas)

x = PAD
for idx, im in enumerate(ims):
    canvas.paste(im, (x, PAD))
    # 左上角序号
    d.rectangle([x, PAD, x + 26, PAD + 26], fill=(229, 57, 53))
    d.text((x + 9, PAD + 7), str(idx + 1), fill=(255, 255, 255))
    x += im.width + GAP

os.makedirs(os.path.dirname(out), exist_ok=True)
canvas.save(out, "JPEG", quality=55, optimize=True)
print(f"{out} {canvas.size[0]}x{canvas.size[1]} {os.path.getsize(out)//1024}KB  ({len(ims)} 张)")
