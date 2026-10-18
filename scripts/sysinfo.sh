# sysinfo.sh: prints the hardware and kernel of this machine, to keep next to
# a set of runs.

dmi() {
  cat "/sys/class/dmi/id/$1" 2>/dev/null || echo "?"
}

echo "machine: $(dmi sys_vendor) $(dmi product_name)"
echo "kernel: $(uname -r)"
echo
lscpu | grep -E '^ *(Model name|Socket|Core|Thread|CPU\(s\)|CPU max MHz|Virtualization|Hypervisor vendor)'
echo
grep MemTotal /proc/meminfo
echo
lsblk -d -o NAME,MODEL,SIZE,ROTA,TRAN
