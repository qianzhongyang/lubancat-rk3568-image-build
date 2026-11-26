#!/usr/bin/env bash
# 选择 RK3568（鲁班猫2）板级配置 → 切换 rootfs 为 Ubuntu 22.04 → 编译
#
# 用法：
#   ./03-build-ubuntu22.sh                        # XFCE 桌面版 + 6.1 内核，分步编译
#   DESKTOP=lite ./03-build-ubuntu22.sh           # 无桌面版
#   KERNEL=5.10  ./03-build-ubuntu22.sh           # 指定 5.10 内核
#   JOBS=24      ./03-build-ubuntu22.sh           # 并行度
#   DO_BUILD=0   ./03-build-ubuntu22.sh           # 只改配置不编译
#   MODE=all     ./03-build-ubuntu22.sh           # 一次跑完（等价 ./build.sh）
#
# 注意：`./build.sh ubuntu` 内部需要 sudo（mount/chroot/mkfs），
#      请在有 TTY 的终端里运行，否则会报 "A terminal is required to authenticate"。
set -uo pipefail

SDK_DIR="${SDK_DIR:-$HOME/LubanCat_SDK}"
CHIP="${CHIP:-rk3566_rk3568}"          # 鲁班猫2 的 RK3568 属于该 chip 家族
BOARD="${BOARD:-LubanCat_rk3568}"       # 板卡前缀
DESKTOP="${DESKTOP:-xfce}"              # xfce | lite
KERNEL="${KERNEL:-6.1}"                 # 6.1 | 5.10
JOBS="${JOBS:-$(nproc)}"
DO_BUILD="${DO_BUILD:-1}"               # 0 = 只配置不编译
MODE="${MODE:-steps}"                   # steps = 分步（推荐）| all = 一次性

info() { printf '\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- 0. 前置检查 ----------
cd "$SDK_DIR" 2>/dev/null || die "找不到 SDK 目录: $SDK_DIR（先跑 02-fetch-sdk.sh）"
[ -x ./build.sh ] || die "缺少 build.sh，SDK 不完整"

# 确保 ~/bin 在 PATH（python2 shim 依赖它）
if ! echo ":$PATH:" | grep -q ":$HOME/bin:"; then
  export PATH="$HOME/bin:$PATH"
fi

# 关键工具检查（对应 README 第 11 节记录的踩坑）
MISSING=""
for t in dtc fdtget flex bison lz4 python3; do
  command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"
done
[ -x /usr/bin/qemu-aarch64-static ] || MISSING="$MISSING qemu-aarch64-static(软链)"
[ -x "$HOME/bin/python2" ] || command -v python2 >/dev/null 2>&1 || MISSING="$MISSING python2"

if [ -n "$MISSING" ]; then
  die "缺少依赖:$MISSING
请先运行: scripts/01-install-deps.sh"
fi

DEFCONFIG_NAME="${BOARD}_ubuntu_${DESKTOP}_defconfig"
DEFCONFIG="device/rockchip/.chips/${CHIP}/${DEFCONFIG_NAME}"

# ---------- 1. 选芯片 + defconfig（非交互） ----------
info "切换板级配置: $CHIP / $DEFCONFIG_NAME"
./build.sh "chip:${CHIP}:${DEFCONFIG_NAME}" >/tmp/lbc-chip.log 2>&1 || {
  warn "切换失败，可用 defconfig 列表："
  ls "device/rockchip/.chips/${CHIP}/" 2>/dev/null | grep defconfig
  die "参见 README 第 6 章"
}

[ -f "$DEFCONFIG" ] || die "defconfig 不存在: $DEFCONFIG"

# ---------- 2. Ubuntu 版本 → 22.04 (jammy) ----------
info "把 rootfs 从 focal(20.04) 切到 jammy(22.04)"
cp -n "$DEFCONFIG" "${DEFCONFIG}.bak" 2>/dev/null || true

# Kconfig 的 choice 只允许一个为 y。这里做幂等重建：
# 丢掉所有旧的 rootfs-choice 行（=y 与 "is not set" 两种形式），统一写在文件头。
printf '%s\n' '# RK_BUILDROOT is not set' >  "${DEFCONFIG}.tmp"
printf '%s\n' '# RK_YOCTO is not set'     >> "${DEFCONFIG}.tmp"
printf '%s\n' 'RK_UBUNTU_JAMMY=y'         >> "${DEFCONFIG}.tmp"
grep -vE '^# RK_(BUILDROOT|YOCTO) is not set$|^RK_UBUNTU_(FOCAL|JAMMY|NOBLE)=y$|^# RK_UBUNTU_(FOCAL|JAMMY|NOBLE) is not set$' \
  "$DEFCONFIG" >> "${DEFCONFIG}.tmp"
mv "${DEFCONFIG}.tmp" "$DEFCONFIG"

# ---------- 3. 内核版本 ----------
if grep -q '^RK_KERNEL_PREFERRED=' "$DEFCONFIG"; then
  info "设置内核版本: $KERNEL"
  sed -i -E "s/^RK_KERNEL_PREFERRED=.*/RK_KERNEL_PREFERRED=\"${KERNEL}\"/" "$DEFCONFIG"
else
  echo "RK_KERNEL_PREFERRED=\"${KERNEL}\"" >> "$DEFCONFIG"
fi

echo "----- $DEFCONFIG -----"
grep -E 'UBUNTU|KERNEL|ROOTFS_IMAGE|DTS_NAME|PARAMETER' "$DEFCONFIG"
echo "----------------------"

# ---------- 4. 校验 choice 唯一性 ----------
COUNT=$(grep -cE '^RK_UBUNTU_(FOCAL|JAMMY|NOBLE)=y' "$DEFCONFIG" || true)
[ "$COUNT" -eq 1 ] || die "Ubuntu 版本 choice 非法（=y 的数量为 $COUNT，应为 1）"

# ---------- 5. 清理旧配置并重新生成 ----------
# 只改 defconfig 不会自动刷新 output/.config（时间戳判断不可靠），这里强制重生成
rm -f output/.config output/.config.old
info "重新生成 output/.config"
./build.sh defconfig:"$DEFCONFIG_NAME" >/tmp/lbc-cfg.log 2>&1 || \
  ./build.sh "chip:${CHIP}:${DEFCONFIG_NAME}" >/tmp/lbc-cfg.log 2>&1 || die "配置生成失败，见 /tmp/lbc-cfg.log"

ACTUAL_VER=$(grep -E '^RK_UBUNTU_VERSION=' output/.config | cut -d'"' -f2)
ACTUAL_NUM=$(grep -E '^RK_UBUNTU_NUMBER='  output/.config | cut -d'"' -f2)
info "output/.config: RK_UBUNTU_VERSION=$ACTUAL_VER ($ACTUAL_NUM)"
[ "$ACTUAL_VER" = "jammy" ] || die "rootfs 未切换为 jammy（当前: $ACTUAL_VER），检查 defconfig 与 Kconfig choice"

info "配置完成：chip=$CHIP defconfig=$DEFCONFIG_NAME rootfs=$ACTUAL_NUM kernel=$KERNEL"

[ "$DO_BUILD" = 1 ] || { info "仅配置模式（DO_BUILD=0），退出"; exit 0; }

# ---------- 5.5 清理残留挂载（rootfs 失败的根因） ----------
# mk-base-ubuntu.sh 是先 `rm -rf binary` 再 `ch-mount.sh -m binary`，
# 而 umount 只挂在 trap ERR 上。一旦中途失败/被 Ctrl-C，proc/sys/dev 会残留，
# 下次 rm -rf 就报大量 "Operation not permitted" 并直接失败。
cleanup_stale_mounts() {
  local dir="$SDK_DIR/ubuntu22.04/binary"
  [ -d "$dir" ] || return 0

  local found=0
  for m in proc sys dev; do
    if grep -q " $dir/$m " /proc/mounts 2>/dev/null; then
      found=1
      warn "发现残留挂载: $dir/$m"
      sudo umount -l "$dir/$m" 2>/dev/null || sudo umount -f "$dir/$m" 2>/dev/null || true
    fi
  done

  if [ "$found" = 1 ]; then
    # 再扫一遍，确认干净
    local left
    left=$(grep -c " $dir/" /proc/mounts 2>/dev/null)
    left=${left:-0}
    if [ "$left" -gt 0 ] 2>/dev/null; then
      die "残留挂载无法卸载，请手动执行：
  sudo umount -l $dir/proc $dir/sys $dir/dev
  grep $dir /proc/mounts   # 应为空"
    fi
    info "残留挂载已清理，继续编译"
  fi
}

# 关键：mk-base-ubuntu.sh 结尾的 `sudo umount` 若因密码超时失败，
# 脚本不检查返回值就 `sudo tar`，会把宿主机 /proc 打进包里（见 README 8.6）。
# 这里提前认证并校验 sudo 可用，避免 rootfs 白跑 60~90 分钟。
ensure_sudo() {
  if ! sudo -n true 2>/dev/null; then
    info "需要 sudo 权限，请输入密码（凭证会缓存，供 rootfs 阶段使用）"
    sudo -v || die "sudo 认证失败，无法继续"
  fi
  sudo -n true 2>/dev/null || die "sudo 凭证无效"
  info "sudo 凭证有效"
}

# ---------- 6. 编译 ----------
# 分步编译：哪一步失败只看那一步，rootfs 的 60~90 分钟不会白跑
run_step() {
  local name="$1"; shift
  info ">>> $name"
  local start=$SECONDS
  if "$@"; then
    info "<<< $name 完成（$((SECONDS-start))s）"
  else
    die "$name 失败。日志：$SDK_DIR/output/log/latest/"
  fi
}

# 关键：宿主机 e2fsprogs >= 1.47 的 mkfs.ext4 会默认开启 orphan_file 特性，
# 而 Ubuntu 22.04 镜像内的 e2fsck 是 1.46.5，不认识该特性，会导致板子卡在 (initramfs)。
# 治本：编译 rootfs 之前先把 mk-image.sh 的 mkfs.ext4 参数固定住（见 README 9.5）。
patch_mk_image() {
  local f="$SDK_DIR/ubuntu22.04/mk-image.sh"
  [ -f "$f" ] || { warn "未找到 mk-image.sh，跳过"; return 0; }

  if grep -q "MKFS_OPTS=" "$f"; then
    info "mk-image.sh 已修正（已关闭 orphan_file），跳过"
    return 0
  fi

  if grep -q '^sudo mkfs\.ext4 -d ' "$f"; then
    # 注意：-O 列出特性是追加，默认特性仍保留，必须用 ^ 显式关闭
    sed -i 's|^sudo mkfs\.ext4 -d |MKFS_OPTS="-O ^orphan_file"\n\nsudo mkfs.ext4 ${MKFS_OPTS} -d |' "$f"
    bash -n "$f" || { warn "补丁后语法有误，已放弃"; return 1; }
    info "已修正 mk-image.sh：mkfs.ext4 不再生成 orphan_file"
  else
    warn "mk-image.sh 的 mkfs.ext4 行格式不同，请手动按 README 9.5 处理"
    return 0
  fi
}

# 兜底：万一 mk-image.sh 没改成（或用了别的打包路径），编译后仍检查一次
check_orphan_file() {
  local img="$SDK_DIR/ubuntu22.04/ubuntu-rk356x-${DESKTOP}-rootfs.img"
  [ -f "$img" ] || { warn "未找到 rootfs 镜像，跳过检查: $img"; return 0; }

  if dumpe2fs -h "$img" 2>/dev/null | grep -q orphan_file; then
    warn "检测到 orphan_file 特性（板子上 e2fsck 1.46.5 不支持），正在移除..."
    sudo tune2fs -O ^orphan_file "$img" || return 1
    dumpe2fs -h "$img" 2>/dev/null | grep "Filesystem features"
    info "orphan_file 已移除，需重新打包固件"
  else
    info "ext4 特性检查通过（无 orphan_file）"
  fi
}

if [ "$MODE" = "all" ]; then
  info "一次性编译（预计 1.5 小时左右）"
  ensure_sudo
  patch_mk_image
  cleanup_stale_mounts
  time ./build.sh || die "编译失败，见 output/log/latest/"
else
  # 治本：编译 rootfs 之前先固定 mkfs.ext4 的 ext4 特性（见 README 9.5）
  run_step "修正 mk-image.sh（关闭 orphan_file）" patch_mk_image
  run_step "loader (u-boot/trust/MiniLoaderAll)" ./build.sh loader
  run_step "kernel (6.1 + dtb + extboot.img)"    ./build.sh kernel
  run_step "sudo 认证" ensure_sudo
  run_step "清理残留挂载" cleanup_stale_mounts
  run_step "rootfs (Ubuntu 22.04, 需 sudo, 60~90min)" ./build.sh ubuntu
  # 兜底：若上面补丁没生效，这里仍会尝试 tune2fs 修掉
  run_step "ext4 特性检查" check_orphan_file
  run_step "firmware (打包 + update.img)"         ./build.sh firmware
fi

# ---------- 7. 结果 ----------
FW="$SDK_DIR/output/firmware/update.img"
if [ -e "$FW" ]; then
  info "编译成功"
  ls -lhL "$FW"
  printf '\n镜像：%s\n' "$FW"
  printf '大小：%s\n' "$(du -h --dereference "$FW" | cut -f1)"
  md5sum "$FW"
  cat <<EOF

--- 镜像内容自检 ---
EOF
  sudo mkdir -p /tmp/lbc-chk 2>/dev/null && \
  sudo mount -o loop,ro "$SDK_DIR/ubuntu22.04/ubuntu-${CHIP%%_*}-${DESKTOP}-rootfs.img" /tmp/lbc-chk 2>/dev/null && {
    grep PRETTY_NAME /tmp/lbc-chk/etc/os-release 2>/dev/null
    echo "内核模块: $(ls /tmp/lbc-chk/lib/modules/ 2>/dev/null)"
    sudo umount /tmp/lbc-chk 2>/dev/null
  } || warn "自检需要 sudo，已跳过"

  cat <<EOF

--- 烧录步骤 ---
板子按住 MASKROM 键上电/插 USB，然后使用 SDK 自带的 upgrade_tool：

  TOOL="$SDK_DIR/tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool"
  sudo "\$TOOL" LD                                  # 确认设备
  sudo "\$TOOL" UF "$FW"                            # 烧写整包

注意：不要用 rkdeveloptool 的 ul 命令，那只写 loader，不会烧固件（会“秒成功”）。

首次登录：cat/temppwd 或 root/root
EOF
else
  warn "未找到 update.img。检查："
  ls -l "$SDK_DIR/output/firmware" 2>/dev/null | head
  warn "常见原因：rootfs 分区超限 / rootfs 构建失败"
  warn "日志：$SDK_DIR/output/log/latest/"
  exit 1
fi
