# UTM + Attic 缓存部署手册

本文档记录了从零部署 NixOS UTM 虚拟机集群 + Attic 本地二进制缓存的经验教训。

## 架构

```
macOS Host
├── vm-aarch64-utm-cache   # 缓存服务器（运行 atticd）
├── vm-aarch64-utm         # worker VM（消费缓存）
└── ...更多 worker
```

- 缓存 VM 通过 avahi mDNS 广播为 `nixos-utm-cache.local`
- Worker VM 在 `nix.settings.substituters` 中配置 `http://nixos-utm-cache.local:8080/main`
- macOS 原生支持 Bonjour/mDNS，无需额外配置即可解析 `.local`

## 关键经验

### 1. Attic Flake vs nixpkgs 内置模块

**问题**：`github:zhaofengli/attic` flake 的 attic-client 编译时使用 `-std=c++2a`（C++20），但 nix 2.31.2 的头文件用了 `std::views::zip`（C++23），导致编译失败：

```
error: 'zip' is not a member of 'std::views'
```

**解决**：不用 attic flake，改用 nixpkgs 自带的 `attic-server`、`attic-client` 和 `services.atticd` NixOS 模块。nixpkgs 的版本已经打过补丁，兼容当前 nix。

**操作**：
- `flake.nix`：删除 `attic.url = "github:zhaofengli/attic";`
- `lib/mksystem.nix`：删除 `inputs.attic.nixosModules.atticd`
- `modules/attic.nix`：保持不变（`services.atticd` 和 `pkgs.attic-client` 来自 nixpkgs）
- 运行 `nix flake lock` 自动清理 lock 文件中的 attic 相关条目

### 2. atticd 的 Token 密钥格式

**问题**：`ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64` 不是随机 base64 字符串，而是 RSA 私钥的 base64 编码。用 `openssl rand -base64 64` 生成的随机数据会导致：

```
RS256 cannot be decoded: Utf8Error(Utf8Error { valid_up_to: 0, error_len: Some(1) })
```

**正确做法**：

```bash
OPENSSL=$(which openssl)
KEY=$($OPENSSL genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 2>/dev/null | base64 -w0)
echo "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$KEY" > /var/lib/atticd/env
chmod 600 /var/lib/atticd/env
systemctl restart atticd
```

### 3. SSH Host Keys 丢失

**问题**：`nixos-rebuild switch` 如果在构建阶段失败（不是激活阶段），系统仍在旧配置上运行。但如果激活阶段部分执行了，sshd 配置可能已更新，而新的 host key 路径下没有密钥文件，导致：

```
sshd: no hostkeys available -- exiting
kex_exchange_identification: Connection closed by remote host
```

**解决**：通过 VM 控制台登录，手动生成 host keys：

```bash
ssh-keygen -A
systemctl restart sshd
```

**预防**：确保 `nixos-rebuild switch` 的构建阶段在远程执行前先在本地验证通过：

```bash
# 先在 macOS 上验证构建（cross-build 或 eval）
nix build --print-out-paths '.#nixosConfigurations."vm-aarch64-utm-cache".config.system.build.toplevel' --no-link --impure
```

### 4. VM 控制台交互（Hammerspoon + SPICE）

**问题**：UTM 的 SPICE 显示窗口不接受 `hs.eventtap.keyStrokes()` 高级输入，只接受原始键盘事件。

**解决**：使用 `~/.hammerspoon/wctl/utm.lua` 模块，通过 `hs.eventtap.event.newKeyEvent()` 发送原始 keyCode：

```lua
-- 用法
require("wctl.utm").type("vm-name", "command here")
-- 自动追加 Return 键
```

注意事项：
- `\n` 不能作为 Return 键，模块内部已处理（keyCode 36）
- 需要完整的 KEY_MAP 和 SHIFT_MAP 映射表
- 截图用 `hs.window.get(windowId):snapshot()` 而非 `hs.screen.mainScreen():snapshot()`
- UTM 有两个窗口：SPICE 显示窗口和管理窗口，要操作正确的那个

### 5. Fish Shell 兼容性

**问题**：NixOS 用户默认 shell 是 fish，通过 SSH 执行 bash 语法（`if/fi`、`&&` 链式命令）会报错：

```
fish: Missing end to balance this if statement
```

**解决**：SSH 命令用 `sudo bash -c '...'` 包裹：

```bash
ssh jqwang@192.168.64.13 "sudo bash -c 'your bash commands here'"
```

### 6. openssl 不在 PATH 中

**问题**：NixOS 的 `bash -c` 环境下 `openssl` 不在 PATH 中（它在 nix store 的某个路径下）。

**解决**：手动查找：

```bash
OPENSSL=$(nix-store -qR /run/current-system | xargs -I{} find {} -name openssl -type f 2>/dev/null | head -1)
```

### 7. SSH 认证变化

**问题**：`vm/bootstrap0` 设置 `initialPassword = "root"` 和 `PermitRootLogin = "yes"`，但 `vm/switch` 应用完整配置后：
- root 的 `initialPassword` 被 `hashedPassword` 覆盖
- `PermitRootLogin` 可能被禁用
- 只能用 `jqwang` 用户 + SSH key 登录

**注意**：`vm/bootstrap` 的 Makefile 目标用 `NIXUSER=root`，但 switch 后 root SSH 不可用。后续操作应改用：

```bash
NIXUSER=jqwang NIXADDR=192.168.64.13 make vm/copy
NIXUSER=jqwang NIXADDR=192.168.64.13 NIXNAME=vm-aarch64-utm-cache make vm/switch
```

`jqwang` 有 `security.sudo.wheelNeedsPassword = false`，所以 `sudo` 无需密码。

### 8. VM IP 地址

**问题**：桥接模式下 VM 的 IP 由 DHCP 分配，每次重启可能变化。之前用的 `198.18.0.191` 在重启后变成了 `192.168.64.13`。

**解决**：
- 部署完成后通过 mDNS 访问：`nixos-utm-cache.local`
- 或在路由器端绑定 MAC → IP
- `utmctl list` 可以确认 VM 是否在运行，但不显示 IP

## Attic 缓存管理

### 初始化

```bash
# 1. 生成 RSA 密钥并写入 env 文件
ssh jqwang@nixos-utm-cache.local "sudo bash -c '
  OPENSSL=/nix/store/.../openssl
  KEY=\$(\$OPENSSL genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 2>/dev/null | base64 -w0)
  echo ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=\$KEY > /var/lib/atticd/env
  chmod 600 /var/lib/atticd/env
  systemctl restart atticd
'"

# 2. 创建 admin token 和 cache
ssh jqwang@nixos-utm-cache.local "sudo bash -c '
  TOKEN=\$(atticd-atticadm make-token --sub admin --validity 10y \
    --pull \"*\" --push \"*\" --create-cache \"*\" --configure-cache \"*\" \
    --configure-cache-retention \"*\" --destroy-cache \"*\")
  attic login local http://localhost:8080 \$TOKEN
  attic cache create main
  attic cache configure main --public
'"

# 3. 推送所有 store paths
ssh jqwang@nixos-utm-cache.local "sudo bash -c '
  nix path-info --all | xargs attic push main
'"
```

### 当前缓存信息

- URL: `http://nixos-utm-cache.local:8080/main`
- Public Key: `main:oA4xP/b/OGxNldLb2kqO9gSu8Bzdu3mp5RXl4LwZqGA=`
- 验证: `curl -sf http://nixos-utm-cache.local:8080/main/nix-cache-info`

### Worker VM 配置

`machines/vm-shared.nix` 中已配置：

```nix
nix.settings = {
  substituters = [
    "http://nixos-utm-cache.local:8080/main"
    "https://nix-community.cachix.org"
    # ...
  ];
  trusted-public-keys = [
    "main:oA4xP/b/OGxNldLb2kqO9gSu8Bzdu3mp5RXl4LwZqGA="
    # ...
  ];
};
```

## 部署流程速查

```bash
# 1. 在 UTM 中创建 VM（桥接模式），从 ISO 启动
# 2. 控制台设置 root 密码，获取 IP
# 3. bootstrap0：分区 + 安装基础系统
make vm/bootstrap0 NIXADDR=<IP> NIXNAME=vm-aarch64-utm

# 4. UTM 中移除 ISO，从磁盘启动
# 5. bootstrap：复制配置 + switch
make vm/bootstrap NIXADDR=<IP> NIXNAME=vm-aarch64-utm

# 6. 后续更新
NIXUSER=jqwang NIXADDR=<IP> make vm/copy
NIXUSER=jqwang NIXADDR=<IP> NIXNAME=vm-aarch64-utm make vm/switch
```
