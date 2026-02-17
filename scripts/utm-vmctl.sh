#!/usr/bin/env bash
# Copyright 2026
#
# Lightweight UTM VM control helper.
# - Build a new VM by duplicating an existing template VM (for no-UI automation).
# - Start / stop / delete VMs.
# - Works via AppleScript since UTM exposes a scripting dictionary.

set -euo pipefail
IFS=$'\n\t'

UTM_APP="${UTM_APP:-UTM}"
DEFAULT_TEMPLATE="${UTM_TEMPLATE_NAME:-NixOS-UTM-Template}"

open_utm() {
  open -g -a "$UTM_APP" >/dev/null 2>&1 || true
}

run_script() {
  local script="$1"
  /usr/bin/osascript <<EOF
tell application "$UTM_APP"
  $script
end tell
EOF
}

vm_exists() {
  local name=$1
  local out
  out="$(run_script "
    if ((count of (virtual machines whose name is \"${name}\")) > 0) then
      return \"1\"
    end if
    return \"0\"
  ")"
  [[ "$out" == "1" ]]
}

list_vms() {
  run_script '
    set out to ""
    repeat with vm in virtual machines
      set out to out & (name of vm) & "\t" & (status of vm) & "\n"
    end repeat
    return out
  '
}

list_names() {
  local names
  names="$(run_script "
    set out to {}
    repeat with vm in virtual machines
      set end of out to (name of vm)
    end repeat
    return out
  ")"
  printf '%s' "$names" | awk 'BEGIN{RS=", "} {gsub(/^ +| +$/, "", $0); if (length($0) > 0) print}'
}

create_vm() {
  local template=$1
  local start_now=$2
  local before after new_name old_name

  if ! vm_exists "$template"; then
    echo "Template '$template' not found. Set it once in UTM UI or pass --template." >&2
    exit 1
  fi

  before="$(list_names)"
  run_script "duplicate (first virtual machine whose name is \"${template}\")"
  after="$(list_names)"

  new_name=""
  while IFS= read -r old_name; do
    if [[ -z "${old_name}" ]]; then
      continue
    fi
    if ! printf '%s\n' "$before" | grep -Fxq "$old_name"; then
      new_name="$old_name"
      break
    fi
  done <<< "$after"

  if [[ -z "$new_name" ]]; then
    echo "Failed to detect duplicated VM name" >&2
    exit 1
  fi

  echo "UTM does not rename clones in this dictionary; created VM is '$new_name'." >&2

  if [[ "$start_now" == "1" ]]; then
    run_script "start (first virtual machine whose name is \"${new_name}\")"
  fi

  echo "$new_name"
}

start_vm() {
  local name=$1
  if ! vm_exists "$name"; then
    echo "VM '$name' not found" >&2
    exit 1
  fi
  run_script "start (first virtual machine whose name is \"${name}\")"
}

stop_vm() {
  local name=$1
  if ! vm_exists "$name"; then
    echo "VM '$name' not found" >&2
    exit 1
  fi
  run_script "stop (first virtual machine whose name is \"${name}\") by request"
}

delete_vm() {
  local name=$1
  if ! vm_exists "$name"; then
    echo "VM '$name' not found" >&2
    exit 1
  fi
  run_script "delete (first virtual machine whose name is \"${name}\")"
}

usage() {
  cat <<'EOF'
Usage:
  scripts/utm-vmctl.sh list
  scripts/utm-vmctl.sh create [--template <template_vm>] [--start]
  scripts/utm-vmctl.sh start <name>
  scripts/utm-vmctl.sh stop <name>
  scripts/utm-vmctl.sh delete <name>

Env:
  UTM_TEMPLATE_NAME   Template VM name (default: NixOS-UTM-Template)
  UTM_APP             Application name for AppleScript (default: UTM)
EOF
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  open_utm
  local cmd=$1
  shift

  case "$cmd" in
    list)
      list_vms
      ;;
    create)
      local name=""
      local template="$DEFAULT_TEMPLATE"
      local start_now=0

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --template)
            template=$2
            shift 2
            ;;
          --start)
            start_now=1
            shift
            ;;
          *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        esac
      done
      create_vm "$template" "$start_now"
      ;;
    start)
      if [[ $# -lt 1 ]]; then
        echo "start: missing <name>" >&2
        exit 1
      fi
      start_vm "$1"
      ;;
    stop)
      if [[ $# -lt 1 ]]; then
        echo "stop: missing <name>" >&2
        exit 1
      fi
      stop_vm "$1"
      ;;
    delete)
      if [[ $# -lt 1 ]]; then
        echo "delete: missing <name>" >&2
        exit 1
      fi
      delete_vm "$1"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
