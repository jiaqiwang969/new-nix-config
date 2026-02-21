# NixOS 系统配置

我的 NixOS / nix-darwin 统一配置仓库。使用 Nix Flakes 管理 macOS 主机和 OrbStack NixOS 容器的开发环境。

## 架构

```
macOS (nix-darwin)          OrbStack NixOS (LXC 容器)
┌─────────────────┐         ┌──────────────────────┐
│ macbook-pro-m1  │         │  vm-aarch64-orb       │
│ Homebrew + Nix  │  ←───→  │  终端开发环境          │
│ GUI 应用        │ 文件共享  │  git/nvim/jj/claude   │
└─────────────────┘ /mnt/mac └──────────────────────┘
```

- macOS 端通过 nix-darwin 管理 Homebrew、shell 配置、系统设置
- OrbStack NixOS 容器作为 Linux 开发环境，共享 macOS 文件系统（`/mnt/mac/`）
- home-manager 统一管理两端的用户配置（shell、编辑器、git 等）

## 快速开始

### macOS

```bash
# 首次安装 nix-darwin 后
make switch NIXNAME=macbook-pro-m1
```

### OrbStack NixOS

```bash
# 1. 创建容器
orb create nixos:25.11 nixos-dev

# 2. 在容器内 apply 配置
orb -m nixos-dev -u root bash -c \
  'cd /mnt/mac/Users/jqwang/00-nixos-config/nixos-config && \
   NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 \
   nixos-rebuild switch --impure --flake ".#vm-aarch64-orb"'

# 3. 进入开发环境
orb -m nixos-dev
# 或 SSH
ssh jqwang@nixos-dev@orb
```

## 目录结构

```
.
├── flake.nix                    # Flake 入口，定义所有系统配置
├── Makefile                     # 常用命令（switch/test/cache/bootstrap）
├── lib/mksystem.nix             # 系统构建函数
├── machines/
│   ├── macbook-pro-m1.nix       # macOS nix-darwin 配置
│   ├── vm-aarch64-orb.nix       # OrbStack NixOS 容器配置
│   ├── vm-shared.nix            # Linux VM 共享配置
│   ├── vm-aarch64.nix           # VMware Fusion aarch64
│   ├── vm-aarch64-prl.nix       # Parallels aarch64
│   ├── vm-intel.nix             # x86_64 VM
│   ├── wsl.nix                  # WSL 配置
│   └── hardware/                # 硬件配置
├── modules/
│   ├── attic.nix                # Attic 二进制缓存
│   └── specialization/          # GUI 桌面环境（Plasma/i3/GNOME）
└── users/jqwang/
    ├── home-manager.nix         # home-manager 主配置
    ├── nixos.nix                # NixOS 用户配置
    ├── darwin.nix               # macOS 用户配置
    ├── config.fish              # Fish shell 配置
    └── ...                      # 其他 dotfiles
```

## 常用命令

```bash
make switch NIXNAME=macbook-pro-m1    # macOS 切换配置
make switch NIXNAME=vm-aarch64-orb    # NixOS 切换配置（需在容器内执行）
make test NIXNAME=<name>              # 测试配置（不激活）
make wsl                              # 构建 WSL 根文件系统
```

## 致谢

本仓库 fork 自 [mitchellh/nixos-config](https://github.com/mitchellh/nixos-config)，在此基础上做了大量定制。

## License

MIT
