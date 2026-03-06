{ config, lib, pkgs, currentSystemUser ? "root", ... }:
let
  cfg = config.services.agentsmith-egress-guard;

  syncScript = pkgs.writeShellScript "agentsmith-egress-guard-sync" ''
    set -euo pipefail

    HELPER="/usr/local/bin/agentsmith-egress"
    ALLOWLIST_FILE=${lib.escapeShellArg cfg.allowlistFile}
    TARGET_USER=${lib.escapeShellArg cfg.targetUser}
    ANCHOR_NAME=${lib.escapeShellArg cfg.anchor}
    MODE=${lib.escapeShellArg cfg.mode}

    if [ ! -x "$HELPER" ]; then
      echo "agentsmith-egress-guard: helper missing: $HELPER"
      exit 0
    fi

    if [ "$MODE" = "print" ]; then
      if [ -f "$ALLOWLIST_FILE" ]; then
        "$HELPER" --print-rules --allowlist "$ALLOWLIST_FILE" --user "$TARGET_USER" --anchor "$ANCHOR_NAME"
      else
        "$HELPER" --print-rules --user "$TARGET_USER" --anchor "$ANCHOR_NAME"
      fi
      exit 0
    fi

    if [ ! -f "$ALLOWLIST_FILE" ]; then
      echo "agentsmith-egress-guard: skip apply, allowlist file missing: $ALLOWLIST_FILE"
      exit 0
    fi

    "$HELPER" --apply --allowlist "$ALLOWLIST_FILE" --user "$TARGET_USER" --anchor "$ANCHOR_NAME"
  '';
in
{
  options.services.agentsmith-egress-guard = {
    enable = lib.mkEnableOption "AgentSmith-RS outbound allowlist guard";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.agentsmith-rs;
      description = "Package providing the agentsmith-egress helper.";
    };

    mode = lib.mkOption {
      type = lib.types.enum [ "enforce" "print" ];
      default = "enforce";
      description = ''
        enforce: periodically apply PF outbound allowlist rules.
        print: render rules only, no PF mutation.
      '';
    };

    targetUser = lib.mkOption {
      type = lib.types.str;
      default = currentSystemUser;
      description = "macOS user whose outbound traffic is constrained by the guard rules.";
    };

    allowlistFile = lib.mkOption {
      type = lib.types.str;
      default = "/Users/${currentSystemUser}/.agentsmith-rs/guard/egress-allowlist.txt";
      example = "/Users/me/.agentsmith-rs/guard/egress-allowlist.txt";
      description = "Text file containing one allowed domain/IP/CIDR per line.";
    };

    anchor = lib.mkOption {
      type = lib.types.str;
      default = "com.apple/agentsmith-rs-egress";
      description = "PF anchor name used for egress allowlist rules.";
    };

    syncIntervalSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = "Launchd periodic sync interval for applying/printing egress rules.";
    };
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.agentsmithEgressGuardInstall.text = ''
      if [ -f "${cfg.package}/bin/agentsmith-egress" ]; then
        mkdir -p /usr/local/bin
        cp -f "${cfg.package}/bin/agentsmith-egress" /usr/local/bin/agentsmith-egress
        chmod 755 /usr/local/bin/agentsmith-egress
      fi
    '';

    launchd.daemons.agentsmith-egress-guard-sync = {
      serviceConfig = {
        Label = "dev.agentsmith-egress-guard-sync";
        ProgramArguments = [ "${syncScript}" ];
        RunAtLoad = true;
        StartInterval = cfg.syncIntervalSeconds;
        StandardOutPath = "/tmp/agentsmith-egress-guard-sync.log";
        StandardErrorPath = "/tmp/agentsmith-egress-guard-sync.err";
      };
    };
  };
}
