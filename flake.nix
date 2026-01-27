{
  description = "My system configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    mac-app-util.url = "github:hraban/mac-app-util";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nix-darwin,
      home-manager,
      mac-app-util,
      nix-vscode-extensions,
      nixpkgs,
      ...
    }:
    let
      # Import host-specific information
      hostInfo = import ./host-info.nix;

      # Helper function to apply macOS Sequoia workaround for GUI apps
      # Refs: https://github.com/nix-darwin/nix-darwin/issues/1315
      fixMacOSApp =
        pkg:
        pkg.overrideAttrs (old: {
          installPhase = "whoami\n" + old.installPhase;
        });

      # nix-darwin configuration (system-level, requires sudo)
      darwinConfiguration =
        { pkgs, ... }:
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          nixpkgs.config.allowUnfree = true;
          nix.settings.experimental-features = "nix-command flakes";
          nix.enable = false;

          security.pam.services.sudo_local.touchIdAuth = true;
          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Used for backwards compatibility. please read the changelog
          # before changing: `darwin-rebuild changelog`.
          system.stateVersion = 4;

          # Declare the user that will be running `nix-darwin`.
          users.users.${hostInfo.username} = {
            name = hostInfo.username;
            home = hostInfo.homedir;
            shell = pkgs.fish;
          };

          # Set the primary user for homebrew and other user-specific options
          system.primaryUser = hostInfo.username;

          programs.fish = {
            enable = true;
            shellAliases = {
              "dr:switch" = "sudo -H darwin-rebuild switch --flake ${hostInfo.flakedir}";
            };
          };
          environment.shells = [ pkgs.fish ];

          environment.systemPackages = [
            pkgs.git
            pkgs.fish
          ];

          # Ensure the default shell is set correctly
          system.activationScripts.postActivation.text = ''
            echo "Setting default shell to fish..."
            /usr/bin/chsh -s /run/current-system/sw/bin/fish ${hostInfo.username} || echo "Failed to change shell"
          '';
        };

      # home-manager configuration (user-level, no sudo required)
      homeConfiguration =
        { pkgs, ... }:
        {
          # this is internal compatibility configuration
          # for home-manager, don't change this!
          home.stateVersion = "25.11";

          home.username = hostInfo.username;
          home.homeDirectory = hostInfo.homedir;

          home.packages = with pkgs; [
            git
            nixfmt
            nil
            nodejs-slim
            podman
            google-chrome
            # GUI apps with macOS Sequoia workaround
            (fixMacOSApp podman-desktop)
            (fixMacOSApp shottr)
            (fixMacOSApp warp-terminal)
          ];

          nixpkgs.overlays = [
            nix-vscode-extensions.overlays.default
          ];

          # Let home-manager install and manage itself.
          programs.home-manager.enable = true;

          programs.vscode = {
            enable = true;
            package = fixMacOSApp pkgs.vscode;
            profiles.default.extensions = with pkgs.vscode-marketplace; [
              dbaeumer.vscode-eslint
              eamodio.gitlens
              esbenp.prettier-vscode
              jnoortheen.nix-ide
              mermaidchart.vscode-mermaid-chart

            ];

            profiles.default.userSettings = {
              "claudeCode.preferredLocation" = "panel";
              "editor.defaultFormatter" = "esbenp.prettier-vscode";
              "editor.formatOnSave" = true;
              "nix.enableLanguageServer" = true;
              "nix.serverPath" = "${pkgs.nil}/bin/nil";
              "nix.formatterPath" = "nixfmt";
              "[nix]" = {
                "editor.defaultFormatter" = "jnoortheen.nix-ide";
              };
              "window.nativeTabs" = true;
              "window.restoreWindows" = "preserve";
              "terminal.integrated.profiles.osx" = {
                default = {
                  path = "${pkgs.fish}/bin/fish";
                };
              };
              "terminal.integrated.defaultProfile.osx" = "default";
            };
          };

          programs.fish = {
            enable = true;
            shellAliases = {
              "hm:switch" = "home-manager switch --flake ${hostInfo.flakedir}";
            };
          };

          home.sessionVariables = {
            EDITOR = "code --wait";
          };
        };
    in
    {
      # nix-darwin configuration (apply with: darwin-rebuild switch --flake ~/.config/nix)
      darwinConfigurations.${hostInfo.hostname} = nix-darwin.lib.darwinSystem {
        modules = [
          darwinConfiguration
          mac-app-util.darwinModules.default
        ];
      };

      # Standalone home-manager configuration (apply with: home-manager switch --flake ~/.config/nix)
      homeConfigurations.${hostInfo.username} = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "aarch64-darwin";
          config.allowUnfree = true;
        };
        modules = [
          homeConfiguration
          mac-app-util.homeManagerModules.default
        ];
      };
    };
}
