#!/usr/bin/env bash
# Ubuntu 26.04 本机编译依赖安装
#
# 背景：官方文档针对 Ubuntu 20.04/22.04，26.04 上多个包已改名/移除。
# 本脚本按 2026-11 实测通过的清单编写，已在 Ubuntu 26.04.1 上验证。
set -euo pipefail

info() { printf '\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "请不要用 root 直接运行，脚本内部会用 sudo"
command -v sudo >/dev/null || die "缺少 sudo"

# ---------- 1. 安装依赖 ----------
info "apt update"
sudo apt update

info "安装编译依赖（26.04 包名已适配）"
# 说明：
#   device-tree-compiler + libfdt1   -> dtc 及其运行库，两者缺一不可
#   qemu-user + qemu-user-binfmt     -> 替代已移除的 qemu-user-static
#   flex/bison/lz4                   -> 内核 kconfig 与压缩需要
#   python-is-python3                -> SDK 检查 python 命令存在
#   lib{gmp,mpc,elf}-dev uuid-dev    -> 内核头文件依赖
sudo apt install -y \
  git ssh make gcc g++ libssl-dev \
  device-tree-compiler libfdt1 \
  qemu-user qemu-user-binfmt \
  flex bison bc lz4 m4 expect \
  patchelf chrpath gawk texinfo diffstat \
  live-build fakeroot cmake gcc-multilib g++-multilib \
  unzip libncurses-dev \
  python-is-python3 python3 python3-pip python3-pyelftools dpkg-dev \
  rsync cpio debootstrap u-boot-tools 7zip locales \
  libgmp-dev libmpc-dev libelf-dev uuid-dev \
  vim less file tree

# ---------- 2. qemu-static 软链 ----------
# 26.04 的 qemu-user 只提供 /usr/bin/qemu-aarch64（static-pie），
# 但 SDK 的 mk-base-ubuntu.sh / mk-ubuntu-rootfs.sh 硬编码了 -static 后缀。
if [ ! -e /usr/bin/qemu-aarch64-static ]; then
  info "补 qemu-aarch64-static 软链（SDK 脚本硬编码此路径）"
  sudo ln -sf /usr/bin/qemu-aarch64 /usr/bin/qemu-aarch64-static
fi

# ---------- 3. python2 shim ----------
# check-loader.sh 无条件要求 python2，但 rk3568 实际不会调用
# （只有 SPL_OF_PLATDATA + dtoc 才会用，rk3568_defconfig 未启用）。
if ! command -v python2 >/dev/null 2>&1; then
  info "创建 python2 -> python3 转发 shim"
  mkdir -p "$HOME/bin"
  cat > "$HOME/bin/python2" <<'SHIM'
#!/bin/sh
# python2 兼容 shim：LubanCat SDK 的 u-boot 脚本硬性检查 python2，
# 但 rk3568 配置下不会真正调用（SPL_OF_PLATDATA 未启用）。转发到 python3。
exec python3 "$@"
SHIM
  chmod +x "$HOME/bin/python2"
fi

if ! echo ":$PATH:" | grep -q ":$HOME/bin:"; then
  info "把 ~/bin 加入 PATH"
  grep -q 'HOME/bin:$PATH' "$HOME/.bashrc" 2>/dev/null || \
    echo 'export PATH=$HOME/bin:$PATH' >> "$HOME/.bashrc"
  export PATH="$HOME/bin:$PATH"
fi

# ---------- 4. binfmt ----------
sudo systemctl restart systemd-binfmt 2>/dev/null || \
  warn "systemd-binfmt 重启失败，稍后手动验证"

# ---------- 5. 验证 ----------
echo
info "环境检查"
chk() {
  local name="$1" cmd="$2" want="$3"
  local out
  out=$(eval "$cmd" 2>&1 | head -1)
  if [ -n "$want" ] && ! echo "$out" | grep -q "$want"; then
    printf '  \033[31m%-22s %s\033[0m\n' "$name" "${out:-<空>}"
    return 1
  fi
  printf '  %-22s %s\n' "$name" "${out:-<空>}"
}

chk "gcc"          "gcc --version"            "gcc"
chk "python3"      "python3 -V"               "Python 3"
chk "python2(shim)" "python2 -V"              "Python 3"
chk "make"         "make --version"           "GNU Make"
chk "dtc"          "dtc --version"            "DTC"
chk "fdtget"       "fdtget --help 2>&1"       "fdtget"
chk "flex"         "flex --version"           "flex"
chk "bison"        "bison --version"          "Bison"
chk "lz4"          "lz4 --version 2>&1"       "lz4"
chk "qemu-aarch64" "qemu-aarch64 --version"   "version"

printf '  %-22s %s\n' "qemu-static 软链" \
  "$([ -e /usr/bin/qemu-aarch64-static ] && echo OK || echo 缺失)"
printf '  %-22s %s\n' "binfmt aarch64" \
  "$(ls /proc/sys/fs/binfmt_misc/ 2>/dev/null | grep -c qemu-aarch64) 条注册"

# GCC 15+ 默认 C23，会让 menuconfig 的 ncurses 检测误报
GCC_MAJOR=$(gcc -dumpversion 2>/dev/null | cut -d. -f1)
if [ "${GCC_MAJOR:-0}" -ge 15 ] 2>/dev/null; then
  printf '  %-22s %s\n' "ncurses 检测" \
    "GCC ${GCC_MAJOR}，menuconfig 需加 HOST_EXTRACFLAGS=-Wno-implicit-int（见 README 3.3）"
else
  printf '  %-22s %s\n' "ncurses 检测" "GCC ${GCC_MAJOR:-?}，无 C23 问题"
fi

if ! ls /proc/sys/fs/binfmt_misc/ 2>/dev/null | grep -q 'qemu-aarch64'; then
  warn "binfmt 未注册，尝试：sudo modprobe binfmt_misc && sudo systemctl restart systemd-binfmt"
fi

echo
info "完成。下一步：scripts/02-fetch-sdk.sh"
