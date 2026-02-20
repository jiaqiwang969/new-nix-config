#!/bin/bash
# 自动化 VM 克隆脚本
# 用于快速创建 Fix-VM 实例

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
TEMPLATE_VM="${1:-vm-aarch64-utm-template}"
FIX_VM_PREFIX="${2:-vm-fix}"
SNAPSHOT_ID="${3:-}"

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# 检查模板 VM 是否存在
check_template() {
    log_info "检查模板 VM '$TEMPLATE_VM'..."

    local exists=$(osascript -e "tell application \"UTM\" to return (name of every virtual machine) contains \"$TEMPLATE_VM\"" 2>/dev/null || echo "false")

    if [ "$exists" != "true" ]; then
        log_error "模板 VM '$TEMPLATE_VM' 不存在"
        exit 1
    fi

    log_success "模板 VM 存在"
}

# 克隆 VM
clone_vm() {
    log_info "克隆 VM..."

    local new_vm_name="${FIX_VM_PREFIX}-${SNAPSHOT_ID:0:8}"

    # 获取克隆前的 VM 列表
    local before=$(osascript -e 'tell application "UTM" to return name of every virtual machine' 2>/dev/null | tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort)

    # 执行克隆
    osascript << EOF
tell application "UTM"
    duplicate (first virtual machine whose name is "$TEMPLATE_VM")
end tell
EOF

    sleep 2

    # 获取克隆后的 VM 列表
    local after=$(osascript -e 'tell application "UTM" to return name of every virtual machine' 2>/dev/null | tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort)

    # 找出新 VM
    local cloned_vm=$(comm -13 <(echo "$before") <(echo "$after") | head -1)

    if [ -z "$cloned_vm" ]; then
        log_error "克隆失败"
        exit 1
    fi

    log_success "VM 已克隆: $cloned_vm"
    echo "$cloned_vm"
}

# 启动 VM
start_vm() {
    local vm_name=$1

    log_info "启动 VM '$vm_name'..."

    osascript << EOF
tell application "UTM"
    activate
    delay 1
    start virtual machine named "$vm_name"
end tell
EOF

    log_success "VM 已启动"
}

# 等待 VM 启动
wait_for_vm() {
    local vm_name=$1
    local max_attempts=120
    local attempt=0

    log_info "等待 VM 启动..."

    while [ $attempt -lt $max_attempts ]; do
        local ip=$(osascript -e "tell application \"UTM\" to query ip virtual machine named \"$vm_name\"" 2>/dev/null | sed 's/, /\n/g' | head -1 || echo "")

        if [ -n "$ip" ]; then
            # 验证 SSH 连接
            if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null jqwang@"$ip" true 2>/dev/null; then
                log_success "VM 已就绪，IP: $ip"
                echo "$ip"
                return 0
            fi
        fi

        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done

    log_error "VM 启动超时"
    exit 1
}

# 恢复工作区
restore_workspace() {
    local vm_ip=$1
    local workspace_path=$2

    log_info "恢复工作区..."

    # 复制工作区到 VM
    rsync -avz -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
        "$workspace_path/" "jqwang@$vm_ip:/workspace/" || {
        log_error "复制工作区失败"
        exit 1
    }

    log_success "工作区已恢复"
}

# 主函数
main() {
    log_info "开始克隆 Fix-VM..."

    # 检查模板
    check_template

    # 克隆 VM
    local cloned_vm=$(clone_vm)

    # 启动 VM
    start_vm "$cloned_vm"

    # 等待 VM 启动
    local vm_ip=$(wait_for_vm "$cloned_vm")

    # 如果提供了工作区路径，恢复工作区
    if [ $# -gt 3 ]; then
        local workspace_path=$4
        restore_workspace "$vm_ip" "$workspace_path"
    fi

    log_success "Fix-VM 已就绪"
    log_info "VM 名称: $cloned_vm"
    log_info "VM IP: $vm_ip"

    # 输出 JSON 格式的结果
    cat << EOF
{
    "vm_name": "$cloned_vm",
    "vm_ip": "$vm_ip",
    "snapshot_id": "$SNAPSHOT_ID"
}
EOF
}

# 运行主函数
main "$@"
