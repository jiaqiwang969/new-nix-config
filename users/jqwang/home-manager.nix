{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  sources = import ../../nix/sources.nix;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  shellAliases = {
    ga = "git add";
    gc = "git commit";
    gco = "git checkout";
    gcp = "git cherry-pick";
    gdiff = "git diff";
    gl = "git prettylog";
    gp = "git push";
    gs = "git status";
    gt = "git tag";

    jd = "jj desc";
    jf = "jj git fetch";
    jn = "jj new";
    jp = "jj git push";
    js = "jj st";
  } // (if isLinux then {
    # Two decades of using a Mac has made this such a strong memory
    # that I'm just going to keep it consistent.
    pbcopy = "xclip";
    pbpaste = "xclip -o";
  } else {});

  # For our MANPAGER env var
  # https://github.com/sharkdp/bat/issues/1145
  manpager = (pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
    sh -c 'col -bx | bat -l man -p'
    '' else ''
    cat "$1" | col -bx | bat --language man --style plain
  ''));

  # Shared danger-check snippet injected into safe-rm on both platforms.
  # Uses only POSIX sh constructs so it works in the bash-based wrapper.
  dangerCheck = ''
    _safe_rm_danger=0
    for _arg in "$@"; do
      case "$_arg" in
        "~"|"$HOME"|"$HOME/"|"/") _safe_rm_danger=1 ;;
        *)
          _expanded="''${_arg/#\~/$HOME}"
          _real="''$(cd "$_expanded" 2>/dev/null && pwd)"
          if [ "$_real" = "$HOME" ] || [ "$_real" = "/" ]; then
            _safe_rm_danger=1
          fi
          ;;
      esac
    done
    if [ "$_safe_rm_danger" = "1" ]; then
      echo "" >&2
      echo "╔══════════════════════════════════════════════════════╗" >&2
      echo "║  !! BLOCKED: rm targeting HOME or root directory !!  ║" >&2
      echo "║  This command would have deleted everything.         ║" >&2
      echo "║  Use __purge_rm if you truly know what you're doing. ║" >&2
      echo "╚══════════════════════════════════════════════════════╝" >&2
      echo "" >&2
      exit 1
    fi
  '';

  # Safe rm wrapper: moves files to trash instead of deleting
  safe-rm = (pkgs.writeShellScriptBin "rm" (if isDarwin then ''
    ${dangerCheck}
    # safe-rm: moves to macOS Trash instead of permanent delete
    args=()
    for arg in "$@"; do
      case "$arg" in
        -f|-r|-rf|-fr|-i|-I|-v|--force|--recursive|--verbose|--interactive*)
          # skip rm flags, trash doesn't need them
          ;;
        --)
          ;;
        *)
          args+=("$arg")
          ;;
      esac
    done
    if [ ''${#args[@]} -eq 0 ]; then
      echo "rm (safe): no files specified" >&2
      exit 1
    fi
    exec ${pkgs.darwin.trash}/bin/trash "''${args[@]}"
  '' else ''
    ${dangerCheck}
    # On Linux, use a trash directory
    TRASH_DIR="$HOME/.local/share/Trash/files"
    mkdir -p "$TRASH_DIR"
    args=()
    for arg in "$@"; do
      case "$arg" in
        -f|-r|-rf|-fr|-i|-I|-v|--force|--recursive|--verbose|--interactive*)
          ;;
        --)
          ;;
        *)
          args+=("$arg")
          ;;
      esac
    done
    if [ ''${#args[@]} -eq 0 ]; then
      echo "rm (safe): no files specified" >&2
      exit 1
    fi
    for f in "''${args[@]}"; do
      mv -- "$f" "$TRASH_DIR/$(basename "$f").$(date +%s)"
    done
  ''));

  # The real rm, only for admin use
  real-rm = (pkgs.writeShellScriptBin "__purge_rm" ''
    exec /bin/rm "$@"
  '');
in {
  # Home-manager 22.11 requires this be set. We never set it so we have
  # to use the old state version.
  home.stateVersion = "18.09";

  # Disabled for now since we mismatch our versions. See flake.nix for details.
  home.enableNixpkgsReleaseCheck = false;

  # We manage our own Nushell config via Chezmoi
  home.shell.enableNushellIntegration = false;

  xdg.enable = true;

  #---------------------------------------------------------------------
  # Packages
  #---------------------------------------------------------------------

  # Packages I always want installed. Most packages I install using
  # per-project flakes sourced with direnv and nix-shell, so this is
  # not a huge list.
  home.packages = [
    safe-rm
    real-rm

    (lib.mkIf isDarwin pkgs._1password-cli)
    pkgs.asciinema
    pkgs.bat
    pkgs.chezmoi
    pkgs.eza
    pkgs.fd
    pkgs.fzf
    pkgs.gh
    pkgs.htop
    pkgs.jq
    pkgs.ripgrep
    pkgs.sentry-cli
    pkgs.starship
    pkgs.tree
    pkgs.watch

    pkgs.gopls
    pkgs.zigpkgs."0.15.2"

    pkgs.rustc
    pkgs.cargo

    pkgs.claude-code
    pkgs.codex

    # Node is required for Copilot.vim
    pkgs.nodejs
  ] ++ (lib.optionals isDarwin [
    # This is automatically setup on Linux
    pkgs.cachix
    pkgs.gettext
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    pkgs.chromium
    pkgs.clang
    pkgs.firefox
    pkgs.rofi
    pkgs.valgrind
    pkgs.zathura
    pkgs.xfce.xfce4-terminal
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "nvim";
    PAGER = "less -FirSwX";
    MANPAGER = "${manpager}/bin/manpager";

    CLAUDE_CODE_MAX_OUTPUT_TOKENS = "64000";
  } // (if isDarwin then {
    # See: https://github.com/NixOS/nixpkgs/issues/390751
    DISPLAY = "nixpkgs-390751";
  } else {});

  home.file = {
    ".gdbinit".source = ./gdbinit;
    ".inputrc".source = ./inputrc;
  };

  xdg.configFile = {
    "i3/config".text = builtins.readFile ./i3;
    "rofi/config.rasi".text = builtins.readFile ./rofi;
  } // (if isDarwin then {
    # Rectangle.app. This has to be imported manually using the app.
    "rectangle/RectangleConfig.json".text = builtins.readFile ./RectangleConfig.json;
  } else {}) // (if isLinux then {
    "ghostty/config".text = builtins.readFile ./ghostty.linux;
  } else {});

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  programs.gpg.enable = !isDarwin;

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = builtins.readFile ./bashrc;
    shellAliases = shellAliases;
  };

  programs.direnv= {
    enable = true;

    config = {
      whitelist = {
        prefix= [
          "$HOME/code/go/src/github.com/hashicorp"
          "$HOME/code/go/src/github.com/jqwang"
        ];

        exact = ["$HOME/.envrc"];
      };
    };
  };

  programs.fish = {
    enable = true;
    shellAliases = shellAliases;
    interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
      "source ${inputs.theme-bobthefish}/functions/fish_prompt.fish"
      "source ${inputs.theme-bobthefish}/functions/fish_right_prompt.fish"
      "source ${inputs.theme-bobthefish}/functions/fish_title.fish"
      (builtins.readFile ./config.fish)
      "set -g SHELL ${pkgs.fish}/bin/fish"
      # Resolve op:// secrets via 1Password CLI
      ''
        if command -q op
          set -gx OPENAI_API_KEY (op read "op://Personal/OpenAPI_Personal/credential" 2>/dev/null)
          set -gx HF_TOKEN (op read "op://Personal/HuggingFace/credential" 2>/dev/null)
          set -gx ANTHROPIC_AUTH_TOKEN (op read "op://Personal/Anthropic/api_key" 2>/dev/null)
          set -e ANTHROPIC_API_KEY
          set -gx ANTHROPIC_BASE_URL (op read "op://Personal/Anthropic/base_url" 2>/dev/null)
        end
      ''
    ] ++ lib.optionals isDarwin [
      # Add TeX Live to PATH on macOS
      "fish_add_path /Library/TeX/texbin"
    ]));

    plugins = map (n: {
      name = n;
      src  = inputs.${n};
    }) [
      "fish-fzf"
      "fish-foreign-env"
      "theme-bobthefish"
    ];
  };

  programs.git = {
    enable = true;
    signing = {
      # Set this to your own GPG key ID (e.g. "0123ABCD") and enable if desired.
      signByDefault = false;
    };
    settings = {
      user.name = "jqwang";
      user.email = "jiaqiwang969@gmail.com";
      branch.autosetuprebase = "always";
      color.ui = true;
      core.askPass = ""; # needs to be empty to use terminal for ask pass
      credential.helper = "store"; # want to make this more secure
      github.user = "jqwang";
      push.default = "tracking";
      init.defaultBranch = "main";
      aliases = {
        cleanup = "!git branch --merged | grep  -v '\\*\\|master\\|develop' | xargs -n 1 -r git branch -d";
        prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
        root = "rev-parse --show-toplevel";
      };
    };
  };

  programs.go = {
    enable = true;
    env = {
      GOPATH = "${config.home.homeDirectory}/Documents/go";
      GOPRIVATE = [ "github.com/jqwang" ];
    };
  };

  programs.jujutsu = {
    enable = true;

    # I don't use "settings" because the path is wrong on macOS at
    # the time of writing this.
  };

  programs.alacritty = {
    enable = !isWSL;

    settings = {
      env.TERM = "xterm-256color";

      key_bindings = [
        { key = "K"; mods = "Command"; chars = "ClearHistory"; }
        { key = "V"; mods = "Command"; action = "Paste"; }
        { key = "C"; mods = "Command"; action = "Copy"; }
        { key = "Key0"; mods = "Command"; action = "ResetFontSize"; }
        { key = "Equals"; mods = "Command"; action = "IncreaseFontSize"; }
        { key = "Subtract"; mods = "Command"; action = "DecreaseFontSize"; }
      ];
    };
  };

  programs.kitty = {
    enable = !isWSL;
    extraConfig = builtins.readFile ./kitty;
  };

  programs.i3status = {
    enable = isLinux && !isWSL;

    general = {
      colors = true;
      color_good = "#8C9440";
      color_bad = "#A54242";
      color_degraded = "#DE935F";
    };

    modules = {
      ipv6.enable = false;
      "wireless _first_".enable = false;
      "battery all".enable = false;
    };
  };

  programs.neovim = {
    enable = true;
    package = inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
  };

  programs.npm = {
    enable = isLinux;
  };

  programs.atuin = {
    enable = true;
  };

  programs.nushell = {
    enable = true;
  };

  programs.oh-my-posh = {
    enable = true;
  };

  services.gpg-agent = {
    enable = isLinux;
    pinentry.package = pkgs.pinentry-tty;

    # cache the keys forever so we don't get asked for a password
    defaultCacheTtl = 31536000;
    maxCacheTtl = 31536000;
  };

  xresources.extraConfig = builtins.readFile ./Xresources;

  # Make cursor not tiny on HiDPI screens
  home.pointerCursor = lib.mkIf (isLinux && !isWSL) {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
    x11.enable = true;
  };
}
