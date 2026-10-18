{
  description = "Benchmark usbvfiod's USB storage read performance across its history";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      inherit (nixpkgs) lib;
      nestedGuest = import ./nested-guest.nix { inherit lib pkgs; };
      qemuVm = import ./qemu-vm.nix { inherit lib pkgs nestedGuest; };
      usbbench = pkgs.writeShellApplication {
        name = "usbbench";
        runtimeInputs = with pkgs; [
          coreutils
          git
          gnugrep
          nix
          (python3.withPackages (ps: [ ps.matplotlib ]))
        ];
        text = ''
          QEMU_VM=${qemuVm}
          PLOT_PY=${./scripts/plot.py}
        ''
        + builtins.readFile ./scripts/usbbench.sh;
      };
      sysinfo = pkgs.writeShellApplication {
        name = "sysinfo";
        runtimeInputs = with pkgs; [
          coreutils
          gnugrep
          util-linux
        ];
        text = builtins.readFile ./scripts/sysinfo.sh;
      };
    in
    {
      packages.x86_64-linux.default = usbbench;
      packages.x86_64-linux.sysinfo = sysinfo;
    };
}
