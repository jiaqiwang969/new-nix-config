{ config, lib, pkgs, currentSystemUser ? "root", ... }:
let
  cfg = config.services.codex-egress-guard;

  syncScript = pkgs.writeShellScript "codex-egress-guard-sync" ''
    set -euo pipefail

    HELPER="/usr/local/bin/es-guard-egress"
    ALLOWLIST_FILE=${lib.escapeShellArg cfg.allowlistFile}
    TARGET_USER=${lib.escapeShellArg cfg.targetUser}
    ANCHOR_NAME=${lib.escapeShellArg cfg.anchor}
    MODE=${lib.escapeShellArg cfg.mode}

    if [ ! -x "$HELPER" ]; then
      echo "codex-egress-guard: helper missing: $HELPER"
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
      echo "codex-egress-guard: skip apply, allowlist file missing: $ALLOWLIST_FILE"
      exit 0
    fi

    "$HELPER" --apply --allowlist "$ALLOWLIST_FILE" --user "$TARGET_USER" --anchor "$ANCHOR_NAME"
  '';
in
{
  options.services.codex-egress-guard = {
    enable = lib.mkEnableOption "codex outbound allowlist guard";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.codex-es-guard;
      description = "Package providing the es-guard-egress helper.";
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
      default = "/Users/${currentSystemUser}/.codex/es-guard/egress-allowlist.txt";
      example = "/Users/me/.codex/es-guard/egress-allowlist.txt";
      description = "Text file containing one allowed domain/IP/CIDR per line.";
    };

    anchor = lib.mkOption {
      type = lib.types.str;
      default = "com.apple/codex-es-guard-egress";
      description = "PF anchor name used for egress allowlist rules.";
    };

    syncIntervalSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = "Launchd periodic sync interval for applying/printing egress rules.";
    };
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.codexEgressGuardInstall.text = ''
      if [ -f "${cfg.package}/bin/es-guard-egress" ]; then
        mkdir -p /usr/local/bin
        cp -f "${cfg.package}/bin/es-guard-egress" /usr/local/bin/es-guard-egress
        chmod 755 /usr/local/bin/es-guard-egress
      fi
    '';

    launchd.daemons.codex-egress-guard-sync = {
      serviceConfig = {
        Label = "dev.codex-egress-guard-sync";
        ProgramArguments = [ "${syncScript}" ];
        RunAtLoad = true;
        StartInterval = cfg.syncIntervalSeconds;
        StandardOutPath = "/tmp/codex-egress-guard-sync.log";
        StandardErrorPath = "/tmp/codex-egress-guard-sync.err";
      };
    };
  };
}
