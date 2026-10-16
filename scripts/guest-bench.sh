# Runs inside the guest: read-only fio jobs against the passed-through USB
# stick. Every result is printed as one line on the console:
#   BENCHRESULT <job> <rep> <bandwidth KiB/s> <IOPS>
# followed by BENCHDONE, or BENCHFAIL if something went wrong.

for _ in $(seq 120); do
  [ -b /dev/sda ] && break
  sleep 1
done
if [ ! -b /dev/sda ]; then
  echo "BENCHFAIL no /dev/sda"
  exit 1
fi
lsusb -t | sed 's/^/BENCHINFO /'

# Repetitions are the outer loop so that slow drift affects all jobs alike.
for rep in 1 2 3; do
  for job in "seq1m read 1M" "seq64k read 64k" "rand4k randread 4k"; do
    read -r name rw bs <<<"$job"
    if ! out=$(timeout 120 fio --readonly --output-format=json \
      --name="$name" --filename=/dev/sda --direct=1 --ioengine=psync \
      --rw="$rw" --bs="$bs" --ramp_time=2 --runtime=15 --time_based); then
      echo "BENCHFAIL fio $name"
      exit 1
    fi
    jq -r --arg rep "$rep" \
      '.jobs[0] | "BENCHRESULT \(.jobname) \($rep) \(.read.bw) \(.read.iops)"' <<<"$out"
  done
done

echo "BENCHDONE"
