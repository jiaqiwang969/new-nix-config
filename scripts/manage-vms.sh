#!/usr/bin/env bash
# UTM 多虚拟机管理脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_CONFIG_FILE="$SCRIPT_DIR/vm-inventory.json"

# 函数：打印带颜色的消息
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# 函数：显示帮助信息
show_help() {
    cat << EOF
UTM 多虚拟机管理脚本

用法: $0 <命令> [选项]

命令:
  list                列出所有配置的虚拟机
  status              显示所有虚拟机的状态
  create <vm-name>    创建新的虚拟机配置
  deploy <vm-name>    部署配置到指定虚拟机
  deploy-all          部署配置到所有虚拟机
  ssh <vm-name>       SSH 连接到指定虚拟机
  ip <vm-name>        显示虚拟机的 IP 地址
  ping <vm-name>      测试虚拟机连接
  update-hosts        更新 /etc/hosts 文件
  generate-ssh-config 生成 SSH 配置

示例:
  $0 list
  $0 create vm-dev-1
  $0 deploy vm-dev-1
  $0 ssh vm-dev-1

EOF
}

# 函数：列出所有虚拟机
list_vms() {
    print_info "已配置的虚拟机："
    echo ""

    if [ ! -f "$VM_CONFIG_FILE" ]; then
        print_warning "未找到虚拟机配置文件: $VM_CONFIG_FILE"
        print_info "运行 '$0 create <vm-name>' 创建第一个虚拟机"
        return
    fi

    # 使用 jq 解析 JSON（如果可用）
    if command -v jq &> /dev/null; then
        jq -r '.vms[] | "  \(.name)\t\(.ip)\t\(.hostname)\t\(.status)"' "$VM_CONFIG_FILE" | \
            column -t -s $'\t' -N "名称,IP地址,主机名,状态"
    else
        cat "$VM_CONFIG_FILE"
    fi
}

# 函数：检查虚拟机状态
check_status() {
    local vm_name=$1
    local vm_ip=$2

    if ping -c 1 -W 1 "$vm_ip" &> /dev/null; then
        echo "online"
    else
        echo "offline"
    fi
}

# 函数：显示所有虚拟机状态
show_status() {
    print_info "检查虚拟机状态..."
    echo ""

    if [ ! -f "$VM_CONFIG_FILE" ]; then
        print_warning "未找到虚拟机配置文件"
        return
    fi

    if ! command -v jq &> /dev/null; then
        print_error "需要安装 jq 来解析配置文件"
        print_info "运行: brew install jq"
        return
    fi

    printf "%-20s %-15s %-20s %-10s\n" "虚拟机名称" "IP地址" "主机名" "状态"
    printf "%-20s %-15s %-20s %-10s\n" "----------" "-------" "------" "----"

    jq -r '.vms[] | "\(.name) \(.ip) \(.hostname)"' "$VM_CONFIG_FILE" | while read -r name ip hostname; do
        status=$(check_status "$name" "$ip")
        if [ "$status" = "online" ]; then
            printf "%-20s %-15s %-20s ${GREEN}%-10s${NC}\n" "$name" "$ip" "$hostname" "在线"
        else
            printf "%-20s %-15s %-20s ${RED}%-10s${NC}\n" "$name" "$ip" "$hostname" "离线"
        fi
    done
}

# 函数：SSH 连接到虚拟机
ssh_to_vm() {
    local vm_name=$1

    if [ -z "$vm_name" ]; then
        print_error "请指定虚拟机名称"
        echo "用法: $0 ssh <vm-name>"
        return 1
    fi

    if ! command -v jq &> /dev/null; then
        print_error "需要安装 jq"
        return 1
    fi

    local vm_ip=$(jq -r ".vms[] | select(.name==\"$vm_name\") | .ip" "$VM_CONFIG_FILE")

    if [ -z "$vm_ip" ] || [ "$vm_ip" = "null" ]; then
        print_error "未找到虚拟机: $vm_name"
        return 1
    fi

    print_info "连接到 $vm_name ($vm_ip)..."
    ssh "jqwang@$vm_ip"
}

# 函数：部署配置到虚拟机
deploy_to_vm() {
    local vm_name=$1

    if [ -z "$vm_name" ]; then
        print_error "请指定虚拟机名称"
        return 1
    fi

    if ! command -v jq &> /dev/null; then
        print_error "需要安装 jq"
        return 1
    fi

    local vm_ip=$(jq -r ".vms[] | select(.name==\"$vm_name\") | .ip" "$VM_CONFIG_FILE")
    local vm_config=$(jq -r ".vms[] | select(.name==\"$vm_name\") | .config" "$VM_CONFIG_FILE")

    if [ -z "$vm_ip" ] || [ "$vm_ip" = "null" ]; then
        print_error "未找到虚拟机: $vm_name"
        return 1
    fi

    print_info "部署配置到 $vm_name ($vm_ip)..."

    # 复制配置文件
    print_info "复制配置文件..."
    rsync -av --exclude='vendor/' \
        --exclude='.git/' \
        --exclude='iso/' \
        --exclude='result' \
        "$SCRIPT_DIR/" "jqwang@$vm_ip:~/nix-config/"

    print_success "配置文件已复制"

    # 应用配置
    print_info "应用 NixOS 配置..."
    ssh "jqwang@$vm_ip" "cd ~/nix-config && sudo nixos-rebuild switch --flake \".#$vm_config\""

    print_success "配置已应用到 $vm_name"
}

# 函数：部署到所有虚拟机
deploy_all() {
    print_info "部署配置到所有虚拟机..."

    if ! command -v jq &> /dev/null; then
        print_error "需要安装 jq"
        return 1
    fi

    jq -r '.vms[] | .name' "$VM_CONFIG_FILE" | while read -r vm_name; do
        echo ""
        print_info "处理虚拟机: $vm_name"
        deploy_to_vm "$vm_name" || print_warning "部署到 $vm_name 失败"
    done

    echo ""
    print_success "所有虚拟机部署完成"
}

# 函数：生成 SSH 配置
generate_ssh_config() {
    print_info "生成 SSH 配置..."

    local ssh_config_file="$HOME/.ssh/config.d/utm-vms"
    mkdir -p "$HOME/.ssh/config.d"

    cat > "$ssh_config_file" << 'EOF'
# UTM 虚拟机 SSH 配置
# 自动生成，请勿手动编辑

EOF

    if ! command -v jq &> /dev/null; then
        print_error "需要安装 jq"
        return 1
    fi

    jq -r '.vms[] | "Host \(.name)\n    HostName \(.ip)\n    User jqwang\n    ForwardAgent yes\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n"' "$VM_CONFIG_FILE" >> "$ssh_config_file"

    print_success "SSH 配置已生成: $ssh_config_file"
    print_info "确保在 ~/.ssh/config 中包含以下行："
    echo "    Include config.d/utm-vms"
}

# 函数：更新 hosts 文件
update_hosts() {
    print_info "更新 /etc/hosts 文件..."

    if ! command -v jq &> /dev/null; then
        print_error "需要安装 jq"
        return 1
    fi

    local hosts_entries=$(mktemp)

    echo "# UTM 虚拟机 - 自动生成" > "$hosts_entries"
    jq -r '.vms[] | "\(.ip)\t\(.hostname)\t\(.name)"' "$VM_CONFIG_FILE" >> "$hosts_entries"

    print_info "将添加以下条目到 /etc/hosts:"
    cat "$hosts_entries"
    echo ""

    print_warning "这需要 sudo 权限"

    # 移除旧的 UTM 虚拟机条目
    sudo sed -i.bak '/# UTM 虚拟机/,/^$/d' /etc/hosts

    # 添加新条目
    echo "" | sudo tee -a /etc/hosts > /dev/null
    cat "$hosts_entries" | sudo tee -a /etc/hosts > /dev/null

    rm "$hosts_entries"

    print_success "/etc/hosts 已更新"
}

# 函数：创建虚拟机配置
create_vm_config() {
    local vm_name=$1

    if [ -z "$vm_name" ]; then
        print_error "请指定虚拟机名称"
        return 1
    fi

    # 初始化配置文件（如果不存在）
    if [ ! -f "$VM_CONFIG_FILE" ]; then
        echo '{"vms":[]}' > "$VM_CONFIG_FILE"
    fi

    # 获取下一个可用的 IP
    local last_ip=$(jq -r '.vms[-1].ip // "192.168.64.9"' "$VM_CONFIG_FILE")
    local next_ip=$(echo "$last_ip" | awk -F. '{print $1"."$2"."$3"."$4+1}')

    local hostname="nixos-${vm_name}"
    local config_name="vm-aarch64-utm"

    print_info "创建虚拟机配置: $vm_name"
    echo "  IP 地址: $next_ip"
    echo "  主机名: $hostname"
    echo "  配置: $config_name"
    echo ""

    # 添加到配置文件
    jq ".vms += [{
        \"name\": \"$vm_name\",
        \"ip\": \"$next_ip\",
        \"hostname\": \"$hostname\",
        \"config\": \"$config_name\",
        \"status\": \"pending\"
    }]" "$VM_CONFIG_FILE" > "${VM_CONFIG_FILE}.tmp"

    mv "${VM_CONFIG_FILE}.tmp" "$VM_CONFIG_FILE"

    print_success "虚拟机配置已创建"
    print_info "下一步："
    echo "  1. 在 UTM 中创建虚拟机"
    echo "  2. 安装 NixOS 并配置静态 IP: $next_ip"
    echo "  3. 运行: $0 deploy $vm_name"
}

# 主函数
main() {
    local command=$1
    shift

    case "$command" in
        list)
            list_vms
            ;;
        status)
            show_status
            ;;
        create)
            create_vm_config "$@"
            ;;
        deploy)
            deploy_to_vm "$@"
            ;;
        deploy-all)
            deploy_all
            ;;
        ssh)
            ssh_to_vm "$@"
            ;;
        ip)
            if ! command -v jq &> /dev/null; then
                print_error "需要安装 jq"
                exit 1
            fi
            jq -r ".vms[] | select(.name==\"$1\") | .ip" "$VM_CONFIG_FILE"
            ;;
        ping)
            local vm_ip=$(jq -r ".vms[] | select(.name==\"$1\") | .ip" "$VM_CONFIG_FILE")
            ping -c 3 "$vm_ip"
            ;;
        update-hosts)
            update_hosts
            ;;
        generate-ssh-config)
            generate_ssh_config
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "未知命令: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
