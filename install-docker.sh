#!/bin/bash

# ==============================================================================
# Interactive Docker Manager Script for Debian/Ubuntu
# 功能: 通过交互式菜单安装、卸载、修复、配置 Docker
# 作者: AI Assistant
# 版本: 3.0 (Interactive)
# ==============================================================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- 全局变量 ---
DOCKER_GPG_KEY="/etc/apt/keyrings/docker.gpg"
DOCKER_SOURCE_LIST="/etc/apt/sources.list.d/docker.list"
MIRROR_URL="https://download.docker.com/linux/debian"
OS=""
OS_VERSION=""

# --- 函数定义 ---

# 显示菜单
show_menu() {
    clear
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo -e "${BOLD}${CYAN}       Docker 交互式管理脚本 v3.0       ${NC}"
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo
    echo -e "  ${GREEN}1.${NC} 安装或更新 Docker"
    echo -e "  ${GREEN}2.${NC} 完全卸载 Docker"
    echo -e "  ${GREEN}3.${NC} 修复 Debian/Ubuntu 软件源 (解决 404 错误)"
    echo -e "  ${GREEN}4.${NC} 配置 Docker 镜像加速器"
    echo -e "  ${GREEN}5.${NC} 查看 Docker 状态"
    echo -e "  ${RED}6.${NC} 退出"
    echo
    echo -e "${CYAN}----------------------------------------${NC}"
    read -p "请输入您的选择 [1-6]: " choice
}

# 打印带颜色的消息
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 暂停并等待用户按键
pause() {
    echo
    read -p "按 Enter 键返回主菜单..." fackEnterKey
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
    elif [[ -f /etc/lsb-release ]]; then
        OS="ubuntu"
        OS_VERSION=$(lsb_release -cs)
        MIRROR_URL="https://download.docker.com/linux/ubuntu"
    else
        print_error "不支持的操作系统。"
        pause
        return 1
    fi
    print_info "检测到操作系统: $OS $OS_VERSION"
    return 0
}

# 选项 1: 安装 Docker
install_docker() {
    clear
    echo -e "${BOLD}${CYAN}--- 安装 Docker ---${NC}"
    echo
    detect_os || return

    print_info "开始安装 Docker..."
    # 1. 卸载旧版本
    print_info "检查并卸载旧版本..."
    sudo apt-get remove -y docker docker-engine docker.io containerd runc > /dev/null 2>&1

    # 2. 安装依赖
    print_info "安装必要的依赖..."
    sudo apt-get update -qq
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
    sudo apt-get update -qq
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
    echo -e "Docker 版本: $(docker --version)"
    echo -e "Docker Compose 版本: $(docker compose version)"
    pause
}

# 选项 2: 卸载 Docker
uninstall_docker() {
    clear
    echo -e "${BOLD}${CYAN}--- 卸载 Docker ---${NC}"
    echo
    print_warning "即将卸载 Docker 及其所有组件（包括镜像、容器和卷）！"
    read -p "确定要继续吗？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "停止 Docker 服务..."
        sudo systemctl stop docker > /dev/null 2>&1
        sudo systemctl disable docker > /dev/null 2>&1

        print_info "卸载 Docker 软件包..."
        sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
        sudo apt-get autoremove -y > /dev/null 2>&1

        print_info "删除 Docker 相关目录和文件..."
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd
        sudo rm -f "$DOCKER_SOURCE_LIST"
        sudo rm -f "$DOCKER_GPG_KEY"
        
        print_success "Docker 已被完全卸载。"
    else
        print_info "已取消卸载操作。"
    fi
    pause
}

# 选项 3: 修复软件源
fix_sources() {
    clear
    echo -e "${BOLD}${CYAN}--- 修复软件源 ---${NC}"
    echo
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
    else
        print_info "未发现 'bullseye/updates' 相关问题。"
    fi

    print_success "软件源修复完成。建议运行 'sudo apt update' 来更新。"
    pause
}

# 选项 4: 配置镜像加速器
configure_mirror() {
    clear
    echo -e "${BOLD}${CYAN}--- 配置镜像加速器 ---${NC}"
    echo
    echo -e "请先前往您的云服务商获取镜像加速器地址，例如："
    echo -e "  - 阿里云: https://cr.console.aliyun.com/cn-hangzhou/instances/mirrors"
    echo -e "  - 腾讯云: https://console.cloud.tencent.com/tke/accelerator"
    echo
    read -p "请输入您的镜像加速器地址: " ACCELERATOR_URL

    if [[ -z "$ACCELERATOR_URL" ]]; then
        print_error "镜像地址不能为空。"
        pause
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
    pause
}

# 选项 5: 查看状态
show_status() {
    clear
    echo -e "${BOLD}${CYAN}--- Docker 状态 ---${NC}"
    echo
    
    if command -v docker &> /dev/null; then
        echo -e "Docker 版本: ${GREEN}$(docker --version)${NC}"
        echo -e "Docker Compose 版本: ${GREEN}$(docker compose version)${NC}"
        echo
        echo -e "服务状态:"
        sudo systemctl is-active docker && echo -e "  - Docker 服务: ${GREEN}运行中${NC}" || echo -e "  - Docker 服务: ${RED}已停止${NC}"
        sudo systemctl is-enabled docker && echo -e "  - 开机自启: ${GREEN}已启用${NC}" || echo -e "  - 开机自启: ${RED}已禁用${NC}"
        echo
        echo -e "镜像列表:"
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" || echo -e "${YELLOW}无法获取镜像列表，Docker 可能未运行。${NC}"
        echo
        echo -e "容器列表:"
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo -e "${YELLOW}无法获取容器列表，Docker 可能未运行。${NC}"

    else
        print_error "Docker 未安装。"
    fi
    pause
}

# --- 主程序 ---
main() {
    check_root

    while true
    do
        show_menu
        case $choice in
            1)
                install_docker
                ;;
            2)
                uninstall_docker
                ;;
            3)
                fix_sources
                ;;
            4)
                configure_mirror
                ;;
            5)
                show_status
                ;;
            6)
                print_info "感谢使用，再见！"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 1 到 6 之间的数字。"
                pause
                ;;
        esac
    done
}

main