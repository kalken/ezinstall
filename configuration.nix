{ pkgs, lib, ... }:

let
  tools = import ./pkgs/packages.nix { inherit pkgs; };
  inherit (tools) ezdialog ezresolution ezhwconfig ezpartition ezinstall;
in
{
  # NixOS doesn't enable these by default. Required for `nixos-install --flake`,
  # ezinstall's `nix eval` hostname detection, and eznix's own autocomplete
  # generation (which also shells out to `nix eval` against a flake).
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # --- Minimal graphical environment ------------------------------------
  services.xserver.enable = true;
  services.xserver.windowManager.openbox.enable = true;
  services.displayManager.defaultSession = "none+openbox";

  # There's only ever one X display on this live ISO (:0) - export it
  # globally so GUI programs also work from eznix's terminal panel (a
  # service of its own, outside the X session, with no DISPLAY otherwise;
  # its login shell picks this up).
  environment.variables.DISPLAY = ":0";

  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "nixos";
  };

  # installation-device.nix sets initialHashedPassword = "" (passwordless
  # login) for the live "nixos" user; override it rather than also setting
  # initialPassword, since NixOS asserts only one of those may be non-null.
  # This is also the password of eznix's web UI: eznix logs people in with
  # their system password (services.eznix.users below).
  users.users.nixos = {
    initialHashedPassword = lib.mkForce null;
    initialPassword = "eznix";
  };

  # Suppress Firefox's first-run onboarding/privacy-notice screens - this ISO
  # only ever opens it pointed straight at eznix, so nobody should see the
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
      # Stops the "save password?" prompt when logging into eznix.
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

  # Launch a browser straight at the eznix UI on login.
  services.xserver.displayManager.sessionCommands = ''
    # eznix's terminal panel runs commands as the "nixos" user, the one this
    # X session belongs to, but from a service of its own that was not
    # started inside the session and has no XAuthority cookie for this
    # display - and GParted is started from there through sudo, as root.
    # Relax access control for local connections so both can reach this
    # session's X server (setxkbmap, xterm, gparted from the terminal buttons).
    ${pkgs.xhost}/bin/xhost +local: || true

    ${pkgs.firefox}/bin/firefox --new-window --kiosk "http://localhost:9090" &

    # Openbox has no separate style-only setting like fluxbox - the theme
    # name lives inside its full rc.xml, so copy the package's own default
    # config (unlike fluxbox's init file, this one's too large to hand-write
    # and still needs its keybindings/mouse bindings) and patch just the
    # <theme><name> line before openbox-session starts and reads it. Onyx is
    # a plain dark gray, close enough to eznix's own dark look; barely
    # visible anyway since Firefox launches fullscreen straight away.
    mkdir -p "$HOME/.config/openbox"
    sed 's|<name>Clearlooks</name>|<name>Onyx</name>|' \
      "${pkgs.openbox}/etc/xdg/openbox/rc.xml" > "$HOME/.config/openbox/rc.xml"
  '';

  environment.systemPackages = [ pkgs.gparted pkgs.xterm ezinstall ezpartition ezhwconfig ezdialog ezresolution ];

  # --- eznix ---------------------------------------------------------------
  # Nothing in eznix runs as root: the editor is its own account, and the
  # terminal panel (so every button below) runs as "nixos". What needs root
  # says so with sudo, which that user has without a password on a live image.
  services.eznix = {
    enable = true;
    users = [ "nixos" ]; # who logs in, with the system password set above, and whose terminal it is
    enableHttps = false; # ephemeral live session, avoid self-signed cert friction
    interfaces = [ ]; # every interface, whatever this machine's are called: reachable from other machines on the network, not just here
    openFirewall = true;
    # No hosts = [ "*" ]: an address is always accepted, and eznix adds this
    # machine's name (nixos) by itself. "*" let any website that
    # points its own name at this machine (DNS rebinding) log in with the
    # public password above and open a root shell; removed 2026-10-19.
    # flake and configDir intentionally left at eznix's own defaults
    # ("/etc/nixos" and "/etc/nixos/eznix"): the *.json tabs stay in that
    # subfolder, which the starting config in templates/default.zip imports
    # with eznix.lib.jsonDir, and ezinstall's `cp -a /etc/nixos/.` carries the
    # whole flake into the installed system as it is.
    mode = "install"; # dedicated install image: show mode = "install" buttons in their own row
    # The terminal is where the install happens, so it stays open on a click
    # in the editor (the user, 2026-10-13).
    terminalAutoHide = false;
    # Nothing is loaded into /etc/nixos at startup: the System menu offers the
    # starting setups under "Start from ezinstall" (every zip in templates/ of
    # this repository, on GitHub), and the suggestions are generated by
    # themselves after each import (the Autocomplete button does the same).
    plugins.system = {
      autocomplete = true;
      sources = [
        {
          name = "Start from ezinstall";
          url = "https://github.com/kalken/ezinstall/tree/main/templates";
        }
      ];
    };

    # eznix's built-in terminal panel is a real interactive shell — use it to
    # load your system (git clone a flake repo, or write configuration.nix by
    # hand) and to partition/mount your disk at /mnt however that config
    # expects (disko, manual parted/mkfs, ...) before clicking Install NixOS.
    buttons = [
      {
        label = "US";
        mode = "install";
        static = true;
        command = "setxkbmap us";
        menu = "Ezmenu/Keyboard layout";
      }
      {
        label = "UK";
        mode = "install";
        static = true;
        command = "setxkbmap gb";
        menu = "Ezmenu/Keyboard layout";
      }
      {
        label = "German";
        mode = "install";
        static = true;
        command = "setxkbmap de";
        menu = "Ezmenu/Keyboard layout";
      }
      {
        label = "Swedish";
        mode = "install";
        static = true;
        command = "setxkbmap se";
        menu = "Ezmenu/Keyboard layout";
      }
      {
        label = "French";
        mode = "install";
        static = true;
        command = "setxkbmap fr";
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
        command = "xterm -rv >/dev/null 2>&1 & disown";
        menu = "Ezmenu";
      }
      {
        label = "Launch Firefox";
        mode = "install";
        static = true;
        command = "firefox >/dev/null 2>&1 & disown";
        menu = "Ezmenu";
      }
      {
        label = "GParted";
        mode = "install";
        static = true;
        command = "sudo -E gparted >/dev/null 2>&1 & disown";
        menu = "Ezmenu/Partition";
      }
      {
        label = "1024x768";
        mode = "install";
        static = true;
        command = "ezresolution 1024x768";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "1280x720";
        mode = "install";
        static = true;
        command = "ezresolution 1280x720";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "1366x768";
        mode = "install";
        static = true;
        command = "ezresolution 1366x768";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "1920x1080";
        mode = "install";
        static = true;
        command = "ezresolution 1920x1080";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "2560x1440";
        mode = "install";
        static = true;
        command = "ezresolution 2560x1440";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "3840x2160";
        mode = "install";
        static = true;
        command = "ezresolution 3840x2160";
        menu = "Ezmenu/Resolution";
      }
      {
        label = "Partition disks (guided)";
        mode = "install";
        static = true;
        command = "sudo ezpartition";
        menu = "Ezmenu/Partition";
      }
      {
        label = "With disks";
        mode = "install";
        static = true;
        command = "sudo ezhwconfig";
        menu = "Ezmenu/Hardware config";
      }
      {
        label = "Without disks";
        mode = "install";
        static = true;
        command = "sudo ezhwconfig --no-filesystems";
        menu = "Ezmenu/Hardware config";
      }
      {
        label = "Install NixOS";
        mode = "install";
        static = true;
        command = "sudo ezinstall";
        save_first = true;
        menu = "Ezmenu";
      }
      {
        label = "Reboot";
        mode = "install";
        static = true;
        command = "sudo reboot";
        menu = "Ezmenu";
      }
    ];
  };
}
