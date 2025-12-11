#!/bin/bash

# ==============================================================================
# Docker Manager Script for Debian/Ubuntu
# 功能: 安装、卸载、修复软件源、配置 Docker
# 作者: AI Assistant (基于 KYKY548 的脚本优化)
# 版本: 2.0
# ==============================================================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 全局变量 ---
DOCKER_GPG_KEY="/etc/apt/keyrings/docker.gpg"
DOCKER_SOURCE_LIST="/etc/apt/sources.list.d/docker.list"
MIRROR_URL="https://download.docker.com/linux/debian"

# --- 函数定义 ---

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本必须以 root 权限运行。请使用 'sudo $0'"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/debian_version ]]; then
        OS="debian"
        OS_VERSION=$(lsb_release -cs)
        print_info "检测到操作系统: $OS $OS_VERSION"
    elif [[ -f /etc/lsb-release ]]; then
        OS="ubuntu"
        OS_VERSION=$(lsb_release -cs)
        print_info "检测到操作系统: $OS $OS_VERSION"
        MIRROR_URL="https://download.docker.com/linux/ubuntu"
    else
        print_error "不支持的操作系统。"
        exit 1
    fi
}

# 修复 Debian 11 常见的软件源问题
fix_sources() {
    print_info "开始修复 Debian/Ubuntu 软件源..."
    SOURCES_LIST="/etc/apt/sources.list"

    if [[ ! -f "$SOURCES_LIST.bak" ]]; then
        sudo cp "$SOURCES_LIST" "$SOURCES_LIST.bak"
        print_info "已备份原始软件源文件到 $SOURCES_LIST.bak"
    fi

    # 修复 security.debian.org 的 bullseye/updates -> bullseye-security
    if grep -q "bullseye/updates" "$SOURCES_LIST"; then
        print_warning "发现过时的安全更新仓库 (bullseye/updates)，正在修复..."
        sudo sed -i 's|bullseye/updates|bullseye-security|g' "$SOURCES_LIST"
        print_success "已将 bullseye/updates 替换为 bullseye-security"
    fi

    # 确保 backports 仓库格式正确 (Debian 11)
    if grep -q "bullseye-backports" "$SOURCES_LIST"; then
        # 检查是否是错误格式，例如没有正确的路径
        if ! grep -q "http://deb.debian.org/debian bullseye-backports" "$SOURCES_LIST"; then
             print_warning "发现可能不正确的 backports 仓库，正在修正..."
             sudo sed -i '/bullseye-backports/d' "$SOURCES_LIST"
             echo "deb http://deb.debian.org/debian bullseye-backports main contrib non-free" | sudo tee -a "$SOURCES_LIST"
             print_success "已修正 backports 仓库格式"
        fi
    fi

    print_success "软件源修复完成。请运行 'sudo apt update' 来更新。"
}

# 安装 Docker
install_docker() {
    print_info "开始安装 Docker..."

    # 1. 卸载旧版本
    print_info "检查并卸载旧版本 Docker..."
    sudo apt-get remove -y docker docker-engine docker.io containerd runc > /dev/null 2>&1

    # 2. 安装依赖
    print_info "安装必要的依赖..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release

    # 3. 添加 GPG 密钥
    print_info "添加 Docker 官方 GPG 密钥..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL "$MIRROR_URL/gpg" | sudo gpg --dearmor -o "$DOCKER_GPG_KEY"
    sudo chmod a+r "$DOCKER_GPG_KEY"

    # 4. 添加软件源
    print_info "添加 Docker 官方软件源..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_GPG_KEY] $MIRROR_URL \
      $OS_VERSION stable" | sudo tee "$DOCKER_SOURCE_LIST" > /dev/null

    # 5. 安装 Docker Engine
    print_info "从官方源安装 Docker Engine..."
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # 6. 启动并设置开机自启
    print_info "启动 Docker 服务..."
    sudo systemctl start docker
    sudo systemctl enable docker

    # 7. 将当前用户加入 docker 组
    CURRENT_USER=${SUDO_USER:-$USER}
    if id "$CURRENT_USER" &>/dev/null; then
        print_info "将用户 '$CURRENT_USER' 添加到 docker 组..."
        sudo usermod -aG docker "$CURRENT_USER"
        print_warning "请注销并重新登录，或运行 'newgrp docker' 以使组权限生效。"
    fi

    print_success "Docker 安装完成！"
    docker --version
    docker compose version
}

# 卸载 Docker
uninstall_docker() {
    print_warning "即将卸载 Docker 及其所有组件！"
    read -p "确定要继续吗？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "停止 Docker 服务..."
        sudo systemctl stop docker
        sudo systemctl disable docker

        print_info "卸载 Docker 软件包..."
        sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo apt-get autoremove -y

        print_info "删除 Docker 相关目录和文件..."
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd
        sudo rm -f "$DOCKER_SOURCE_LIST"
        sudo rm -f "$DOCKER_GPG_KEY"
        
        print_success "Docker 已被完全卸载。"
    else
        print_info "已取消卸载操作。"
    fi
}

# 配置镜像加速器
configure_mirror() {
    print_info "配置 Docker 镜像加速器..."
    read -p "请输入您的镜像加速器地址 (例如: https://xxx.mirror.aliyuncs.com): " ACCELERATOR_URL

    if [[ -z "$ACCELERATOR_URL" ]]; then
        print_error "镜像地址不能为空。"
        return 1
    fi

    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "$ACCELERATOR_URL"
  ]
}
EOF

    print_info "重启 Docker 服务以应用配置..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker

    print_success "镜像加速器配置成功！"
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  install         安装或更新 Docker"
    echo "  uninstall       完全卸载 Docker"
    echo "  fix-sources     修复 Debian 11 常见的软件源错误"
    echo "  configure-mirror 配置 Docker 镜像加速器"
    echo "  help            显示此帮助信息"
}

# --- 主程序 ---
main() {
    check_root
    detect_os

    case "${1:-help}" in
        "install")
            install_docker
            ;;
        "uninstall")
            uninstall_docker
            ;;
        "fix-sources")
            fix_sources
            ;;
        "configure-mirror")
            configure_mirror
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

main "$@"