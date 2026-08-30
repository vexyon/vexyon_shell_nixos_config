{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    vexyon.url = "github:vexyon/vexyon_shell_nixos";
    comfyui-nix.url = "github:utensils/comfyui-nix";
  };

  outputs = { nixpkgs, vexyon, comfyui-nix, ... }: {
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
            user = "vexyon";
          };

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
          };
        }
      ];
    };
  };
}
