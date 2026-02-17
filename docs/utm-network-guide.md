# UTM 虚拟机网络配置指南

## 网络模式说明

UTM 提供多种网络模式，每种都有不同的 IP 分配方式：

### 1. Shared Network（共享网络）- 推荐

**特点：**
- ✅ 每个 VM 自动获得独立的 IP 地址
- ✅ VM 可以访问互联网
- ✅ VM 可以访问宿主机
- ✅ 宿主机可以通过 IP 访问 VM
- ⚠️ VM 之间默认可以互相访问
- ⚠️ IP 地址由 DHCP 动态分配（可能会变化）

**IP 地址范围：**
- 通常是 `192.168.64.x` 或 `192.168.65.x`
- 每个 VM 会获得不同的 IP，例如：
  - VM1: 192.168.64.2
  - VM2: 192.168.64.3
  - VM3: 192.168.64.4

**配置方法：**
在 UTM 虚拟机设置中：
- Network Mode: **Shared Network**
- 无需额外配置

### 2. Bridged Network（桥接网络）

**特点：**
- ✅ VM 获得与宿主机同一网段的 IP
- ✅ VM 在局域网中像独立设备一样
- ✅ 局域网内其他设备可以直接访问 VM
- ⚠️ 需要路由器支持
- ⚠️ 可能受到网络管理员限制

**IP 地址范围：**
- 与宿主机相同的网段，例如：
  - 宿主机: 192.168.1.100
  - VM1: 192.168.1.101
  - VM2: 192.168.1.102

**配置方法：**
在 UTM 虚拟机设置中：
- Network Mode: **Bridged (Advanced)**
- Bridge Interface: 选择你的网络接口（通常是 en0）

### 3. Host Only（仅主机）

**特点：**
- ✅ VM 只能与宿主机通信
- ✅ 完全隔离，安全性高
- ❌ VM 无法访问互联网
- ❌ 局域网内其他设备无法访问 VM

**适用场景：**
- 测试隔离环境
- 安全敏感的开发

## 为每个 VM 配置固定 IP

### 方案 1：使用 DHCP 静态映射（推荐）

在 NixOS 配置中，为每个 VM 设置不同的 MAC 地址，然后配置静态 IP：

#### 1. 在 UTM 中设置 MAC 地址

每个 VM 的设置中：
- 进入 Network 设置
- 记录或自定义 MAC 地址

#### 2. 在 NixOS 配置中设置静态 IP

编辑各个 VM 的配置文件：

**vm-aarch64-utm.nix:**
```nix
{ config, pkgs, ... }: {
  # 网络配置
  networking.hostName = "nixos-utm-1";

  # 方式 A：使用 DHCP 但设置静态 IP
  networking.interfaces.enp0s10 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.64.10";
      prefixLength = 24;
    }];
  };

  networking.defaultGateway = "192.168.64.1";
  networking.nameservers = [ "192.168.64.1" "8.8.8.8" ];
}
```

**vm-aarch64-utm-2.nix:**
```nix
{ config, pkgs, ... }: {
  networking.hostName = "nixos-utm-2";

  networking.interfaces.enp0s10 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.64.11";
      prefixLength = 24;
    }];
  };

  networking.defaultGateway = "192.168.64.1";
  networking.nameservers = [ "192.168.64.1" "8.8.8.8" ];
}
```

### 方案 2：使用 systemd-networkd

更现代的网络配置方式：

```nix
{ config, pkgs, ... }: {
  networking.useNetworkd = true;

  systemd.network = {
    enable = true;

    networks."10-lan" = {
      matchConfig.Name = "enp0s10";
      networkConfig = {
        Address = "192.168.64.10/24";
        Gateway = "192.168.64.1";
        DNS = [ "192.168.64.1" "8.8.8.8" ];
      };
    };
  };
}
```

### 方案 3：使用 DHCP 但配置主机名映射

保持 DHCP，但在宿主机上配置 SSH 别名：

**~/.ssh/config:**
```
Host nixos-vm-1
    HostName 192.168.64.10
    User jqwang
    ForwardAgent yes

Host nixos-vm-2
    HostName 192.168.64.11
    User jqwang
    ForwardAgent yes

Host nixos-vm-3
    HostName 192.168.64.12
    User jqwang
    ForwardAgent yes
```

## 多 VM 配置示例

### 创建多个 VM 配置

在你的 flake.nix 中已经有多个 VM 配置，让我们为它们分配不同的 IP：

#### 1. 创建 VM 特定的配置文件

**machines/vm-aarch64-utm-1.nix:**
```nix
{ config, pkgs, modulesPath, ... }: {
  imports = [
    ./hardware/vm-aarch64-utm.nix
    ./vm-shared.nix
  ];

  networking.hostName = "nixos-utm-1";
  networking.interfaces.enp0s10 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.64.10";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.64.1";
  networking.nameservers = [ "192.168.64.1" ];

  services.spice-vdagentd.enable = true;
  environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";
}
```

**machines/vm-aarch64-utm-2.nix:**
```nix
{ config, pkgs, modulesPath, ... }: {
  imports = [
    ./hardware/vm-aarch64-utm.nix
    ./vm-shared.nix
  ];

  networking.hostName = "nixos-utm-2";
  networking.interfaces.enp0s10 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.64.11";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.64.1";
  networking.nameservers = [ "192.168.64.1" ];

  services.spice-vdagentd.enable = true;
  environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";
}
```

#### 2. 更新 flake.nix

```nix
{
  outputs = { self, nixpkgs, home-manager, darwin, ... }@inputs: {
    # ... 其他配置 ...

    nixosConfigurations.vm-aarch64-utm-1 = mkSystem "vm-aarch64-utm-1" {
      system = "aarch64-linux";
      user   = "jqwang";
    };

    nixosConfigurations.vm-aarch64-utm-2 = mkSystem "vm-aarch64-utm-2" {
      system = "aarch64-linux";
      user   = "jqwang";
    };

    nixosConfigurations.vm-aarch64-utm-3 = mkSystem "vm-aarch64-utm-3" {
      system = "aarch64-linux";
      user   = "jqwang";
    };
  };
}
```

## 验证网络配置

### 在每个 VM 中检查 IP

```bash
# 查看 IP 地址
ip addr show enp0s10

# 测试网络连接
ping -c 3 8.8.8.8

# 测试 DNS
nslookup google.com

# 查看路由
ip route
```

### 从宿主机测试连接

```bash
# 测试 VM 1
ping 192.168.64.10
ssh jqwang@192.168.64.10

# 测试 VM 2
ping 192.168.64.11
ssh jqwang@192.168.64.11

# 测试 VM 3
ping 192.168.64.12
ssh jqwang@192.168.64.12
```

### VM 之间互相测试

在 VM 1 中：
```bash
# 测试连接到 VM 2
ping 192.168.64.11

# SSH 到 VM 2
ssh jqwang@192.168.64.11
```

## IP 地址规划建议

### 推荐的 IP 分配方案

```
网关/宿主机:     192.168.64.1
保留范围:        192.168.64.2-9   (DHCP 动态分配)
VM 静态 IP:      192.168.64.10-99 (手动分配)
  - VM 1:        192.168.64.10
  - VM 2:        192.168.64.11
  - VM 3:        192.168.64.12
  - VM 4:        192.168.64.13
  - ...
测试/临时 VM:    192.168.64.100-199
```

### 创建 IP 管理文档

**ip-assignments.md:**
```markdown
# UTM VM IP 地址分配表

| VM 名称 | 主机名 | IP 地址 | MAC 地址 | 用途 | 状态 |
|---------|--------|---------|----------|------|------|
| NixOS-Dev-1 | nixos-utm-1 | 192.168.64.10 | 52:54:00:12:34:10 | 开发环境 | 活跃 |
| NixOS-Dev-2 | nixos-utm-2 | 192.168.64.11 | 52:54:00:12:34:11 | 测试环境 | 活跃 |
| NixOS-Dev-3 | nixos-utm-3 | 192.168.64.12 | 52:54:00:12:34:12 | CI/CD | 待建 |
```

## 故障排查

### 问题 1：IP 地址冲突

**症状：** 网络连接不稳定，频繁断开

**解决：**
```bash
# 在 VM 中检查 IP 冲突
sudo arping -D -I enp0s10 192.168.64.10

# 重启网络服务
sudo systemctl restart systemd-networkd
```

### 问题 2：无法获取 IP

**症状：** VM 没有 IP 地址

**解决：**
```bash
# 检查网络接口
ip link show

# 手动启动接口
sudo ip link set enp0s10 up

# 重新获取 DHCP
sudo dhclient enp0s10
```

### 问题 3：VM 之间无法通信

**症状：** VM 可以访问互联网，但无法互相 ping 通

**解决：**
- 检查防火墙设置
- 确认使用相同的网络模式（都是 Shared Network）
- 检查 IP 地址是否在同一子网

```bash
# 在 NixOS 中临时关闭防火墙测试
sudo systemctl stop firewall

# 如果可以通信，则配置防火墙规则
```

## 高级配置

### 配置端口转发

如果需要从外部网络访问 VM：

```nix
# 在 vm-shared.nix 中
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 80 443 8080 ];
  allowedUDPPorts = [ 53 ];
};
```

### 配置 mDNS（Avahi）

使用主机名而不是 IP 地址访问：

```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;
  publish = {
    enable = true;
    addresses = true;
    domain = true;
    hinfo = true;
    userServices = true;
    workstation = true;
  };
};
```

之后可以使用：
```bash
ssh jqwang@nixos-utm-1.local
```

## 总结

**推荐配置：**
1. 使用 Shared Network 模式
2. 为每个 VM 配置静态 IP（192.168.64.10+）
3. 在宿主机配置 SSH 别名
4. 使用 Avahi/mDNS 实现主机名访问
5. 维护 IP 分配文档

这样每个 VM 都有独立且固定的 IP 地址，便于管理和访问。
