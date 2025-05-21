# Proxmox VE 系统镜像安装工具

[![License](https://img.shields.io/github/license/Tiancaizhi9098/Proxmox-VE-Images)](https://github.com/Tiancaizhi9098/Proxmox-VE-Images/blob/main/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Tiancaizhi9098/Proxmox-VE-Images?style=social)](https://github.com/Tiancaizhi9098/Proxmox-VE-Images/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/Tiancaizhi9098/Proxmox-VE-Images?style=social)](https://github.com/Tiancaizhi9098/Proxmox-VE-Images/network/members)

这是一个自动化工具，用于在Proxmox VE平台上快速部署各种Linux系统镜像的模板虚拟机。

## 功能特点

* **自动化部署**：一键安装多种Linux发行版镜像
* **智能配置**：自动检测PVE环境的存储和网络配置
* **冲突解决**：识别并处理重复的VMID
* **镜像完整性检查**：确保下载的镜像完好无损
* **一键清理**：可随时清理下载的镜像文件
* **用户友好**：简单的交互式菜单界面
* **灵活选择**：支持单个或批量安装镜像

## 支持的系统镜像

本工具支持以下Linux发行版镜像（按字母顺序排列）：

1. AlmaLinux 8/9
2. AlpineLinux Edge/Stable
3. CentOS 7/8-Stream/9-Stream
4. Debian 11/12
5. RockyLinux 8/9
6. Ubuntu 18.04/20.04/22.04/24.04

所有镜像文件来源于[oneclickvirt/pve_kvm_images](https://github.com/oneclickvirt/pve_kvm_images/releases/tag/images)，为经过优化的Cloud Init镜像。

## 系统要求

* Proxmox VE 7.0+
* 至少2GB可用存储空间
* 网络连接（用于下载镜像）
* Root权限

## 快速开始

使用以下命令一键安装并运行：

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/Tiancaizhi9098/Proxmox-VE-Images/main/create_pve_templates.sh)"
```

或者分步安装：

```bash
# 下载脚本
wget -O /usr/local/bin/create_pve_templates.sh https://raw.githubusercontent.com/Tiancaizhi9098/Proxmox-VE-Images/main/create_pve_templates.sh

# 添加执行权限
chmod +x /usr/local/bin/create_pve_templates.sh

# 运行脚本
create_pve_templates.sh
```

## 使用说明

1. 运行脚本后，会自动选择第一个可用的存储和网桥
2. 主菜单提供以下选项：
   - 创建单个系统模板
   - 创建全部系统模板
   - 创建单个系统虚拟机（不转换为模板）
   - 清理所有镜像文件
   - 退出
3. 选择创建单个系统模板后，可以从15种系统镜像中选择一个
4. 脚本会自动下载镜像文件（如果不存在），并检查其完整性
5. 创建完成后，即可在PVE界面中看到新建的模板或虚拟机

## 镜像说明

所有安装的模板虚拟机配置如下：

* VMID：从8000开始
* 内存：2GB
* CPU核心：2个
* 启用Cloud-Init支持
* 启用QEMU Guest Agent
* 设置开机自启
* 默认磁盘类型：virtio-scsi-pci

## 故障排除

如果遇到问题，请检查：

1. 是否使用root权限运行脚本
2. PVE环境是否正常
3. 网络连接是否可用
4. 存储空间是否充足

## 贡献

欢迎提交Issues或Pull Requests来改进此项目！

## 许可证

本项目采用 MIT 许可证。 