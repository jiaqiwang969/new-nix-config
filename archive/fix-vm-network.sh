#!/usr/bin/env bash
# 修复虚拟机网络配置的脚本

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║           修复虚拟机网络配置                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "当前虚拟机使用 DHCP (192.168.64.2)，需要配置为静态 IP (192.168.64.10)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "方案一：在虚拟机终端中手动配置（推荐）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. 在虚拟机中登录："
echo "   用户名: jqwang"
echo "   密码: jqwang"
echo ""
echo "2. 编辑配置文件："
echo "   sudo nano /etc/nixos/configuration.nix"
echo ""
echo "3. 在 system.stateVersion 之前添加："
echo ""
cat << 'EOF'
  # 网络配置 - 静态 IP
  networking.useDHCP = false;
  networking.interfaces.enp0s1 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.64.10";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.64.1";
  networking.nameservers = [ "192.168.64.1" "8.8.8.8" ];
  networking.hostName = "nixos-dev-1";
EOF
echo ""
echo "4. 保存: Ctrl+X, Y, Enter"
echo ""
echo "5. 应用配置:"
echo "   sudo nixos-rebuild switch"
echo ""
echo "6. 重启:"
echo "   sudo reboot"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "方案二：使用 nix-config 部署（完整配置）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "如果你想直接应用完整的 nix-config 配置："
echo ""
echo "1. 先配置静态 IP（使用方案一）"
echo "2. 重启后，在 macOS 上运行："
echo "   cd /Users/jqwang/00-nixos-config/nixos-config"
echo "   make utm/bootstrap NIXADDR=192.168.64.10 NIXNAME=vm-aarch64-utm-1"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
