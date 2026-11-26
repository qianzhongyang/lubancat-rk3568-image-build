#!/usr/bin/env bash
# 安装 repo 并拉取鲁班猫通用 SDK（lubancat_linux_generic.xml）
# 支持重试：github 的 git 通道偶尔会被 RST 打断
set -uo pipefail

SDK_DIR="${SDK_DIR:-$HOME/LubanCat_SDK}"
MANIFEST="${MANIFEST:-lubancat_linux_generic.xml}"
BRANCH="${BRANCH:-linux}"
JOBS="${JOBS:-4}"
RETRY="${RETRY:-3}"
REPO_URL_MIRROR="https://mirrors.ustc.edu.cn/aosp/git-repo"
REPO_URL_FALLBACK="https://mirrors.tuna.tsinghua.edu.cn/git/git-repo"
MANIFEST_URL="https://github.com/LubanCat/manifests.git"

info() { printf '\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- 1. repo 工具 ----------
if ! command -v repo >/dev/null 2>&1; then
  info "安装 repo 到 ~/bin"
  mkdir -p "$HOME/bin"
  if ! curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/bin/repo"; then
    warn "Google 源不可用，改用 apt 版 repo"
    sudo apt install -y repo || die "repo 安装失败"
  else
    chmod a+x "$HOME/bin/repo"
  fi
  export PATH="$HOME/bin:$PATH"
  grep -q 'HOME/bin:$PATH' "$HOME/.bashrc" 2>/dev/null || \
    echo 'export PATH=$HOME/bin:$PATH' >> "$HOME/.bashrc"
fi
repo --version | head -3

# ---------- 2. git 调优（缓解 RST） ----------
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999
git config --global http.version HTTP/1.1

# ---------- 3. 目录与权限 ----------
mkdir -p "$SDK_DIR"
case "$(findmnt -fnu -o FSTYPE -T "$SDK_DIR" 2>/dev/null)" in
  ext*|f2fs|btrfs|xfs) ;;
  *) die "$SDK_DIR 不在 ext4/f2fs/btrfs/xfs 分区上，build.sh 会拒绝编译" ;;
esac

# ---------- 3.5 git 身份（repo init 的硬前提） ----------
# repo init 末尾要读 GIT_COMMITTER_IDENT，缺 user.name/email 会直接抛异常
if ! git var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
  warn "git 身份未配置，repo init 会失败"
  die '请先执行：
  git config --global user.name  "你的名字"
  git config --global user.email "you@example.com"'
fi

cd "$SDK_DIR"

# ---------- 4. repo init ----------
if [ ! -f .repo/manifest.xml ]; then
  info "repo init ($MANIFEST)"
  # 先试中科大（路径是 /aosp/git-repo），失败再回退清华
  INIT_OK=0
  for url in "$REPO_URL_MIRROR" "$REPO_URL_FALLBACK"; do
    info "使用 repo-url: $url"
    for i in $(seq 1 "$RETRY"); do
      if repo init --depth=1 --repo-url "$url" \
           -u "$MANIFEST_URL" -b "$BRANCH" -m "$MANIFEST"; then
        INIT_OK=1; break 2
      fi
      warn "repo init 第 $i 次失败（$url），清理后重试"
      rm -rf .repo
      sleep 5
    done
    warn "该镜像不可用，尝试下一个"
  done
  [ "$INIT_OK" = 1 ] || die "repo init 失败（检查 github 网络/代理）"
else
  info ".repo 已存在，跳过 init（如需重来：rm -rf $SDK_DIR/.repo）"
fi

# ---------- 5. repo sync ----------
info "repo sync -c -j$JOBS（约 12 GB，可中断续传）"
for i in $(seq 1 "$RETRY"); do
  if .repo/repo/repo sync -c -j"$JOBS"; then
    SYNC_OK=1; break
  fi
  warn "sync 第 $i 次失败，10s 后重试（已下载内容会保留）"
  sleep 10
done

if [ "${SYNC_OK:-0}" != 1 ]; then
  warn "sync 未全部成功。常见处理："
  cat <<'EOF'
  # 1) 直接重跑（repo 断点续传）
  .repo/repo/repo sync -c -j4

  # 2) 只同步失败的仓库
  .repo/repo/repo sync -c -j1 -f --fail-fast=false

  # 3) 有代理时
  export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890

  # 4) 彻底重来
  rm -rf .repo && repo init --depth=1 \
      --repo-url https://mirrors.ustc.edu.cn/aosp/git-repo \
      -u https://github.com/LubanCat/manifests.git -b linux -m lubancat_linux_generic.xml
EOF
  exit 1
fi

# ---------- 6. 校验 ----------
[ -x ./build.sh ] || ln -rsf device/rockchip/common/scripts/build.sh ./build.sh 2>/dev/null || true
[ -x ./build.sh ] || die "build.sh 缺失，SDK 不完整"

info "SDK 拉取完成"
ls -1 | head -20
echo
info "下一步：按 README 对应分支继续（见 docs 或分支 README）"
