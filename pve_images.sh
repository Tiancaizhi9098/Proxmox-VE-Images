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
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "请使用root权限运行此脚本"
        exit 1
    fi
}

# 检查是否为PVE环境
check_pve() {
    if [ ! -f /usr/bin/pvesh ]; then
        error "此脚本只能在Proxmox VE环境中运行"
        exit 1
    fi
}

# 创建临时目录
create_temp_dir() {
    mkdir -p /tmp/images
    if [ $? -ne 0 ]; then
        error "无法创建临时目录: /tmp/images"
        exit 1
    fi
}

# 获取所有可用存储
get_storages() {
    local storages
    storages=$(pvesh get /storage --output-format=json | jq -r '.[] | select(.active==1 and .content | contains("images")) | .storage')
    
    if [ -z "$storages" ]; then
        # 如果没有包含images的存储，尝试获取包含vm的存储
        storages=$(pvesh get /storage --output-format=json | jq -r '.[] | select(.active==1 and .content | contains("vm") or .content | contains("images")) | .storage')
    fi
    
    if [ -z "$storages" ]; then
        # 如果仍然没有找到合适的存储，获取所有活跃的存储
        storages=$(pvesh get /storage --output-format=json | jq -r '.[] | select(.active==1) | .storage')
    fi
    
    echo "$storages"
}

# 获取所有可用网卡
get_bridges() {
    pvesh get /nodes/$(hostname)/network --output-format=json | jq -r '.[] | select(.type=="bridge" and .active==1) | .iface'
}

# 检查并处理重复的VMID
check_vmid() {
    local vmid=$1
    if qm status $vmid &>/dev/null; then
        warning "VMID $vmid 已存在"
        read -p "是否停止并删除此VM? (y/n): " confirm
        if [[ $confirm == [yY] ]]; then
            info "正在停止VMID $vmid..."
            qm stop $vmid --timeout 60 &>/dev/null
            info "正在删除VMID $vmid..."
            qm destroy $vmid &>/dev/null
            success "VMID $vmid 已被删除"
            return 0
        else
            return 1
        fi
    fi
    return 0
}

# 下载镜像
download_image() {
    local image_url=$1
    local filename=$2
    
    info "正在下载 $filename..."
    wget -q --show-progress -O "/tmp/images/$filename" "$image_url"
    
    if [ $? -ne 0 ]; then
        error "下载 $filename 失败"
        return 1
    fi
    
    success "成功下载 $filename"
    return 0
}

# 获取下一个可用的VMID
get_next_vmid() {
    pvesh get /cluster/nextid
}

# 安装镜像
install_image() {
    local image_name=$1
    local image_url=$2
    local filename=$3
    local vmid=$(get_next_vmid)
    
    # 检查VMID是否可用
    if ! check_vmid $vmid; then
        warning "跳过安装 $image_name"
        return
    fi
    
    # 选择存储
    local storages=$(get_storages)
    if [ -z "$storages" ]; then
        error "找不到可用的存储"
        return
    fi
    
    PS3="请选择存储: "
    select storage in $storages; do
        if [ -n "$storage" ]; then
            break
        else
            echo "无效选择，请重试"
        fi
    done
    
    # 选择网络桥接
    local bridges=$(get_bridges)
    if [ -z "$bridges" ]; then
        error "找不到可用的网络桥接"
        return
    fi
    
    PS3="请选择网络桥接: "
    select bridge in $bridges; do
        if [ -n "$bridge" ]; then
            break
        else
            echo "无效选择，请重试"
        fi
    done
    
    # 下载镜像
    if ! download_image "$image_url" "$filename"; then
        return
    fi
    
    # 创建VM
    info "创建虚拟机 VMID $vmid ($image_name)..."
    qm create $vmid --name "$image_name" --onboot 1 --memory 2048 --cores 2 --net0 virtio,bridge=$bridge
    
    # 导入磁盘
    info "导入磁盘镜像..."
    qm importdisk $vmid "/tmp/images/$filename" $storage
    
    # 配置虚拟机
    info "配置虚拟机..."
    qm set $vmid --scsihw virtio-scsi-pci --scsi0 $storage:vm-$vmid-disk-0
    qm set $vmid --boot c --bootdisk scsi0
    qm set $vmid --ide2 $storage:cloudinit
    qm set $vmid --serial0 socket --vga serial0
    qm set $vmid --agent enabled=1
    
    success "虚拟机 $image_name (VMID: $vmid) 创建完成"
}

# 清理临时文件
cleanup() {
    info "正在清理临时文件..."
    rm -rf /tmp/images
    success "清理完成"
}

# 安装所有镜像
install_all() {
    # 按字母顺序安装所有镜像
    for i in {1..16}; do
        case $i in
            1) install_image "AlmaLinux-8" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/almalinux8.qcow2" "almalinux8.qcow2" ;;
            2) install_image "AlmaLinux-9" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/almalinux9.qcow2" "almalinux9.qcow2" ;;
            3) install_image "AlpineLinux-Edge" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/alpinelinux_edge.qcow2" "alpinelinux_edge.qcow2" ;;
            4) install_image "AlpineLinux-Stable" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/alpinelinux_stable.qcow2" "alpinelinux_stable.qcow2" ;;
            5) install_image "CentOS-7" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos7.qcow2" "centos7.qcow2" ;;
            6) install_image "CentOS-Stream-8" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos8-stream.qcow2" "centos8-stream.qcow2" ;;
            7) install_image "CentOS-Stream-9" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos9-stream.qcow2" "centos9-stream.qcow2" ;;
            8) install_image "CentOS-Stream-10" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos10-stream.qcow2" "centos10-stream.qcow2" ;;
            9) install_image "Debian-11" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/debian11.qcow2" "debian11.qcow2" ;;
            10) install_image "Debian-12" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/debian12.qcow2" "debian12.qcow2" ;;
            11) install_image "Rocky-8" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/rockylinux8.qcow2" "rockylinux8.qcow2" ;;
            12) install_image "Rocky-9" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/rockylinux9.qcow2" "rockylinux9.qcow2" ;;
            13) install_image "Ubuntu-18.04" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu18.qcow2" "ubuntu18.qcow2" ;;
            14) install_image "Ubuntu-20.04" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu20.qcow2" "ubuntu20.qcow2" ;;
            15) install_image "Ubuntu-22.04" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu22.qcow2" "ubuntu22.qcow2" ;;
            16) install_image "Ubuntu-24.04" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu24.qcow2" "ubuntu24.qcow2" ;;
        esac
    done
}

# 显示主菜单
show_menu() {
    clear
    echo "============================================"
    echo "       Proxmox VE 系统镜像安装工具       "
    echo "============================================"
    echo "  1. AlmaLinux-8"
    echo "  2. AlmaLinux-9"
    echo "  3. AlpineLinux-Edge"
    echo "  4. AlpineLinux-Stable"
    echo "  5. CentOS-7"
    echo "  6. CentOS-Stream-8"
    echo "  7. CentOS-Stream-9"
    echo "  8. CentOS-Stream-10"
    echo "  9. Debian-11"
    echo " 10. Debian-12"
    echo " 11. Rocky-8"
    echo " 12. Rocky-9"
    echo " 13. Ubuntu-18.04"
    echo " 14. Ubuntu-20.04"
    echo " 15. Ubuntu-22.04"
    echo " 16. Ubuntu-24.04"
    echo "--------------------------------------------"
    echo " 17. 一键安装所有镜像"
    echo " 18. 清理临时文件"
    echo " 19. 退出"
    echo "============================================"
    read -p "请选择操作 [1-19]: " choice
    
    case $choice in
        1) install_image "AlmaLinux-8" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/almalinux8.qcow2" "almalinux8.qcow2" ;;
        2) install_image "AlmaLinux-9" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/almalinux9.qcow2" "almalinux9.qcow2" ;;
        3) install_image "AlpineLinux-Edge" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/alpinelinux_edge.qcow2" "alpinelinux_edge.qcow2" ;;
        4) install_image "AlpineLinux-Stable" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/alpinelinux_stable.qcow2" "alpinelinux_stable.qcow2" ;;
        5) install_image "CentOS-7" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos7.qcow2" "centos7.qcow2" ;;
        6) install_image "CentOS-Stream-8" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos8-stream.qcow2" "centos8-stream.qcow2" ;;
        7) install_image "CentOS-Stream-9" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos9-stream.qcow2" "centos9-stream.qcow2" ;;
        8) install_image "CentOS-Stream-10" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos10-stream.qcow2" "centos10-stream.qcow2" ;;
        9) install_image "Debian-11" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/debian11.qcow2" "debian11.qcow2" ;;
        10) install_image "Debian-12" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/debian12.qcow2" "debian12.qcow2" ;;
        11) install_image "Rocky-8" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/rockylinux8.qcow2" "rockylinux8.qcow2" ;;
        12) install_image "Rocky-9" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/rockylinux9.qcow2" "rockylinux9.qcow2" ;;
        13) install_image "Ubuntu-18.04" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu18.qcow2" "ubuntu18.qcow2" ;;
        14) install_image "Ubuntu-20.04" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu20.qcow2" "ubuntu20.qcow2" ;;
        15) install_image "Ubuntu-22.04" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu22.qcow2" "ubuntu22.qcow2" ;;
        16) install_image "Ubuntu-24.04" "https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu24.qcow2" "ubuntu24.qcow2" ;;
        17) install_all ;;
        18) cleanup ;;
        19) exit 0 ;;
        *) error "无效选择，请重试" ;;
    esac
    
    read -p "按Enter键继续..."
    show_menu
}

# 主函数
main() {
    check_root
    check_pve
    create_temp_dir
    show_menu
}

# 执行主函数
main 