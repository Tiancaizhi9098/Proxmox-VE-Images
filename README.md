# Proxmox VE 系统镜像安装工具

[![license](https://img.shields.io/github/license/Tiancaizhi9098/Proxmox-VE-Images)](https://github.com/Tiancaizhi9098/Proxmox-VE-Images/blob/main/LICENSE)

这是一个自动化工具，用于在Proxmox VE平台上快速部署各种Linux系统镜像的模板虚拟机。

## 功能特点

- **自动化部署**：一键安装多种Linux发行版镜像
- **智能配置**：自动检测PVE环境的存储和网络配置
- **冲突解决**：识别并处理重复的VMID
- **用户友好**：简单的交互式菜单界面
- **灵活选择**：支持单个或批量安装镜像

## 支持的系统镜像

本工具支持以下Linux发行版镜像（按字母顺序排列）：

1. AlmaLinux 8/9
2. AlpineLinux Edge/Stable
3. CentOS 7
4. CentOS Stream 8/9/10
5. Debian 11/12
6. Rocky Linux 8/9
7. Ubuntu 18.04/20.04/22.04/24.04

所有镜像文件来源于[oneclickvirt/pve_kvm_images](https://github.com/oneclickvirt/pve_kvm_images/releases/tag/images)，为经过优化的Cloud Init镜像。

## 系统要求

- Proxmox VE 7.0+
- 至少2GB可用存储空间
- 网络连接（用于下载镜像）
- 以下软件包：
  - jq
  - wget
  - qm
  - pvesh

## 快速开始

使用以下命令一键安装并运行：

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/Tiancaizhi9098/Proxmox-VE-Images/main/install.sh)"
```

或者分步安装：

```bash
# 下载脚本
wget -O /usr/local/bin/pve_images.sh https://raw.githubusercontent.com/Tiancaizhi9098/Proxmox-VE-Images/main/pve_images.sh

# 添加执行权限
chmod +x /usr/local/bin/pve_images.sh

# 运行脚本
pve_images.sh
```

## 使用说明

1. 运行脚本后，会显示镜像选择菜单
2. 选择要安装的镜像编号（1-16）或选项（17-19）
3. 按照提示选择存储和网络桥接设备
4. 等待镜像下载和安装完成
5. 重复以上步骤安装其他镜像，或选择退出

## 镜像说明

所有安装的模板虚拟机配置如下：

- 内存：2GB
- CPU核心：2个
- 启用Cloud-Init支持
- 启用QEMU Guest Agent
- 设置开机自启
- 默认磁盘类型：virtio-scsi-pci

## 故障排除

如果遇到问题，请检查：

1. 是否使用root权限运行脚本
2. PVE环境是否正常
3. 网络连接是否可用
4. 存储空间是否充足
5. 所有依赖包是否已安装

## 卸载

本工具不会对系统进行永久性更改。如果要卸载，只需：

```bash
rm /usr/local/bin/pve_images.sh
rm -rf /tmp/images  # 删除临时文件目录
```

## 许可证

本项目采用 MIT 许可证。 