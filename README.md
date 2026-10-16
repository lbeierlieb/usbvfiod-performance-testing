# usbvfiod performance across its history

Measures how fast a Cloud Hypervisor guest reads from a USB 3 stick passed
through with [usbvfiod](https://github.com/cyberus-technology/usbvfiod), for
every merge to `main` since it works with real USB sticks (PR #104, 2025-10-16).
Earlier merges either supported only the endpoints of QEMU's emulated USB
stick, or gave up when a real stick took longer than 800 ms for the first bulk
transfer after a reset.

For each merge, `usbbench`

1. builds usbvfiod with that revision's own `flake.lock` (tests skipped),
2. resets the stick (`usbreset`, as usbvfiod itself does since PR #87) and
   starts usbvfiod with `--device /dev/bus/usb/BBB/DDD`,
3. boots a fixed NixOS guest in a fixed Cloud Hypervisor version,
4. lets the guest read `/dev/sda` sequentially in 1 MiB blocks for 15 s, three
   times (fio, read-only, `O_DIRECT`, queue depth 1). 1 MiB is the largest
   command the guest's usb-storage driver sends to a USB 3 device,
5. appends the results to `usbbench-work/results.csv`.

At the end it draws `usbbench-work/plot.png`: the median of the three
repetitions, with failed revisions and releases marked.

The stick is only read, never written.

## Running

Requirements: x86_64 Linux, Nix with flakes, `/dev/kvm` access.

```console
$ lsusb                                     # find the stick, e.g. Bus 002 Device 003
$ sudo chown $USER /dev/bus/usb/002/003
$ nix run . -- /dev/bus/usb/002/003
```

Each revision takes roughly 2 minutes plus its build, so the whole run takes
a night. It can be interrupted at any time; a rerun skips revisions that
already have results. To retry a revision, delete its lines from
`results.csv`.

If the stick re-enumerates (new device number), the script stops. Give the
new device node your user and rerun with the new path.

Per-revision logs (build, usbvfiod, Cloud Hypervisor, guest console) are in
`usbbench-work/runs/<rev>/`.
