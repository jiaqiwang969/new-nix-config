{ pkgs, inputs, ... }:

{
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/fish" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using fish as our shell
  programs.fish.enable = true;

  # We require this because we use lazy.nvim against the best wishes
  # a pure Nix system so this lets those unpatched binaries run.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages
  ];

  users.users.jqwang = {
    isNormalUser = true;
    home = "/home/jqwang";
    extraGroups = [ "docker" "lxd" "wheel" ];
    shell = pkgs.fish;
    # Password hash for local login (recreate with `openssl passwd -6 ...`)
    hashedPassword = "$6$su51z6mPtrkGFynP$hnYMhvMFCQXI7/ni7ET5tAtKXjOeKAXUzo.2X6AZRB3JqbAxehGK5t8ts1umK.mr2jGXAjOr2ex9./TjTyEbR/";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFjFka95UiprmSFObYiKafcW3QsIAEKz768N9crOVU7H jqwang@jqwangs-MacBook-Pro.local"
    ];
  };
}
