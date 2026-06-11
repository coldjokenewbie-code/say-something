"""簡化車床 3D 模型 — 以 CadQuery 建模並匯出 STEP 與預覽圖。單位:mm"""
import cadquery as cq

parts = []  # (name, workplane, rgb color)

def add(name, wp, color):
    parts.append((name, wp, color))

GRAY = (0.55, 0.58, 0.62)
DARKGRAY = (0.30, 0.32, 0.36)
GREEN = (0.16, 0.42, 0.38)   # 機身常見的墨綠色
STEEL = (0.75, 0.77, 0.80)
RED = (0.65, 0.15, 0.15)
BLACK = (0.12, 0.12, 0.14)

# ---------- 尺寸基準 ----------
BED_L, BED_W, BED_H = 1400, 260, 180     # 床身
BED_TOP = 750                            # 床身頂面高度
SPINDLE_Z = BED_TOP + 150                # 主軸中心高

# ---------- 床腳 ----------
for i, x in enumerate([120, BED_L - 120]):
    leg = (cq.Workplane("XY")
           .box(220, 300, BED_TOP - BED_H, centered=(True, True, False))
           .translate((x, 0, 0)))
    add(f"leg_{i}", leg, GREEN)

# 接屑盤
tray = (cq.Workplane("XY")
        .box(BED_L + 100, 420, 25, centered=(True, True, False))
        .translate((BED_L / 2, 0, 40)))
add("chip_tray", tray, DARKGRAY)

# ---------- 床身與導軌 ----------
bed = (cq.Workplane("XY")
       .box(BED_L, BED_W, BED_H, centered=(True, True, False))
       .translate((BED_L / 2, 0, BED_TOP - BED_H)))
add("bed", bed, GREEN)

for i, y in enumerate([-85, 85]):  # 兩條 V 形導軌(以梯形稜柱近似)
    way = (cq.Workplane("YZ")
           .polyline([(y - 35, BED_TOP), (y + 35, BED_TOP),
                      (y + 20, BED_TOP + 30), (y - 20, BED_TOP + 30)])
           .close().extrude(BED_L))
    add(f"way_{i}", way, STEEL)

WAY_TOP = BED_TOP + 30

# ---------- 主軸箱(左) ----------
HEAD_L = 360
head = (cq.Workplane("XY")
        .box(HEAD_L, 320, SPINDLE_Z + 130 - WAY_TOP, centered=(True, True, False))
        .translate((HEAD_L / 2, 0, WAY_TOP))
        .edges("|Z").fillet(15))
add("headstock", head, GREEN)

# 主軸 + 三爪卡盤
spindle = (cq.Workplane("YZ")
           .workplane(offset=HEAD_L)
           .circle(45).extrude(50)
           .translate((0, 0, SPINDLE_Z)))
add("spindle", spindle, STEEL)

chuck = (cq.Workplane("YZ")
         .workplane(offset=HEAD_L + 50)
         .circle(95).extrude(90)
         .edges().chamfer(6)
         .translate((0, 0, SPINDLE_Z)))
add("chuck_body", chuck, DARKGRAY)

for i in range(3):  # 三個卡爪
    jaw = (cq.Workplane("XY")
           .box(60, 30, 35, centered=(True, True, False))
           .translate((0, 55, 0))
           .rotate((0, 0, 0), (0, 0, 1), i * 120)
           .rotate((0, 0, 0), (0, 1, 0), 90)
           .translate((HEAD_L + 140, 0, SPINDLE_Z)))
    add(f"jaw_{i}", jaw, STEEL)

# 工件(夾在卡盤上的圓棒)
stock = (cq.Workplane("YZ")
         .workplane(offset=HEAD_L + 90)
         .circle(30).extrude(330)
         .translate((0, 0, SPINDLE_Z)))
add("workpiece", stock, (0.80, 0.66, 0.35))

# 變速箱手柄(從主軸箱前面伸出, 前面 = -Y; "XZ" 平面法向為 -Y, 故 offset=160 → y=-160)
for i, zx in enumerate([(120, SPINDLE_Z + 60), (240, SPINDLE_Z + 60)]):
    lever = (cq.Workplane("XZ")
             .workplane(offset=160)
             .circle(8).extrude(40)
             .translate((zx[0], 0, zx[1])))
    knob = (cq.Workplane("XY")
            .sphere(16)
            .translate((zx[0], -212, zx[1])))
    add(f"lever_{i}", lever, BLACK)
    add(f"knob_{i}", knob, RED)

# ---------- 溜板(刀架)組 ----------
CAR_X = 720  # 溜板位置
saddle = (cq.Workplane("XY")
          .box(260, 340, 45, centered=(True, True, False))
          .translate((CAR_X, 0, WAY_TOP)))
add("saddle", saddle, GREEN)

cross_slide = (cq.Workplane("XY")
               .box(190, 220, 40, centered=(True, True, False))
               .translate((CAR_X, -20, WAY_TOP + 45)))
add("cross_slide", cross_slide, GRAY)

compound = (cq.Workplane("XY")
            .box(130, 130, 38, centered=(True, True, False))
            .rotate((0, 0, 0), (0, 0, 1), 20)
            .translate((CAR_X, -30, WAY_TOP + 85)))
add("compound", compound, GRAY)

toolpost = (cq.Workplane("XY")
            .circle(38).extrude(70)
            .translate((CAR_X, -30, WAY_TOP + 123)))
add("toolpost", toolpost, DARKGRAY)

toolbit = (cq.Workplane("XY")
           .box(100, 16, 16, centered=(False, True, False))
           .translate((CAR_X - 95, -30, SPINDLE_Z - 8)))
add("toolbit", toolbit, STEEL)

# 床鞍前掛箱(apron)+ 手輪
apron = (cq.Workplane("XY")
         .box(240, 60, 160, centered=(True, True, False))
         .translate((CAR_X, -160, BED_TOP - 160)))
add("apron", apron, GREEN)

def handwheel(x, y, z, axis="Y", dia=110):
    """簡化手輪:圓盤+把手。axis=Y 時 y 為圓盤靠機身那面的位置, 向 -Y(前方)伸出"""
    if axis == "Y":
        wheel = (cq.Workplane("XZ").workplane(offset=-y)
                 .circle(dia / 2).extrude(18)
                 .faces().chamfer(3)
                 .translate((x, 0, z)))
        handle = (cq.Workplane("XZ").workplane(offset=-y + 18)
                  .center(dia / 2 - 18, 0)
                  .circle(7).extrude(35)
                  .translate((x, 0, z)))
    else:  # X 軸向(尾座手輪)
        wheel = (cq.Workplane("YZ").workplane(offset=x)
                 .circle(dia / 2).extrude(18)
                 .faces().chamfer(3)
                 .translate((0, y, z)))
        handle = (cq.Workplane("YZ").workplane(offset=x + 18)
                  .center(dia / 2 - 18, 0)
                  .circle(7).extrude(35)
                  .translate((0, y, z)))
    return wheel, handle

w, h = handwheel(CAR_X - 60, -190, BED_TOP - 80)           # 縱向進給手輪(掛箱前)
add("apron_wheel", w, BLACK); add("apron_handle", h, STEEL)
w, h = handwheel(CAR_X, -170, WAY_TOP + 65, dia=80)        # 橫向進給手輪(床鞍前)
add("cross_wheel", w, BLACK); add("cross_handle", h, STEEL)

# ---------- 尾座(右) ----------
TS_X = 1180
ts_base = (cq.Workplane("XY")
           .box(200, 200, 50, centered=(True, True, False))
           .translate((TS_X, 0, WAY_TOP)))
add("tailstock_base", ts_base, GREEN)

ts_body = (cq.Workplane("XY")
           .box(180, 170, SPINDLE_Z + 60 - (WAY_TOP + 50), centered=(True, True, False))
           .translate((TS_X, 0, WAY_TOP + 50))
           .edges("|X").fillet(10))
add("tailstock_body", ts_body, GREEN)

quill = (cq.Workplane("YZ")
         .workplane(offset=TS_X - 170)
         .circle(28).extrude(80)
         .translate((0, 0, SPINDLE_Z)))
add("quill", quill, STEEL)

center = (cq.Workplane("YZ")  # 頂針(圓錐)
          .workplane(offset=TS_X - 170)
          .circle(20).workplane(offset=-55).circle(2)
          .loft()
          .translate((0, 0, SPINDLE_Z)))
add("dead_center", center, STEEL)

w, h = handwheel(TS_X + 90, 0, SPINDLE_Z, axis="X")        # 尾座手輪
add("ts_wheel", w, BLACK); add("ts_handle", h, STEEL)

# ---------- 導螺桿與光桿 ----------
lead = (cq.Workplane("YZ")
        .workplane(offset=HEAD_L)
        .circle(13).extrude(BED_L - HEAD_L)
        .translate((0, -150, BED_TOP - 60)))
add("leadscrew", lead, STEEL)

feed = (cq.Workplane("YZ")
        .workplane(offset=HEAD_L)
        .circle(9).extrude(BED_L - HEAD_L)
        .translate((0, -150, BED_TOP - 100)))
add("feedrod", feed, STEEL)

# ---------- 匯出 STEP(帶顏色的組件) ----------
asm = cq.Assembly(name="lathe")
for name, wp, color in parts:
    asm.add(wp, name=name, color=cq.Color(*color))
asm.save("/tmp/lathe/lathe.step")
print("STEP exported:", len(parts), "parts")

# ---------- 算繪預覽圖 ----------
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

def collect_tris():
    out = []
    for name, wp, color in parts:
        for solid in wp.vals():
            verts, tris = solid.tessellate(1.2)
            v = np.array([(p.x, p.y, p.z) for p in verts])
            out.append((v, np.array(tris), color))
    return out

meshes = collect_tris()

all_polys, all_colors = [], []
light = np.array([0.4, -0.7, 0.6]); light /= np.linalg.norm(light)
for v, t, c in meshes:
    polys = v[t]
    n = np.cross(polys[:, 1] - polys[:, 0], polys[:, 2] - polys[:, 0])
    n /= (np.linalg.norm(n, axis=1, keepdims=True) + 1e-9)
    shade = 0.45 + 0.55 * np.clip(n @ light, 0, 1)
    face = np.clip(np.array(c)[None, :] * shade[:, None], 0, 1)
    all_polys.append(polys)
    all_colors.append(face)
all_polys = np.concatenate(all_polys)
all_colors = np.concatenate(all_colors)

def render(elev, azim, fname):
    fig = plt.figure(figsize=(12, 8), dpi=110)
    ax = fig.add_subplot(111, projection="3d")
    # 單一集合讓 matplotlib 對全部三角面做整體深度排序
    pc = Poly3DCollection(all_polys, facecolors=all_colors, edgecolors="none")
    ax.add_collection3d(pc)
    ax.set_xlim(-50, 1450); ax.set_ylim(-750, 750); ax.set_zlim(0, 1250)
    ax.set_box_aspect((1500, 1500, 1250))
    ax.view_init(elev=elev, azim=azim)
    ax.axis("off")
    plt.tight_layout(pad=0)
    plt.savefig(fname, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print("saved", fname)

render(22, -55, "/tmp/lathe/preview_front.png")
render(22, -125, "/tmp/lathe/preview_back.png")
render(8, -90, "/tmp/lathe/preview_side.png")
