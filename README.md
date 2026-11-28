# lubancat-rk3568-image-build

鲁班猫2（RK3568）可烧录镜像构建方案集。**每个发行版一个分支**，各自包含一份从零到上板的实测教程。

> 所有方案均在 **Ubuntu 26.04 宿主机**上编写并实测。

## 方案索引

| 目标系统 | 分支 | 桌面 | 内核 |
| --- | --- | --- | --- |
| Ubuntu 24.04 LTS (noble) | [`ubuntu/noble`](../../tree/ubuntu/noble) | XFCE | 6.1 |
| Ubuntu 22.04 LTS (jammy) | [`ubuntu/jammy`](../../tree/ubuntu/jammy) | XFCE | 6.1 |

## 快速开始

```bash
git clone https://github.com/qianzhongyang/lubancat-rk3568-image-build.git
cd lubancat-rk3568-image-build

# Ubuntu 22.04
git checkout ubuntu/jammy
# Ubuntu 24.04
git checkout ubuntu/noble
```

进去后**直接看该分支的** `README.md`，从第一章按顺序往下走即可。所有脚本和命令都在里面。

## 为什么需要这个仓库

野火（EmbedFire）官方文档主要针对 Ubuntu 20.04 / 22.04 宿主机。在 **Ubuntu 24.04、26.04** 上，
因为以下几个变化，照着官方流程走会连续卡住：

| 变化                            | 后果                                                  |
| ----------------------------- | --------------------------------------------------- |
| GCC 15 默认 C23                 | `menuconfig` 报「找不到 ncurses」，实际是 `main()` 隐式返回类型编译失败 |
| `qemu-user-static` 从仓库移除      | chroot 阶段直接失败                                       |
| `mkfs.ext4` 默认开 `orphan_file` | 目标若是 22.04，**编译全程正常，烧到板子才卡在** `(initramfs)`         |
| SDK 缺 `ubuntu24.04` 目录        | 选 noble 后 `cd` 目标目录直接失败（只有 20.04 / 22.04 目录）        |

第三条最麻烦——它不会在任何编译步骤里报错，只有真正上机才暴露。

每个分支的文档都记录了这类问题的**真实报错原文、成因、修复方法**，而不是复述官方流程。

> 关于 `orphan_file` 的适用范围：它是 **22.04 的问题**。24.04 自带 `e2fsck 1.47.0`，
> 正好跨过引入该特性的版本线，所以 `ubuntu/noble` 分支不受影响——
> 但两边的 `mk-image.sh` 都保留了 `-O ^orphan_file`，让同一套脚本能跨版本通用。

## 仓库约定

- **分支 = 发行版**。`main` 只放本总览，不放任何脚本
- 通用步骤（装依赖、拉 SDK）在各分支里内容相同，因为它们是**宿主机侧**的准备，与目标发行版无关
- 分支命名用 `系统/代号`，如 `ubuntu/jammy`、`debian/bookworm`

## 相关知识

- 目标板卡：鲁班猫2（LubanCat-2），Rockchip RK3568，四核 Cortex-A55
- 同芯片族 RK3566 板卡亦可参考（SDK 的 chip family 同为 `rk3566_rk3568`）
- SDK：鲁班猫通用 SDK，manifest 为 `lubancat_linux_generic.xml`

## 许可

文档与脚本可自由使用、修改、转载，注明出处即可。
