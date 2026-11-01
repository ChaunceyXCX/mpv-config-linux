#!/usr/bin/env bash
# 把「Linux 改造」重放到当前工作区（幂等，可反复执行）。
#
# 用途：上游 dyphire/mpv-config 更新后，拉取新上游再重放本脚本，
#       即可得到等价于 linux-wayland-niri 分支的 Linux 适配。
#
#   ./linux/apply-linux-patch.sh          # 应用全部改动
#   ./linux/apply-linux-patch.sh --check  # 只检查还差哪些改动，不写文件
#
# 改动清单见 linux/README-linux.md 「一、相对上游的改动」。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

exec python3 - "$CHECK_ONLY" <<'PY'
import os, re, shutil, subprocess, sys

check_only = sys.argv[1] == "1"
stats = {"applied": 0, "skipped": 0, "pending": 0, "warn": 0}

def head(msg):
    print(f"\n== {msg} ==")

def ok(label):
    stats["applied"] += 1
    print(f"  + 已应用: {label}")

def skip(label):
    stats["skipped"] += 1
    print(f"  = 跳过（已应用）: {label}")

def pending(label):
    stats["pending"] += 1
    print(f"  → 待应用: {label}")

def warn(label):
    stats["warn"] += 1
    print(f"  !! {label}")

def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)

def exact(path, old, new, label):
    """整段精确替换。new 已存在 → 跳过。"""
    if not os.path.exists(path):
        warn(f"缺文件 {path}（{label}）")
        return
    s = read(path)
    if new in s:
        return skip(label)
    if old not in s:
        return warn(f"未匹配: {label} —— 上游可能改过这一行，请人工确认")
    if check_only:
        return pending(label)
    write(path, s.replace(old, new, 1))
    ok(label)

def lines(path, old_line, new_line, label, comment_prefix="# "):
    """按行替换（保留行内注释）。old_line 为整行前缀匹配。"""
    if not os.path.exists(path):
        return warn(f"缺文件 {path}（{label}）")
    src = read(path).split("\n")
    out, changed, hit_new = [], 0, False
    for l in src:
        if l.strip() == new_line.strip() or l.startswith(new_line[:40]):
            hit_new = True
        if l.startswith(old_line):
            out.append(new_line); changed += 1
        else:
            out.append(l)
    if changed == 0:
        if hit_new:
            return skip(label)
        return warn(f"未匹配: {label}")
    if check_only:
        return pending(label)
    write(path, "\n".join(out))
    ok(label)

def delete_lines(path, prefixes, label):
    if not os.path.exists(path):
        return warn(f"缺文件 {path}（{label}）")
    src = read(path).split("\n")
    kept = [l for l in src if not any(l.startswith(p) for p in prefixes)]
    if len(kept) == len(src):
        return skip(label)
    if check_only:
        return pending(label)
    write(path, "\n".join(kept))
    ok(label)

def move_into_archive(src, label):
    if not os.path.exists(src):
        return skip(label)
    dst = os.path.join("archive", "windows", os.path.basename(src))
    if check_only:
        return pending(label)
    os.makedirs(os.path.join("archive", "windows"), exist_ok=True)
    if shutil.which("git") and os.path.isdir(".git"):
        r = subprocess.run(["git", "mv", src, dst], capture_output=True, text=True)
        if r.returncode != 0:
            shutil.move(src, dst)
    else:
        shutil.move(src, dst)
    ok(label)

# ── 1. mpv.conf ────────────────────────────────────────────────────────
head("mpv.conf")

HEADER = """##┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
##┃ Linux 分支（linux-wayland-niri）—— 基于上游 dyphire/mpv-config 改造      ┃
##┃ 适配目标：Linux + Wayland（niri/DMS 桌面）+ NVIDIA 显卡                  ┃
##┃ 主要改动（详见 linux/README-linux.md）：                                ┃
##┃   · gpu-api: d3d11 → vulkan        · ao: wasapi → pipewire,pulse,alsa   ┃
##┃   · hwdec 说明改为 nvdec / vaapi   · ipc: 命名管道 → /tmp/mpv-socket    ┃
##┃   · glsl-shaders 列表分隔符 ';' → ':'（mpv 的路径列表按平台分隔）        ┃
##┃   · 禁用 Windows 专属项：no-title-bar / window-corners / snap-window /  ┃
##┃     load-context-menu                                                   ┃
##┃   · 新增 linux/ 安装脚本、uosc 动态配色（matugen）、niri 窗口规则         ┃
##┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

"""

if os.path.exists("mpv.conf"):
    s = read("mpv.conf")
    if "Linux 分支（linux-wayland-niri）" in s:
        skip("文件头 Linux 分支说明")
    elif check_only:
        pending("文件头 Linux 分支说明")
    else:
        write("mpv.conf", HEADER + s)
        ok("文件头 Linux 分支说明")

exact("mpv.conf",
    "gpu-api=d3d11                         # <opengl/vulkan/d3d11> [SVP 补帧时推荐设置为 d3d11] 选择图形绘制接口",
    "gpu-api=vulkan                        # <opengl/vulkan> [Linux] NVIDIA 闭源驱动 + gpu-next 推荐 vulkan；Intel/AMD 也可用 vulkan，遇到兼容问题改 opengl",
    "gpu-api d3d11 → vulkan")

exact("mpv.conf",
    'hwdec=auto-copy-safe                  # 指定应使用的硬件视频解码 API，软解改为 no，Windows 上的硬解建议使用 d3d11va 或 d3d12va-copy。d3d11va 具有最好的硬件解码支持，提供了 av1 格式的 4k60 帧和 8k 下的原生硬解加速。nvdec 虽然支持 yuv444 硬解，但该格式较为少见而且软解下并无压力',
    '''hwdec=auto-copy-safe                  # 指定应使用的硬件视频解码 API，软解改为 no
                                      # [Linux] NVIDIA: nvdec-copy（copy-back，兼容性最好）/ nvdec（零拷贝，需 gpu-next 互操作）
                                      # [Linux] AMD/Intel: vaapi-copy / vaapi（需要 libva + 对应驱动）
                                      # auto-copy-safe 会自动挑选可用方案；硬解花屏/绿屏时先改 no 排除硬解问题''',
    "hwdec 注释补全 Linux 方案")

exact("mpv.conf",
    "no-title-bar                          # 控制是否使用窗口标题栏播放，默认启用。与 --no-border 不同，--no-title-bar 可以保留 Windows 原生窗口特性",
    "# no-title-bar                        # [Linux 分支已禁用] Windows 专属：Wayland 下有无标题栏由合成器决定（niri 无标题栏），X11 用 --no-border",
    "禁用 no-title-bar")

exact("mpv.conf",
    "# no-title-bar                        # [Linux 分支已禁用] Windows 专属：Wayland 下有无标题栏由合成器决定（niri 无标题栏），X11 用 --no-border",
    """# no-title-bar                        # [Linux 分支已禁用] Windows 专属：Wayland 下有无标题栏由合成器决定（niri 无标题栏），X11 用 --no-border
border=no                             # [Linux] niri 不提供服务端窗口装饰，Wayland 下 mpv 会自绘 CSD（右上角最小化/最大化/关闭）——关掉更干净；等价于上游 no-title-bar 想要的效果""",
    "Wayland 下关闭 CSD 边框（border=no）")

exact("mpv.conf",
    "window-corners=roundsmall             # <default|donotround|round|roundsmall> 控制窗口圆角的首选项。default: 让系统决定是否圆角; donotround: 禁用圆角；round: 启用圆角；roundsmall: 启用半径较小的圆角",
    "# window-corners=roundsmall           # [Linux 分支已禁用] Windows 专属（DWM）。Wayland 下圆角由合成器绘制，niri 用 window-rule 的 geometry-corner-radius",
    "禁用 window-corners")

exact("mpv.conf",
    "snap-window=yes                       # 窗口移动时捕捉窗口到屏幕边缘 (仅限 windows 系统)",
    "# snap-window=yes                     # [Linux 分支已禁用] 仅限 Windows；Wayland 下窗口吸附/平铺由合成器（niri）负责",
    "禁用 snap-window")

exact("mpv.conf",
    "input-ipc-server=\\\\.\\pipe\\mpvsocket   # input-ipc-server=<ipc_path> 开启 Ipc 功能，Linux/MacOS: input-ipc-server=/tmp/mpvsocket",
    "input-ipc-server=/tmp/mpv-socket      # input-ipc-server=<ipc_path> 开启 Ipc 功能。Windows 为 \\\\.\\pipe\\mpvsocket，Linux/macOS 为 unix socket（macast 投屏时用它自己的 /tmp/macast_mpvsocketNNNN，两者互不影响）",
    "IPC 命名管道 → /tmp/mpv-socket")

exact("mpv.conf",
    """ao=wasapi                             # --ao=<driver1,driver2,...[,]> 指定要使用的音频输出驱动程序的优先级列表，如果列表有尾随的 ','，mpv 将回退到未包含在列表中的驱动程序
                                      ## windows 推荐 wasapi；linux 推荐 alsa，需配合参数--audio-channels=auto；macos 推荐 coreaudio 或 coreaudio_exclusive""",
    """ao=pipewire,pulse,alsa                # --ao=<driver1,driver2,...[,]> 音频输出驱动优先级列表，如果列表有尾随的 ','，mpv 将回退到未包含在列表中的驱动程序
                                      ## [Linux] 现代桌面（niri/DMS/Hyprland）统一走 PipeWire：pipewire → 无 PipeWire 时回退 pulse → 再回退 alsa
                                      ## 需要独占/直通多声道时可用 ao=alsa 并配合 --audio-channels=auto""",
    "ao wasapi → pipewire,pulse,alsa")

exact("mpv.conf",
    "load-context-menu=yes                                                           # 启用 mpv 内置的菜单绘制脚本 [context_menu.lua]，Windows 平台默认 no",
    "# load-context-menu=yes                                                         # [Linux 分支已禁用] Windows 专属（右键上下文菜单）；Linux 用 osc-style/menu.conf 与 uosc 菜单",
    "禁用 load-context-menu")

exact("mpv.conf",
    'profile-desc=8k av1 下使用 d3d11va 硬解来解决掉帧问题，该方案仅限 --gpu-api=d3d11 下可用',
    'profile-desc=8k 内容降级策略：Linux 分支用 nvdec/vaapi 硬解 + 关掉插值与着色器来解决掉帧',
    "[8k-fix] 描述改为 Linux 方案")

exact("mpv.conf",
    " profile-cond=window_maximized and vid and not get(\"current-tracks/video/albumart\")",
    " profile-cond=window_maximized and vid and not get(\"current-tracks/video/albumart\")   # [Linux] Wayland 下 window-maximized 只有部分合成器会上报，niri 下可能永远不成立",
    "[maximized] 加 Wayland 说明")

exact("mpv.conf",
    " profile-cond=window_minimized and vid and not get(\"current-tracks/video/albumart\")",
    " profile-cond=window_minimized and vid and not get(\"current-tracks/video/albumart\")   # [Linux] window-minimized 为 Windows 专属属性，Wayland/X11 下不会触发",
    "[minimized] 加 Wayland 说明")

# glsl-shaders：路径列表分隔符（Windows ';' → Unix ':'）
ANCHOR = "## 此处的 --glsl-shaders=<value> 用于指定每次随 MPV 共同启动的着色器（支持多项）"
NOTE = "## [Linux 注意] 路径列表的分隔符随平台不同：Windows 用 \";\"，Linux/macOS 用 \":\"（本分支已全部改为 \":\"）"
if os.path.exists("mpv.conf"):
    s = read("mpv.conf")
    if NOTE in s:
        skip("glsl-shaders 分隔符提示注释")
    elif check_only:
        if any(re.match(r'^\s*glsl-shaders="', l) and ';' in l for l in s.split("\n")):
            pending("glsl-shaders ';' → ':'")
    else:
        out, changed = [], 0
        for l in s.split("\n"):
            if re.match(r'^\s*glsl-shaders="', l) and ";~~/" in l:
                l = l.replace(";~~/", ":~~/"); changed += 1
            out.append(l)
        s = "\n".join(out)
        if ANCHOR in s:
            s = s.replace(ANCHOR, ANCHOR + "\n" + NOTE, 1)
        write("mpv.conf", s)
        if changed:
            ok(f"glsl-shaders 分隔符 ';' → ':'（{changed} 处）")
        else:
            skip("glsl-shaders 分隔符 ';' → ':'")

# ── 2. input.conf（Windows 专属解码器/flip 菜单项）───────────────────────
head("input.conf")
exact("input.conf",
    '#                set hwdec "d3d11va"                                                                                    #menu: 视频 > 切换  解码方式 > d3d11va 硬解',
    '#                set hwdec "vaapi"                                                                                      #menu: 视频 > 切换  解码方式 > vaapi 硬解（AMD/Intel）',
    "d3d11va 菜单项 → vaapi")

exact("input.conf",
    '#                set hwdec "d3d12va-copy"                                                                               #menu: 视频 > 切换  解码方式 > d3d12va-copy 硬解',
    '#                set hwdec "vaapi-copy"                                                                                 #menu: 视频 > 切换  解码方式 > vaapi-copy 硬解（AMD/Intel）',
    "d3d12va-copy 菜单项 → vaapi-copy")

delete_lines("input.conf",
    ['#                set hwdec "d3d11va-copy"',
     '#                cycle d3d11-flip;'],
    "删除 Windows 专属菜单项（d3d11va-copy / d3d11-flip）")

# ── 3. script-opts ─────────────────────────────────────────────────────
head("script-opts")
exact("script-opts/uosc.conf",
    "top_bar_controls=yes",
    """# [Linux/niri] Wayland 下没有服务端窗口装饰，mpv 已用 border=no 去掉 CSD；
# uosc 自绘的最小化/最大化/关闭按钮在像素级平铺窗口里只会碍事，故关闭。
# 需要时改回 yes 即可。
top_bar_controls=no""",
    "uosc 关闭自绘窗口按钮（top_bar_controls=no）")

exact("script-opts/history_bookmark.conf",
    "history_dir=/:var%APPDATA%/mpv/files/historybookmarks",
    "history_dir=~~/files/historybookmarks",
    "history_bookmark 书签目录 → ~~/files")

# ── 4. 脚本跨平台修复 ───────────────────────────────────────────────────
head("scripts")
exact("scripts/uosc_danmaku/sites/iqiyi.lua",
    """    local now = os.time()
    for name in pairs(entries) do
        local pid = name:match(TEMP_NAME_PATTERN)""",
    """    local now = os.time()
    -- [Linux/新版 mpv 修复] utils.readdir 现在返回数组（数字键），旧写法
    -- `for name in pairs(entries)` 取到的是数字，name:match() 会抛
    -- "attempt to index local 'name' (a number value)" 并让整个 danmaku 脚本加载失败。
    local names = {}
    for k, v in pairs(entries) do
        names[#names + 1] = type(v) == 'string' and v or tostring(k)
    end
    for _, name in ipairs(names) do
        local pid = name:match(TEMP_NAME_PATTERN)""",
    "uosc_danmaku iqiyi.lua readdir 兼容性")

# ── 4.5 .gitignore（运行期产物）──────────────────────────────────────────
head(".gitignore")
if os.path.exists(".gitignore"):
    gi = read(".gitignore")
    if "file_browser_favourites.txt" in gi:
        skip(".gitignore 追加运行期文件")
    elif check_only:
        pending(".gitignore 追加运行期文件")
    else:
        if not gi.endswith("\n"):
            gi += "\n"
        gi += "\n# 运行期生成（file_browser 收藏等）\nscript-opts/file_browser_favourites.txt\n"
        write(".gitignore", gi)
        ok(".gitignore 追加运行期文件")

# ── 5. Windows 专属资源移入 archive/windows ─────────────────────────────
head("Windows 专属资源归档")
move_into_archive("scripts/display-info.dll", "display-info.dll（Windows DLL 脚本）→ archive/windows")
move_into_archive("script-modules/file-browser-addons/winsort.lua", "file-browser winsort.lua（依赖 shlwapi）→ archive/windows")
move_into_archive("scripts/simple-mpv-webui", "simple-mpv-webui（依赖 LuaSocket）→ archive/windows")

print()
print(f"合计：已应用 {stats['applied']}，已存在 {stats['skipped']}，"
      f"{'待应用' if check_only else '未匹配'} {stats['pending'] if check_only else stats['warn']}")
if stats["warn"]:
    sys.exit(2)
PY
