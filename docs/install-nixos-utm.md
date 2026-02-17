# UTM + NixOS 虚拟机完整安装指南

## 前置准备

### 1. 下载 NixOS ISO

```bash
cd ~/Downloads

# 下载 NixOS 25.11 ARM64 最小化版本（推荐）
curl -L -O https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-aarch64-linux.iso

# 或者下载 GNOME 桌面版本
curl -L -O https://channels.nixos.org/nixos-25.11/latest-nixos-gnome-aarch64-linux.iso
```

### 2. 验证下载

```bash
ls -lh ~/Downloads/*.iso
```

## 第一部分：在 UTM 中创建虚拟机

### 方法 1：使用 GUI（推荐新手）

1. **启动 UTM**
   ```bash
   open -a UTM
   ```

2. **创建虚拟机**
   - 点击右上角 "+" 按钮
   - 选择 "Virtualize"（虚拟化模式，性能最佳）
   - 选择 "Linux"

3. **配置参数**
   - **Boot ISO Image**: 浏览并选择下载的 ISO 文件
   - **Architecture**: ARM64 (aarch64)
   - **Memory**: 4096 MB（建议 4-8GB）
   - **CPU Cores**: 4（根据你的 Mac 配置调整）
   - **Storage**: 60 GB（建议 40-80GB）

4. **网络配置**
   - Network Mode: **Shared Network**
   - 这样 VM 可以访问互联网和宿主机

5. **其他设置**
   - 启用 "SPICE Guest Tools"（用于剪贴板共享和自动分辨率调整）
   - 启用 "Clipboard Sharing"

6. **保存**
   - 命名为 "NixOS-Dev" 或你喜欢的名字
   - 点击 "Save"

### 方法 2：导入预配置（高级）

如果你有 UTM 配置文件，可以直接导入。

## 第二部分：安装 NixOS

### 1. 启动虚拟机

在 UTM 中选择刚创建的虚拟机，点击 "Play" 按钮启动。

### 2. 进入 NixOS 安装环境

虚拟机启动后会进入 NixOS Live 环境。

### 3. 设置 root 密码（用于安装过程）

```bash
# 在 VM 终端中执行
sudo su
passwd
# 输入密码：root（或你喜欢的密码）
```

### 4. 磁盘分区

```bash
# 查看磁盘
lsblk

# 通常磁盘是 /dev/vda
# 使用 parted 进行分区
parted /dev/vda -- mklabel gpt
parted /dev/vda -- mkpart primary 512MB -8GB
parted /dev/vda -- mkpart primary linux-swap -8GB 100%
parted /dev/vda -- mkpart ESP fat32 1MB 512MB
parted /dev/vda -- set 3 esp on

# 格式化分区
mkfs.ext4 -L nixos /dev/vda1
mkswap -L swap /dev/vda2
mkfs.fat -F 32 -n boot /dev/vda3

# 挂载分区
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot
swapon /dev/vda2
```

### 5. 生成初始配置

```bash
nixos-generate-config --root /mnt
```

### 6. 编辑配置文件

```bash
nano /mnt/etc/nixos/configuration.nix
```

添加以下内容（在 `system.stateVersion` 之前）：

```nix
  # 启用 Nix Flakes
  nix.package = pkgs.nixVersions.latest;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # 启用 SSH
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitRootLogin = "yes";

  # 设置用户
  users.users.root.initialPassword = "root";
  users.users.jqwang = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    initialPassword = "jqwang";
  };

  # 允许 sudo 无密码
  security.sudo.wheelNeedsPassword = false;

  # 网络配置（UTM 使用 enp0s10）
  networking.interfaces.enp0s10.useDHCP = true;
  networking.hostName = "nixos-dev";

  # SPICE 支持（UTM 需要）
  services.spice-vdagentd.enable = true;

  # 软件渲染（M1 Mac 需要）
  environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";

  # 允许不受支持的系统
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;
```

保存并退出（Ctrl+X, Y, Enter）。

### 7. 执行安装

```bash
nixos-install --no-root-passwd
```

安装过程需要 10-30 分钟，取决于网络速度。

### 8. 重启

```bash
reboot
```

**重要**: 重启前，在 UTM 中移除 ISO 镜像：
- 点击虚拟机设置（齿轮图标）
- 找到 CD/DVD 驱动器
- 点击 "Clear" 移除 ISO

## 第三部分：使用你的 NixOS 配置

### 1. 登录虚拟机

```bash
# 用户名: jqwang
# 密码: jqwang（或你设置的密码）
```

### 2. 从宿主机复制配置到虚拟机

在 **宿主机（macOS）** 上执行：

```bash
cd /Users/jqwang/00-nixos-config/nixos-config

# 获取 VM 的 IP 地址（在 VM 中运行 `ip addr` 查看）
# 假设 VM IP 是 192.168.64.2

# 复制配置文件到 VM
rsync -av --exclude='vendor/' \
  --exclude='.git/' \
  --exclude='iso/' \
  ./ jqwang@192.168.64.2:~/nix-config/

# 或者使用 Makefile（需要设置环境变量）
NIXADDR=192.168.64.2 NIXNAME=vm-aarch64-utm make vm/copy
```

### 3. 在虚拟机中应用配置

在 **虚拟机** 中执行：

```bash
# 切换到配置目录
cd ~/nix-config

# 应用配置
sudo nixos-rebuild switch --flake ".#vm-aarch64-utm"
```

### 4. 重启虚拟机

```bash
sudo reboot
```

## 第四部分：配置 SSH 访问（可选但推荐）

### 1. 在虚拟机中查看 IP 地址

```bash
ip addr show enp0s10
# 记下 IP 地址，例如 192.168.64.2
```

### 2. 从宿主机 SSH 连接

```bash
# 在 macOS 上
ssh jqwang@192.168.64.2
```

### 3. 配置 SSH 密钥（推荐）

在 **宿主机** 上：

```bash
# 复制 SSH 公钥到 VM
ssh-copy-id jqwang@192.168.64.2

# 之后可以无密码登录
ssh jqwang@192.168.64.2
```

### 4. 配置 SSH 别名

编辑 `~/.ssh/config`：

```
Host nixos-vm
    HostName 192.168.64.2
    User jqwang
    ForwardAgent yes
```

之后可以直接使用：

```bash
ssh nixos-vm
```

## 第五部分：使用 Makefile 管理虚拟机

你的配置中已经有 Makefile，可以简化操作：

### 复制配置到 VM

```bash
cd /Users/jqwang/00-nixos-config/nixos-config

# 设置 VM 地址和名称
export NIXADDR=192.168.64.2
export NIXNAME=vm-aarch64-utm
export NIXUSER=jqwang

# 复制配置
make vm/copy

# 在 VM 中应用配置
make vm/switch
```

### 复制密钥到 VM

```bash
make vm/secrets
```

## 常见问题

### 1. 网络无法连接

检查 UTM 网络设置：
- 确保使用 "Shared Network" 模式
- 在 VM 中运行 `ip addr` 确认网卡名称
- 确认配置文件中的网卡名称匹配（通常是 `enp0s10`）

### 2. 显示分辨率问题

```bash
# 在 VM 中安装 SPICE 工具
sudo systemctl enable spice-vdagentd
sudo systemctl start spice-vdagentd
```

### 3. 剪贴板共享不工作

确保：
- UTM 设置中启用了 "Clipboard Sharing"
- SPICE 服务正在运行
- 安装了 `spice-vdagent` 包

### 4. 性能问题

- 确保使用 "Virtualize" 模式而不是 "Emulate"
- 增加分配的 CPU 核心和内存
- 启用硬件加速（如果可用）

## 下一步

安装完成后，你可以：

1. **安装桌面环境**
   - 你的配置支持 GNOME、KDE Plasma 和 i3
   - 使用 specialisation 切换桌面环境

2. **配置开发环境**
   - 你的配置已包含 Docker、Tailscale 等工具
   - 使用 home-manager 管理用户配置

3. **同步密钥和配置**
   - 使用 `make vm/secrets` 同步 GPG 和 SSH 密钥

4. **测试和开发**
   - 在虚拟机中测试 NixOS 配置
   - 使用快照功能保存状态

## 有用的命令

```bash
# 查看系统信息
nixos-version

# 更新系统
sudo nixos-rebuild switch --upgrade

# 查看配置选项
man configuration.nix

# 搜索包
nix search nixpkgs <package-name>

# 清理旧的系统版本
sudo nix-collect-garbage -d

# 查看系统日志
journalctl -xe
```

## 参考资源

- [NixOS 官方文档](https://nixos.org/manual/nixos/stable/)
- [UTM 文档](https://docs.getutm.app/)
- [你的配置仓库](file:///Users/jqwang/00-nixos-config/nixos-config)
