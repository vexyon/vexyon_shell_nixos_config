{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    vexyon.url = "github:vexyon/vexyon_shell_nixos";
    hermes-agent.url = "github:NousResearch/hermes-agent";
    codex.url = "github:sadjow/codex-cli-nix";
  };

  outputs = inputs@{ nixpkgs, vexyon, hermes-agent, codex, ... }:
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
            environment.systemPackages = [
              hermes-agent.packages.${system}.minimal.hermesDesktop
              codex.packages.${system}.default
            ];
          }
        ];
      };
    };
}
