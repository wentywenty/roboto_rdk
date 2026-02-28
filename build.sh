#!/bin/bash
###
# RDK X5 Build Script
#
# Usage: sudo ./build.sh <command> [-c config_file]
#
# Commands:
#   setup      Install dependencies, toolchain, repo init & sync
#   kernel     Build standard + RT kernels
#   bootloader Build bootloader (miniboot/uboot/nand_disk.img)
#   rootfs     Build Ubuntu rootfs (samplefs)
#   debs       Build deb packages
#   pack       Pack final image (debs install + image creation)
#   image      Full build: kernel + bootloader + debs + pack
#   all        Everything: setup + kernel + bootloader + rootfs + debs + pack
#
# Options:
#   -c  Specify config file (default: ubuntu-22.04_desktop_rdk-x5_release.conf)
#   -h  Show help
###

set -euo pipefail

export HR_LOCAL_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

CONFIG_FILE="${HR_LOCAL_DIR}/build_params/ubuntu-22.04_desktop_rdk-x5_release.conf"
TOOLCHAIN_URL="http://archive.d-robotics.cc/toolchain/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz"
TOOLCHAIN_DIR="/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu"

show_help() {
    echo "Usage: sudo $0 <command> [-c config_file]"
    echo
    echo "Commands:"
    echo "  setup      Install dependencies, download toolchain, repo sync"
    echo "  kernel     Build standard kernel + RT kernel"
    echo "  bootloader Build bootloader (miniboot/uboot/nand_disk.img)"
    echo "  rootfs     Build Ubuntu rootfs (samplefs)"
    echo "  debs       Build deb packages from source"
    echo "  pack       Pack final .img image (install debs + create partitions)"
    echo "  image      Full build: kernel + bootloader + debs + pack"
    echo "  all        Everything: setup + kernel + bootloader + rootfs + debs + pack"
    echo
    echo "Options:"
    echo "  -c file  Specify config file"
    echo "  -h       Show this help"
    echo
    echo "Examples:"
    echo "  sudo $0 setup              # Prepare build environment"
    echo "  sudo $0 kernel             # Build both kernels"
    echo "  sudo $0 rootfs             # Build Ubuntu samplefs"
    echo "  sudo $0 image              # kernel + debs + pack"
    echo "  sudo $0 all                # Full build from scratch"
    echo "  sudo $0 pack -c build_params/ubuntu-22.04_server_rdk-x5_release.conf"
}

# Parse command
COMMAND="${1:-}"
if [ -z "${COMMAND}" ] || [ "${COMMAND}" = "-h" ]; then
    show_help
    exit 0
fi
shift

# Parse options
while getopts ":c:h" opt; do
    case ${opt} in
        c) CONFIG_FILE="$OPTARG" ;;
        h) show_help; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; show_help; exit 1 ;;
        :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
    esac
done

# Must run as root
if [ "$(whoami)" != "root" ]; then
    echo "[ERROR]: This script requires root privileges. Please execute it with sudo."
    exit 1
fi

########################################
# setup: Install deps + toolchain + repo
########################################
do_setup() {
    echo ""
    echo "========================================="
    echo "[setup] Installing build dependencies..."
    echo "========================================="
    apt-get update
    apt-get install -y \
        build-essential make cmake libpcre3 libpcre3-dev bc bison \
        flex python3-numpy python3-pip mtd-utils zlib1g-dev debootstrap \
        libdata-hexdumper-perl libncurses5-dev zip qemu-user-static \
        curl repo git liblz4-tool apt-cacher-ng libssl-dev checkpolicy autoconf \
        android-sdk-libsparse-utils mtools parted dosfstools udev rsync \
        device-tree-compiler u-boot-tools ccache

    echo ""
    echo "========================================="
    echo "[setup] Setting up cross-compilation toolchain..."
    echo "========================================="
    if [ ! -d "${TOOLCHAIN_DIR}" ]; then
        TOOLCHAIN_FILE="/tmp/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz"
        if [ ! -f "${TOOLCHAIN_FILE}" ]; then
            echo "Downloading toolchain..."
            curl -fL -o "${TOOLCHAIN_FILE}" "${TOOLCHAIN_URL}"
        fi
        echo "Extracting toolchain to /opt ..."
        tar -xf "${TOOLCHAIN_FILE}" -C /opt
        rm -f "${TOOLCHAIN_FILE}"
    else
        echo "Toolchain already exists at ${TOOLCHAIN_DIR}, skipping."
    fi

    echo ""
    echo "========================================="
    echo "[setup] Syncing source code with repo..."
    echo "========================================="
    export REPO_URL='https://mirrors.tuna.tsinghua.edu.cn/git/git-repo/'
    cd "${HR_LOCAL_DIR}"
    if [ ! -d "${HR_LOCAL_DIR}/.repo" ]; then
        sudo -u "${SUDO_USER}" bash -c "export REPO_URL='https://mirrors.tuna.tsinghua.edu.cn/git/git-repo/' && cd '${HR_LOCAL_DIR}' && repo init -u git@github.com:D-Robotics/x5-manifest.git -b main"
    fi
    sudo -u "${SUDO_USER}" bash -c "cd '${HR_LOCAL_DIR}' && repo sync" || echo "[setup] repo sync reported errors (may be safe to ignore if only x5-rdk-gen checkout failed)"

    echo "[setup] Done."
}

########################################
# kernel: Build standard + RT kernels
########################################
do_kernel() {
    echo ""
    echo "========================================="
    echo "[kernel] Building standard kernel..."
    echo "========================================="
    cd "${HR_LOCAL_DIR}"
    bash "${HR_LOCAL_DIR}/mk_kernel.sh"

    echo ""
    echo "========================================="
    echo "[kernel] Building RT kernel..."
    echo "========================================="
    bash "${HR_LOCAL_DIR}/mk_kernel_rt.sh"

    echo "[kernel] Done."
}

########################################
# bootloader: Build miniboot/uboot
########################################
do_bootloader() {
    echo ""
    echo "========================================="
    echo "[bootloader] Building bootloader..."
    echo "========================================="
    cd "${HR_LOCAL_DIR}/source/bootloader/build"
    ./xbuild.sh lunch 0
    ./xbuild.sh

    # Copy nand_disk.img to hobot-miniboot firmware directory
    local BOOTLOADER_OUT="${HR_LOCAL_DIR}/source/bootloader/out/product"
    local MINIBOOT_FW_DIR="${HR_LOCAL_DIR}/source/hobot-miniboot/debian/lib/firmware/rdk/miniboot/stable"
    if [ -f "${BOOTLOADER_OUT}/nand_disk.img" ]; then
        local DATE_TAG=$(date '+%Y%m%d')
        mkdir -p "${MINIBOOT_FW_DIR}"
        cp -f "${BOOTLOADER_OUT}/nand_disk.img" "${MINIBOOT_FW_DIR}/disk_nand_minimum_boot_${DATE_TAG}.img"
        echo "[bootloader] Copied nand_disk.img to hobot-miniboot firmware as disk_nand_minimum_boot_${DATE_TAG}.img"
    else
        echo "[bootloader] WARNING: nand_disk.img not found in ${BOOTLOADER_OUT}"
    fi

    echo "[bootloader] Done."
}

########################################
# rootfs: Build Ubuntu samplefs
########################################
do_rootfs() {
    echo ""
    echo "========================================="
    echo "[rootfs] Building Ubuntu samplefs..."
    echo "========================================="
    cd "${HR_LOCAL_DIR}/samplefs"
    bash "${HR_LOCAL_DIR}/samplefs/make_ubuntu_samplefs.sh" desktop

    # Copy samplefs to rootfs/ for pack_image.sh
    mkdir -p "${HR_LOCAL_DIR}/rootfs"
    cp -f "${HR_LOCAL_DIR}"/samplefs/desktop/samplefs_desktop_*.tar.gz "${HR_LOCAL_DIR}/rootfs/"

    # Extract samplefs to deploy/rootfs/ as sysroot for cross-compilation (hobot-spdev etc.)
    echo "[rootfs] Extracting samplefs to deploy/rootfs for sysroot..."
    local SYSROOT_DIR="${HR_LOCAL_DIR}/deploy/rootfs"
    rm -rf "${SYSROOT_DIR}"
    mkdir -p "${SYSROOT_DIR}"
    tar --same-owner --numeric-owner -xzpf "${HR_LOCAL_DIR}"/rootfs/samplefs_desktop_*.tar.gz -C "${SYSROOT_DIR}"

    echo "[rootfs] Done."
}

########################################
# debs: Build deb packages
########################################
do_debs() {
    echo ""
    echo "========================================="
    echo "[debs] Building deb packages..."
    echo "========================================="

    # Ensure sysroot (deploy/rootfs) exists - required by hobot-spdev cross-compilation
    local SYSROOT_DIR="${HR_LOCAL_DIR}/deploy/rootfs"
    if [ ! -f "${SYSROOT_DIR}/usr/include/string.h" ] && \
       [ ! -f "${SYSROOT_DIR}/usr/include/aarch64-linux-gnu/gnu/stubs.h" ]; then
        local SAMPLEFS_TAR=$(ls "${HR_LOCAL_DIR}"/rootfs/samplefs_desktop_*.tar.gz 2>/dev/null | head -1)
        if [ -z "${SAMPLEFS_TAR}" ]; then
            echo "[ERROR] deploy/rootfs sysroot not found, and no samplefs tarball in rootfs/."
            echo "        Please run './build.sh rootfs' first."
            exit 1
        fi
        echo "[debs] deploy/rootfs sysroot not found, extracting from ${SAMPLEFS_TAR}..."
        mkdir -p "${SYSROOT_DIR}"
        tar --same-owner --numeric-owner -xzpf "${SAMPLEFS_TAR}" -C "${SYSROOT_DIR}"
    fi

    cd "${HR_LOCAL_DIR}"
    bash "${HR_LOCAL_DIR}/mk_debs.sh"

    echo "[debs] Done."
}

########################################
# pack: Pack final image
########################################
do_pack() {
    echo ""
    echo "========================================="
    echo "[pack] Packing image..."
    echo "========================================="
    cd "${HR_LOCAL_DIR}"
    bash "${HR_LOCAL_DIR}/pack_image.sh" -l -c "${CONFIG_FILE}"

    # Calculate SHA256 and create zip archive
    source "${CONFIG_FILE}"
    local IMG_FILE="${HR_LOCAL_DIR}/deploy/${RDK_IMAGE_NAME}"
    if [ -f "${IMG_FILE}" ]; then
        echo "[pack] Calculating SHA256..."
        (cd "${HR_LOCAL_DIR}/deploy" && sha256sum "$(basename "${IMG_FILE}")" | tee "${IMG_FILE}.sha256")
        echo "[pack] Creating zip archive..."
        (cd "${HR_LOCAL_DIR}/deploy" && zip "$(basename "${IMG_FILE}" .img).zip" "$(basename "${IMG_FILE}")" "$(basename "${IMG_FILE}").sha256")
        echo "[pack] Zip created: ${IMG_FILE%.img}.zip"
    fi

    echo "[pack] Done."
}

########################################
# image: kernel + debs + pack
########################################
do_image() {
    do_kernel
    do_bootloader
    do_debs
    do_pack
}

########################################
# all: setup + kernel + rootfs + debs + pack
########################################
do_all() {
    do_setup
    do_kernel
    do_bootloader
    do_rootfs
    do_debs
    do_pack
}

########################################
# Execute command
########################################
echo "========================================="
echo "RDK X5 Build - Command: ${COMMAND}"
echo "Config: ${CONFIG_FILE}"
echo "========================================="

case "${COMMAND}" in
    setup)      do_setup ;;
    kernel)     do_kernel ;;
    bootloader) do_bootloader ;;
    rootfs)     do_rootfs ;;
    debs)       do_debs ;;
    pack)       do_pack ;;
    image)      do_image ;;
    all)        do_all ;;
    *)
        echo "[ERROR]: Unknown command '${COMMAND}'"
        show_help
        exit 1
        ;;
esac

echo ""
echo "========================================="
echo "Build '${COMMAND}' completed!"
echo "========================================="
echo "========================================="
