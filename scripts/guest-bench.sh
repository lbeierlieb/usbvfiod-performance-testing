# guest-bench.sh BLOCKDEVICE
#
# Read-only fio jobs against the USB stick: in the guest on the passed-through
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

# Repetitions are the outer loop so that slow drift affects all jobs alike.
for rep in 1 2 3; do
  for job in "seq1m read 1M" "seq64k read 64k" "rand4k randread 4k"; do
    read -r name rw bs <<<"$job"
    if ! out=$(timeout 120 fio --readonly --output-format=json \
      --name="$name" --filename="$dev" --direct=1 --ioengine=psync \
      --rw="$rw" --bs="$bs" --ramp_time=2 --runtime=15 --time_based); then
      echo "BENCHFAIL fio $name"
      exit 1
    fi
    jq -r --arg rep "$rep" \
      '.jobs[0] | "BENCHRESULT \(.jobname) \($rep) \(.read.bw) \(.read.iops)"' <<<"$out"
  done
done

echo "BENCHDONE"
