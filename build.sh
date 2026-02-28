#!/bin/bash
###
# RDK X5 Build Script
#
# Usage: sudo ./build.sh <command> [-c config_file]
#
# Commands:
#   setup    Install dependencies, toolchain, repo init & sync
#   kernel   Build standard + RT kernels
#   rootfs   Build Ubuntu rootfs (samplefs)
#   debs     Build deb packages
#   pack     Pack final image (debs install + image creation)
#   image    Full build: kernel + debs + pack (assumes setup done)
#   all      Everything: setup + kernel + rootfs + debs + pack
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
    echo "  setup    Install dependencies, download toolchain, repo sync"
    echo "  kernel   Build standard kernel + RT kernel"
    echo "  rootfs   Build Ubuntu rootfs (samplefs)"
    echo "  debs     Build deb packages from source"
    echo "  pack     Pack final .img image (install debs + create partitions)"
    echo "  image    Full build: kernel + debs + pack"
    echo "  all      Everything: setup + kernel + rootfs + debs + pack"
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
    sudo -u "${SUDO_USER}" bash -c "cd '${HR_LOCAL_DIR}' && repo sync"

    echo ""
    echo "========================================="
    echo "[setup] Downloading deb packages..."
    echo "========================================="
    cd "${HR_LOCAL_DIR}"
    bash "${HR_LOCAL_DIR}/download_deb_pkgs.sh" -c "${CONFIG_FILE}"

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

    echo "[pack] Done."
}

########################################
# image: kernel + debs + pack
########################################
do_image() {
    do_kernel
    do_debs
    do_pack
}

########################################
# all: setup + kernel + rootfs + debs + pack
########################################
do_all() {
    do_setup
    do_kernel
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
    setup)  do_setup ;;
    kernel) do_kernel ;;
    rootfs) do_rootfs ;;
    debs)   do_debs ;;
    pack)   do_pack ;;
    image)  do_image ;;
    all)    do_all ;;
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
