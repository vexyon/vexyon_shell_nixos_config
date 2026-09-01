{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    vexyon.url = "github:vexyon/vexyon_shell_nixos";
    comfyui-nix.url = "github:utensils/comfyui-nix";
  };

  outputs = inputs@{ nixpkgs, vexyon, comfyui-nix, ... }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs system; };
        modules = [
          ./configuration.nix
          vexyon.nixosModules.vexyon
          {
            services.vexyon = {
              enable = true;
              user = "vexyon";
            };

            users.users.vexyon.extraGroups = [ "wheel" ];
          }
        ];
      };
    };
}
