#!/usr/bin/env bash
# Linux 分支安装脚本：把本仓库部署为 mpv 的配置目录
#
#   ./install.sh                 # 复制到 ~/.config/mpv（会先备份已存在的配置）
#   ./install.sh --link          # 用符号链接方式部署（改仓库即生效，适合跟进上游）
#   ./install.sh --fonts         # 同时安装仓库自带字体到 ~/.local/share/fonts/mpv-config
#   ./install.sh --with-matugen  # 生成 uosc 动态配色模板到 ~/.config/matugen
#   ./install.sh --dir DIR       # 指定目标配置目录（默认 ~/.config/mpv）
#   ./install.sh --dry-run
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/mpv"
MODE="copy"
INSTALL_FONTS=0
WITH_MATUGEN=0
DRY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --link) MODE=link ;;
        --fonts) INSTALL_FONTS=1 ;;
        --with-matugen) WITH_MATUGEN=1 ;;
        --dir) TARGET="$2"; shift ;;
        --dry-run) DRY=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
    shift
done

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }

# ── 依赖检查 ────────────────────────────────────────────────────
log "检查依赖"
need_cmd() { command -v "$1" >/dev/null 2>&1; }
if need_cmd mpv; then
    log "mpv: $(mpv --version | head -1)"
else
    warn "未找到 mpv，请先安装（Arch: sudo pacman -S mpv）"
fi
for c in ffmpeg yt-dlp curl; do
    need_cmd "$c" && log "$c: 已安装" || warn "$c: 未安装（相关脚本功能会缺失；yt-dlp 用于在线视频）"
done
# 注意：不要用 grep -q 配合 pipefail —— grep 提前退出会让 fc-list 收到 SIGPIPE(141)，
# 在 `set -o pipefail` 下会被误判成「没装字体」。
if fc-list : family 2>/dev/null | grep -i "Noto Sans CJK" >/dev/null; then
    log "中文字体 noto-fonts-cjk: 已安装"
else
    warn "缺少中文字体（Arch: pacman -S noto-fonts-cjk），否则字幕/OSD 中文会变方块"
fi

# ── 部署 ────────────────────────────────────────────────────────
EXCLUDES=(--exclude=.git --exclude=archive --exclude=linux --exclude=README.md --exclude=LICENSE.MD)

if [ "$DRY" -eq 1 ]; then
    log "dry-run：将把 $REPO_DIR 部署到 $TARGET（模式：$MODE）"
    exit 0
fi

mkdir -p "$(dirname "$TARGET")"
if [ -e "$TARGET" ] && [ "${TARGET_MERGED:-0}" != "1" ]; then
    BAK="${TARGET}.bak-$(date +%Y%m%d-%H%M%S)"
    log "已存在 $TARGET，备份到 $BAK"
    mv "$TARGET" "$BAK"
fi

if [ "$MODE" = "link" ]; then
    log "符号链接部署 → $TARGET"
    mkdir -p "$TARGET"
    for item in mpv.conf input.conf inputevent_key.conf menu.conf manager.json \
                script-opts script-modules scripts shaders fonts icc osc-style; do
        [ -e "$REPO_DIR/$item" ] && ln -sfn "$REPO_DIR/$item" "$TARGET/$item"
    done
else
    log "复制部署 → $TARGET（约 90MB，含着色器/字体/脚本）"
    mkdir -p "$TARGET"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a "${EXCLUDES[@]}" "$REPO_DIR"/ "$TARGET"/
    else
        tar -C "$REPO_DIR" -cf - "${EXCLUDES[@]}" . | tar -C "$TARGET" -xf -
    fi
fi

# mpv 运行时需要的目录（log-file / watch-later / screenshot 都指向 ~~/files、~~/cache）
mkdir -p "$TARGET/files/screen" "$TARGET/cache/watch_later" "$TARGET/files/historybookmarks"

# ── 可选：字体 ──────────────────────────────────────────────────
if [ "$INSTALL_FONTS" -eq 1 ] && [ -d "$REPO_DIR/fonts" ]; then
    FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/mpv-config"
    log "安装仓库字体 → $FONT_DIR"
    mkdir -p "$FONT_DIR"
    cp -f "$REPO_DIR"/fonts/*.ttf "$REPO_DIR"/fonts/*.otf "$FONT_DIR"/ 2>/dev/null || true
    fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
    log "字体已刷新缓存"
fi

# ── 可选：uosc 动态配色（matugen） ───────────────────────────────
if [ "$WITH_MATUGEN" -eq 1 ]; then
    MG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/matugen"
    log "安装 uosc 动态配色模板 → $MG_DIR"
    mkdir -p "$MG_DIR/templates"
    cp -f "$REPO_DIR/linux/templates/uosc.conf" "$MG_DIR/templates/uosc.conf"
    if ! grep -q 'templates.uosc' "$MG_DIR/config.toml" 2>/dev/null; then
        cat >> "$MG_DIR/config.toml" <<'EOF'

# mpv / uosc 界面配色（由 wallpaper 动态生成）
[templates.uosc]
input_path = '~/.config/matugen/templates/uosc.conf'
output_path = '~/.config/mpv/script-opts/uosc.conf'
EOF
        log "已向 matugen config.toml 追加 uosc 模板"
    else
        log "matugen 中已存在 uosc 模板，跳过"
    fi
fi

log "完成。启动：mpv <文件>"
log "投屏（手机 → 本机）请见 linux/README-linux.md 的 “DLNA 投屏” 一节"
