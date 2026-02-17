{ config, pkgs, modulesPath, lib, ... }: {
  imports = [
    ./hardware/vm-aarch64-utm.nix
    ./vm-shared.nix
    ../modules/attic.nix
  ];

  # Bridge mode on VM. Force DHCP on to override vm-shared default.
  networking.useDHCP = lib.mkForce true;

  # Override hostname from vm-shared.nix
  networking.hostName = lib.mkForce "nixos-utm-cache";

  # Qemu
  services.spice-vdagentd.enable = true;

  # For now, we need this since hardware acceleration does not work.
  environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";

  # Lots of stuff that uses aarch64 that claims doesn't work, but actually works.
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;
}
