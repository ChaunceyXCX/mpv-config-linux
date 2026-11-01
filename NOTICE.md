# NOTICE / 来源说明

本仓库是 **[dyphire/mpv-config](https://github.com/dyphire/mpv-config)** 的 **Linux 派生版本**
（分支 `linux-wayland-niri`），面向 Linux + Wayland（niri / DankMaterialShell）+ NVIDIA 环境改造。

## 许可与归属

上游仓库未提供覆盖全仓库的单一许可证文件，各文件（脚本、着色器）通常自带许可证声明
（见文件头 / 各子目录内的 LICENSE）。本派生版本：

- **不改变**任何第三方脚本、着色器的许可与版权声明，原样保留
- 改造部分（`mpv.conf` 的 Linux 适配、`input.conf` 的菜单调整、`script-opts` 的路径修正、
  `scripts/uosc_danmaku/sites/iqiyi.lua` 的兼容性修复、`linux/` 目录下的全部内容）
  按上游相同条款提供，作者为 `ChaunceyXCX`
- 若你二次分发，请同时保留上游仓库地址与本说明

上游仓库：https://github.com/dyphire/mpv-config
所属项目 mpv：https://github.com/mpv-player/mpv （GPL/LGPL）

## 与上游的差异

见 `linux/README-linux.md`「一、相对上游的改动」，或直接跑：

```bash
./linux/apply-linux-patch.sh --check
```

## 上游同步

```bash
git remote add upstream https://github.com/dyphire/mpv-config.git
git fetch upstream
git switch -c upstream-sync upstream/master
cp -r linux/ /tmp/linux-keep && git checkout -- . 2>/dev/null
cp -r /tmp/linux-keep linux/
./linux/apply-linux-patch.sh
```
