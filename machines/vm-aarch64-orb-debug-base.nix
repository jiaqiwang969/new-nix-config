{ config, pkgs, modulesPath, lib, currentSystemName, ... }: {
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
    ./vm-shared.nix
  ];

  # --- OrbStack LXC 容器：覆盖不兼容的选项 ---

  # 无 bootloader（共享内核）
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  # 网络由 OrbStack 管理
  networking.hostName = lib.mkForce "nixos-debug-base";
  networking.useDHCP = lib.mkForce false;
  networking.useHostResolvConf = lib.mkForce false;
  networking.dhcpcd.enable = lib.mkForce false;
  systemd.network.enable = true;
  systemd.network.networks."50-eth0" = {
    matchConfig.Name = "eth0";
    networkConfig = { DHCP = "ipv4"; IPv6AcceptRA = true; };
    linkConfig.RequiredForOnline = "routable";
  };

  # 禁用所有 GUI specialisation
  specialisation = lib.mkForce {};

  # 禁用容器中不可用的服务
  virtualisation.docker.enable = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;
  services.flatpak.enable = lib.mkForce false;
  services.snap.enable = lib.mkForce false;
  i18n.inputMethod.enable = lib.mkForce false;

  # OrbStack guest 集成
  environment.shellInit = ''
    . /opt/orbstack-guest/etc/profile-early
    . /opt/orbstack-guest/etc/profile-late
  '';
  programs.ssh.extraConfig = ''
    Include /opt/orbstack-guest/etc/ssh_config
  '';
  services.resolved.enable = lib.mkForce false;
  environment.etc."resolv.conf".source = lib.mkForce "/opt/orbstack-guest/etc/resolv.conf";

  # OrbStack 用户组
  users.groups.orbstack.gid = 67278;

  # Rosetta x86 模拟
  nix.settings.extra-platforms = [ "x86_64-linux" "i686-linux" ];

  # 使用 nixos-dev 上的 Attic cache 加速构建（优先于官方 cache）
  nix.settings.substituters = lib.mkBefore [
    "http://nixos-orb.local:8080/main"
  ];
  nix.settings.trusted-public-keys = lib.mkAfter [
    "main:9EEszuiyiG9xkuZmcZTL7EzLwqSEO9MEiViV7ymLNgs="
  ];

  # 覆盖用户定义（uid=1000 以兼容 isNormalUser + per-user profile）
  users.users.jqwang = lib.mkForce {
    isNormalUser = true;
    uid = 1000;
    home = "/home/jqwang";
    extraGroups = [ "wheel" "orbstack" ];
    shell = pkgs.fish;
    hashedPassword = "$6$/vVYppRJz7JvDE5m$HgiOTUq6foeYud/qnX9iOzuewEP5/sQ/epaUXlCngs1P/CE2uh7pulWpqxQMeSdeiQW6QDmxc5XSCTmua7kK0.";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFjFka95UiprmSFObYiKafcW3QsIAEKz768N9crOVU7H jqwang@jqwangs-MacBook-Pro.local"
    ];
  };

  # systemd watchdog 禁用（OrbStack 需要）
  systemd.services."systemd-oomd".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-userdbd".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-udevd".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-timesyncd".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-timedated".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-portabled".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-nspawn@".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-machined".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-localed".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-logind".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-journald@".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-journald".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-journal-remote".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-journal-upload".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-importd".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-hostnamed".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-homed".serviceConfig.WatchdogSec = 0;
  systemd.services."systemd-networkd".serviceConfig.WatchdogSec = lib.mkIf config.systemd.network.enable 0;

  # LXC 容器中 /etc/profiles/per-user 不会自动创建
  systemd.services.orbstack-hm-profile = {
    description = "Create per-user profile symlink for OrbStack LXC";
    after = [ "home-manager-jqwang.service" ];
    wants = [ "home-manager-jqwang.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      HM_GEN="/home/jqwang/.local/state/home-manager/gcroots/current-home"
      if [ -e "$HM_GEN/home-path" ]; then
        mkdir -p /etc/profiles/per-user
        ln -sfn "$(readlink -f "$HM_GEN/home-path")" /etc/profiles/per-user/jqwang
      fi
    '';
  };

  # ~/.codex 符号链接到 Mac 宿主机，共享所有配置和状态
  system.activationScripts.codex-symlink = ''
    if [ ! -L /home/jqwang/.codex ]; then
      rm -rf /home/jqwang/.codex
      ln -sfn /mnt/mac/Users/jqwang/.codex /home/jqwang/.codex
      chown -h 1000:users /home/jqwang/.codex
    fi
  '';

  # 端口转发：容器 localhost:8317 → Mac 宿主机 host.internal:8317
  systemd.services.cliproxy-forward = {
    description = "Forward localhost:8317 to Mac host cliproxy";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:8317,fork,reuseaddr TCP:host.internal:8317";
      Restart = "always";
      RestartSec = 3;
    };
  };

  system.stateVersion = lib.mkForce "25.11";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;
}
