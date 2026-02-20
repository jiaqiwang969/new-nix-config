#!/bin/bash
# VM 自动化集成脚本
# 完整的时间旅行调试 VM 工作流

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_CONFIG_DIR="${SCRIPT_DIR}/.."
WORKSPACE_DIR="${WORKSPACE_DIR:-.}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-.time-travel-snapshots}"
TEMPLATE_VM="${TEMPLATE_VM:-vm-aarch64-utm-template}"
FIX_VM_PREFIX="${FIX_VM_PREFIX:-vm-fix}"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_step() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 显示帮助
show_help() {
    cat << EOF
VM 自动化集成脚本

用法: $0 <命令> [选项]

命令:
  setup-template          搭建模板 VM
  clone-fix-vm            克隆 Fix-VM
  run-fix-workflow        运行完整的修复工作流
  cleanup-fix-vm          清理 Fix-VM
  list-vms                列出所有 VM
  get-vm-ip               获取 VM IP
  ssh-to-vm               SSH 连接到 VM
  exec-in-vm              在 VM 中执行命令
  copy-to-vm              复制文件到 VM
  copy-from-vm            从 VM 复制文件

选项:
  --snapshot-id <id>      快照 ID
  --vm-name <name>        VM 名称
  --template <name>       模板 VM 名称 (默认: vm-aarch64-utm-template)
  --workspace <path>      工作区路径 (默认: .)
  --help                  显示帮助

示例:
  # 搭建模板 VM
  $0 setup-template

  # 克隆 Fix-VM
  $0 clone-fix-vm --snapshot-id abc123

  # 运行完整工作流
  $0 run-fix-workflow --snapshot-id abc123

  # SSH 连接
  $0 ssh-to-vm --vm-name vm-fix-abc123

  # 在 VM 中执行命令
  $0 exec-in-vm --vm-name vm-fix-abc123 --cmd "cargo check"

EOF
}

# 解析参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --snapshot-id)
                SNAPSHOT_ID="$2"
                shift 2
                ;;
            --vm-name)
                VM_NAME="$2"
                shift 2
                ;;
            --template)
                TEMPLATE_VM="$2"
                shift 2
                ;;
            --workspace)
                WORKSPACE_DIR="$2"
                shift 2
                ;;
            --cmd)
                CMD="$2"
                shift 2
                ;;
            --src)
                SRC="$2"
                shift 2
                ;;
            --dst)
                DST="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 搭建模板 VM
setup_template() {
    log_step "搭建模板 VM"

    bash "$NIXOS_CONFIG_DIR/scripts/auto-setup-vm.sh" "$TEMPLATE_VM"

    log_success "模板 VM 搭建完成"
}

# 克隆 Fix-VM
clone_fix_vm() {
    if [ -z "${SNAPSHOT_ID:-}" ]; then
        log_error "SNAPSHOT_ID 未指定"
        exit 1
    fi

    log_step "克隆 Fix-VM (SNAPSHOT_ID: $SNAPSHOT_ID)"

    local output=$(bash "$NIXOS_CONFIG_DIR/scripts/clone-fix-vm.sh" \
        "$TEMPLATE_VM" "$FIX_VM_PREFIX" "$SNAPSHOT_ID" "$WORKSPACE_DIR")

    echo "$output" | jq .

    log_success "Fix-VM 克隆完成"
}

# 获取 VM IP
get_vm_ip() {
    if [ -z "${VM_NAME:-}" ]; then
        log_error "VM_NAME 未指定"
        exit 1
    fi

    local ip=$(osascript -e "tell application \"UTM\" to query ip virtual machine named \"$VM_NAME\"" 2>/dev/null | sed 's/, /\n/g' | head -1 || echo "")

    if [ -z "$ip" ]; then
        log_error "无法获取 VM IP"
        exit 1
    fi

    echo "$ip"
}

# SSH 连接到 VM
ssh_to_vm() {
    if [ -z "${VM_NAME:-}" ]; then
        log_error "VM_NAME 未指定"
        exit 1
    fi

    local ip=$(get_vm_ip)

    log_info "连接到 $VM_NAME ($ip)..."

    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null jqwang@"$ip"
}

# 在 VM 中执行命令
exec_in_vm() {
    if [ -z "${VM_NAME:-}" ]; then
        log_error "VM_NAME 未指定"
        exit 1
    fi

    if [ -z "${CMD:-}" ]; then
        log_error "CMD 未指定"
        exit 1
    fi

    local ip=$(get_vm_ip)

    log_info "在 $VM_NAME 中执行: $CMD"

    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null jqwang@"$ip" "$CMD"
}

# 复制文件到 VM
copy_to_vm() {
    if [ -z "${VM_NAME:-}" ]; then
        log_error "VM_NAME 未指定"
        exit 1
    fi

    if [ -z "${SRC:-}" ] || [ -z "${DST:-}" ]; then
        log_error "SRC 或 DST 未指定"
        exit 1
    fi

    local ip=$(get_vm_ip)

    log_info "复制 $SRC 到 $VM_NAME:$DST"

    rsync -avz -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
        "$SRC" "jqwang@$ip:$DST"

    log_success "复制完成"
}

# 从 VM 复制文件
copy_from_vm() {
    if [ -z "${VM_NAME:-}" ]; then
        log_error "VM_NAME 未指定"
        exit 1
    fi

    if [ -z "${SRC:-}" ] || [ -z "${DST:-}" ]; then
        log_error "SRC 或 DST 未指定"
        exit 1
    fi

    local ip=$(get_vm_ip)

    log_info "从 $VM_NAME:$SRC 复制到 $DST"

    rsync -avz -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
        "jqwang@$ip:$SRC" "$DST"

    log_success "复制完成"
}

# 列出所有 VM
list_vms() {
    log_step "所有虚拟机"

    osascript -e 'tell application "UTM" to return name of every virtual machine' 2>/dev/null | \
        tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort | nl

    log_success "列表完成"
}

# 运行完整的修复工作流
run_fix_workflow() {
    if [ -z "${SNAPSHOT_ID:-}" ]; then
        log_error "SNAPSHOT_ID 未指定"
        exit 1
    fi

    log_step "运行完整的修复工作流"

    # 1. 克隆 Fix-VM
    log_info "1. 克隆 Fix-VM..."
    local output=$(bash "$NIXOS_CONFIG_DIR/scripts/clone-fix-vm.sh" \
        "$TEMPLATE_VM" "$FIX_VM_PREFIX" "$SNAPSHOT_ID" "$WORKSPACE_DIR")

    local vm_name=$(echo "$output" | jq -r '.vm_name')
    local vm_ip=$(echo "$output" | jq -r '.vm_ip')

    log_success "Fix-VM 已创建: $vm_name ($vm_ip)"

    # 2. 验证工作区
    log_info "2. 验证工作区..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null jqwang@"$vm_ip" \
        "cd /workspace && git status" || true

    log_success "工作区已验证"

    # 3. 输出 VM 信息
    log_info "3. VM 信息:"
    echo "   VM 名称: $vm_name"
    echo "   VM IP: $vm_ip"
    echo "   快照 ID: $SNAPSHOT_ID"

    # 4. 提示后续步骤
    log_info "4. 后续步骤:"
    echo "   - SSH 连接: $0 ssh-to-vm --vm-name $vm_name"
    echo "   - 执行命令: $0 exec-in-vm --vm-name $vm_name --cmd 'cargo check'"
    echo "   - 复制文件: $0 copy-from-vm --vm-name $vm_name --src /workspace --dst ./fixed"
    echo "   - 清理 VM: $0 cleanup-fix-vm --vm-name $vm_name"

    log_success "工作流已启动"
}

# 清理 Fix-VM
cleanup_fix_vm() {
    if [ -z "${VM_NAME:-}" ]; then
        log_error "VM_NAME 未指定"
        exit 1
    fi

    log_step "清理 Fix-VM: $VM_NAME"

    # 停止 VM
    log_info "停止 VM..."
    osascript -e "tell application \"UTM\" to stop virtual machine named \"$VM_NAME\" by request" 2>/dev/null || true

    sleep 5

    # 删除 VM
    log_info "删除 VM..."
    osascript -e "tell application \"UTM\" to delete virtual machine named \"$VM_NAME\"" 2>/dev/null || true

    log_success "Fix-VM 已删除"
}

# 主函数
main() {
    if [ $# -lt 1 ]; then
        show_help
        exit 1
    fi

    local command=$1
    shift

    parse_args "$@"

    case $command in
        setup-template)
            setup_template
            ;;
        clone-fix-vm)
            clone_fix_vm
            ;;
        run-fix-workflow)
            run_fix_workflow
            ;;
        cleanup-fix-vm)
            cleanup_fix_vm
            ;;
        list-vms)
            list_vms
            ;;
        get-vm-ip)
            get_vm_ip
            ;;
        ssh-to-vm)
            ssh_to_vm
            ;;
        exec-in-vm)
            exec_in_vm
            ;;
        copy-to-vm)
            copy_to_vm
            ;;
        copy-from-vm)
            copy_from_vm
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
