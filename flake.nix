{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    vexyon.url = "github:vexyon/vexyon_shell_nixos";
    comfyui-nix.url = "github:utensils/comfyui-nix";
  };

  outputs = { nixpkgs, vexyon, comfyui-nix, ... }: {
    # ⚠ REPLACE `myhost` with your own machine's hostname (an identifier — run
    #   `hostname` in a terminal if you are not sure what yours is).
    #   `myhost` appears TWICE: here, and in the `nixos-rebuild switch
    #   --flake .#myhost` command further down. The two MUST match exactly, or
    #   the rebuild will not find this configuration.
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        vexyon.nixosModules.vexyon
        comfyui-nix.nixosModules.default
        {
          nixpkgs.overlays = [ comfyui-nix.overlays.default ];
          services.vexyon = {
            enable = true;
            # ⚠ REQUIRED — replace `yourname` with your actual Linux username.
            #   `yourname` appears TWICE in this example: here, and in the
            #   `users.users.yourname` line below. Change BOTH, to the same
            #   username.
            user = "vexyon";
          };

          # The power menu's polkit rule grants the login1 actions to `wheel`,
          # so the user must be in it or suspend/reboot/shutdown will ask for a
          # password the shell cannot prompt for.
          #
          # ⚠ SECOND occurrence of `yourname` — replace it here too, with the
          #   same username you used above.
          users.users.vexyon.extraGroups = [ "wheel" ];

          # ComfyUI, sin tocar configuration.nix
          services.comfyui = {
            enable = true;
            gpuSupport = "cuda";
            enableManager = true;
            port = 8188;
            listenAddress = "127.0.0.1";
            dataDir = "/home/vexyon/Storage/AI-Models";
            openFirewall = false;
        }
      ];
    };
  };
}
