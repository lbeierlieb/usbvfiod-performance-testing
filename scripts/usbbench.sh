# usbbench /dev/bus/usb/BBB/DDD
#
# For every merge to usbvfiod's main branch since real USB sticks work,
# build usbvfiod, boot a Cloud Hypervisor guest with the USB stick passed
# through, and record the guest's read performance in results.csv.
# Everything lives in ./usbbench-work. Interrupt at any time; a rerun skips
# the revisions that are already in results.csv.
# (GUEST_KERNEL, GUEST_INITRD, GUEST_CMDLINE and PLOT_PY are set by the flake.)

if [ $# -ne 1 ]; then
  echo "usage: usbbench /dev/bus/usb/BBB/DDD" >&2
  exit 1
fi
DEVICE=$1
WORK=$PWD/usbbench-work
CLONE=$WORK/usbvfiod
RESULTS=$WORK/results.csv

# The first merge that works with real USB sticks (PR #104, 2025-10-16).
# Before PR #78 only the bulk endpoints of QEMU's emulated stick were
# supported, and before PR #104 usbvfiod gave up when a bulk OUT transfer
# took longer than 800 ms, which happens on the first one after a reset.
FIRST_MERGE=cc50318

check_device() {
  if [ ! -r "$DEVICE" ] || [ ! -w "$DEVICE" ]; then
    echo "$DEVICE is missing or not read/writable. If the stick got a new" >&2
    echo "device number, fix that and rerun with the new path." >&2
    exit 1
  fi
}
check_device

mkdir -p "$WORK"
# Unix socket paths are limited to 108 bytes, too short for the run directory.
SOCKET=$(mktemp -d)/usbvfiod.sock
if [ ! -d "$CLONE" ]; then
  git clone https://github.com/cyberus-technology/usbvfiod "$CLONE"
fi
if [ ! -e "$WORK/merges.txt" ]; then
  git -C "$CLONE" log --first-parent --merges --reverse --format='%H %cs' \
    "$FIRST_MERGE^..origin/main" >"$WORK/merges.txt"
fi
if [ ! -e "$RESULTS" ]; then
  echo "rev,date,status,job,rep,bw_kib,iops" >"$RESULTS"
fi

while read -r rev date; do
  if grep -q "^$rev," "$RESULTS"; then
    continue
  fi
  run=$WORK/runs/$rev
  rm -rf "$run"
  mkdir -p "$run"
  echo "=== $rev ($date)"

  # Build with the revision's own flake.lock; skip its tests.
  if ! nix build --impure -L -o "$run/usbvfiod" --expr "
      (builtins.getFlake \"git+file://$CLONE?rev=$rev\")
        .packages.x86_64-linux.default.overrideAttrs { doCheck = false; }
    " >"$run/build.log" 2>&1; then
    echo "$rev,$date,build-failed,,,," >>"$RESULTS"
    continue
  fi

  # usbvfiod resets the stick at launch only since PR #87 (2025-09-25).
  # Older revisions leave it in a bad state for the next launch, so reset it
  # here before every revision alike.
  usbreset "${DEVICE#/dev/bus/usb/}" >"$run/usbreset.log" 2>&1
  check_device
  rm -f "$SOCKET"
  "$run/usbvfiod/bin/usbvfiod" --socket-path "$SOCKET" \
    --device "$DEVICE" >"$run/usbvfiod.log" 2>&1 &
  usbvfiod_pid=$!
  for _ in $(seq 50); do
    [ -S "$SOCKET" ] && break
    sleep 0.1
  done

  # Boot takes well under a minute, the fio runs 3 x 17s.
  timeout --kill-after=10 600 cloud-hypervisor \
    --kernel "$GUEST_KERNEL" \
    --initramfs "$GUEST_INITRD" \
    --cmdline "$GUEST_CMDLINE" \
    --cpus boot=2 \
    --memory size=4G,shared=on \
    --user-device socket="$SOCKET" \
    --console file="$run/console.log" \
    --serial off \
    >"$run/cloud-hypervisor.log" 2>&1 || true
  kill "$usbvfiod_pid" 2>/dev/null || true
  wait "$usbvfiod_pid" 2>/dev/null || true

  tr -d '\r' <"$run/console.log" >"$run/console.txt" 2>/dev/null || true
  if grep -q '^BENCHDONE' "$run/console.txt"; then
    status=ok
  else
    status=failed
  fi
  { grep '^BENCHRESULT' "$run/console.txt" || true; } |
    while read -r _ job rep bw iops; do
      echo "$rev,$date,$status,$job,$rep,$bw,$iops" >>"$RESULTS"
    done
  if ! grep -q "^$rev," "$RESULTS"; then
    echo "$rev,$date,$status,,,," >>"$RESULTS"
  fi
  echo "    $status"

  # Give the stick a moment before the next usbvfiod grabs it.
  sleep 3
done <"$WORK/merges.txt"

python3 "$PLOT_PY" "$CLONE" "$RESULTS" "$WORK/plot.png"
