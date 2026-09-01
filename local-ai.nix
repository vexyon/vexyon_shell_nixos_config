{ pkgs, inputs, system, ... }:

let
  comfyPkg = inputs.comfyui-nix.packages.${system}.cuda;

  local-code = pkgs.writeShellScriptBin "local-code" ''
    set -uo pipefail

    export OLLAMA_MODELS=/home/vexyon/Storage/AI-Models-Code

    up() { curl -sf --max-time 1 http://127.0.0.1:11434/api/version >/dev/null 2>&1; }

    if ! up; then
      ollama serve >/dev/null 2>&1 &
      ollama_pid=$!
      trap 'kill "$ollama_pid" 2>/dev/null' EXIT INT TERM HUP
      for _ in $(seq 1 60); do
        up && break
        sleep 0.5
      done
    fi

    opencode "$@"
  '';

  comfyui = pkgs.writeShellScriptBin "comfyui" ''
    set -uo pipefail
    echo "ComfyUI en http://127.0.0.1:8188"
    exec ${comfyPkg}/bin/comfy-ui \
      --listen 127.0.0.1 \
      --port 8188 \
      --base-directory /home/vexyon/Storage/AI-Models-IMG \
      --enable-manager \
      "$@"
  '';
in
{
  nix.settings = {
    substituters = [ "https://cache.nixos-cuda.org" ];
    trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  environment.systemPackages = [ local-code comfyui ];
}
