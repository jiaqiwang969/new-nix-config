# NixOS / macOS Configurations

极简部署指南。

## 常用命令

### 1. 部署本机 Mac
直接应用当前仓库的配置到宿主机 (M4):
```bash
make macbook-pro-m4
```

### 2. 初始化缓存与开发节点 (nixos-dev)
创建/更新 `nixos-dev`，启动内部 Attic 缓存服务，并自动将整个 Nix Store 推送至 cache 中：
```bash
make orb-cache
```
*提示：该命令是**完全幂等且安全**的，即使系统已经部署好也可以随时多次运行。它在底层会自动处理以下细节：*
- **容器复用**：如果 `nixos-dev` 已经存在，则保持原样，不会破坏或重建。
- **配置热更**：执行 `nixos-rebuild switch`，如果没有改动则会在 1-2 秒内完成（空跑）；若有改动则只构建更新部分。
- **缓存鉴权**：系统会检查 `/var/lib/atticd/env` 秘钥是否存在，若存在则跳过初始化，保护已有缓存数据。随后自动配置并激活 `main` 缓存的公共访问权限（`Configured "main" on "local"`）。
- **增量推送**：执行 `attic push` 时会自动查询服务端 hash，已经存在的包会被秒跳过，只将**新增的编译产物**同步到缓存中，实现极速增量推送。

### 3. 部署 Agent 节点
通过上述缓存节点加速，极速部署出新的 Agent 容器环境：
```bash
make orb-agent/01
make orb-agent/02
# 依此类推...
```
*架构细节与状态打通：* 
基于我们核心的 `orb-agent-base.nix`，为了确保这些 Agent 能和外网的代理及主机的上下文联动，容器被专门做了如下处理：
- **挂载 `.codex` 上下文**：启动时自动将容器内 `~/.codex` 软链接挂载到宿主机（Mac）的 `~/.codex`。使得所有跑在容器里的 Agent 能立刻拥有和宿主机完全同步的 API 秘钥、技能文件（skills）以及历史记忆流。
- **打通 `8317` 代理端口**：由于你的本地 CLIProxyAPI（API代理）运行在宿主的 `8317` 端口上，Agent 内会自动利用 `socat` 后台服务将容器里的 `localhost:8317` 反向透传到宿主机的 `host.internal:8317`，保证在全封闭容器环境内的模型请求也能经过统一的 API 网关。

## 依赖锁定 (Freeze)

更新所有 Flake 依赖并锁定版本（Freeze）：
```bash
nix flake update
```
*提示：Nix 默认依靠 `flake.lock` 来冻结 (freeze) 依赖版本，确保无论在哪台机器上构建，都会使用完全一致的依赖包。*

## 开发与重构经验 (Lessons Learned)

在将构建流程精简化的过程中，我们遇到了几个底层坑，特此记录以防后人踩坑：

1. **OrbStack 的嵌套 SSH 死锁**
   - **坑**：最初我们在 Makefile 中的容器构建脚本 (`orb -m nixos-agent ...`) 里，再次内嵌调用了 `orb -m nixos-dev bash -c ...` 来动态获取缓存节点的 IP。这导致了底层 Unix Socket (`@->@`) 发生“Connection reset by peer”以及 SSH 代理套接字崩溃死锁，容器直接坏死。
   - **解法**：绝不能让 `orb` 命令行嵌套调用。必须在 Mac 宿主机的 Makefile 顶层解析出 `DEV_IP=$(orb -m nixos-dev ...)`，然后将其作为普通字符串变量，喂给后续独立启动的构建容器。

2. **复杂的 Bash 单/双引号逃逸 (Quoting Hell)**
   - **坑**：在使用 `bash -c "..."` 传递多行配置脚本，且脚本内部还包含 `"`、`$` 及正则过滤符号时，Makefile 的解析和 Bash 展开发生了错乱，导致容器内执行到了类似 `sed: unknown command: "` 的语法错误。
   - **解法**：放弃在长命令参数中做字符串拼接。Makefile 改为通过 `echo` 和单引号（`echo '...'`）将逻辑写到宿主机的一个临时脚本文本（`.tmp_cache_script.sh`）中，然后使用 `cat script.sh | orb -m xxx bash` 以标准输入的方式喂给容器，杜绝了一切转义异常。

3. **Nix Flake 的 Git Tracked 盲区**
   - **坑**：重命名 NixOS 目标或添加新的 `.nix` 配置后（如 `nixos-agent-01.nix`），如果直接运行 `nixos-rebuild`，会报 `does not provide attribute...` 找不到该目标的错误。
   - **解法**：当项目根目录是一个 Git 仓库时，Nix **严格只对已经被 Git Tracked (暂存或提交) 的文件进行求值**。必须先 `git add flake.nix machines/*.nix` 才能让 Nix 看见这些新增的配置。
