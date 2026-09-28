{ pkgs, lib, ... }:

let
  tools = import ./pkgs/packages.nix { inherit pkgs; };
  inherit (tools) ezdialog ezresolution ezhwconfig ezpartition ezinstall;
in
{
  # NixOS doesn't enable these by default. Required for `nixos-install --flake`,
  # ezinstall's `nix eval` hostname detection, and ezconf's own autocomplete
  # generation (which also shells out to `nix eval` against a flake).
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # --- Minimal graphical environment ------------------------------------
  services.xserver.enable = true;
  services.xserver.windowManager.openbox.enable = true;
  services.displayManager.defaultSession = "none+openbox";

  # There's only ever one X display on this live ISO (:0) - export it
  # globally so GUI programs also work from ezconf's terminal panel (which
  # runs as root, with no DISPLAY of its own otherwise), not just from the
  # per-button `DISPLAY=:0 ...` commands already set individually below.
  environment.variables.DISPLAY = ":0";

  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "nixos";
  };

  # installation-device.nix sets initialHashedPassword = "" (passwordless
  # login) for the live "nixos" user; override it rather than also setting
  # initialPassword, since NixOS asserts only one of those may be non-null.
  # Matches ezconf's own web UI password so there's one password to remember.
  users.users.nixos = {
    initialHashedPassword = lib.mkForce null;
    initialPassword = "ezconf";
  };

  # Suppress Firefox's first-run onboarding/privacy-notice screens - this ISO
  # only ever opens it pointed straight at ezconf, so nobody should see the
  # welcome tab, default-browser prompt, or data-collection notice first.
  # /etc/firefox/policies/policies.json (written below) is a fixed path any
  # firefox binary reads at startup, regardless of which one is launched.
  programs.firefox = {
    enable = true;
    policies = {
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      DontCheckDefaultBrowser = true;
      DisableTelemetry = true;
      # Stops the "save password?" prompt when logging into ezconf.
      PasswordManagerEnabled = false;
    };
    preferences = {
      "browser.aboutwelcome.enabled" = false;
      "datareporting.policy.dataSubmissionEnabled" = false;
      # dataSubmissionEnabled alone doesn't stop the "Firefox Privacy Notice"
      # tab/notification bar from appearing on first run - Firefox still opens
      # it until it sees the notification itself as bypassed.
      "datareporting.policy.dataSubmissionPolicyBypassNotification" = true;
      # Firefox's built-in dark theme is a lightweight theme add-on
      # (firefox-compact-dark@mozilla.org) selected via this pref - same
      # mechanism as picking it manually in about:addons.
      "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
    };
  };

  # Fonts so web pages don't render as tofu boxes.
  fonts.fontconfig.enable = true;
  fonts.packages = with pkgs; [
    dejavu_fonts
    liberation_ttf
    noto-fonts-color-emoji
  ];

  # Launch a browser straight at the ezconf UI on login.
  services.xserver.displayManager.sessionCommands = ''
    # ezconf's terminal panel runs commands as root (services.ezconf's own
    # user), not as the "nixos" user this X session belongs to, so it has no
    # XAuthority cookie for this display - relax access control for local
    # connections so setxkbmap (run as root, from the terminal buttons) can
    # still reach this session's X server regardless of who's connected to
    # ezconf's web UI or which user ran the command.
    ${pkgs.xhost}/bin/xhost +local: || true

    ${pkgs.firefox}/bin/firefox --new-window --kiosk "http://localhost:9090" &

    # Openbox has no separate style-only setting like fluxbox - the theme
    # name lives inside its full rc.xml, so copy the package's own default
    # config (unlike fluxbox's init file, this one's too large to hand-write
    # and still needs its keybindings/mouse bindings) and patch just the
    # <theme><name> line before openbox-session starts and reads it. Onyx is
    # a plain dark gray, close enough to ezconf's own dark look; barely
    # visible anyway since Firefox launches fullscreen straight away.
    mkdir -p "$HOME/.config/openbox"
    sed 's|<name>Clearlooks</name>|<name>Onyx</name>|' \
      "${pkgs.openbox}/etc/xdg/openbox/rc.xml" > "$HOME/.config/openbox/rc.xml"
  '';

  environment.systemPackages = [ pkgs.gparted pkgs.xterm ezinstall ezpartition ezhwconfig ezdialog ezresolution ];

  # --- ezconf --------------------------------------------------------------
  services.ezconf = {
    enable = true;
    https = false; # localhost-only ephemeral live session, avoid self-signed cert friction
    listen = "0.0.0.0"; # reachable from other machines on the network, not just localhost
    trustedHosts = [ "*" ]; # disable the Host-header/CSRF check so any address/hostname can connect
    # configDir intentionally left at ezconf's own default ("/etc/nixos/ezconf")
    # rather than pointed at /etc/nixos itself - ezconf's generated default.nix
    # and *.json tabs stay confined to that subdirectory instead of landing
    # directly in /etc/nixos, where ezinstall's `cp -a /etc/nixos/.` would
    # otherwise carry them permanently into the installed system's top-level
    # config dir.
    mode = "install"; # dedicated install image: show mode = "install" buttons in their own row
    generateAutocomplete = false; # skip the first-start ezconf-mkoptions eval; use the UI's Autocomplete button instead
    auth = {
      method = "custom";
      username = "nixos";
      password = "ezconf";
    };

    # ezconf's built-in terminal panel is a real interactive shell — use it to
    # load your system (git clone a flake repo, or write configuration.nix by
    # hand) and to partition/mount your disk at /mnt however that config
    # expects (disko, manual parted/mkfs, ...) before clicking Install NixOS.
    buttons = [
      {
        label = "US";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 setxkbmap us";
        menu = "Ezmenu/Keyboard layout";
      }
      {
        label = "UK";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 setxkbmap gb";
        menu = "Ezmenu/Keyboard layout";
      }
      {
        label = "German";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 setxkbmap de";
        menu = "Ezmenu/Keyboard layout";
      }
      {
        label = "Swedish";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 setxkbmap se";
        menu = "Ezmenu/Keyboard layout";
      }
      {
        label = "French";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 setxkbmap fr";
        menu = "Ezmenu/Keyboard layout";
      }
      {
        label = "List disks";
        mode = "install";
        static = true;
        command = "lsblk -o NAME,SIZE,MODEL,TYPE,LABEL,MOUNTPOINT";
        menu = "Ezmenu";
      }
      {
        label = "Launch terminal";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 xterm -rv >/dev/null 2>&1 & disown";
        menu = "Ezmenu";
      }
      {
        label = "GParted";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 gparted >/dev/null 2>&1 & disown";
        menu = "Ezmenu/Partition";
      }
      {
        label = "1024x768";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 ezresolution 1024x768";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "1280x720";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 ezresolution 1280x720";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "1366x768";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 ezresolution 1366x768";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "1920x1080";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 ezresolution 1920x1080";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "2560x1440";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 ezresolution 2560x1440";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "3840x2160";
        mode = "install";
        static = true;
        command = "DISPLAY=:0 ezresolution 3840x2160";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "Partition disks (guided)";
        mode = "install";
        static = true;
        command = "ezpartition";
        menu = "Ezmenu/Partition";
      }
      {
        label = "With disks";
        mode = "install";
        static = true;
        command = "ezhwconfig";
        menu = "Ezmenu/Hardware config";
      }
      {
        label = "Without disks";
        mode = "install";
        static = true;
        command = "ezhwconfig --no-filesystems";
        menu = "Ezmenu/Hardware config";
      }
      {
        label = "Install NixOS";
        mode = "install";
        static = true;
        command = "ezinstall";
        save_first = true;
        menu = "Ezmenu";
      }
      {
        label = "Reboot";
        mode = "install";
        static = true;
        command = "reboot";
        menu = "Ezmenu";
      }
    ];
  };
}
