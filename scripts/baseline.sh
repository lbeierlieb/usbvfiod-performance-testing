# baseline /dev/sdX
#
# Runs the guest's fio jobs natively on the host's block device of the stick
# and prints the median of the three repetitions per job. The raw output is
# kept in usbbench-work/baseline.log.
# (GUEST_BENCH is set by the flake.)

if [ $# -ne 1 ]; then
  echo "usage: baseline /dev/sdX" >&2
  exit 1
fi
mkdir -p usbbench-work
bash "$GUEST_BENCH" "$1" | tee usbbench-work/baseline.log

echo
echo "native baseline, median of 3 runs:"
for job in seq1m seq64k rand4k; do
  grep "^BENCHRESULT $job " usbbench-work/baseline.log | cut -d' ' -f4,5 | sort -n | sed -n 2p |
    awk -v job="$job" '{ printf "%-7s %8.1f MB/s %8.0f IOPS\n", job, $1 * 1024 / 1e6, $2 }'
done
