# The Cloud Hypervisor guest: a NixOS netboot image (as in usbvfiod's own
# integration tests) that runs scripts/guest-bench.sh on boot, prints the
# results on the virtio console (hvc0) and powers off.
{ lib, pkgs }:
let
  nixos = lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      "${pkgs.path}/nixos/modules/installer/netboot/netboot-minimal.nix"
      (
        { config, ... }:
        {
          boot.initrd.kernelModules = [ "virtio_console" ];
          boot.zfs.forceImportRoot = false;
          boot.kernelParams = [
            # Same as usbvfiod's tests: autosuspend is not supported.
            "usbcore.autosuspend=-1"
            "console=hvc0"
            "quiet"
            "loglevel=3"
          ];

          networking.useDHCP = false;
          services.openssh.enable = lib.mkForce false;
          documentation.enable = false;

          # Keep the console free for the benchmark output.
          systemd.services."serial-getty@hvc0".enable = false;
          systemd.services."getty@tty1".enable = false;

          systemd.services.usbbench = {
            wantedBy = [ "multi-user.target" ];
            after = [ "multi-user.target" ];
            path = with pkgs; [
              bash
              coreutils
              fio
              gnused
              jq
              usbutils
            ];
            serviceConfig = {
              Type = "oneshot";
              StandardOutput = "tty";
              StandardError = "tty";
              TTYPath = "/dev/hvc0";
              ExecStart = "${pkgs.bash}/bin/bash ${./scripts/guest-bench.sh} /dev/sda";
              ExecStopPost = "${pkgs.systemd}/bin/systemctl poweroff --force --force";
            };
          };

          system.stateVersion = config.system.nixos.release;
        }
      )
    ];
  };
  inherit (nixos) config;
in
{
  kernel = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
  initrd = "${config.system.build.netbootRamdisk}/initrd";
  cmdline = "init=${config.system.build.toplevel}/init " + toString config.boot.kernelParams;
}
