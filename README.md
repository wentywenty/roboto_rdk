# RDK X5 System Image Builder

English | [简体中文](./README_CN.md)

> Official D-Robotics documentation: [简体中文](./READMErdk_CN.md) | [English](./READMErdk_EN.md)

Build tool for Ubuntu 22.04 (Jammy) ARM64 system images targeting the D-Robotics RDK X5 development board.

## Features

- One-click full system image build (standard kernel + RT real-time kernel)
- Subcommand-based build, supports step-by-step execution
- Local deb package compilation, also supports downloading prebuilt packages from the official repository
- Automatic Ubuntu Desktop / Server rootfs generation
- Boots with RT real-time kernel by default

## System Requirements

- **Host OS**: Ubuntu 22.04 (recommended, matches target system)
- **Architecture**: x86_64
- **Privileges**: Requires root / sudo
- **Disk Space**: 50GB+ free space recommended
- **Network**: Access to GitHub and Ubuntu package repositories required

## Quick Start

### One-Click Full Build

```bash
sudo ./build.sh all
```

Executes in order: environment setup → kernel build → bootloader build → rootfs build → deb packaging → image generation.

### Step-by-Step Build

```bash
# 1. Initialize environment (install dependencies, toolchain, fetch source code)
sudo ./build.sh setup

# 2. Build Bootloader (miniboot/uboot/nand_disk.img)
sudo ./build.sh bootloader

# 3. Build kernels (standard + RT)
sudo ./build.sh kernel

# 4. Build Ubuntu rootfs
sudo ./build.sh rootfs

# 5. Build deb packages from source
sudo ./build.sh debs

# 6. Generate final system image
sudo ./build.sh pack
```

### Quick Image Rebuild (Skip rootfs Build)

If rootfs is already built and placed in the `rootfs/` directory:

```bash
# Build kernel + bootloader + deb packages + generate image
sudo ./build.sh image
```

## build.sh Subcommands

| Command | Description | Equivalent |
|---------|-------------|------------|
| `setup` | Install build dependencies, download cross-compilation toolchain, repo sync source code | apt-get + toolchain + repo sync |
| `bootloader` | Build bootloader and copy nand_disk.img to miniboot firmware directory | xbuild.sh lunch 0 + xbuild.sh |
| `kernel` | Build standard kernel and RT real-time kernel | mk_kernel.sh + mk_kernel_rt.sh |
| `rootfs` | Build Ubuntu rootfs, copy to `rootfs/`, extract sysroot to `deploy/rootfs/` | make_ubuntu_samplefs.sh desktop |
| `debs` | Build all deb packages from source (auto-detects/extracts sysroot) | mk_debs.sh |
| `pack` | Generate final `.img` image file | pack_image.sh -l |
| `image` | Full build (without environment setup and rootfs) | kernel + bootloader + debs + pack |
| `all` | Complete build pipeline | setup + kernel + bootloader + rootfs + debs + pack |

### Options

```
-c <config_file>  Specify build config file (default: ubuntu-22.04_desktop_rdk-x5_release.conf)
-h                Show help
```

### Examples

```bash
# Pack image with Server configuration
sudo ./build.sh pack -c build_params/ubuntu-22.04_server_rdk-x5_release.conf

# Full build with Beta configuration
sudo ./build.sh all -c build_params/ubuntu-22.04_desktop_rdk-x5_beta.conf
```

## Directory Structure

```
.
├── build.sh                     # Main build script (subcommand entry point)
├── build_params/                # Build configuration files
│   ├── ubuntu-22.04_desktop_rdk-x5_release.conf
│   ├── ubuntu-22.04_desktop_rdk-x5_beta.conf
│   ├── ubuntu-22.04_server_rdk-x5_release.conf
│   └── ubuntu-22.04_server_rdk-x5_beta.conf
├── mk_kernel.sh                 # Build standard kernel
├── mk_kernel_rt.sh              # Build RT real-time kernel
├── mk_debs.sh                   # Build source code and package as deb
├── pack_image.sh                # Pack system image
├── download_deb_pkgs.sh         # Download prebuilt deb packages from official repo
├── download_samplefs.sh         # Download prebuilt rootfs from official server
├── hobot_customize_rootfs.sh    # Rootfs customization script
├── VERSION                      # Image version number
├── samplefs/                    # Rootfs build directory
│   ├── make_ubuntu_samplefs.sh  # Build Ubuntu rootfs using debootstrap
│   ├── jammy/                   # Ubuntu 22.04 package lists
│   └── desktop/                 # Desktop rootfs build output
├── source/                      # Source code directory (fetched via repo sync)
│   ├── kernel/                  # Linux kernel source (6.1.83)
│   ├── kernel-rt/               # RT kernel source (6.1.83-rt28)
│   ├── bootloader/              # miniboot + U-Boot source
│   ├── hobot-boot/              # Kernel image + boot.scr packaging
│   ├── hobot-dtb/               # Device trees
│   ├── hobot-multimedia/        # Multimedia libraries
│   ├── hobot-camera/            # Camera drivers
│   ├── hobot-dnn/               # BPU neural network inference runtime
│   ├── hobot-configs/           # System configuration
│   └── ...                      # Other hobot-* package sources
├── rootfs/                      # rootfs tar.gz storage (used by pack)
├── deb_packages/                # Prebuilt deb packages from official repo
├── third_packages/              # Third-party deb packages (user-provided, auto-installed)
└── deploy/                      # Build output directory
    ├── kernel/                  # Kernel build artifacts (Image, Image-rt, dtb, modules)
    ├── deb_pkgs/                # Locally compiled deb packages
    └── rootfs/                  # Extracted root filesystem
```

## Build Process Details

### Image Packing Flow (pack_image.sh)

```
rootfs/*.tar.gz (samplefs)
    │
    ├─ Extract to deploy/rootfs/
    ├─ Run hobot_customize_rootfs.sh for customization
    ├─ Install deb packages (merged, keep latest version for duplicates):
    │   ├─ deb_packages/       (prebuilt packages from official repo)
    │   ├─ third_packages/     (user-provided third-party packages)
    │   └─ deploy/deb_pkgs/    (locally compiled packages, -l mode)
    ├─ Generate RT kernel boot.scr (boots Image-rt by default)
    └─ Create partitions and write .img file
```

### Deb Package Sources

Deb packages installed in the system image come from multiple sources:

| Source | Directory | Description |
|--------|-----------|-------------|
| Official prebuilt | `deb_packages/` | Downloaded by `download_deb_pkgs.sh` from `archive.d-robotics.cc` |
| Locally compiled | `deploy/deb_pkgs/` | Built by `mk_debs.sh` from `source/` |
| Third-party | `third_packages/` | User-provided custom deb packages |

**Note**: `pack_image.sh` installs **all** `.deb` files from the above directories, regardless of `RDK_DEB_PKG_LIST` in the config file. To exclude a package, remove its `.deb` file from the directory.

### Locally Compiled Deb Packages

`mk_debs.sh` builds the following 17 packages:

| Package | Description |
|---------|-------------|
| hobot-boot | Kernel images (Image + Image-rt) + driver modules + boot.scr |
| hobot-kernel-headers | Kernel headers (for building external modules) |
| hobot-dtb | Device trees + overlays |
| hobot-configs | System configuration |
| hobot-utils | System utility collection |
| hobot-display | MIPI DSI display driver |
| hobot-wifi | Wi-Fi configuration |
| hobot-io | GPIO / I2C / SPI interface tools |
| hobot-io-samples | IO interface examples |
| hobot-multimedia | Multimedia support libraries |
| hobot-multimedia-dev | Multimedia development headers |
| hobot-multimedia-samples | Multimedia examples |
| hobot-camera | Camera sensor drivers |
| hobot-dnn | BPU inference runtime |
| hobot-spdev | Python / C++ development interface |
| hobot-miniboot | Miniboot updater |
| hobot-audio-config | Audio HAT configuration + overlays |

## Kernel

### Standard Kernel and RT Kernel

This project builds two kernels simultaneously:

| Kernel | Version | defconfig | Output |
|--------|---------|-----------|--------|
| Standard | 6.1.83 | `hobot_x5_rdk_ubuntu_defconfig` | `deploy/kernel/Image` |
| RT | 6.1.83-rt28 | `hobot_x5_rdk_ubuntu_rt_defconfig` | `deploy/kernel/Image-rt` |

The **RT real-time kernel** is used for booting by default (`pack_image.sh` automatically modifies `boot.scr` to load `Image-rt`).

### Build Kernel Separately

```bash
# Build standard kernel
./mk_kernel.sh

# Build RT kernel
./mk_kernel_rt.sh
```

Build artifacts are located in `deploy/kernel/`:

```
deploy/kernel/
├── Image              # Standard kernel image
├── Image-rt           # RT real-time kernel image
├── dtb/               # Device tree files
├── modules/           # Kernel modules
└── kernel_headers/    # Kernel header files
```

## FAQ

### rootfs Build Fails (apt-cacher-ng Issue)

The rootfs build uses `apt-cacher-ng` as an apt proxy cache. Ensure the service is running:

```bash
sudo systemctl start apt-cacher-ng
sudo systemctl enable apt-cacher-ng
```

### pack_image.sh Reports tar Extraction Failure

Ensure there is only one `samplefs*.tar.gz` file in the `rootfs/` directory and that it is not corrupted:

```bash
ls rootfs/samplefs*.tar.gz
file rootfs/samplefs*.tar.gz
```

### Cross-Compilation Toolchain Not Found

The toolchain is installed by default at `/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/`. Verify the directory exists, or re-run:

```bash
sudo ./build.sh setup
```

### repo sync Reports "unsupported checkout state"

```
error.GitError: Cannot checkout x5-rdk-gen: .../.git: unsupported checkout state
```

This is expected and can be safely ignored. The x5-rdk-gen repository is the working directory itself, containing locally added/modified files. repo cannot checkout over these, but it does not affect syncing of subprojects under `source/`.

### Installing Additional Third-Party Packages

To pre-install extra deb packages in the image, create a `third_packages/` directory and place `.deb` files inside:

```bash
mkdir -p third_packages
cp your-package.deb third_packages/
sudo ./build.sh pack
```

## License

See the [LICENSE](./LICENSE) file for details.
