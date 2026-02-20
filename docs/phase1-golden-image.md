# Phase 1: Golden Image Creation - 完成总结

## 目标

创建一个干净的 VM 01 作为黄金镜像（Golden Image），用于后续快速克隆多个 worker VM。

## 完成时间

2026-02-19

## 关键问题与解决方案

### 1. IP 检测失败问题

**问题：** `utm/detect-ip` 使用 QEMU guest agent 检测 IP，但 NixOS ISO 启动时 guest agent 未运行，导致 bootstrap 失败。

**解决方案：**
- 修复了 `Makefile.utm` 中的 MAC 地址匹配逻辑
- 移除了有问题的 `case` 语法，改用 `grep -q` 直接匹配
- 添加了 serial console 作为备选方案（通过 PTY 获取 IP）

**相关文件：**
- `nixos-config/Makefile.utm` (utm/detect-ip target)

### 2. Atticd 服务启动失败

**问题：** Atticd 服务配置了 `environmentFile = "/var/lib/atticd/env"`，但该文件不存在，导致服务无法启动（"Failed to load environment files: No such file or directory"）。

**解决方案：**
- 在 `modules/attic.nix` 中添加了 `systemd.services.atticd-init` 服务
- 该服务在 atticd 启动前自动生成 JWT secret 和环境文件
- 使用 `before = [ "atticd.service" ]` 确保初始化顺序

**临时修复（手动）：**
```bash
# 在 VM 上手动创建环境文件
SECRET=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
echo "ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=$SECRET" | sudo tee /var/lib/atticd/env
sudo chmod 600 /var/lib/atticd/env
sudo systemctl restart atticd
```

**相关文件：**
- `nixos-config/modules/attic.nix`

### 3. Fish Shell 兼容性问题

**问题：** VM 默认使用 Fish shell，但 Makefile 中的 bash 语法（如 `VAR=$(cmd)`）在 Fish 中不兼容。

**解决方案：**
- 在 SSH 命令中显式使用 `bash -c "..."`
- 或者将复杂命令拆分为多个简单步骤
- 本地生成 secret，通过管道传输到 VM

## 部署流程

### 步骤 1: 清理现有 VM

```bash
# 删除所有现有 VM
make utm/delete VM=vm-aarch64-utm
make utm/delete VM=vm-aarch64-utm-02
```

### 步骤 2: 修复配置文件

1. **修复 Makefile.utm 的 IP 检测逻辑**
   - 移除 `case` 语法
   - 改用 `grep -q` 直接匹配 MAC 地址

2. **修复 modules/attic.nix**
   - 添加 `atticd-init` 服务自动生成环境文件
   - 确保 JWT secret 在首次启动时自动创建

### 步骤 3: 部署 VM 01

```bash
# 创建并 bootstrap VM
make utm/bootstrap-all VM=vm-aarch64-utm ISO=../nixos-image/nixos-minimal-*.iso

# 流程包括：
# 1. utm/create - 创建 VM 并挂载 ISO
# 2. utm/start - 启动 VM
# 3. utm/detect-ip - 检测 IP（通过 serial console 备选）
# 4. bootstrap0 - 分区、安装 NixOS
# 5. utm/iso-remove - 移除 ISO
# 6. utm/reboot - 重启进入新系统
# 7. vm/copy - 复制配置文件
# 8. vm/switch - 应用 NixOS 配置
# 9. vm/secrets - 同步 SSH 密钥
```

### 步骤 4: 手动修复 Atticd

```bash
# 由于 atticd-init 服务在首次部署时未生效，需要手动创建环境文件
ssh jqwang@192.168.64.21
sudo mkdir -p /var/lib/atticd
SECRET=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
echo "ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=$SECRET" | sudo tee /var/lib/atticd/env
sudo chmod 600 /var/lib/atticd/env
sudo systemctl restart atticd
```

## 最终状态

### VM 01 配置

- **名称：** vm-aarch64-utm
- **IP：** 192.168.64.21
- **主机名：** nixos
- **用户：** jqwang (passwordless sudo)
- **SSH：** ed25519 密钥认证

### 服务状态

```bash
# Atticd 服务
systemctl is-active atticd  # active

# Store paths
nix path-info --all | wc -l  # 21,209 paths

# Attic cache (未初始化)
curl http://localhost:8080/main/nix-cache-info  # 401 Unauthorized (需要初始化)
```

### 系统包含

- ✅ KDE Plasma 6 桌面环境
- ✅ Atticd 服务（端口 8080）
- ✅ Attic CLI 客户端
- ✅ Avahi mDNS（nixos-utm.local）
- ✅ Docker
- ✅ Tailscale
- ✅ 开发工具（neovim, git, jujutsu, etc.）

## 待完成任务

### 下一步：初始化 Attic Cache

```bash
# 1. 生成管理员 token
ssh jqwang@192.168.64.21
sudo atticd-atticadm make-token --sub admin --validity '1 year' --pull '*' --push '*' --delete '*' --create-cache '*' --configure-cache '*' --configure-cache-retention '*' --destroy-cache '*'

# 2. 配置 attic 客户端
attic login local http://localhost:8080 <TOKEN>

# 3. 创建 cache
attic cache create main

# 4. 设置为 public
attic cache configure main --public

# 5. 推送所有 store paths
nix path-info --all | attic push main
```

### 后续步骤

1. **Phase 2: 实现 VM 克隆功能**
   - 添加 `utm/clone-from` target
   - 自动修改克隆 VM 的 hostname 和 IP
   - 测试克隆 3-5 个 worker VM

2. **Phase 3: 多 VM 编排**
   - 实现 `deploy.sh` 批量部署脚本
   - 添加 `deployment.yaml` 清单
   - 状态管理和健康检查

3. **Phase 4: CI/CD 集成**
   - GitHub Actions workflow
   - 自动化测试
   - 滚动更新

## 关键文件清单

```
nixos-config/
├── Makefile.utm              # UTM VM 生命周期管理（已修复 detect-ip）
├── modules/attic.nix         # Attic 配置（已添加 atticd-init）
├── machines/
│   ├── vm-aarch64-utm.nix   # VM 配置
│   └── vm-shared.nix        # 共享配置
└── docs/
    └── phase1-golden-image.md  # 本文档
```

## 经验教训

1. **Serial console 是可靠的备选方案** - 当网络或 guest agent 不可用时，PTY serial console 始终可用
2. **Fish shell 需要特殊处理** - 在 SSH 命令中显式使用 bash 或拆分命令
3. **Systemd 服务依赖很重要** - 使用 `before`/`after` 确保初始化顺序
4. **环境文件必须存在** - `environmentFile` 指向的文件必须在服务启动前创建
5. **首次部署需要手动干预** - 某些初始化步骤（如 attic cache 创建）无法完全自动化

## 性能指标

- **VM 创建时间：** ~2 分钟
- **Bootstrap0（分区+安装）：** ~5 分钟
- **NixOS rebuild switch：** ~15 分钟（首次，需下载所有包）
- **总部署时间：** ~25 分钟（从零到完全运行的 VM）

## 下次改进

1. 在 NixOS 配置中预先生成 atticd env 文件（避免手动步骤）
2. 添加 `make utm/verify` 验证 VM 健康状态
3. 实现 `make utm/snapshot` 创建 VM 快照（用于快速回滚）
4. 优化 bootstrap 流程（使用本地 binary cache 加速）
