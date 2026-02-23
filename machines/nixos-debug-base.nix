{ lib, ... }: {
  imports = [ ./orb-agent-base.nix ];
  networking.hostName = lib.mkForce "nixos-debug-base";
}
