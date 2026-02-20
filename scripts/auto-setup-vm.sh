#!/bin/bash
# 简化的 VM 自动化搭建脚本
# 使用现有的 Makefile.utm 命令

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_CONFIG_DIR="${SCRIPT_DIR}/.."
VM_NAME="${1:-vm-aarch64-utm-template}"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_step() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 检查前置条件
check_prerequisites() {
    log_step "检查前置条件"

    # 检查 UTM
    if ! [ -d "/Applications/UTM.app" ]; then
        log_error "UTM 未安装"
        exit 1
    fi
    log_success "UTM 已安装"

    # 检查 sshpass
    if ! command -v sshpass &> /dev/null; then
        log_info "安装 sshpass..."
        brew install sshpass || {
            log_error "无法安装 sshpass"
            exit 1
        }
    fi
    log_success "sshpass 可用"

    # 检查 NixOS ISO
    local iso=$(ls -t "${NIXOS_CONFIG_DIR}/../nixos-image"/*.iso 2>/dev/null | head -1 || echo "")
    if [ -z "$iso" ] || [ ! -f "$iso" ]; then
        log_error "NixOS ISO 未找到"
        exit 1
    fi
    log_success "NixOS ISO: $iso"

    # 检查 SSH 密钥
    if [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
        log_info "生成 SSH 密钥..."
        ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ""
    fi
    log_success "SSH 密钥可用"
}

# 使用 Makefile 进行搭建
setup_with_makefile() {
    log_step "使用 Makefile 搭建 VM"

    cd "$NIXOS_CONFIG_DIR"

    # 创建 VM
    log_info "创建 VM '$VM_NAME'..."
    make -f Makefile.utm utm/create NIXNAME="$VM_NAME" || {
        log_error "VM 创建失败"
        exit 1
    }
    log_success "VM 已创建"

    # 启动 VM
    log_info "启动 VM..."
    make -f Makefile.utm utm/start NIXNAME="$VM_NAME"
    log_success "VM 已启动"

    # 等待 VM 启动
    log_info "等待 VM 启动（约 25 秒）..."
    sleep 25

    # 准备 SSH
    log_info "准备 SSH 环境..."
    make -f Makefile.utm utm/iso-prepare-ssh NIXNAME="$VM_NAME"
    log_success "SSH 已准备"

    # 检测 IP
    log_info "检测 VM IP..."
    local boot_ip=$(make -f Makefile.utm utm/detect-ip NIXNAME="$VM_NAME")
    log_success "VM IP: $boot_ip"

    # 执行 bootstrap0
    log_info "执行 bootstrap0（分区和安装）..."
    make -f Makefile.utm utm/bootstrap0 NIXADDR="$boot_ip" NIXNAME="$VM_NAME" || {
        log_error "bootstrap0 失败"
        exit 1
    }
    log_success "bootstrap0 完成"

    # 等待 VM 重启
    log_info "等待 VM 重启（约 30 秒）..."
    sleep 30

    # 检测新 IP
    log_info "检测重启后的 VM IP..."
    local disk_ip=$(make -f Makefile.utm utm/detect-ip NIXNAME="$VM_NAME")
    log_success "VM IP: $disk_ip"

    # 执行 bootstrap
    log_info "执行 bootstrap（应用完整配置）..."
    make -f Makefile.utm utm/bootstrap NIXADDR="$disk_ip" NIXNAME="$VM_NAME" || {
        log_error "bootstrap 失败"
        exit 1
    }
    log_success "bootstrap 完成"

    # 停止 VM
    log_info "停止 VM..."
    make -f Makefile.utm utm/stop NIXNAME="$VM_NAME"
    log_success "VM 已停止"

    # 移除 ISO
    log_info "移除 ISO..."
    make -f Makefile.utm utm/remove-removable-drives NIXNAME="$VM_NAME"
    log_success "ISO 已移除"
}

# 主函数
main() {
    log_step "VM 自动化搭建"
    log_info "VM 名称: $VM_NAME"

    check_prerequisites

    setup_with_makefile

    log_step "搭建完成"
    log_success "模板 VM '$VM_NAME' 已就绪"
    log_info "下次启动时可用于克隆"
}

# 运行主函数
main "$@"
