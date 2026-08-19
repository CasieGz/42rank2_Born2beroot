#! /bin/bash
# Shebang: the kernel reads this first line and runs the file with bash.
# (Without it, the shell that started the script would interpret it.)

############### Architecture ###############
# uname = "unix name": print kernel / OS info.
# -a = all: kernel name, hostname, kernel release, kernel version, machine, OS.
# $(...) = command substitution: run the command, put its stdout into the variable.
ARC=$(uname -a)

############### Physical Processors Count (physical CPU) ###############
# /proc/cpuinfo is a kernel file. One block per *logical* CPU (core/thread).
# Each block has "physical id : N" = which *socket* that logical CPU belongs to.
# Pipeline ( | = stdout of the left command becomes stdin of the right):
#   cat     print the file
#   grep    keep only lines that contain the string "physical id"
#   sort    put identical ids next to each other (uniq only collapses *neighbours*)
#   uniq    drop duplicate consecutive lines -> one line per physical CPU
#   wc -l   "word count, lines": how many lines = how many physical CPUs
P_PROC_COUNT=$(cat /proc/cpuinfo | grep 'physical id' | sort | uniq | wc -l)

############### Virtual Processors Count (virtual CPU) ###############
# Same file, but the line "processor : N" exists once per logical CPU / thread.
# grep keeps those lines, wc -l counts them = vCPU count (what the OS sees).
V_PROC_COUNT=$(cat /proc/cpuinfo | grep 'processor' | wc -l)

############### RAM Usage ###############
# free = show RAM and swap.
# --mega = sizes in megabytes.
# awk = text tool: read line by line, split into fields on whitespace ($1, $2, ...).
# '/^Mem/' is an awk *pattern* (regex): ^ = start of line, so "line starts with Mem".
# No action block { } means the default: print that whole line.
# Result is one line like:  Mem:   total  used  free  shared  buff/cache  available
MEM=$(free --mega | awk '/^Mem/') #to get memory (RAM) record in megabytes
# echo $MEM sends that line into awk again.
# { ... } with no pattern = run this on every (the only) line.
# $2 = total, $3 = used  (field 1 is the word "Mem:").
# printf = formatted print (does not add a newline unless you put \n).
#   %s     = string
#   %.2f   = floating number, 2 digits after the comma
#   %%     = a literal % character
#   $3*100/$2 = used / total * 100  (awk does math on fields)
MEM_USE=$(echo $MEM | awk '{printf "%s/%sMB (%.2f%%)", $3, $2, $3*100/$2}')
# printf: $3 is third line of MEM and  then $2 second line third is calculation of percentage

############### Disk Usage ###############
# df = "disk free": one line per mounted filesystem.
# --block-size=GB (or MB) = print sizes in those units.
# grep '^\/dev' = regex: line *starts with* /dev (real block devices, not tmpfs).
#   ^     start of line
#   \/    a literal /  (the backslash escapes / inside the regex)
#   dev   then the letters "dev"
# awk '{sum += $2} END {print sum}':
#   for each line, add field 2 (total size) to variable sum
#   END { } runs *once after* all lines
#   print the total
# --block-size in GB or MB , with only real partitions starting with dev. Add up whole column
# 2 and when done (END) print that sum into DISK_T_GB
DISK_T_GB=$(df --block-size=GB | grep '^\/dev' | awk '{sum += $2} END {print sum}')
# same but with used MB
# $3 on a df line is the *used* column
DISK_U_MB=$(df --block-size=MB | grep '^\/dev' | awk '{sum += $3} END {print sum}')
# count amount of partitions with i. Reads and adds up the $5th column and at the end divides
# that sum by the amount of elements to store that percentage in DISK_U_PER
# Default df: field 5 is Use% like "49%". awk turns that into the number 49 (stops at '%').
# i++ = how many filesystems. END: average of those percentages, print with two decimals + %.
DISK_U_PER=$(df | grep '^\/dev' | awk '{i++; sum += $5} END {printf "%.2f%%", sum/i}')
# store it formatted and in the right constalation in DISK_USE
# ${VAR} = insert the variable (braces so the following letters are not part of the name)
DISK_USE=$(echo "${DISK_U_MB}/${DISK_T_GB}Gb (${DISK_U_PER})")

############### CPU Utilization ###############
# top = live process list. We need a single snapshot we can pipe.
# -b = batch mode (plain text, no interactive screen)
# -n 1 = one refresh, then quit
# Line 3 looks like:  %Cpu(s): 6.7 us, 1.2 sy, 0.0 ni, 91.8 id, ...
# awk -F, = set the field separator to *comma* (not space).
#   $1 = "%Cpu(s): 6.7 us"
#   $4 = " 91.8 id"   (idle %)
# NR = Number of Record = line number. NR==3 = only the third line of top.
# awk converts " 91.8 id" to 91.8 when doing math.
# 100 - idle = busy CPU. %.1f = one decimal. %% = the % sign.
# execute top once and then quit it. -F, seperate columns at commas not spaces
# ouput only line three from top
CPU_USE=$(top -bn 1 | awk -F, 'NR==3 {printf "%.1f%%", 100-$4}')

############### Last Boot ###############
# who = who is logged in. -b = time of last boot.
# Example:   system boot  2021-04-25 14:45
# $1=system  $2=boot  $3=date  $4=time
# print $3, $4  (the comma in awk print = space between them)
LAST_BOOT=$(who -b | awk '{print $3, $4}')

############### LVM Use ###############
# lsblk = list block devices (disks, partitions, LVM volumes).
# LVM logical volumes are marked "lvm" in that output.
# grep keep those lines, wc -l count them.
LVM_COUNT=$(lsblk | grep 'lvm' | wc -l)
# [ ... ] = test command. -gt = greater than (integer).
# if count > 0 -> we use LVM. then / else / fi = if-statement in bash.
# $(if ...; then echo yes; else echo no; fi) stores "yes" or "no" in LVM_USE.
LVM_USE=$(if [ $LVM_COUNT -gt 0 ]; then echo yes; else echo no; fi)

############### TCP Connections ###############
# ss = socket statistics (replacement for netstat).
# -t = TCP only.
# ESTAB = ESTABLISHED (a live connection, not LISTEN).
# wc -l = how many such lines.
# awk '{printf "%d ESTABLISHED", $0}':
#   $0 = the whole line (here: the number from wc)
#   %d = print as integer
#   then the word ESTABLISHED, as the subject example shows
TCP=$(ss -t | grep 'ESTAB' | wc -l | awk '{printf "%d ESTABLISHED", $0}')

############### User Log ###############
# users = names of people logged in, one line, separated by spaces.
# Same person twice if they have two sessions.
# sed = stream editor. 's/ /\n/g' = substitute:
#   s     substitute
#   / /   find a space
#   /\n/  replace with a newline
#   g     global: every space, not only the first
# sort | uniq = unique names (uniq needs sorted input).
# wc -l = how many distinct users.
LOG_COUNT=$(users | sed 's/ /\n/g' | sort | uniq | wc -l)

############### Network ###############
# hostname -I = all IPv4/IPv6 addresses of this machine (space-separated).
IP=$(hostname -I)
# ip address = interfaces, IPs, and MAC addresses.
# grep 'ether' = lines like:   link/ether 08:00:27:51:9b:a5
# awk 'NR==1 {print $2}' = first of those lines only, field 2 = the MAC.
MAC=$(ip address | grep 'ether' | awk 'NR==1 {print $2}')
NETWORK=$(echo "IP ${IP}(${MAC})")

############### Sudo ###############
# journalctl = systemd journal (system log).
# grep 'sudo.*COMMAND':
#   sudo      the word sudo
#   .         any character
#   *         zero or more of that
#   COMMAND   then the word COMMAND
# sudo logs executed commands as "... sudo ... COMMAND ..."
# wc -l = how many such log lines = how many sudo commands (approx.).
# awk '{print $0, "cmd"}' = print that number, a space, then the word cmd.
# The command below should be run with root privileges to show count for all users
SUDO_COUNT=$(journalctl | grep 'sudo.*COMMAND' | wc -l | awk '{print $0, "cmd"}')

# wall = write a message to *all* logged-in terminals (TTY + SSH).
# Double quotes "..." so $ARC, $MEM_USE, ... are expanded to their values.
# A backslash at end of line inside "..." continues the string on the next line
# (the newline after \ is not stored). That is why this is one wall message.
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
