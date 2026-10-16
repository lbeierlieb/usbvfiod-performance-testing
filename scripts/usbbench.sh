# usbbench
#
# Measures sequential 1 MiB reads from QEMU's emulated USB 3 stick:
# - once directly in the QEMU VM (baseline), and
# - for every merge to usbvfiod's main branch since USB storage works, in a
#   fresh QEMU VM, passed through with that usbvfiod to a Cloud Hypervisor
#   guest.
# Everything lives in ./usbbench-work. Interrupt at any time; a rerun skips
# what is already in results.csv.
# (QEMU_VM and PLOT_PY are set by the flake.)

WORK=$PWD/usbbench-work
CLONE=$WORK/usbvfiod
RESULTS=$WORK/results.csv
STICK=$WORK/stick.img

# The first merge with working USB storage (PR #63, 2025-08-26).
FIRST_MERGE=013e90c

mkdir -p "$WORK"
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
if [ ! -e "$STICK" ]; then
  head -c 1G /dev/urandom >"$STICK.tmp"
  mv "$STICK.tmp" "$STICK"
fi

# run_vm REV DATE DIR [KERNEL_PARAMS]
# Boots a fresh QEMU VM with the emulated stick, keeps its console in
# DIR/vm.log and appends its results to results.csv.
run_vm() {
  local rev=$1 date=$2 dir=$3 params=${4:-} status

  # The VM would read from stdin, which is merges.txt in the loop below.
  QEMU_OPTS="-drive if=none,id=stick,format=raw,file=$STICK -device usb-storage,bus=xhci.0,drive=stick" \
    QEMU_KERNEL_PARAMS="$params" \
    timeout --kill-after=10 900 "$QEMU_VM/bin/run-usbbench-vm" </dev/null >"$dir/vm.log" 2>&1 || true

  tr -d '\r' <"$dir/vm.log" >"$dir/vm.txt"
  if grep -q '^BENCHDONE' "$dir/vm.txt"; then
    status=ok
  else
    status=failed
  fi
  { grep '^BENCHRESULT' "$dir/vm.txt" || true; } |
    while read -r _ job rep bw iops; do
      echo "$rev,$date,$status,$job,$rep,$bw,$iops" >>"$RESULTS"
    done
  if ! grep -q "^$rev," "$RESULTS"; then
    echo "$rev,$date,$status,,,," >>"$RESULTS"
  fi
  echo "    $status"
}

if ! grep -q '^baseline,' "$RESULTS"; then
  echo "=== baseline"
  mkdir -p "$WORK/runs/baseline"
  run_vm baseline - "$WORK/runs/baseline"
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

  run_vm "$rev" "$date" "$run" "usbbench.usbvfiod=$(readlink -f "$run/usbvfiod")/bin/usbvfiod"
done <"$WORK/merges.txt"

python3 "$PLOT_PY" "$CLONE" "$RESULTS" "$WORK/plot.png"
