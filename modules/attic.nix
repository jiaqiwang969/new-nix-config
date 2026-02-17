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
