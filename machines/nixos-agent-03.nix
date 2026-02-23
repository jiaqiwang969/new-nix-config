{ lib, ... }: {
  imports = [ ./orb-agent-base.nix ];
  networking.hostName = lib.mkForce "nixos-agent-03";
}
