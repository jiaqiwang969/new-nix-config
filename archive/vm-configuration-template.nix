# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.consoleMode = "0";

  # Nix Flakes
  nix.package = pkgs.nixVersions.latest;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Network configuration - Static IP for vm-dev-1
  networking.interfaces.enp0s10 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "192.168.64.13";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.64.1";
  networking.nameservers = [ "192.168.64.1" "8.8.8.8" ];
  networking.hostName = "nixos-vm-dev-1";

  # Set your time zone
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable the OpenSSH daemon
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitRootLogin = "yes";

  # SPICE support for UTM
  services.spice-vdagentd.enable = true;

  # Software rendering for M1 Mac
  environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";

  # Define user accounts
  users.users.root.initialPassword = "root";
  users.users.jqwang = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    initialPassword = "jqwang";
  };

  # Don't require password for sudo
  security.sudo.wheelNeedsPassword = false;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
    htop
    tmux
  ];

  # Enable Docker
  virtualisation.docker.enable = true;

  # Disable the firewall (we're in a VM)
  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
