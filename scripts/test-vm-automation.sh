#!/bin/bash
# VM 自动化测试脚本

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

# 测试计数
TESTS_PASSED=0
TESTS_FAILED=0

# 测试函数
run_test() {
    local test_name=$1
    local test_cmd=$2

    log_test "$test_name"

    if eval "$test_cmd" > /dev/null 2>&1; then
        log_success "$test_name 通过"
        ((TESTS_PASSED++))
    else
        log_error "$test_name 失败"
        ((TESTS_FAILED++))
    fi
}

# 测试前置条件
test_prerequisites() {
    log_info "测试前置条件..."

    run_test "UTM 已安装" "[ -d '/Applications/UTM.app' ]"
    run_test "osascript 可用" "command -v osascript"
    run_test "sshpass 可用" "command -v sshpass"
    run_test "SSH 密钥存在" "[ -f '$HOME/.ssh/id_ed25519' ]"
    run_test "NixOS ISO 存在" "[ -f \"\$(ls /Users/jqwang/00-nixos-config/nixos-image/*.iso 2>/dev/null | head -1)\" ]"
}

# 测试脚本存在
test_scripts() {
    log_info "测试脚本文件..."

    local script_dir="/Users/jqwang/00-nixos-config/nixos-config/scripts"

    run_test "auto-setup-vm.sh 存在" "[ -f '$script_dir/auto-setup-vm.sh' ]"
    run_test "clone-fix-vm.sh 存在" "[ -f '$script_dir/clone-fix-vm.sh' ]"
    run_test "vm-automation.sh 存在" "[ -f '$script_dir/vm-automation.sh' ]"

    run_test "auto-setup-vm.sh 可执行" "[ -x '$script_dir/auto-setup-vm.sh' ]"
    run_test "clone-fix-vm.sh 可执行" "[ -x '$script_dir/clone-fix-vm.sh' ]"
    run_test "vm-automation.sh 可执行" "[ -x '$script_dir/vm-automation.sh' ]"
}

# 测试 Makefile
test_makefile() {
    log_info "测试 Makefile..."

    local makefile="/Users/jqwang/00-nixos-config/nixos-config/Makefile.vm-automation"

    run_test "Makefile.vm-automation 存在" "[ -f '$makefile' ]"
    run_test "Makefile 包含 vm-setup" "grep -q 'vm-setup' '$makefile'"
    run_test "Makefile 包含 vm-clone" "grep -q 'vm-clone' '$makefile'"
    run_test "Makefile 包含 vm-list" "grep -q 'vm-list' '$makefile'"
}

# 测试 VM 操作
test_vm_operations() {
    log_info "测试 VM 操作..."

    # 这些测试需要 UTM 运行，所以只做基本检查
    run_test "可以列出 VM" "osascript -e 'tell application \"UTM\" to return name of every virtual machine' 2>/dev/null | grep -q ."
}

# 显示测试结果
show_results() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "测试结果"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}通过: $TESTS_PASSED${NC}"
    echo -e "${RED}失败: $TESTS_FAILED${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "所有测试通过！"
        return 0
    else
        log_error "有 $TESTS_FAILED 个测试失败"
        return 1
    fi
}

# 主函数
main() {
    log_info "开始 VM 自动化测试..."
    echo ""

    test_prerequisites
    echo ""

    test_scripts
    echo ""

    test_makefile
    echo ""

    test_vm_operations
    echo ""

    show_results
}

# 运行主函数
main "$@"
