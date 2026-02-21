{ config, pkgs, ... }: {
  services.atticd = {
    enable = true;
    environmentFile = "/var/lib/atticd/env";
    settings = {
      listen = "[::]:8080";
      database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";
      storage = {
        type = "local";
        path = "/var/lib/atticd/storage";
      };
      chunking = {
        nar-size-threshold = 65536;
        min-size = 16384;
        avg-size = 65536;
        max-size = 262144;
      };
      garbage-collection = {
        interval = "24 hours";
        default-retention-period = "6 months";
      };
    };
  };

  # 1. Generate JWT secret and env file on first boot before atticd starts
  systemd.services.atticd-init = {
    description = "Initialize Attic environment file";
    before = [ "atticd.service" ];
    requiredBy = [ "atticd.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/atticd
      if [ ! -f /var/lib/atticd/env ]; then
        SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 64)
        echo "ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=$SECRET" > /var/lib/atticd/env.tmp
        mv /var/lib/atticd/env.tmp /var/lib/atticd/env
        chmod 600 /var/lib/atticd/env
      fi
    '';
  };

  # 2. Automatically create 'main' cache once atticd is up and running
  systemd.services.atticd-setup-cache = {
    description = "Setup default main cache for Attic";
    wantedBy = [ "multi-user.target" ];
    after = [ "atticd.service" ];
    requires = [ "atticd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    script = let
      configFile = config.services.atticd.settings;
      # The NixOS atticd module generates a checked TOML config; reference it
      # via the systemd unit's ExecStart to stay in sync.
      atticdConfigFile = "/run/atticd/atticd.toml";
    in ''
      # Wait for atticd API to become responsive
      for i in {1..30}; do
        if ${pkgs.curl}/bin/curl -s http://localhost:8080/ > /dev/null; then
          break
        fi
        sleep 1
      done

      # Load the JWT secret so atticadm can sign tokens
      set -a
      . /var/lib/atticd/env
      set +a

      # Find the config file atticd is actually using
      ATTICD_CONFIG=$(${pkgs.procps}/bin/ps -o args= -p $(${pkgs.procps}/bin/pgrep -x atticd) | ${pkgs.gnugrep}/bin/grep -oP '(?<=-f )\S+')

      # Generate admin token
      TOKEN=$(${pkgs.attic-server}/bin/atticadm -f "$ATTICD_CONFIG" make-token --sub admin --validity '10y' --pull '*' --push '*' --create-cache '*' --configure-cache '*' --configure-cache-retention '*' --destroy-cache '*')

      # Login and configure main cache
      ${pkgs.attic-client}/bin/attic login local http://localhost:8080 $TOKEN
      ${pkgs.attic-client}/bin/attic cache create main || true
      ${pkgs.attic-client}/bin/attic cache configure main --public --upstream-cache-key-name ""
    '';
  };

  # mDNS so cache is discoverable as nixos-utm.local (macOS has native Bonjour)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # attic CLI for pushing paths
  environment.systemPackages = [ pkgs.attic-client ];
}
