#!/bin/bash

# 彩色输出函数
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 打印带颜色的信息
info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

error() {
    echo -e "${RED}[错误]${NC} $1" >&2
}

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    error "请使用root权限运行此脚本"
    exit 1
fi

# 检查是否为PVE环境
if [ ! -f /usr/bin/pvesh ]; then
    error "此脚本只能在Proxmox VE环境中运行"
    exit 1
fi

# 检查并安装依赖
info "检查依赖..."
missing_deps=()

for cmd in wget jq pvesh qm; do
    if ! command -v $cmd &> /dev/null; then
        missing_deps+=($cmd)
    fi
done

if [ ${#missing_deps[@]} -gt 0 ]; then
    info "正在安装缺少的依赖: ${missing_deps[*]}"
    
    # 检查包管理器
    if command -v apt &> /dev/null; then
        apt-get update
        for dep in "${missing_deps[@]}"; do
            case $dep in
                jq) apt-get install -y jq ;;
                wget) apt-get install -y wget ;;
                # 其他依赖项可能不需要安装，因为它们应该是PVE的一部分
            esac
        done
    elif command -v yum &> /dev/null; then
        for dep in "${missing_deps[@]}"; do
            case $dep in
                jq) yum install -y jq ;;
                wget) yum install -y wget ;;
            esac
        done
    else
        error "无法确定包管理器，请手动安装以下依赖: ${missing_deps[*]}"
        exit 1
    fi
    
    # 再次检查依赖是否安装成功
    for cmd in "${missing_deps[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            error "依赖 $cmd 安装失败，请手动安装后重试"
            exit 1
        fi
    done
    
    success "所有依赖已安装"
fi

# 下载主脚本
info "下载主脚本..."
wget -q -O /usr/local/bin/pve_images.sh https://raw.githubusercontent.com/Tiancaizhi9098/Proxmox-VE-Images/main/pve_images.sh

if [ $? -ne 0 ]; then
    error "下载脚本失败"
    exit 1
fi

# 设置执行权限
chmod +x /usr/local/bin/pve_images.sh

success "安装完成！"
info "运行以下命令以启动工具："
echo -e "${GREEN}pve_images.sh${NC}"

# 自动运行主脚本
echo
info "准备启动主程序..."
sleep 2
/usr/local/bin/pve_images.sh 