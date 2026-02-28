# RDK X5 系统镜像构建

基于 D-Robotics RDK X5 开发板的 Ubuntu 22.04 (Jammy) ARM64 系统镜像构建工具。

> 官方文档：[简体中文](./READMErdk_CN.md) | [English](./READMErdk_EN.md)

## 功能特性

- 一键构建完整系统镜像（标准内核 + RT 实时内核）
- 子命令式构建，支持分步执行
- 本地编译 deb 包，也支持从官方仓库下载预编译包
- 自动构建 Ubuntu Desktop / Server rootfs
- 默认使用 RT 实时内核启动

## 系统要求

- **主机系统**：Ubuntu 22.04（推荐，与目标系统一致）
- **架构**：x86_64
- **权限**：需要 root / sudo
- **磁盘空间**：建议 50GB 以上可用空间
- **网络**：需要访问 GitHub 和 Ubuntu 软件源

## 快速开始

### 一键全量构建

```bash
sudo ./build.sh all
```

将依次执行：环境初始化 → 内核编译 → Bootloader 编译 → rootfs 构建 → deb 打包 → 镜像生成。

### 分步构建

```bash
# 1. 初始化环境（安装依赖、工具链、拉取源码）
sudo ./build.sh setup

# 2. 编译 Bootloader（miniboot/uboot/nand_disk.img）
sudo ./build.sh bootloader

# 3. 编译内核（标准内核 + RT 内核）
sudo ./build.sh kernel

# 4. 构建 Ubuntu rootfs
sudo ./build.sh rootfs

# 5. 编译并打包 deb 软件包
sudo ./build.sh debs

# 6. 生成最终系统镜像
sudo ./build.sh pack
```

### 快速重建镜像（跳过 rootfs 构建）

如果 rootfs 已经构建好并放在 `rootfs/` 目录下，可以直接：

```bash
# 编译内核 + bootloader + 打包 deb + 生成镜像
sudo ./build.sh image
```

## build.sh 子命令说明

| 命令 | 说明 | 等价操作 |
|------|------|----------|
| `setup` | 安装构建依赖、下载交叉编译工具链、repo sync 源码 | apt-get + toolchain + repo sync |
| `bootloader` | 编译 Bootloader 并复制 nand_disk.img 到 miniboot 固件目录 | xbuild.sh lunch 0 + xbuild.sh |
| `kernel` | 编译标准内核和 RT 实时内核 | mk_kernel.sh + mk_kernel_rt.sh |
| `rootfs` | 构建 Ubuntu rootfs 并拷贝到 `rootfs/` 目录，解压 sysroot 到 `deploy/rootfs/` | make_ubuntu_samplefs.sh desktop |
| `debs` | 从源码编译所有 deb 包（自动检测/解压 sysroot） | mk_debs.sh |
| `pack` | 打包生成最终 `.img` 镜像文件 | pack_image.sh -l |
| `image` | 完整构建（不含环境初始化和 rootfs） | kernel + bootloader + debs + pack |
| `all` | 全流程构建 | setup + kernel + bootloader + rootfs + debs + pack |

### 选项

```
-c <配置文件>   指定构建配置文件（默认：ubuntu-22.04_desktop_rdk-x5_release.conf）
-h             显示帮助信息
```

### 示例

```bash
# 使用 Server 配置打包镜像
sudo ./build.sh pack -c build_params/ubuntu-22.04_server_rdk-x5_release.conf

# 使用 Beta 配置全量构建
sudo ./build.sh all -c build_params/ubuntu-22.04_desktop_rdk-x5_beta.conf
```

## 目录结构

```
.
├── build.sh                     # 主构建脚本（子命令入口）
├── build_params/                # 构建配置文件
│   ├── ubuntu-22.04_desktop_rdk-x5_release.conf
│   ├── ubuntu-22.04_desktop_rdk-x5_beta.conf
│   ├── ubuntu-22.04_server_rdk-x5_release.conf
│   └── ubuntu-22.04_server_rdk-x5_beta.conf
├── mk_kernel.sh                 # 编译标准内核
├── mk_kernel_rt.sh              # 编译 RT 实时内核
├── mk_debs.sh                   # 编译源码并打包 deb
├── pack_image.sh                # 打包系统镜像
├── download_deb_pkgs.sh         # 从官方仓库下载预编译 deb 包
├── download_samplefs.sh         # 从官方服务器下载预制 rootfs（分步构建时不需要）
├── hobot_customize_rootfs.sh    # rootfs 定制化脚本
├── VERSION                      # 镜像版本号
├── samplefs/                    # rootfs 构建目录
│   ├── make_ubuntu_samplefs.sh  # 使用 debootstrap 构建 Ubuntu rootfs
│   ├── jammy/                   # Ubuntu 22.04 软件包列表
│   └── desktop/                 # Desktop 版 rootfs 构建产物
├── source/                      # 源码目录（repo sync 下载）
│   ├── kernel/                  # Linux 内核源码 (6.1.83)
│   ├── kernel-rt/               # RT 内核源码 (6.1.83-rt28)
│   ├── bootloader/              # miniboot + U-Boot 源码
│   ├── hobot-boot/              # 内核镜像 + boot.scr 打包
│   ├── hobot-dtb/               # 设备树
│   ├── hobot-multimedia/        # 多媒体库
│   ├── hobot-camera/            # 摄像头驱动
│   ├── hobot-dnn/               # BPU 神经网络推理运行时
│   ├── hobot-configs/           # 系统配置
│   └── ...                      # 其他 hobot-* 软件包源码
├── rootfs/                      # rootfs tar.gz 存放目录（pack 时使用）
├── deb_packages/                # 官方下载的预编译 deb 包
├── third_packages/              # 第三方 deb 包（用户自行放入，会自动安装）
└── deploy/                      # 构建产物输出目录
    ├── kernel/                  # 内核编译产物（Image, Image-rt, dtb, modules）
    ├── deb_pkgs/                # 本地编译的 deb 包
    └── rootfs/                  # 解压后的根文件系统
```

## 构建流程详解

### 镜像打包流程（pack_image.sh）

```
rootfs/*.tar.gz (samplefs)
    │
    ├─ 解压到 deploy/rootfs/
    ├─ 执行 hobot_customize_rootfs.sh 定制化配置
    ├─ 安装 deb 包（来源合并，同名保留最新版本）：
    │   ├─ deb_packages/       （官方下载的预编译包）
    │   ├─ third_packages/     （用户自定义第三方包）
    │   └─ deploy/deb_pkgs/    （本地编译的包，-l 模式）
    ├─ 生成 RT 内核 boot.scr（默认使用 Image-rt 启动）
    └─ 创建分区并写入 .img 镜像文件
```

### Deb 包来源说明

系统镜像中安装的 deb 包有两种来源：

| 来源 | 目录 | 说明 |
|------|------|------|
| 官方预编译 | `deb_packages/` | 由 `download_deb_pkgs.sh` 从 `archive.d-robotics.cc` 下载 |
| 本地编译 | `deploy/deb_pkgs/` | 由 `mk_debs.sh` 从 `source/` 源码编译生成 |
| 第三方 | `third_packages/` | 用户手动放入的自定义 deb 包 |

**注意**：`pack_image.sh` 会安装以上所有目录中的 **全部** `.deb` 文件，不受配置文件中 `RDK_DEB_PKG_LIST` 限制。如需排除某个包，需将其 `.deb` 文件从目录中移除。

### 本地编译的 Deb 包列表

`mk_debs.sh` 可编译以下 18 个软件包：

| 包名 | 说明 |
|------|------|
| hobot-boot | 内核镜像 (Image + Image-rt) + 驱动模块 + boot.scr |
| hobot-kernel-headers | 内核头文件（用于编译外部模块） |
| hobot-dtb | 设备树 + Overlay |
| hobot-configs | 系统配置 |
| hobot-utils | 系统工具集 |
| hobot-display | MIPI DSI 显示屏驱动 |
| hobot-wifi | Wi-Fi 配置 |
| hobot-io | GPIO / I2C / SPI 接口工具 |
| hobot-io-samples | IO 接口使用示例 |
| hobot-multimedia | 多媒体支持库 |
| hobot-multimedia-dev | 多媒体开发头文件 |
| hobot-multimedia-samples | 多媒体示例 |
| hobot-camera | 摄像头 Sensor 驱动 |
| hobot-dnn | BPU 推理运行时 |
| hobot-spdev | Python / C++ 开发接口 |
| hobot-sp-samples | spdev 示例代码 |
| hobot-miniboot | Miniboot 更新器 |
| hobot-audio-config | 音频 HAT 配置 + Overlay |

## 内核相关

### 标准内核与 RT 内核

本项目同时编译两个内核：

| 内核 | 版本 | defconfig | 输出 |
|------|------|-----------|------|
| 标准内核 | 6.1.83 | `hobot_x5_rdk_ubuntu_defconfig` | `deploy/kernel/Image` |
| RT 内核 | 6.1.83-rt28 | `hobot_x5_rdk_ubuntu_rt_defconfig` | `deploy/kernel/Image-rt` |

默认使用 **RT 实时内核** 启动（`pack_image.sh` 中会自动将 `boot.scr` 修改为加载 `Image-rt`）。

### 单独编译内核

```bash
# 编译标准内核
./mk_kernel.sh

# 编译 RT 内核
./mk_kernel_rt.sh
```

编译产物位于 `deploy/kernel/`：

```
deploy/kernel/
├── Image              # 标准内核镜像
├── Image-rt           # RT 实时内核镜像
├── dtb/               # 设备树文件
├── modules/           # 内核模块
└── kernel_headers/    # 内核头文件
```

## 构建配置

配置文件位于 `build_params/` 目录，主要变量说明：

| 变量 | 说明 | 示例值 |
|------|------|--------|
| `RDK_IMAGE_NAME` | 输出镜像文件名 | `rdk-x5-ubuntu22-preinstalled-desktop-3.4.1-arm64.img` |
| `RDK_UBUNTU_VERSION` | Ubuntu 版本代号 | `jammy` |
| `RDK_IMAGE_TYPE` | 镜像类型 | `desktop` / `server` |
| `RDK_ARCHIVE_URL` | 官方 deb 包仓库地址 | `http://archive.d-robotics.cc/ubuntu-rdk-x5` |
| `RDK_DEB_PKG_LIST` | 需下载的官方 deb 包列表 | 用于 `download_deb_pkgs.sh` |
| `RDK_DEB_PKG_DIR` | 下载的 deb 包存放目录 | `deb_packages` |
| `RDK_THIRD_DEB_PKG_DIR` | 第三方 deb 包目录 | `third_packages` |
| `RDK_ROOTFS_DIR` | rootfs tar.gz 存放目录 | `rootfs` |

## 自定义安装第三方软件包

如需在镜像中预装额外的 deb 包，创建 `third_packages/` 目录并放入 `.deb` 文件即可：

```bash
mkdir -p third_packages
cp your-package.deb third_packages/
sudo ./build.sh pack
```

## 常见问题

### rootfs 构建失败（apt-cacher-ng 问题）

rootfs 构建使用 `apt-cacher-ng` 作为 apt 代理缓存。确保服务正在运行：

```bash
sudo systemctl start apt-cacher-ng
sudo systemctl enable apt-cacher-ng
```

### pack_image.sh 报 tar 解压失败

确保 `rootfs/` 目录下只有一个 `samplefs*.tar.gz` 文件，且文件完整未损坏：

```bash
ls rootfs/samplefs*.tar.gz
file rootfs/samplefs*.tar.gz
```

### 交叉编译工具链找不到

工具链默认安装在 `/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/`，确认该目录存在，或重新执行：

```bash
sudo ./build.sh setup
```

### repo sync 报 unsupported checkout state

```
error.GitError: Cannot checkout x5-rdk-gen: .../.git: unsupported checkout state
```

这是正常现象，可以忽略。因为 x5-rdk-gen 仓库本身就是当前工作目录，存在本地新增/修改的文件，repo 无法对其执行 checkout，但不影响 `source/` 下各子项目的正常同步。

## 许可证

详见 [LICENSE](./LICENSE) 文件。
