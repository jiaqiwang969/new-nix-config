#!/usr/bin/env bash
# 虚拟机安装后的验证和配置脚本

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║           虚拟机安装后验证脚本                                        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

VM_IP="192.168.64.13"
VM_NAME="vm-dev-1"
VM_USER="jqwang"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第一步：测试网络连接"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "测试 ping 连接..."
if ping -c 3 -W 2 $VM_IP &> /dev/null; then
    print_status 0 "虚拟机 $VM_IP 可以 ping 通"
else
    print_status 1 "虚拟机 $VM_IP 无法 ping 通"
    echo ""
    echo -e "${YELLOW}提示：${NC}"
    echo "  1. 确认虚拟机已启动"
    echo "  2. 确认虚拟机网络配置正确"
    echo "  3. 在虚拟机中运行: ip addr show enp0s10"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第二步：测试 SSH 连接"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "测试 SSH 连接..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "echo 'SSH connection successful'" &> /dev/null; then
    print_status 0 "SSH 连接成功"
else
    print_status 1 "SSH 连接失败"
    echo ""
    echo -e "${YELLOW}提示：${NC}"
    echo "  1. 确认 SSH 服务已启动: systemctl status sshd"
    echo "  2. 确认防火墙允许 SSH: sudo firewall-cmd --list-all"
    echo "  3. 尝试手动连接: ssh $VM_USER@$VM_IP"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第三步：获取虚拟机信息"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "获取系统信息..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@$VM_IP << 'ENDSSH'
echo "主机名: $(hostname)"
echo "NixOS 版本: $(nixos-version)"
echo "内核版本: $(uname -r)"
echo "IP 地址: $(ip -4 addr show enp0s10 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
echo "内存: $(free -h | awk '/^Mem:/ {print $2}')"
echo "磁盘: $(df -h / | awk 'NR==2 {print $2}')"
ENDSSH

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第四步：配置 SSH 密钥（可选）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "是否配置 SSH 密钥以实现无密码登录？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "配置 SSH 密钥..."
    if [ -f ~/.ssh/id_rsa.pub ] || [ -f ~/.ssh/id_ed25519.pub ]; then
        ssh-copy-id -o StrictHostKeyChecking=no $VM_USER@$VM_IP
        print_status $? "SSH 密钥已配置"
    else
        echo -e "${YELLOW}未找到 SSH 密钥，正在生成...${NC}"
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
        ssh-copy-id -o StrictHostKeyChecking=no $VM_USER@$VM_IP
        print_status $? "SSH 密钥已生成并配置"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第五步：生成 SSH 配置"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "是否生成 SSH 配置文件？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd /Users/jqwang/00-nixos-config/nixos-config
    ./manage-vms.sh generate-ssh-config
    print_status $? "SSH 配置已生成"

    echo ""
    echo "现在可以使用以下命令连接："
    echo "  ssh $VM_NAME"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "第六步：部署 NixOS 配置"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "是否立即部署 NixOS 配置？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd /Users/jqwang/00-nixos-config/nixos-config
    echo "开始部署配置..."
    ./manage-vms.sh deploy $VM_NAME
    print_status $? "配置部署完成"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                     验证完成！                                        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "虚拟机信息："
echo "  名称: $VM_NAME"
echo "  IP: $VM_IP"
echo "  用户: $VM_USER"
echo ""
echo "常用命令："
echo "  连接虚拟机: ssh $VM_USER@$VM_IP"
echo "  或使用别名: ssh $VM_NAME"
echo "  部署配置: ./manage-vms.sh deploy $VM_NAME"
echo "  查看状态: ./manage-vms.sh status"
echo ""
