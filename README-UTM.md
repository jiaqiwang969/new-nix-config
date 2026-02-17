# NixOS Config - UTM 虚拟机管理

这是一个用于管理 UTM 虚拟机的 NixOS 配置仓库。

## 📁 目录结构

```
nixos-config/
├── docs/                    # 文档
│   ├── UTM-BRIDGED-MODE.txt    # 桥接模式安装指南（推荐）
│   ├── install-nixos-utm.md    # 详细安装文档
│   └── utm-network-guide.md    # 网络配置指南
├── scripts/                 # 脚本工具
│   └── manage-vms.sh           # 虚拟机管理脚本
├── machines/                # 虚拟机配置
│   ├── vm-aarch64-utm.nix      # 默认 UTM 配置
│   ├── vm-aarch64-utm-1.nix    # VM 1 配置
│   ├── vm-aarch64-utm-2.nix    # VM 2 配置
│   └── vm-aarch64-utm-3.nix    # VM 3 配置
├── users/                   # 用户配置
│   └── jqwang/
│       ├── home-manager.nix    # Home Manager 配置
│       ├── darwin.nix          # macOS 配置
│       └── nixos.nix           # NixOS 用户配置
├── Makefile                 # 主 Makefile
├── Makefile.utm             # UTM 专用 Makefile
├── flake.nix                # Nix Flake 配置
└── vm-inventory.json        # 虚拟机清单

## 🚀 快速开始

### 1. 创建 UTM 虚拟机（桥接模式）

在 UTM 中：
- 点击 "+" → "Virtualize" → "Linux"
- Boot ISO: `/Users/jqwang/00-nixos-config/nixos-image/nixos-latest.iso`
- Memory: 4096 MB, CPU: 4 cores, Storage: 60 GB
- **Network: Bridged (Advanced)** - 选择你的网卡
- 保存并启动

### 2. 安装 NixOS

在虚拟机中设置 root 密码：
```bash
sudo su
passwd  # 输入: root
```

查看虚拟机 IP：
```bash
ip addr
```

在 macOS 上运行安装：
```bash
cd /Users/jqwang/00-nixos-config/nixos-config

# 第一阶段：安装基础系统
make utm/bootstrap0 NIXADDR=<虚拟机IP> NIXNAME=vm-aarch64-utm-1

# 移除 ISO 并重启虚拟机

# 第二阶段：应用完整配置
make utm/bootstrap NIXADDR=<虚拟机IP> NIXNAME=vm-aarch64-utm-1
```

### 3. 管理虚拟机

```bash
# 查看所有虚拟机
./scripts/manage-vms.sh list

# 检查状态
./scripts/manage-vms.sh status

# SSH 连接
./scripts/manage-vms.sh ssh vm-dev-1

# 部署配置
./scripts/manage-vms.sh deploy vm-dev-1
```

## 📚 文档

- **[桥接模式安装指南](docs/UTM-BRIDGED-MODE.txt)** - 推荐的安装方式
- **[详细安装文档](docs/install-nixos-utm.md)** - 完整的安装步骤
- **[网络配置指南](docs/utm-network-guide.md)** - 网络配置说明

## 🔧 配置说明

### 网络模式

所有虚拟机配置使用**桥接模式 + DHCP**：
- 虚拟机像局域网中的真实机器
- IP 由路由器 DHCP 分配
- 更稳定，SSH 连接更可靠

### 虚拟机配置

- `vm-aarch64-utm.nix` - 默认配置
- `vm-aarch64-utm-1.nix` - 开发环境 1
- `vm-aarch64-utm-2.nix` - 开发环境 2
- `vm-aarch64-utm-3.nix` - 开发环境 3

所有配置包含：
- Docker 虚拟化
- Tailscale VPN
- 中文输入法 (fcitx5)
- 桌面环境 (GNOME/KDE/i3)
- 开发工具包

## 🛠️ Makefile 命令

### UTM 虚拟机

```bash
# 第一阶段：安装基础系统
make utm/bootstrap0 NIXADDR=<IP> NIXNAME=<配置名>

# 第二阶段：应用完整配置
make utm/bootstrap NIXADDR=<IP> NIXNAME=<配置名>

# 一键安装（交互式）
make utm/bootstrap-all NIXADDR=<IP> NIXNAME=<配置名>
```

### 通用命令

```bash
# 复制配置到虚拟机
make vm/copy NIXADDR=<IP> NIXNAME=<配置名>

# 应用配置
make vm/switch NIXADDR=<IP> NIXNAME=<配置名>

# 复制密钥
make vm/secrets NIXADDR=<IP>
```

### macOS (nix-darwin)

```bash
# 应用 macOS 配置
make switch NIXNAME=macbook-pro-m1
```

## 📝 注意事项

1. **桥接模式**：推荐使用桥接模式，比共享网络更稳定
2. **DHCP**：使用 DHCP 自动获取 IP，避免手动配置静态 IP
3. **SSH 密钥**：第二阶段会自动配置 SSH 公钥认证
4. **固定 IP**：如需固定 IP，在路由器端配置 DHCP 保留

## 🔍 故障排查

### SSH 连接问题

如果 SSH 连接失败：
1. 检查虚拟机 IP：`ip addr`
2. 测试网络：`ping 223.5.5.5`
3. 检查 SSH 服务：`sudo systemctl status sshd`
4. 重置密码：`sudo passwd jqwang`

### 网络问题

如果虚拟机无网络：
1. 确认使用桥接模式
2. 检查网络接口：`ip link show`
3. 重启网络：`sudo systemctl restart systemd-networkd`

## 📦 相关文件

- `flake.nix` - Nix Flake 配置
- `Makefile` - 主 Makefile
- `Makefile.utm` - UTM 专用命令
- `vm-inventory.json` - 虚拟机清单

## 🎯 下一步

1. 阅读 [桥接模式安装指南](docs/UTM-BRIDGED-MODE.txt)
2. 创建第一个虚拟机
3. 根据需要创建更多虚拟机

---

**提示**：所有旧的脚本和文档已归档到 `archive/` 目录。
