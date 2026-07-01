#! /bin/bash 

############### Architecture ###############
ARC=$(uname -a)

############### Physical Processors Count (physical CPU) ###############
P_PROC_COUNT=$(cat /proc/cpuinfo | grep 'physical id' | sort | uniq | wc -l)

############### Virtual Processors Count (virtual CPU) ###############
V_PROC_COUNT=$(cat /proc/cpuinfo | grep 'processor' | wc -l)

############### RAM Usage ###############
MEM=$(free --mega | awk '/^Mem/') #to get memory (RAM) record in megabytes
MEM_USE=$(echo $MEM | awk '{printf "%s/%sMB (%.2f%%)", $3, $2, $3*100/$2}')
# printf: $3 is third line of MEM and  then $2 second line third is calculation of percentage

############### Disk Usage ###############
# --block-size in GB or MB , with only real partitions starting with dev. Add up whole column
# 2 and when done (END) print that sum into DISK_T_GB
DISK_T_GB=$(df --block-size=GB | grep '^\/dev' | awk '{sum += $2} END {print sum}')
# same but with used MB 
DISK_U_MB=$(df --block-size=MB | grep '^\/dev' | awk '{sum += $3} END {print sum}')
# count amount of partitions with i. Reads and adds up the $5th column and at the end divides
# that sum by the amount of elements to store that percentage in DISK_U_PER
DISK_U_PER=$(df | grep '^\/dev' | awk '{i++; sum += $5} END {printf "%.2f%%", sum/i}')
# store it formatted and in the right constalation in DISK_USE
DISK_USE=$(echo "${DISK_U_MB}/${DISK_T_GB}Gb (${DISK_U_PER})")

############### CPU Utilization ###############
# execute top once and then quit it. -F, seperate columns at commas not spaces
# ouput only line three from top
CPU_USE=$(top -bn 1 | awk -F, 'NR==3 {printf "%.1f%%", 100-$4}')

############### Last Boot ###############
LAST_BOOT=$(who -b | awk '{print $3, $4}')

############### LVM Use ###############
LVM_COUNT=$(lsblk | grep 'lvm' | wc -l)
LVM_USE=$(if [ $LVM_COUNT -gt 0 ]; then echo yes; else echo no; fi)

############### TCP Connections ###############
TCP=$(ss -t | grep 'ESTAB' | wc -l | awk '{printf "%d ESTABLISHED", $0}')

############### User Log ###############
LOG_COUNT=$(users | sed 's/ /\n/g' | sort | uniq | wc -l)

############### Network ###############
IP=$(hostname -I)
MAC=$(ip address | grep 'ether' | awk 'NR==1 {print $2}')
NETWORK=$(echo "IP ${IP}(${MAC})")

############### Sudo ###############
# The command below should be run with root privileges to show count for all users
SUDO_COUNT=$(journalctl | grep 'sudo.*COMMAND' | wc -l | awk '{print $0, "cmd"}')

wall "\
 #Architecture: $ARC
 #CPU physical : $P_PROC_COUNT
 #vCPU : $V_PROC_COUNT
 #Memory Usage: $MEM_USE
 #Disk Usage: $DISK_USE
 #CPU load: $CPU_USE
 #Last boot: $LAST_BOOT
 #LVM use: $LVM_USE
 #Connections TCP : $TCP
 #User log: $LOG_COUNT
 #Network: $NETWORK
 #Sudo : $SUDO_COUNT\
"

