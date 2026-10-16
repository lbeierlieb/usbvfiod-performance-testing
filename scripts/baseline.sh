# baseline /dev/sdX
#
# Runs the guest's fio job natively on the host's block device of the stick
# and prints the median of the three repetitions. The raw output is kept in
# usbbench-work/baseline.log.
# (GUEST_BENCH is set by the flake.)

if [ $# -ne 1 ]; then
  echo "usage: baseline /dev/sdX" >&2
  exit 1
fi
mkdir -p usbbench-work
bash "$GUEST_BENCH" "$1" | tee usbbench-work/baseline.log

echo
echo "native baseline, median of 3 runs:"
grep '^BENCHRESULT ' usbbench-work/baseline.log | cut -d' ' -f4,5 | sort -n | sed -n 2p |
  awk '{ printf "%.1f MB/s, %.0f IOPS\n", $1 * 1024 / 1e6, $2 }'
