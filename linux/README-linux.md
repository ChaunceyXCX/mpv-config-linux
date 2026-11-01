# mpv-config · Linux 分支（linux-wayland-niri）

基于上游 [dyphire/mpv-config](https://github.com/dyphire/mpv-config)（Windows 向配置）改造的 **Linux + Wayland** 版本。
适配目标环境：**Arch Linux + niri + DMS(DankMaterialShell) + PipeWire + NVIDIA 显卡**，同时尽量不破坏 AMD/Intel 与 X11 的可用性。

---

## 一、相对上游的改动

### 1. `mpv.conf`

| 选项 | 上游（Windows） | 本分支（Linux） |
| --- | --- | --- |
| `gpu-api` | `d3d11` | `vulkan`（NVIDIA 闭源驱动 + `gpu-next` 最佳；兼容问题可改 `opengl`） |
| `ao` | `wasapi` | `pipewire,pulse,alsa` |
| `hwdec` | `auto-copy-safe`（注解只讲 d3d11va） | 保持 `auto-copy-safe`，注解补全 Linux 方案：**NVIDIA → `nvdec-copy`/`nvdec`，AMD/Intel → `vaapi-copy`/`vaapi`** |
| `input-ipc-server` | `\\.\pipe\mpvsocket` | `/tmp/mpv-socket` |
| `no-title-bar` | 启用 | **禁用**（Windows 专属；Wayland 无标题栏由合成器决定） |
| `window-corners=roundsmall` | 启用 | **禁用**（Windows DWM 专属；Wayland 圆角由合成器画） |
| `snap-window=yes` | 启用 | **禁用**（仅 Windows；niri 自管平铺/吸附） |
| `load-context-menu=yes` | 启用 | **禁用**（Windows 专属右键菜单） |
| `[maximized]` / `[minimized]` | 依赖 `window-maximized`/`window-minimized` | 保留但对 Wayland 可行性加了说明（niri 下可能不生效） |
| 文件头 | — | 新增「Linux 分支改动一览」注释块 |

### 2. `script-opts/`

- `history_bookmark.conf`：`/:var%APPDATA%/mpv/files/historybookmarks` → `~~/files/historybookmarks`
- 其余脚本（`uosc`、`uosc_danmaku`、`file_browser`、`thumbfast`、`autosubsync`、`mpv_torrserver` 等）本身已跨平台，`script-opts` 里的路径均为 `~~/` 相对路径，无需改动
- `chapter-make-read` / `history-bookmark` / `delete-current-file` / `mpv-animated` / `mpv-cropscreen` / `open_dialog` 等脚本内部都带 `if platform == "windows"` 分支，Linux 下走各自的 `python/sh` 实现，无需修改

### 3. 新增 `linux/`

| 文件 | 作用 |
| --- | --- |
| `install.sh` | 一键部署到 `~/.config/mpv`（复制或符号链接），可选装字体、可选装 uosc 动态配色模板 |
| `templates/uosc.conf` | uosc 配色模板（matugen 占位符），让播放器 UI 跟着壁纸动态换色 |
| `niri-window-rule.kdl` | niri 窗口规则片段（投屏/全屏、圆角、浮动） |
| `README-linux.md` | 本文档 |

---

## 二、安装

```bash
git clone <本仓库> ~/Projects/mpv-config-linux
cd ~/Projects/mpv-config-linux
git checkout linux-wayland-niri
./linux/install.sh --fonts          # 复制到 ~/.config/mpv，并安装自带字体
# 或（跟随仓库改动，便于同步上游）
./linux/install.sh --link
```

依赖（Arch）：

```bash
# 核心
sudo pacman -S mpv ffmpeg yt-dlp noto-fonts-cjk
# 可选：脚本增强
sudo pacman -S jq curl wget python          # 部分脚本用到
```

未部署前可以先"试驾"，不影响现有配置：

```bash
mpv --config-dir=$PWD ~/Videos/某个视频.mkv
```

---

## 三、Wayland (niri) 下的适配

### 1. 窗口规则（`linux/niri-window-rule.kdl`）

```kdl
window-rule {
    match app-id=r#"^mpv$"#
    # 播放视频时想要的圆角（niri 负责画，mpv 的 window-corners 在 Linux 无效）
    geometry-corner-radius 12
    clip-to-geometry true
}

window-rule {
    # 投屏（macast 调起 mpv，标题变化频繁）→ 全屏 + 焦点
    match app-id=r#"^mpv$"#
    open-fullscreen true
    open-focused true
}
```

> `--ontop`（上游默认开启）在 Wayland 下多数合成器不生效；niri 想"置顶"可用
> `window-rule { match app-id="mpv"; open-floating true }`（浮动窗口在平铺层之上）。

### 2. 显示/HDR

- `gpu-api=vulkan` + `vo=gpu-next` 是 niri + NVIDIA 的稳定组合
- Wayland 下 mpv **拿不到系统 ICC**：`[ICC]` 里的 `icc-profile-auto` 实际不生效，
  色彩管理请依赖 `[Target]`/`[HDR]` 的 `target-prim/trc`；
  需要精确校色时手动填 `icc-profile=/path/to/display.icc`
- HDR：niri 26.04 已有 `target-colorspace-hint` 支持，`[HDR-PASS]` 可直接用

---

## 四、DLNA 投屏（手机 → 本机）集成

本分支的配置与 **macast**（DLNA MediaRenderer）配合良好，注意几点：

1. macast 启动 mpv 时会自带一堆命令行参数：
   `--idle=yes --no-terminal --ontop --hwdec=yes --script-opts=osc-...`
   其中 `hwdec=yes` 会**覆盖** `mpv.conf` 里的 `hwdec`；需要指定具体解码器时，
   在 macast 的设置里改用自定义播放器命令，或让 `mpv.conf` 不写 `hwdec`。
2. macast 用自己的 IPC socket（`/tmp/macast_mpvsocketNNNN`），与 `mpv.conf` 里的
   `/tmp/mpv-socket` 互不冲突。
3. `script-opts/uosc.conf` 里的界面配色对投屏同样生效（uosc 会 `set osc no`）。
4. macast 与 minidlna 抢 SSDP `1900/udp`，建议用 systemd user unit 做交接：

```ini
# ~/.config/systemd/user/macast.service
[Unit]
Description=Macast DLNA 投屏接收端
After=niri.service graphical-session.target

[Service]
ExecStartPre=-/usr/bin/systemctl stop minidlna
ExecStart=/usr/bin/macast
ExecStopPost=-/usr/bin/systemctl start minidlna
KillSignal=SIGKILL
SuccessExitStatus=SIGKILL

[Install]
WantedBy=default.target
```

---

## 五、uosc 动态配色（可选）

```bash
./linux/install.sh --with-matugen
# 之后每次换壁纸（matugen 重跑）都会自动生成 ~/.config/mpv/script-opts/uosc.conf
```

模板使用的 token（Material 3）：

```
foreground=on_surface   foreground_text=surface
background=surface_container_high   background_text=on_surface
match=primary  success=tertiary  error=error
window_border=outline_variant  curtain=scrim
```

不想用动态配色就保持仓库自带的 `script-opts/uosc.conf`（固定深色主题）。

---

## 六、已知限制

| 项目 | 说明 |
| --- | --- |
| `[maximized]` / `[minimized]` profile | 依赖 Windows 专属属性，Wayland 下基本不触发 |
| `no-title-bar` / `window-corners` / `snap-window` / `load-context-menu` | Windows 专属，已在分支禁用（注释保留原文便于对照） |
| `fonts/`（46MB） | 上游为 Windows 打包的字体；Linux 建议直接用 `noto-fonts-cjk` 等系统字体，`--fonts` 仅在需要 ASS 特殊字体时装 |
| `archive/` | 上游历史备份，不参与部署 |
| `--hwdec` 与 NVIDIA 私有驱动 | 4:4:4 / AV1 等格式在某些驱动版本会花屏，遇到时退回 `hwdec=no` 或 `nvdec-copy` |

---

## 七、同步上游

```bash
git remote add upstream https://github.com/dyphire/mpv-config.git   # 仅首次
git fetch upstream
git switch -c upstream-sync upstream/master        # 拉取纯上游
bash linux/apply-linux-patch.sh                    # 重放 Linux 改造（见脚本注释）
```

> `linux/apply-linux-patch.sh` 是按本文「一、相对上游的改动」逐条落地的幂等脚本，
> 上游更新后重放即可（不会重复插入已存在的改动）。
