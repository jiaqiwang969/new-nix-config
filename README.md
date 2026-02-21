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


## 愿景与测试哲学：沙盒定格与极速环境复刻

基于 NixOS + OrbStack + Attic 的缓存闭环，我们构建了一套极速的计算节点分发机制。

**核心思想：**
> “我打算把软件关进 VM 小屋里面。一旦它出错，就立刻‘时间定格’。从这个节点里 clone 出一整套完全相同的场景，然后在克隆体里修复错误。修复验证成功后，通过 undo 机制替换掉出错那一刻的‘定格’，然后继续运行。如果还能修复，就继续；如果不能，则重复这个过程。”

**架构实现与速度优化：**
1. **全局主节点 (`nixos-dev`) 缓存预热**：
   - 使用 `nixos-dev` 作为主控开发环境与第一节点。它内置了 **Attic 二进制缓存服务**。
   - 通过 `make cache/push`，主节点构建出的所有系统镜像包会被推送至本地网络的 Attic 仓库中。
2. **`?shallow=1` 浅克隆求值与 `--fast` 极速部署**：
   - 我们的 `flake.nix` 对依赖的远端仓库开启了浅克隆（shallow fetch），去除了克隆完整 Git 历史的巨大网络开销，将 Nix 的“求值阶段”耗时降到了毫秒级别。
   - `Makefile` 的部署动作加入了 `--fast` 参数，跳过繁琐的系统依赖检查。
3. **Agent 节点的无网秒级弹出**：
   - 当需要复刻当前环境（或创建一个新的测试舱）时，我们只需通过 `orb create nixos:unstable nixos-agent-xx` 拉起一个极轻量的空壳。
   - 在部署过程中，Agent 节点通过动态探针（Dynamic Cache Probing）自动感知到局域网的 Attic 缓存，**直接屏蔽 `cache.nixos.org` 的外网干扰**。
   - 一套包含了 Neovim、Git、Fish 及各类开发工具链的完整系统，能够在 **1分钟以内** 纯局域网拉取完毕并瞬间复原出和主控机一模一样的生产环境。

这套机制让我们能够放肆地进行危险的破坏性实验、复杂的多节点分布式网络调试以及系统级 BUG 追踪，随时“快照备份”，随时“平行克隆”。

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
