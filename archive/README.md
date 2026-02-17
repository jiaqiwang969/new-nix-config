# 归档说明

这个目录包含了开发过程中创建的旧脚本和文档，已被新的简化版本替代。

## 📋 归档内容

### 文档
- `GETTING-STARTED.txt` - 旧的入门指南
- `READY-TO-START.txt` - 旧的准备指南
- `UTM-BOOTSTRAP-GUIDE.txt` - 旧的 bootstrap 指南
- `UTM-CORRECT-FLOW.txt` - 流程说明（已整合）
- `SSH-TROUBLESHOOT.txt` - SSH 故障排查（已整合）
- `VM-CHECK-RESULT.txt` - 检查结果示例

### 脚本
- `create-utm-vm.sh` - 创建虚拟机辅助脚本
- `create-vm-configs.sh` - 生成配置文件脚本
- `fix-vm-network.sh` - 网络修复脚本
- `install-cheatsheet.sh` - 安装速查卡
- `install-utm-vm.sh` - 安装脚本（改进版）
- `quick-start.sh` - 快速开始脚本
- `verify-vm.sh` - 验证脚本

## ✅ 当前推荐使用

### 文档
- `../docs/UTM-BRIDGED-MODE.txt` - **桥接模式安装指南（推荐）**
- `../docs/install-nixos-utm.md` - 详细安装文档
- `../docs/utm-network-guide.md` - 网络配置指南

### 脚本
- `../scripts/manage-vms.sh` - 虚拟机管理脚本

### Makefile
- `../Makefile.utm` - UTM 专用 Makefile 命令
  - `make utm/bootstrap0` - 第一阶段安装
  - `make utm/bootstrap` - 第二阶段配置

## 🗑️ 为什么归档

这些文件是在探索和开发过程中创建的：
1. 尝试了多种网络配置方式（共享网络 vs 桥接）
2. 尝试了静态 IP vs DHCP
3. 创建了多个版本的安装脚本
4. 最终确定了最佳实践：**桥接模式 + DHCP**

现在所有功能都整合到了：
- Makefile.utm（自动化安装）
- manage-vms.sh（虚拟机管理）
- 简化的文档

## 📝 保留原因

保留这些文件是为了：
- 参考历史开发过程
- 了解不同方案的尝试
- 在需要时可以查看旧的实现

如果你需要这些文件中的某些功能，可以参考它们的实现。

---

**建议**：使用 `../docs/UTM-BRIDGED-MODE.txt` 开始新的虚拟机安装。
