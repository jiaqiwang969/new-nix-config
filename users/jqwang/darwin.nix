{ inputs, pkgs, ... }:

{
  homebrew = {
    enable = true;
    casks  = [
      "1password"
      "claude"
      "cleanshot"
      "discord"
      "fantastical"
      "google-chrome"
      "hammerspoon"
      "imageoptim"
      "istat-menus"
      "monodraw"
      "raycast"
      "rectangle"
      "screenflow"
      "slack"
      "spotify"
    ];

    brews = [
      "gnupg"
    ];
  };

  # The user should already exist, but we need to set this up so Nix knows
  # what our home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  users.users.jqwang = {
    home = "/Users/jqwang";
    shell = pkgs.fish;
  };

  # Register fish as a valid login shell and enable it
  environment.shells = [ pkgs.fish ];
  programs.fish.enable = true;

  # Required for some settings like homebrew to know what user to apply to.
  system.primaryUser = "jqwang";

  # 键盘速度配置
  system.defaults.NSGlobalDomain = {
    InitialKeyRepeat = 10;  # 按住键后开始重复的延迟 (默认15, 最小10)
    KeyRepeat = 1;          # 键重复速度 (默认2, 最小1)
  };
}
