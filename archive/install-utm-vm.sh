#!/usr/bin/env bash
# UTM 虚拟机安装脚本 - 改进版
# 使用 heredoc 而不是 sed 来生成配置文件

set -e

NIXADDR="${1:-192.168.64.3}"
STATIC_IP="${2:-192.168.64.10}"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║           UTM 虚拟机安装脚本（改进版）                               ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "当前 IP: $NIXADDR"
echo "目标静态 IP: $STATIC_IP"
echo ""

# 使用 sshpass 连接
SSH_CMD="sshpass -p root ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "步骤 1: 磁盘分区..."
$SSH_CMD root@$NIXADDR "
    parted /dev/vda -- mklabel gpt
    parted /dev/vda -- mkpart primary 512MB -8GB
    parted /dev/vda -- mkpart primary linux-swap -8GB 100%
    parted /dev/vda -- mkpart ESP fat32 1MB 512MB
    parted /dev/vda -- set 3 esp on
    sleep 1
"

echo "步骤 2: 格式化分区..."
$SSH_CMD root@$NIXADDR "
    mkfs.ext4 -L nixos /dev/vda1
    mkswap -L swap /dev/vda2
    mkfs.fat -F 32 -n boot /dev/vda3
    sleep 1
"

echo "步骤 3: 挂载分区..."
$SSH_CMD root@$NIXADDR "
    mount /dev/disk/by-label/nixos /mnt
    mkdir -p /mnt/boot
    mount /dev/disk/by-label/boot /mnt/boot
    swapon /dev/vda2
"

echo "步骤 4: 生成配置..."
$SSH_CMD root@$NIXADDR "nixos-generate-config --root /mnt"

echo "步骤 5: 创建自定义配置文件..."
$SSH_CMD root@$NIXADDR "cat > /mnt/etc/nixos/configuration.nix << 'NIXEOF'
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Nix Flakes
  nix.package = pkgs.nixVersions.latest;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
  nix.settings.substituters = [\"https://mitchellh-nixos-config.cachix.org\"];
  nix.settings.trusted-public-keys = [\"mitchellh-nixos-config.cachix.org-1:bjEbXJyLrL1HZZHBbO4QALnI5faYZppzkU4D2s0G8RQ=\"];

  # Network configuration - Static IP
  networking.useDHCP = false;
  networking.interfaces.enp0s1 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = \"$STATIC_IP\";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = \"192.168.64.1\";
  networking.nameservers = [ \"192.168.64.1\" \"8.8.8.8\" ];
  networking.hostName = \"nixos-dev-1\";

  # SSH
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitRootLogin = \"yes\";

  # Users
  users.users.root.initialPassword = \"root\";
  users.users.jqwang = {
    isNormalUser = true;
    extraGroups = [ \"wheel\" \"networkmanager\" \"docker\" ];
    initialPassword = \"jqwang\";
  };

  # Sudo without password
  security.sudo.wheelNeedsPassword = false;

  # UTM specific
  services.spice-vdagentd.enable = true;
  environment.variables.LIBGL_ALWAYS_SOFTWARE = \"1\";

  # Allow unfree
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;

  # Packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
  ];

  system.stateVersion = \"25.11\";
}
NIXEOF
"

echo "步骤 6: 验证配置文件..."
$SSH_CMD root@$NIXADDR "cat /mnt/etc/nixos/configuration.nix | head -20"

echo ""
echo "步骤 7: 安装 NixOS..."
echo "这将需要 10-30 分钟..."
$SSH_CMD root@$NIXADDR "nixos-install --no-root-passwd"

echo ""
echo "✓ 安装完成！"
echo ""
echo "下一步："
echo "1. 在 UTM 中移除 ISO 镜像"
echo "2. 重启虚拟机"
echo "3. 虚拟机应该会使用 IP: $STATIC_IP"
echo ""
