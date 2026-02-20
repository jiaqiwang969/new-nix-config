{ config, pkgs, modulesPath, lib, currentSystemName, ... }: {
  imports = [
    ./hardware/vm-aarch64-utm.nix
    ./vm-shared.nix
    ../modules/attic.nix
  ];

  # Bridge mode on VM. Force DHCP on to override vm-shared default.
  networking.useDHCP = lib.mkForce true;

  # Derive hostname from the flake config name (e.g. vm-aarch64-utm → nixos-utm)
  networking.hostName = lib.mkForce (builtins.replaceStrings ["vm-aarch64-"] ["nixos-"] currentSystemName);

  # Qemu
  services.spice-vdagentd.enable = true;

  # For now, we need this since hardware acceleration does not work.
  environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";

  # Serial console for CLI automation (UTM PTY mode)
  # aarch64 QEMU virt machine exposes PL011 UART as ttyAMA0
  boot.kernelParams = [ "console=ttyAMA0,115200" "console=tty0" ];
  systemd.services."serial-getty@ttyAMA0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  # Lots of stuff that uses aarch64 that claims doesn't work, but actually works.
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;
}
