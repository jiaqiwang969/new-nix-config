#!/usr/bin/env bash
# 为不同的虚拟机创建特定配置文件

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 创建 vm-dev-1 配置
cat > "$SCRIPT_DIR/machines/vm-aarch64-utm-1.nix" << 'EOF'
{ config, pkgs, modulesPath, ... }: {
  imports = [
    ./hardware/vm-aarch64-utm.nix
    ./vm-shared.nix
  ];

  # Network configuration - vm-dev-1
  networking.interfaces.enp0s10 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.64.10";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.64.1";
  networking.nameservers = [ "192.168.64.1" "8.8.8.8" ];
  networking.hostName = "nixos-dev-1";

  # UTM specific
  services.spice-vdagentd.enable = true;
  environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;
}
EOF

# 创建 vm-dev-2 配置
cat > "$SCRIPT_DIR/machines/vm-aarch64-utm-2.nix" << 'EOF'
{ config, pkgs, modulesPath, ... }: {
  imports = [
    ./hardware/vm-aarch64-utm.nix
    ./vm-shared.nix
  ];

  # Network configuration - vm-dev-2
  networking.interfaces.enp0s10 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.64.11";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.64.1";
  networking.nameservers = [ "192.168.64.1" "8.8.8.8" ];
  networking.hostName = "nixos-dev-2";

  # UTM specific
  services.spice-vdagentd.enable = true;
  environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;
}
EOF

# 创建 vm-dev-3 配置
cat > "$SCRIPT_DIR/machines/vm-aarch64-utm-3.nix" << 'EOF'
{ config, pkgs, modulesPath, ... }: {
  imports = [
    ./hardware/vm-aarch64-utm.nix
    ./vm-shared.nix
  ];

  # Network configuration - vm-dev-3
  networking.interfaces.enp0s10 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.64.12";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.64.1";
  networking.nameservers = [ "192.168.64.1" "8.8.8.8" ];
  networking.hostName = "nixos-dev-3";

  # UTM specific
  services.spice-vdagentd.enable = true;
  environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;
}
EOF

echo "✓ 虚拟机配置文件已创建："
echo "  - machines/vm-aarch64-utm-1.nix (192.168.64.10)"
echo "  - machines/vm-aarch64-utm-2.nix (192.168.64.11)"
echo "  - machines/vm-aarch64-utm-3.nix (192.168.64.12)"
echo ""
echo "现在需要更新 flake.nix 以包含这些配置"
