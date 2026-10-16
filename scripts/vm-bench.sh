# Runs inside the QEMU VM and prints everything on its serial console.
# (GUEST_BENCH, GUEST_KERNEL, GUEST_INITRD and GUEST_CMDLINE are set by Nix.)
#
# Without usbbench.usbvfiod=PATH on the kernel command line, it runs the fio
# job directly on QEMU's emulated USB stick: the baseline. With it, it passes
# the stick through to a Cloud Hypervisor guest with that usbvfiod binary,
# and the guest runs the fio job.

usbvfiod=$(sed -n 's/.*usbbench\.usbvfiod=\([^ ]*\).*/\1/p' /proc/cmdline)
if [ -z "$usbvfiod" ]; then
  bash "$GUEST_BENCH" /dev/sda
  exit
fi

# Wait for /dev/kvm and the emulated stick (46f4:0001) as /dev/bus/usb/BBB/DDD.
device=
for _ in $(seq 60); do
  for d in /sys/bus/usb/devices/*; do
    if [ "$(cat "$d/idVendor" 2>/dev/null)" = 46f4 ]; then
      device=$(printf '/dev/bus/usb/%03d/%03d' "$(cat "$d/busnum")" "$(cat "$d/devnum")")
    fi
  done
  [ -n "$device" ] && [ -e /dev/kvm ] && break
  sleep 1
done
if [ -z "$device" ] || [ ! -e /dev/kvm ]; then
  echo "BENCHFAIL no stick or no /dev/kvm"
  exit 1
fi

"$usbvfiod" --socket-path /tmp/usbvfiod.sock --device "$device" >/tmp/usbvfiod.log 2>&1 &
usbvfiod_pid=$!
for _ in $(seq 50); do
  [ -S /tmp/usbvfiod.sock ] && break
  sleep 0.1
done

timeout 600 cloud-hypervisor \
  --kernel "$GUEST_KERNEL" \
  --initramfs "$GUEST_INITRD" \
  --cmdline "$GUEST_CMDLINE" \
  --cpus boot=2 \
  --memory size=2G,shared=on \
  --user-device socket=/tmp/usbvfiod.sock \
  --console file=/tmp/guest.log \
  --serial off \
  >/tmp/cloud-hypervisor.log 2>&1 || true
kill "$usbvfiod_pid" 2>/dev/null || true

# The guest's results, then all logs for debugging.
tr -d '\r' </tmp/guest.log | grep -a '^BENCH' || true
sed 's/^/guest: /' /tmp/guest.log
sed 's/^/usbvfiod: /' /tmp/usbvfiod.log
sed 's/^/cloud-hypervisor: /' /tmp/cloud-hypervisor.log
