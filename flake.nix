{
  description = "Benchmark USB stick read performance through usbvfiod across its history";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      guest = import ./chv-guest.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
      };
      usbbench = pkgs.writeShellApplication {
        name = "usbbench";
        runtimeInputs = with pkgs; [
          cloud-hypervisor
          coreutils
          git
          gnugrep
          nix
          usbutils
          (python3.withPackages (ps: [ ps.matplotlib ]))
        ];
        text = ''
          GUEST_KERNEL=${guest.kernel}
          GUEST_INITRD=${guest.initrd}
          GUEST_CMDLINE="${guest.cmdline}"
          PLOT_PY=${./scripts/plot.py}
        ''
        + builtins.readFile ./scripts/usbbench.sh;
      };
    in
    {
      packages.x86_64-linux.default = usbbench;
    };
}
