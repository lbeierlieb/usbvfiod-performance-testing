# guest-bench.sh BLOCKDEVICE
#
# Read-only fio job against the USB stick: in the guest on the passed-through
# stick, and natively for the baseline. Every result is printed as one line:
#   BENCHRESULT <job> <rep> <bandwidth KiB/s> <IOPS>
# followed by BENCHDONE, or BENCHFAIL if something went wrong.

dev=$1

for _ in $(seq 120); do
  [ -b "$dev" ] && break
  sleep 1
done
if [ ! -b "$dev" ]; then
  echo "BENCHFAIL no $dev"
  exit 1
fi
lsusb -t | sed 's/^/BENCHINFO /'

# 1 MiB is the largest SCSI command usb-storage sends to USB 3 devices, so
# every read is exactly one Bulk-Only Transport command.
for rep in 1 2 3; do
  if ! out=$(timeout 120 fio --readonly --output-format=json \
    --name=seq1m --filename="$dev" --direct=1 --ioengine=psync \
    --rw=read --bs=1M --ramp_time=2 --runtime=15 --time_based); then
    echo "BENCHFAIL fio"
    exit 1
  fi
  jq -r --arg rep "$rep" \
    '.jobs[0] | "BENCHRESULT \(.jobname) \($rep) \(.read.bw) \(.read.iops)"' <<<"$out"
done

echo "BENCHDONE"
