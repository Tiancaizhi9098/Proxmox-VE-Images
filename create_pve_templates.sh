#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 检测脚本是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
   echo -e "${RED}错误: 此脚本必须以root权限运行${NC}" >&2
   exit 1
fi

# 获取可用存储
get_storages() {
    # 使用pvesm命令获取所有存储
    pvesm status | grep -v "Name\|------" | awk '{print $1}'
}

# 获取可用网桥
get_bridges() {
    # 列出所有网桥
    ip link show type bridge | grep -o "vmbr[0-9]*" || echo "vmbr0"
}

# 检查命令是否可用
check_command() {
    command -v "$1" >/dev/null 2>&1 || { 
        echo -e "${RED}错误: 需要 $1 但未安装.${NC}" >&2
        return 1
    }
    return 0
}

# 检查镜像完整性
check_image_integrity() {
    local image_file="$1"
    
    echo -e "${BLUE}正在检查镜像完整性: $image_file...${NC}"
    
    # 检查文件是否存在
    if [ ! -f "$image_file" ]; then
        echo -e "${RED}错误: 镜像文件不存在${NC}"
        return 1
    fi
    
    # 检查文件大小是否为0
    local file_size=$(stat -c %s "$image_file" 2>/dev/null || stat -f %z "$image_file")
    if [ "$file_size" -eq 0 ]; then
        echo -e "${RED}错误: 镜像文件大小为0${NC}"
        return 1
    fi
    
    # 尝试使用qemu-img检查镜像
    if command -v qemu-img >/dev/null 2>&1; then
        if ! qemu-img check "$image_file" >/dev/null 2>&1; then
            echo -e "${RED}错误: 镜像完整性检查失败${NC}"
            return 1
        fi
    else
        # 如果没有qemu-img，至少检查文件大小是否合理（>10MB）
        if [ "$file_size" -lt 10485760 ]; then
            echo -e "${YELLOW}警告: 镜像文件较小，可能不完整${NC}"
            read -p "是否继续? (y/n): " continue_choice
            if [[ $continue_choice != [yY] ]]; then
                return 1
            fi
        fi
    fi
    
    echo -e "${GREEN}镜像完整性检查通过${NC}"
    return 0
}

# 下载镜像
download_image() {
    local image_url="$1"
    local image_name="$2"
    
    if [ -f "$image_name" ]; then
        echo -e "${YELLOW}文件 $image_name 已存在，检查完整性...${NC}"
        if ! check_image_integrity "$image_name"; then
            echo -e "${YELLOW}现有镜像不完整，将重新下载${NC}"
            rm -f "$image_name"
        else
            return 0
        fi
    fi
    
    echo -e "${BLUE}正在下载 $image_name...${NC}"
    if ! wget -q --show-progress "$image_url" -O "$image_name"; then
        echo -e "${RED}下载 $image_name 失败${NC}"
        return 1
    fi
    
    # 检查下载的镜像完整性
    if ! check_image_integrity "$image_name"; then
        echo -e "${RED}下载的镜像不完整，中止操作${NC}"
        rm -f "$image_name"
        return 1
    fi
    
    echo -e "${GREEN}下载 $image_name 完成${NC}"
    return 0
}

# 清理所有镜像
cleanup_all_images() {
    echo -e "${BLUE}准备清理所有镜像文件...${NC}"
    
    local count=0
    for system in "${!images[@]}"; do
        if [[ $system == *"_name" ]]; then
            local image_file="${images[$system]}"
            if [ -f "$image_file" ]; then
                echo -e "${YELLOW}删除: $image_file${NC}"
                rm -f "$image_file"
                count=$((count+1))
            fi
        fi
    done
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}未找到任何镜像文件${NC}"
    else
        echo -e "${GREEN}成功清理 $count 个镜像文件${NC}"
    fi
}

# 创建VM模板
create_vm_template() {
    local vm_id="$1"
    local vm_name="$2"
    local image_file="$3"
    local storage="$4"
    local bridge="$5"
    local mem="$6"
    local cores="$7"
    local convert_to_template="${8:-yes}"  # 默认转换为模板
    
    # 检查VM ID是否已经存在
    if qm status $vm_id >/dev/null 2>&1; then
        echo -e "${YELLOW}VM ID $vm_id 已存在${NC}"
        read -p "是否停止并删除现有虚拟机? (y/n): " confirm
        if [[ $confirm == [yY] ]]; then
            echo -e "${BLUE}正在停止虚拟机 $vm_id...${NC}"
            qm stop $vm_id || true
            echo -e "${BLUE}正在删除虚拟机 $vm_id...${NC}"
            qm destroy $vm_id || { 
                echo -e "${RED}删除虚拟机失败，中止操作${NC}"
                return 1
            }
            echo -e "${GREEN}已删除现有虚拟机 $vm_id${NC}"
        else
            echo -e "${RED}操作已取消${NC}"
            return 1
        fi
    fi

    echo -e "${BLUE}正在创建 $vm_name 模板 (ID: $vm_id)...${NC}"
    
    # 创建VM
    qm create $vm_id --name "$vm_name" --onboot 1 --memory $mem --cores $cores --net0 "virtio,bridge=$bridge"
    
    # 导入磁盘
    qm importdisk $vm_id "$image_file" "$storage"
    
    # 获取导入后的磁盘信息
    local disk_info=$(qm config $vm_id | grep -E "unused[0-9]+:" | head -1)
    if [ -z "$disk_info" ]; then
        echo -e "${RED}错误: 无法找到导入的磁盘${NC}"
        return 1
    fi
    
    # 提取磁盘路径
    local disk_path=$(echo $disk_info | awk '{print $2}' | sed -e "s/'//g")
    echo -e "${BLUE}导入的磁盘路径: $disk_path${NC}"
    
    # 配置VM - 使用磁盘完整路径
    qm set $vm_id --scsihw virtio-scsi-pci
    qm set $vm_id --scsi0 "$disk_path"
    qm set $vm_id --boot c --bootdisk scsi0
    qm set $vm_id --ide2 "$storage:cloudinit"
    qm set $vm_id --serial0 socket --vga serial0
    qm set $vm_id --agent enabled=1
    
    # 转换为模板（如果需要）
    if [[ $convert_to_template == "yes" ]]; then
        qm template $vm_id
        echo -e "${GREEN}$vm_name 模板 (ID: $vm_id) 创建完成${NC}"
    else
        echo -e "${GREEN}$vm_name 虚拟机 (ID: $vm_id) 创建完成${NC}"
    fi
    
    return 0
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}         PVE 模板创建工具         ${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${YELLOW}1)${NC} 创建单个系统模板"
    echo -e "${YELLOW}2)${NC} 创建全部系统模板"
    echo -e "${YELLOW}3)${NC} 创建单个系统虚拟机（不转换为模板）"
    echo -e "${YELLOW}4)${NC} 清理所有镜像文件"
    echo -e "${YELLOW}5)${NC} 退出"
    echo -e "${BLUE}===========================================${NC}"
    echo -n "请输入选项 [1-5]: "
}

# 显示系统选择菜单
show_system_menu() {
    clear
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}         系统镜像选择         ${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${YELLOW}1)${NC} AlmaLinux 9"
    echo -e "${YELLOW}2)${NC} AlmaLinux 8"
    echo -e "${YELLOW}3)${NC} Alpine Linux Edge"
    echo -e "${YELLOW}4)${NC} Alpine Linux Stable"
    echo -e "${YELLOW}5)${NC} CentOS 9 Stream"
    echo -e "${YELLOW}6)${NC} CentOS 8 Stream"
    echo -e "${YELLOW}7)${NC} CentOS 7"
    echo -e "${YELLOW}8)${NC} Debian 12"
    echo -e "${YELLOW}9)${NC} Debian 11"
    echo -e "${YELLOW}10)${NC} RockyLinux 9"
    echo -e "${YELLOW}11)${NC} RockyLinux 8"
    echo -e "${YELLOW}12)${NC} Ubuntu 24.04"
    echo -e "${YELLOW}13)${NC} Ubuntu 22.04"
    echo -e "${YELLOW}14)${NC} Ubuntu 20.04"
    echo -e "${YELLOW}15)${NC} Ubuntu 18.04"
    echo -e "${YELLOW}16)${NC} 返回主菜单"
    echo -e "${BLUE}===========================================${NC}"
    echo -n "请输入选项 [1-16]: "
}

# 镜像信息列表
declare -A images=(
    ["almalinux9_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/almalinux9.qcow2"
    ["almalinux9_name"]="almalinux9.qcow2"
    ["almalinux9_vmname"]="AlmaLinux-9"
    ["almalinux9_id"]="8000"
    
    ["almalinux8_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/almalinux8.qcow2"
    ["almalinux8_name"]="almalinux8.qcow2"
    ["almalinux8_vmname"]="AlmaLinux-8"
    ["almalinux8_id"]="8001"
    
    ["alpinelinux_edge_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/alpinelinux_edge.qcow2"
    ["alpinelinux_edge_name"]="alpinelinux_edge.qcow2"
    ["alpinelinux_edge_vmname"]="Alpine-Linux-Edge"
    ["alpinelinux_edge_id"]="8002"
    
    ["alpinelinux_stable_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/alpinelinux_stable.qcow2"
    ["alpinelinux_stable_name"]="alpinelinux_stable.qcow2"
    ["alpinelinux_stable_vmname"]="Alpine-Linux-Stable"
    ["alpinelinux_stable_id"]="8003"
    
    ["centos9_stream_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos9-stream.qcow2"
    ["centos9_stream_name"]="centos9-stream.qcow2"
    ["centos9_stream_vmname"]="CentOS-9-Stream"
    ["centos9_stream_id"]="8004"
    
    ["centos8_stream_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos8-stream.qcow2"
    ["centos8_stream_name"]="centos8-stream.qcow2"
    ["centos8_stream_vmname"]="CentOS-8-Stream"
    ["centos8_stream_id"]="8005"
    
    ["centos7_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/centos7.qcow2"
    ["centos7_name"]="centos7.qcow2"
    ["centos7_vmname"]="CentOS-7"
    ["centos7_id"]="8006"
    
    ["debian12_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/debian12.qcow2"
    ["debian12_name"]="debian12.qcow2"
    ["debian12_vmname"]="Debian-12"
    ["debian12_id"]="8007"
    
    ["debian11_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/debian11.qcow2"
    ["debian11_name"]="debian11.qcow2"
    ["debian11_vmname"]="Debian-11"
    ["debian11_id"]="8008"
    
    ["rockylinux9_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/rockylinux9.qcow2"
    ["rockylinux9_name"]="rockylinux9.qcow2"
    ["rockylinux9_vmname"]="RockyLinux-9"
    ["rockylinux9_id"]="8009"
    
    ["rockylinux8_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/rockylinux8.qcow2"
    ["rockylinux8_name"]="rockylinux8.qcow2"
    ["rockylinux8_vmname"]="RockyLinux-8"
    ["rockylinux8_id"]="8010"
    
    ["ubuntu24_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu24.qcow2"
    ["ubuntu24_name"]="ubuntu24.qcow2"
    ["ubuntu24_vmname"]="Ubuntu-24.04"
    ["ubuntu24_id"]="8011"
    
    ["ubuntu22_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu22.qcow2"
    ["ubuntu22_name"]="ubuntu22.qcow2"
    ["ubuntu22_vmname"]="Ubuntu-22.04"
    ["ubuntu22_id"]="8012"
    
    ["ubuntu20_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu20.qcow2"
    ["ubuntu20_name"]="ubuntu20.qcow2"
    ["ubuntu20_vmname"]="Ubuntu-20.04"
    ["ubuntu20_id"]="8013"
    
    ["ubuntu18_url"]="https://github.com/oneclickvirt/pve_kvm_images/releases/download/images/ubuntu18.qcow2"
    ["ubuntu18_name"]="ubuntu18.qcow2"
    ["ubuntu18_vmname"]="Ubuntu-18.04"
    ["ubuntu18_id"]="8014"
)

# 检查必要的命令
check_dependencies() {
    local failed=0
    
    for cmd in qm pvesm wget ip; do
        if ! check_command "$cmd"; then
            failed=1
        fi
    done
    
    if [ $failed -eq 1 ]; then
        echo -e "${RED}请安装缺少的依赖后再运行此脚本${NC}"
        exit 1
    fi
}

# 创建单个系统模板
create_single_template() {
    local system="$1"
    local convert_to_template="${2:-yes}"  # 默认转换为模板
    local url="${images[${system}_url]}"
    local name="${images[${system}_name]}"
    local vmname="${images[${system}_vmname]}"
    local id="${images[${system}_id]}"
    
    # 设置默认内存和CPU核心数
    local mem=2048
    local cores=2
    
    # 下载镜像
    if ! download_image "$url" "$name"; then
        return 1
    fi
    
    # 创建模板
    if ! create_vm_template "$id" "$vmname" "$name" "$selected_storage" "$selected_bridge" "$mem" "$cores" "$convert_to_template"; then
        return 1
    fi
    
    return 0
}

# 主程序
main() {
    # 检查依赖
    check_dependencies
    
    # 获取可用存储
    local storages=($(get_storages))
    if [ ${#storages[@]} -eq 0 ]; then
        echo -e "${RED}错误: 未找到可用存储${NC}"
        exit 1
    fi
    
    # 获取可用网桥
    local bridges=($(get_bridges))
    if [ ${#bridges[@]} -eq 0 ]; then
        echo -e "${RED}错误: 未找到可用网桥${NC}"
        exit 1
    fi
    
    # 默认选择第一个存储和网桥
    selected_storage=${storages[0]}
    selected_bridge=${bridges[0]}
    
    echo -e "${GREEN}已选择存储: $selected_storage${NC}"
    echo -e "${GREEN}已选择网桥: $selected_bridge${NC}"
    echo -e "${YELLOW}是否要手动选择存储和网桥? (y/n，默认: n): ${NC}"
    read -p "" manual_select
    
    if [[ $manual_select == [yY] ]]; then
        # 选择存储
        echo -e "${BLUE}可用存储:${NC}"
        for i in "${!storages[@]}"; do
            echo -e "${YELLOW}$((i+1))${NC}) ${storages[$i]}"
        done
        
        while true; do
            read -p "请选择存储 [1-${#storages[@]}]: " storage_choice
            if [[ "$storage_choice" =~ ^[0-9]+$ && "$storage_choice" -ge 1 && "$storage_choice" -le "${#storages[@]}" ]]; then
                selected_storage=${storages[$((storage_choice-1))]}
                break
            fi
            echo -e "${RED}无效选择，请重试${NC}"
        done
        
        echo -e "${GREEN}已选择存储: $selected_storage${NC}"
        
        # 选择网桥
        echo -e "${BLUE}可用网桥:${NC}"
        for i in "${!bridges[@]}"; do
            echo -e "${YELLOW}$((i+1))${NC}) ${bridges[$i]}"
        done
        
        while true; do
            read -p "请选择网桥 [1-${#bridges[@]}]: " bridge_choice
            if [[ "$bridge_choice" =~ ^[0-9]+$ && "$bridge_choice" -ge 1 && "$bridge_choice" -le "${#bridges[@]}" ]]; then
                selected_bridge=${bridges[$((bridge_choice-1))]}
                break
            fi
            echo -e "${RED}无效选择，请重试${NC}"
        done
        
        echo -e "${GREEN}已选择网桥: $selected_bridge${NC}"
    fi
    
    # 主菜单循环
    while true; do
        show_main_menu
        read choice
        
        case $choice in
            1)
                # 显示系统菜单
                while true; do
                    show_system_menu
                    read system_choice
                    
                    case $system_choice in
                        1) create_single_template "almalinux9"; read -p "按Enter继续..." ;;
                        2) create_single_template "almalinux8"; read -p "按Enter继续..." ;;
                        3) create_single_template "alpinelinux_edge"; read -p "按Enter继续..." ;;
                        4) create_single_template "alpinelinux_stable"; read -p "按Enter继续..." ;;
                        5) create_single_template "centos9_stream"; read -p "按Enter继续..." ;;
                        6) create_single_template "centos8_stream"; read -p "按Enter继续..." ;;
                        7) create_single_template "centos7"; read -p "按Enter继续..." ;;
                        8) create_single_template "debian12"; read -p "按Enter继续..." ;;
                        9) create_single_template "debian11"; read -p "按Enter继续..." ;;
                        10) create_single_template "rockylinux9"; read -p "按Enter继续..." ;;
                        11) create_single_template "rockylinux8"; read -p "按Enter继续..." ;;
                        12) create_single_template "ubuntu24"; read -p "按Enter继续..." ;;
                        13) create_single_template "ubuntu22"; read -p "按Enter继续..." ;;
                        14) create_single_template "ubuntu20"; read -p "按Enter继续..." ;;
                        15) create_single_template "ubuntu18"; read -p "按Enter继续..." ;;
                        16) break ;;
                        *) echo -e "${RED}无效选择，请重试${NC}" ;;
                    esac
                done
                ;;
            2)
                echo -e "${BLUE}开始创建所有系统模板...${NC}"
                
                systems=("almalinux9" "almalinux8" "alpinelinux_edge" "alpinelinux_stable" "centos9_stream" "centos8_stream" "centos7" "debian12" "debian11" "rockylinux9" "rockylinux8" "ubuntu24" "ubuntu22" "ubuntu20" "ubuntu18")
                
                for system in "${systems[@]}"; do
                    create_single_template "$system"
                done
                
                echo -e "${GREEN}所有系统模板创建完成${NC}"
                read -p "按Enter继续..."
                ;;
            3)
                # 显示系统菜单 - 创建虚拟机而不是模板
                while true; do
                    show_system_menu
                    read system_choice
                    
                    case $system_choice in
                        1) create_single_template "almalinux9" "no"; read -p "按Enter继续..." ;;
                        2) create_single_template "almalinux8" "no"; read -p "按Enter继续..." ;;
                        3) create_single_template "alpinelinux_edge" "no"; read -p "按Enter继续..." ;;
                        4) create_single_template "alpinelinux_stable" "no"; read -p "按Enter继续..." ;;
                        5) create_single_template "centos9_stream" "no"; read -p "按Enter继续..." ;;
                        6) create_single_template "centos8_stream" "no"; read -p "按Enter继续..." ;;
                        7) create_single_template "centos7" "no"; read -p "按Enter继续..." ;;
                        8) create_single_template "debian12" "no"; read -p "按Enter继续..." ;;
                        9) create_single_template "debian11" "no"; read -p "按Enter继续..." ;;
                        10) create_single_template "rockylinux9" "no"; read -p "按Enter继续..." ;;
                        11) create_single_template "rockylinux8" "no"; read -p "按Enter继续..." ;;
                        12) create_single_template "ubuntu24" "no"; read -p "按Enter继续..." ;;
                        13) create_single_template "ubuntu22" "no"; read -p "按Enter继续..." ;;
                        14) create_single_template "ubuntu20" "no"; read -p "按Enter继续..." ;;
                        15) create_single_template "ubuntu18" "no"; read -p "按Enter继续..." ;;
                        16) break ;;
                        *) echo -e "${RED}无效选择，请重试${NC}" ;;
                    esac
                done
                ;;
            4)
                cleanup_all_images
                read -p "按Enter继续..."
                ;;
            5)
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重试${NC}"
                ;;
        esac
    done
}

# 执行主程序
main 