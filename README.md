# lubancat-rk3568-image-build

鲁班猫2（RK3568）可烧录镜像构建方案集。每个发行版一份**实测通过**的完整教程 + 配套脚本。

> 所有方案均在 **Ubuntu 26.04 宿主机**上从零跑通，并烧录上板验证。

## 收录方案

| 目标系统 | 分支 | 桌面 | 内核 | 状态 |
| --- | --- | --- | --- | --- |
| Ubuntu 22.04 LTS (jammy) | [`ubuntu/jammy`](../../tree/ubuntu/jammy) | XFCE | 6.1 | ✅ 已上板验证 |
| Ubuntu 20.04 LTS (focal) | `ubuntu/focal` | — | — | ⬜ 待补充 |
| Debian 12 (bookworm) | `debian/bookworm` | — | — | ⬜ 待补充 |

切换分支即可查看对应教程：

```bash
git checkout ubuntu/jammy
```

## 为什么需要这个仓库

野火官方文档主要针对 Ubuntu 20.04 / 22.04 宿主机。在 **Ubuntu 24.04、26.04** 上，
由于包重命名、`qemu-user-static` 被移除、`mkfs.ext4` 默认特性变更等原因，
照着官方文档走会在多个环节卡住，且部分问题**编译全程不报错、只有烧到板子上才暴露**。

每个分支的文档都记录了真实报错的现象、原因和修复方法，不是照抄官方流程。

## 目录说明

| 路径 | 说明 |
| --- | --- |
| `README.md` | 本文件，方案总览（所有分支共用） |
| `scripts/01-install-deps.sh` | 安装宿主机编译依赖，26.04 包名已适配（**与发行版无关**） |
| `scripts/02-fetch-sdk.sh` | 拉取鲁班猫通用 SDK，含仓库完整性校验（**与发行版无关**） |
| `<分支内>` | 各分支额外提供的编译脚本与完整教程 |

`01`、`02` 两个脚本在所有分支上通用；具体发行版的编译步骤和踩坑记录在对应分支的 `README.md` 里。

## 快速开始

```bash
git clone -b ubuntu/jammy <仓库地址>
cd lubancat-rk3568-image-build

./scripts/01-install-deps.sh     # 装依赖（需要 sudo）
./scripts/02-fetch-sdk.sh        # 拉 SDK
# 之后按该分支 README 继续
```

## 相关知识

- 目标板卡：鲁班猫2（LubanCat-2），Rockchip RK3568，四核 Cortex-A55
- 同芯片族 RK3566 板卡亦可参考（SDK 的 chip family 同为 `rk3566_rk3568`）
- SDK：鲁班猫通用 SDK，manifest 为 `lubancat_linux_generic.xml`

## 许可

文档与脚本可自由使用、修改、转载，注明出处即可。
