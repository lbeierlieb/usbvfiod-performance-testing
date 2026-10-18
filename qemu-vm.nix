# The QEMU VM: a NixOS VM with an xHCI controller (as in usbvfiod's own
# integration tests) that runs scripts/vm-bench.sh on boot and powers off.
# The emulated USB stick is added on the QEMU command line at runtime. The
# host's /nix/store is shared with the VM, so every usbvfiod build is
# available inside.
{
  lib,
  pkgs,
  nestedGuest,
}:
let
  vm-bench = pkgs.writeShellApplication {
    name = "vm-bench";
    runtimeInputs = with pkgs; [
      bash
      cloud-hypervisor
      coreutils
      fio
      gnugrep
      gnused
      jq
      usbutils
    ];
    text = ''
      GUEST_BENCH=${./scripts/guest-bench.sh}
      GUEST_KERNEL=${nestedGuest.kernel}
      GUEST_INITRD=${nestedGuest.initrd}
      GUEST_CMDLINE="${nestedGuest.cmdline}"
    ''
    + builtins.readFile ./scripts/vm-bench.sh;
  };

  nixos = lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      (
        { config, modulesPath, ... }:
        {
          imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];

          networking.hostName = "usbbench";

          virtualisation = {
            diskImage = null;
            graphics = false;
            cores = 2;
            memorySize = 4096;
            qemu.options = [ "-device qemu-xhci,id=xhci" ];
          };

          boot.kernelParams = [
            "quiet"
            "loglevel=3"
          ];
          networking.useDHCP = false;
          documentation.enable = false;

          # Keep the console free for the benchmark output.
          systemd.services."serial-getty@ttyS0".enable = false;

          systemd.services.usbbench = {
            wantedBy = [ "multi-user.target" ];
            after = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              StandardOutput = "tty";
              StandardError = "tty";
              TTYPath = "/dev/ttyS0";
              ExecStart = lib.getExe vm-bench;
              ExecStopPost = "${pkgs.systemd}/bin/systemctl poweroff --force --force";
            };
          };

          system.stateVersion = config.system.nixos.release;
        }
      )
    ];
  };
in
nixos.config.system.build.vm
