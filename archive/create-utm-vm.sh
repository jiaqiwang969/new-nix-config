#!/usr/bin/env bash
# UTM NixOS 虚拟机创建脚本

set -e

# 配置变量
VM_NAME="NixOS-Dev"
ISO_PATH="$HOME/00-nixos-config/nixos-image/nixos-latest.iso"
DISK_SIZE="60"  # GB
MEMORY="4096"   # MB
CPU_CORES="4"

echo "=== UTM NixOS 虚拟机创建指南 ==="
echo ""
echo "配置信息："
echo "  虚拟机名称: $VM_NAME"
echo "  ISO 路径: $ISO_PATH"
echo "  磁盘大小: ${DISK_SIZE}GB"
echo "  内存: ${MEMORY}MB"
echo "  CPU 核心: $CPU_CORES"
echo ""

# 检查 ISO 是否存在
if [ ! -f "$ISO_PATH" ]; then
    echo "❌ 错误: ISO 文件不存在: $ISO_PATH"
    echo ""
    echo "请先下载 NixOS ISO："
    echo "  cd ~/Downloads"
    echo "  curl -L -O https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-aarch64-linux.iso"
    exit 1
fi

echo "✅ ISO 文件已找到"
echo ""
echo "请按照以下步骤在 UTM 中创建虚拟机："
echo ""
echo "1. 打开 UTM 应用"
echo "   open -a UTM"
echo ""
echo "2. 点击 '+' 创建新虚拟机"
echo ""
echo "3. 选择 'Virtualize' (虚拟化)"
echo ""
echo "4. 选择 'Linux'"
echo ""
echo "5. 配置虚拟机："
echo "   - Boot ISO: $ISO_PATH"
echo "   - Memory: ${MEMORY} MB"
echo "   - CPU Cores: $CPU_CORES"
echo "   - Storage: ${DISK_SIZE} GB"
echo ""
echo "6. 网络设置："
echo "   - Network Mode: Shared Network"
echo ""
echo "7. 保存并启动虚拟机"
echo ""
echo "虚拟机启动后，继续执行 NixOS 安装步骤。"
