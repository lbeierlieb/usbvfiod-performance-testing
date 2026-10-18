# Runs inside the QEMU VM and prints everything on its serial console.
# (GUEST_BENCH, GUEST_KERNEL, GUEST_INITRD and GUEST_CMDLINE are set by Nix.)
#
# usbbench.mode= on the kernel command line selects what is measured:
# - baseline: the fio job directly on QEMU's emulated USB stick,
# - qemu: the stick passed through with usb-host to a nested QEMU guest,
# - usbvfiod: the stick passed through to a Cloud Hypervisor guest with the
#   usbvfiod binary given as usbbench.usbvfiod=PATH.
# In both passthrough modes, the nested guest runs the fio job.

# cmdline_param NAME: the value of NAME= on the kernel command line.
cmdline_param() {
  sed -n "s/.*$1=\([^ ]*\).*/\1/p" /proc/cmdline
}

mode=$(cmdline_param 'usbbench\.mode')
case $mode in
baseline)
  bash "$GUEST_BENCH" /dev/sda
  exit
  ;;
qemu | usbvfiod) ;;
*)
  echo "BENCHFAIL unknown usbbench.mode=$mode"
  exit 1
  ;;
esac

# Wait for /dev/kvm and the emulated stick (46f4:0001).
busnum=
devnum=
for _ in $(seq 60); do
  for d in /sys/bus/usb/devices/*; do
    if [ "$(cat "$d/idVendor" 2>/dev/null)" = 46f4 ]; then
      busnum=$(cat "$d/busnum")
      devnum=$(cat "$d/devnum")
    fi
  done
  [ -n "$busnum" ] && [ -e /dev/kvm ] && break
  sleep 1
done
if [ -z "$busnum" ] || [ ! -e /dev/kvm ]; then
  echo "BENCHFAIL no stick or no /dev/kvm"
  exit 1
fi

if [ "$mode" = qemu ]; then
  # The guest's virtio console is hvc0, as in Cloud Hypervisor.
  timeout 600 qemu-system-x86_64 \
    -machine q35,accel=kvm \
    -cpu host \
    -smp 2 \
    -m 2G \
    -nodefaults \
    -display none \
    -serial none \
    -monitor none \
    -kernel "$GUEST_KERNEL" \
    -initrd "$GUEST_INITRD" \
    -append "$GUEST_CMDLINE" \
    -device qemu-xhci,id=xhci \
    -device usb-host,bus=xhci.0,hostbus="$busnum",hostaddr="$devnum" \
    -device virtio-serial-pci \
    -chardev file,id=console,path=/tmp/guest.log \
    -device virtconsole,chardev=console \
    >/tmp/qemu.log 2>&1 || true
else
  usbvfiod=$(cmdline_param 'usbbench\.usbvfiod')
  device=$(printf '/dev/bus/usb/%03d/%03d' "$busnum" "$devnum")
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
fi

# The guest's results, then all logs for debugging.
touch /tmp/guest.log
tr -d '\r' </tmp/guest.log | grep -a '^BENCH' || true
sed 's/^/guest: /' /tmp/guest.log
for log in qemu usbvfiod cloud-hypervisor; do
  if [ -e "/tmp/$log.log" ]; then
    sed "s/^/$log: /" "/tmp/$log.log"
  fi
done
