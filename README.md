*This project has been created as part of the 42 curriculum by casgarna*

# Born2beRoot

## Description

Born2beRoot is a system-administration project from the 42 curriculum. The goal is to create a virtual machine, install a minimal Linux server (no graphical interface), and harden it with strict security rules.

This repository does **not** contain the virtual machine. It contains:

- this `README.md`
- `monitoring.sh` (the required system-info script)
- `signature.txt` (SHA-1 hash of the VM disk, submitted separately)

The VM itself is set up in VirtualBox (or UTM) and evaluated by comparing the disk signature and by a peer defense.

---

## Project description

### Goal

Set up a first server that:

- runs a **minimal** Debian (or Rocky) install with no X.org / Wayland / GUI
- uses **encrypted LVM** partitions
- runs **SSH on port 4242**, with **root login disabled**
- uses a **firewall** that only allows the ports you need (4242 for mandatory)
- enforces a **strong password policy** and a **strict sudo configuration**
- broadcasts system stats every 10 minutes via `monitoring.sh`

### How a virtual machine works (defense)

A **hypervisor** (VirtualBox or UTM) runs on the **host** (your Mac) and **emulates hardware**: CPU, RAM, disk, network card. The **guest** OS (Debian) runs inside that fake machine and thinks it has real hardware. The guest disk is just a file (`.vdi` / `.qcow2`) on the host.

**Why use a VM**

- Isolation: if the server is misconfigured, the host stays intact.
- No extra physical machine needed for a Linux server.
- Snapshots / copies: you can freeze a state (but evaluations start with **no** snapshots).
- Reproducible: peers check a **signature** of the disk instead of shipping the whole VM in Git.

**This project:** VirtualBox (or UTM) + Debian guest, no GUI, encrypted disk.

### Operating system choice: Debian

I chose **Debian** (latest stable, not testing/unstable).

| | Debian | Rocky Linux |
|---|---|---|
| Origin | Community-driven, Debian Project | Community rebuild of RHEL (Red Hat family) |
| Package manager | `apt` / `aptitude` (`.deb`) | `dnf` (`.rpm`) |
| Mandatory MAC | **AppArmor** | **SELinux** |
| Firewall in this subject | **UFW** | **firewalld** |
| Difficulty | Easier for beginners, huge docs | Closer to enterprise RHEL, more complex |
| Release model | Stable, conservative | RHEL-compatible, longer enterprise cycle |

**Why Debian for this project**

- The subject itself recommends Debian if you are new to sysadmin.
- AppArmor is simpler to reason about than SELinux.
- UFW is a thin wrapper around `iptables`/`nftables` and matches the “only port 4242” rule well.
- `apt` documentation and peer knowledge at 42 are abundant.

**Debian drawbacks**

- Packages in *stable* can be older than on rolling/enterprise-adjacent distros.
- You must stay on **stable**, not testing/unstable.
- Less “RHEL-shop” experience than Rocky.

**Rocky drawbacks (why I did not pick it)**

- More setup complexity (SELinux must be on at boot and adapted; KDump is not required).
- `firewalld` zones and SELinux contexts are extra moving parts for a first server.

### Main design choices

**Hypervisor:** VirtualBox on macOS (UTM if VirtualBox is not available). The VM has **no GUI**; everything is done in the TTY / over SSH.

**Hostname:** `casgarna42` (login + `42`). During evaluation this hostname must be changeable.

**Users**

- `root`: local console only; **SSH root login forbidden**
- `casgarna`: belongs to `user42` and `sudo`

**Partitions:** at least **two encrypted LVM partitions**. Sizes are chosen so the system boots and runs without wasting disk. Encrypted LVM means: physical disk → encrypted volume → LVM volume group → logical volumes (`/`, `/home`, swap, …). You unlock with a passphrase at boot.

**Services (mandatory)**

- OpenSSH listening on **4242**, `PermitRootLogin no`
- **UFW** enabled at boot, default deny incoming, **4242/tcp** allowed
- **AppArmor** enabled at boot
- **cron** + `wall` for `monitoring.sh` every 10 minutes
- **sudo** with custom policy (see below)

**No graphics stack** (`xorg`, `wayland`, desktop environments): installing one is an automatic 0.

### Comparisons required by the subject

#### Debian vs Rocky Linux

See the table above. Short version: Debian is Debian-family (`apt`, AppArmor, UFW). Rocky is RHEL-family (`dnf`, SELinux, firewalld). Same project rules, different tools.

#### AppArmor vs SELinux

Both are **Mandatory Access Control (MAC)** systems: they limit what a process can do even if it runs as root.

| | AppArmor (Debian) | SELinux (Rocky) |
|---|---|---|
| Model | Path-based profiles | Label/type-based (files, ports, processes) |
| Default feel | Easier: profiles per application | Stricter and more granular |
| Typical commands | `aa-status`, `aa-enforce` | `getenforce`, `sestatus`, `semanage` |
| Subject rule | Must run at startup | Must run at startup; config adapted |

AppArmor asks: “may `/usr/sbin/sshd` access this path?”  
SELinux asks: “does this *type* have permission to talk to that *type*?”

#### UFW vs firewalld

| | UFW (Debian) | firewalld (Rocky) |
|---|---|---|
| Meaning | Uncomplicated Firewall | Dynamic firewall daemon |
| Style | Simple allow/deny rules | Zones (public, drop, …) + services |
| Persistence | `ufw enable` + rules in `/etc/ufw` | `firewall-cmd --permanent` then `--reload` |
| This project | Leave **4242** open (plus bonus ports if any) | Same idea with `firewalld` |

Both must be **active when the VM starts**. Default policy: deny incoming, allow outgoing, except the ports you explicitly open.

#### VirtualBox vs UTM

| | VirtualBox | UTM |
|---|---|---|
| Typical use | Intel Mac / Windows / Linux | Apple Silicon Mac (also Intel) |
| Disk format | `.vdi` | `.qcow2` (inside the `.utm` bundle) |
| Signature | `shasum file.vdi` | `shasum …/Images/disk-0.qcow2` |
| Subject | Mandatory if you can use it | Allowed if you cannot use VirtualBox |

The VM is **never** committed to Git. Only the SHA-1 of the disk goes into `signature.txt`. **Starting the VM changes the disk**, so the hash changes. For evaluations: keep a copy of the disk **or** use a snapshot workflow (see Submission).

#### `apt` vs `aptitude` (Debian defense question)

- **`apt`**: the usual command-line tool (`apt update`, `apt install`). Talks to `apt-get` / `dpkg`.
- **`aptitude`**: another frontend with a TUI, better at **dependency conflict resolution** (can suggest solutions when packages conflict).
- Both use the same `.deb` packages and `/etc/apt/sources.list`.
- `apt-get` is the older, more stable scripting interface; `apt` is friendlier for humans.

---

## Lexicon

Short explanations of the terms used in this project (useful for the defense).

| Term | What it is |
|---|---|
| **MAC** (Mandatory Access Control) | Kernel security model: the system (not the file owner) decides what a process may do. Even **root** is limited. Opposite of DAC (Discretionary Access Control), where the owner of a file sets `chmod`/`chown`. AppArmor and SELinux are MAC. |
| **AppArmor** | Debian’s MAC. Each program gets a **profile** that lists allowed **file paths**. Simpler: “may `sshd` read `/etc/ssh`?” Check: `aa-status`. |
| **SELinux** | Rocky/RHEL’s MAC. Everything has a **label/type** (file, port, process). Stricter and more granular: “may this *type* talk to that *type*?” Check: `getenforce` / `sestatus`. Must be on at boot on Rocky. |
| **`.deb`** | Debian package file (like an installer). Installed by `dpkg`; `apt`/`aptitude` fetch them and resolve dependencies. |
| **`.rpm`** | Red Hat package file. Same idea as `.deb`, used on Rocky/RHEL/Fedora. Installed via `dnf` / `rpm`. |
| **`apt`** | Default Debian package manager for humans: `apt update`, `apt install`. Uses `.deb` packages. |
| **`apt-get`** | Older, more stable `apt` backend. Preferred in scripts. Same packages as `apt`. |
| **`aptitude`** | Another Debian frontend (CLI + TUI). Better at **solving dependency conflicts** (can propose several solutions). Same `.deb` repos as `apt`. |
| **`dpkg`** | Low-level Debian tool that actually installs/removes a `.deb`. `apt` calls `dpkg`. |
| **`dnf`** | Rocky/RHEL package manager (successor of `yum`). Installs `.rpm` packages, resolves dependencies. |
| **UFW** | Uncomplicated Firewall (Debian). Simple allow/deny wrapper around `iptables`/`nftables`. This project: only **4242/tcp** open. |
| **firewalld** | Rocky’s firewall daemon. Uses **zones** (public, drop, …) and services. Same job as UFW: block everything except what you allow. |
| **iptables / nftables** | The actual kernel packet filters. UFW and firewalld are friendlier frontends on top of them. |
| **SSH** | Secure Shell: encrypted remote login. Here: port **4242**, **no root login**. Client: `ssh user@ip -p 4242`. |
| **OpenSSH** | The SSH server/client used on Debian (`sshd`). Config: `/etc/ssh/sshd_config`. |
| **sudo** | Run one command as another user (usually root) without logging in as root. Config in `/etc/sudoers` and `/etc/sudoers.d/`. |
| **TTY** | A real text terminal (console or SSH session). `requiretty` means sudo only works if you have one, not from a detached script without a terminal. |
| **PAM** | Pluggable Authentication Modules. Hooks used for login/password rules (`pam_pwquality` = password complexity). |
| **password aging** | How long a password may live before it must be changed. Not complexity (length, A-z, digit): that is PAM/`pwquality`. Aging is: max 30 days, min 2 days between changes, warning 7 days before expiry. Set in `/etc/login.defs` (`PASS_MAX_DAYS`, `PASS_MIN_DAYS`, `PASS_WARN_AGE`). |
| **`chage`** | **ch**ange **age**. Show or set a user’s aging. `sudo chage -l casgarna` lists last change, min/max days, expiry, warning. |
| **LVM** | Logical Volume Manager. Disk is split into **PV → VG → LV**, so you can resize volumes later. This project: **encrypted** LVM, at least two LVs. |
| **PV / VG / LV** | Physical Volume (real disk/partition), Volume Group (pool), Logical Volume (the “partition” you format, e.g. `/`, `/home`, swap). |
| **LUKS** | Linux disk encryption. You type a passphrase at boot; then LVM volumes become readable. |
| **cron** | Scheduler: run a command at a time or interval (`*/10 * * * *` = every 10 minutes, `@reboot` = at startup). How `monitoring.sh` is launched. Stop it here without editing the script. |
| **`wall`** | Write a message to **all** logged-in terminals. That is how the monitoring banner appears everywhere. |
| **hostname** | Machine name on the network. Must be `login` + `42` (e.g. `casgarna42`). Change with `hostnamectl`. |
| **VirtualBox** | Oracle hypervisor: runs a full VM (`.vdi` disk). Mandatory if you can use it. |
| **UTM** | Hypervisor for Mac (esp. Apple Silicon). Disk is `.qcow2`. Allowed if VirtualBox is not usable. |
| **SHA-1 / signature** | Fingerprint of the VM disk file. Pasted into `signature.txt`. Changes as soon as the VM is started. |
| **snapshot** | Frozen copy of VM state. Evaluations must **start with none**; you may create one during defense and delete it after. |
| **X.org / Wayland** | Graphical display servers (GUI). **Forbidden** in this project: no desktop. |
| **KDump** | Kernel crash dump service on Rocky. The subject says you do **not** have to set it up. |
| **lighttpd / MariaDB / PHP** | Bonus web stack for WordPress (lightweight HTTP server, database, PHP). Not NGINX/Apache. |

---

## Mandatory setup (what the VM must do)

To **read** a config file: `cat`, `less`, or `grep`. To **edit**: `sudo nano /path/to/file` (or `vim`). Files under `/etc` need `sudo`. In nano: `Ctrl+W` search, `Ctrl+O` save, `Ctrl+X` quit.

### Firewall (UFW)

```bash
sudo ufw status verbose          # must show active, 4242/tcp ALLOW
sudo nano /etc/ufw/ufw.conf      # ENABLED=yes (on at boot)
sudo nano /etc/ufw/user.rules    # the allow/deny rules (look for 4242)
```

Set it up (already done on the VM):

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 4242/tcp
sudo ufw enable
```

**What UFW is for (defense):** a simple frontend for the kernel firewall. Default deny incoming means the VM is closed except ports you allow. Value: fewer accidental open services, SSH only on 4242.

**Evaluation live test:** add port 8080, show it, then delete it:

```bash
sudo ufw status numbered
sudo ufw allow 8080
sudo ufw status
sudo ufw delete allow 8080        # or: sudo ufw status numbered then sudo ufw delete <number>
sudo ufw status
```

### SSH

Config file: `/etc/ssh/sshd_config`. Needed lines: `Port 4242` and `PermitRootLogin no`.

```bash
sudo nano /etc/ssh/sshd_config
sudo grep -E '^Port|^PermitRootLogin' /etc/ssh/sshd_config
sudo systemctl status ssh        # service running?
sudo ss -tlnp | grep 4242        # listening on 4242?
sudo systemctl restart ssh       # after you edit the file
```

Connect from the host:

```bash
ssh casgarna@<VM_IP> -p 4242
```

**How to get `<VM_IP>`** (run **inside** the VM):

```bash
hostname -I              # all addresses, the one monitoring.sh uses
ip -4 addr show          # IPv4 per interface (look at eth0 / enp0s3, not 127.0.0.1)
ip a                     # short form of ip address
```

Ignore `127.0.0.1` (localhost). The VM address is often `10.0.2.15` (VirtualBox **NAT**) or something like `192.168.x.x` (**bridged**).

- **Bridged adapter:** SSH to that `192.168...` IP from your Mac.
- **NAT (default):** the host often cannot reach `10.0.2.15` directly. In VirtualBox: Settings → Network → Advanced → Port Forwarding: host port `4242` → guest port `4242`, then:

```bash
ssh casgarna@127.0.0.1 -p 4242    # 127.0.0.1 = your Mac, forwarded into the VM
```

On the host you can also try: `ping <VM_IP>` or VirtualBox → Machine → Session Information.

Root over SSH must fail. During defense a **new account** is created and SSH is tested with it.

### Password policy

**Aging** (expiry / min days / warning) is in `/etc/login.defs`. Look for `PASS_MAX_DAYS`, `PASS_MIN_DAYS`, `PASS_WARN_AGE`.

```bash
sudo nano /etc/login.defs
sudo grep -E '^PASS_MAX_DAYS|^PASS_MIN_DAYS|^PASS_WARN_AGE' /etc/login.defs
```

**Complexity** (length, upper/lower/digit, max 3 identical chars, no username, 7 new chars) is PAM + `pam_pwquality`:

```bash
sudo nano /etc/pam.d/common-password     # line with pam_pwquality.so
sudo nano /etc/security/pwquality.conf   # minlen, ucredit, maxrepeat, difok, ...
dpkg -l | grep libpam-pwquality          # package installed?
```

Typical `pwquality` settings: `minlen=10`, `ucredit=-1`, `lcredit=-1`, `dcredit=-1`, `maxrepeat=3`, `usercheck=1`, `difok=7`, `enforce_for_root`. (`difok` does **not** apply to root, as in the subject.)

| Rule | Value | Where |
|---|---|---|
| Password expiry | every **30** days | `PASS_MAX_DAYS` in `login.defs` |
| Minimum days between changes | **2** | `PASS_MIN_DAYS` in `login.defs` |
| Warning before expiry | **7** days | `PASS_WARN_AGE` in `login.defs` |
| Minimum length | **10** | `minlen` / `pam_pwquality` |
| Complexity | upper + lower + digit | `ucredit` `lcredit` `dcredit` |
| No more than **3** identical characters in a row | yes | `maxrepeat=3` |
| Must not contain the username | yes | `usercheck=1` |
| At least **7** characters not in the previous password | yes (**not** for root) | `difok=7` |
| Root password | must still follow the other rules | `enforce_for_root` |

After the policy files are in place, **all existing passwords** (including root) must be changed so they actually match the policy:

```bash
passwd                  # change your own password
sudo passwd root        # change root
sudo chage -l casgarna  # show aging for a user
```

**Why this policy (defense: “because the subject says so” is not enough)**

Advantages:

- Expiry (30 days) limits how long a stolen password stays valid.
- Min 2 days between changes stops users from rotating back to the old password immediately.
- 7-day warning gives time to pick a new one before lockout.
- Length + upper/lower/digit + no username + max 3 identical chars makes guessing / brute force harder.

Disadvantages:

- People write passwords down or reuse a pattern (`Summer2024!`).
- Min 2 days is painful if you typed a bad password and want to fix it now.
- Strict PAM can lock you out if you break `common-password`.
- Complexity rules do not replace a password manager or 2FA.

### sudo

Do **not** edit `/etc/sudoers` with `nano` (a syntax error can lock you out). Use `visudo`. Extra rules usually live in `/etc/sudoers.d/`.

```bash
sudo ls /etc/sudoers.d/
sudo visudo                           # main file /etc/sudoers
sudo visudo -f /etc/sudoers.d/yourfile
sudo cat /etc/sudoers.d/*             # read-only view of custom rules
sudo ls -l /var/log/sudo/             # sudo I/O logs must exist
```

`sudo` is installed; user `casgarna` is in group `sudo`. Extra rules:

- max **3** authentication attempts (`passwd_tries=3`)
- **custom message** on wrong password (`badpass_message="..."`)
- log **inputs and outputs** under `/var/log/sudo/` (`iolog_dir`, `log_input`, `log_output`)
- **`requiretty`** (must have a real TTY)
- **restricted `secure_path`**, e.g.  
  `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin`

**What sudo is for (defense):** you stay a normal user and elevate **one command** instead of logging in as root all day. Example: `sudo apt update` vs `su -` (full root shell). Logs show who did what. Restricted `secure_path` stops a fake `ls` in your home from running as root. `requiretty` blocks sudo from some detached scripts. Limited tries slow brute force.

Show that a sudo command is logged:

```bash
ls -l /var/log/sudo/
sudo cat /var/log/sudo/*          # or ls the latest file in there
sudo echo test                    # then check the log again: it should grow / get a new entry
```

### Groups, users, hostname

- Login user present, in **`user42`** and **`sudo`**.
- During evaluation: create a **new user** and put them in a group.

```bash
getent group user42
getent group sudo
grep casgarna /etc/group              # which groups is the user in?
sudo nano /etc/group                  # groups file (or use adduser)
sudo adduser newuser
sudo adduser newuser user42
id casgarna                           # uid, groups

hostname                              # current name
cat /etc/hostname                     # persisted hostname
sudo nano /etc/hostname
hostnamectl set-hostname newname42    # evaluation: change hostname
```

### AppArmor

Must be **running at startup**. Profiles live in `/etc/apparmor.d/`.

```bash
sudo aa-status
systemctl status apparmor
systemctl is-enabled apparmor         # enabled at boot?
ls /etc/apparmor.d/
```

### Encrypted LVM

At least **two encrypted LVM partitions**. Check during defense:

```bash
lsblk
sudo lsblk -o NAME,FSTYPE,TYPE,SIZE,MOUNTPOINT
sudo pvs; sudo vgs; sudo lvs
sudo cat /etc/crypttab                # encrypted volumes at boot
sudo cat /etc/fstab                   # what is mounted where
```

`monitoring.sh` reports `LVM use: yes` if any `lvm` devices exist.

**How LVM works (defense):** LVM sits between the disk and the filesystem. A **Physical Volume** (PV) is the real disk or LUKS device. A **Volume Group** (VG) is a pool of PVs. A **Logical Volume** (LV) is a slice of that pool that you format and mount (`/`, `/home`, swap). You can grow an LV later without repartitioning the whole disk. Here the PV is **encrypted (LUKS)**, so you unlock it at boot, then LVM and the filesystems appear.

---

## Instructions

### What to submit

At the **root of the Git repository**:

1. `README.md` (this file)
2. `signature.txt`: **only** the SHA-1 of the VM disk (one hash, no extra text)

Do **not** put the `.vdi` / `.qcow2` / VM folder in Git.

### How to get `signature.txt`

Find the VM disk, then hash it with SHA-1.

| System | Typical VM folder | Command |
|---|---|---|
| macOS (VirtualBox) | `~/VirtualBox VMs/` | `shasum your_vm.vdi` |
| Linux | `~/VirtualBox VMs/` | `sha1sum your_vm.vdi` |
| Windows | `%HOMEDRIVE%%HOMEPATH%\VirtualBox VMs\` | `certUtil -hashfile your_vm.vdi sha1` |
| Mac M1/ARM (UTM) | `~/Library/Containers/com.utmapp.UTM/Data/Documents/` | `shasum your.utm/Images/disk-0.qcow2` |

Example hash format:

```
6e657c4619944be17df3c31faa030c25e43e40af
```

**The hash changes as soon as you start the VM.** For every evaluation, either:

- keep an untouched copy of the disk and evaluate that, or
- use snapshots: start **with no snapshots**, create one for the defense, delete it afterwards.

If `signature.txt` does not match the disk → **grade 0**.

### Running the virtual machine

1. Open VirtualBox (or UTM).
2. Confirm **no snapshots** at the start of an evaluation.
3. Start the VM. Unlock encrypted volumes if asked.
4. Log in on TTY as `casgarna` (or root on the console only).
5. Confirm hostname, UFW, SSH, AppArmor, LVM.

There is **no compilation**. `monitoring.sh` is a bash script; it must be executable and scheduled, not compiled.

### `monitoring.sh`

The script gathers system info and broadcasts it to **all terminals** with `wall`. It must run **at boot** and **every 10 minutes**, with **no error output**. The banner is optional.

It prints:

| Line | Meaning | How the script gets it |
|---|---|---|
| Architecture | OS + kernel | `uname -a` |
| Physical CPU | sockets / physical CPUs | unique `physical id` in `/proc/cpuinfo` |
| vCPU | logical processors | `processor` lines in `/proc/cpuinfo` |
| Memory | used / total MB + % | `free --mega` |
| Disk | used / total + % | `df` on `/dev/*` |
| CPU load | utilization % | `top -bn 1` (100 − idle) |
| Last boot | date and time | `who -b` |
| LVM use | yes / no | `lsblk` contains `lvm` |
| TCP connections | ESTABLISHED count | `ss -t` |
| User log | logged-in users | `users` |
| Network | IPv4 + MAC | `hostname -I`, `ip address` (`ether`) |
| Sudo | sudo command count | `journalctl` lines matching `sudo.*COMMAND` |

Sudo count is more accurate when the script runs as **root** (cron as root).

**Schedule (cron):** do not loop inside the script. Use root’s crontab so you can **stop the broadcasts without editing the script**:

```bash
sudo crontab -l                  # view (does not open an editor)
sudo crontab -e                  # edit (opens nano/vim)
which nano                       # cron uses $EDITOR; nano is typical
sudo nano /path/to/monitoring.sh # the script file itself
ls -l /path/to/monitoring.sh     # must be executable: chmod +x
```

Example (every 10 minutes, and `@reboot`):

```cron
*/10 * * * * /path/to/monitoring.sh
@reboot /path/to/monitoring.sh
```

**Interrupt during evaluation (without modifying the script):** `sudo crontab -e`, comment the two lines with `#`, save. Or `sudo crontab -r` (only if that is acceptable in the eval). The script file itself stays unchanged.

**Change interval to every 1 minute (evaluation):** in `sudo crontab -e`, change `*/10` to `*/1` (or `* * * * *`). Wait and check that `wall` shows **new** values (RAM, CPU, sudo count). Then put it back or disable cron as below.

**Stop it at next boot, without touching the script:**

```bash
ls -l /path/to/monitoring.sh      # note path, size, permissions (e.g. -rwxr-xr-x)
sudo crontab -e                   # comment or delete BOTH lines (the */10 and @reboot)
sudo reboot
# after login: script file still there, same rights, same content; no wall every 10 min
ls -l /path/to/monitoring.sh
```

Do **not** `chmod` or `nano` the script for this check. Only cron changes.

`wall` writes a broadcast to every logged-in TTY. That is why evaluators see the banner on the console and over SSH.

---

## Defense (evaluation sheet)

Walkthrough in the same order as the scale. You must be able to **do** each step and **explain** it. “Because the subject asks for it” is not a valid answer.

### 0. Before the VM starts

- Evaluator clones **your** Git repo into an **empty** folder (`git clone`).
- Repo root has `README.md` and `signature.txt` (no VM file in Git).
- First README line is italic: *This project has been created as part of the 42 curriculum by casgarna*
- README has Description, Project description, OS choice + pros/cons, design choices, comparisons (Debian/Rocky, AppArmor/SELinux, UFW/firewalld, VirtualBox/UTM).
- **No snapshots.** VM is **not** already running.
- Signature of the disk matches `signature.txt` (`diff` the two hashes). Ask where the `.vdi` (or `.qcow2`) is.

```bash
# on the host, from the cloned repo
cat signature.txt
shasum "/path/to/your.vdi"                 # first field is the hash
# put the hash only in a temp file and:
diff signature.txt /tmp/disk.hash
```

Protect the original disk: **cold snapshot** (create before start, delete at the end) **or** copy the `.vdi` and boot the copy. Starting the VM changes the hash.

Then start the VM. Unlock LUKS if asked. Login is **not root** (`casgarna`), password follows the policy. **No GUI**.

### 1. Project overview (talk)

Have a one-sentence answer ready:

| Question | Short answer |
|---|---|
| How does a VM work? | Hypervisor emulates CPU/RAM/disk/NIC; guest OS runs isolated in a disk file. |
| Purpose of VMs? | Isolation, no extra hardware, snapshots, safe testing. |
| Why Debian? | Subject recommends it; AppArmor + UFW + apt are simpler for a first server. |
| Debian vs Rocky? | Debian: `apt`/`.deb`, AppArmor, UFW. Rocky: `dnf`/`.rpm`, SELinux, firewalld. |
| `apt` vs `aptitude`? | Same `.deb` repos. `apt` is the daily tool. `aptitude` is better at solving dependency conflicts (TUI). |
| What is AppArmor? | MAC: path-based profiles that limit a program even as root. `aa-status`. |

The monitoring script should already be broadcasting every 10 minutes (`wall`).

### 2. Simple setup

```bash
echo $XDG_SESSION_TYPE                 # should not be wayland/x11; you are on TTY
whoami                                 # not root
cat /etc/os-release                    # Debian
sudo ufw status verbose                # active
sudo systemctl status ssh              # running (Debian: ssh.service)
sudo systemctl status ufw
```

### 3. User step 1: your login + password policy

```bash
id casgarna
getent group sudo
getent group user42                    # casgarna must be in both
```

Create a **new user** (evaluator chooses a password that follows the rules: 10+ chars, upper, lower, digit, no username, no 4 identical in a row):

```bash
sudo adduser evaluser                  # it will reject a weak password if PAM is correct
```

Explain the **two files** (or three): `/etc/login.defs` (aging) and `/etc/pam.d/common-password` plus `/etc/security/pwquality.conf` (complexity). Open them with `sudo nano` / `grep` as in [Password policy](#password-policy).

### 4. User step 2: group `evaluating`

```bash
sudo addgroup evaluating
sudo adduser evaluser evaluating
getent group evaluating
id evaluser
```

Then explain **advantages and disadvantages** of the password policy (see that section). Not “the subject required it”.

### 5. Hostname and partitions

Must be `casgarna42`. Evaluator replaces the login with **theirs**, then reboot. It must **stick**.

```bash
hostname
cat /etc/hostname
# also check /etc/hosts if 127.0.1.1 still has the old name
cat /etc/hosts
sudo hostnamectl set-hostname THEIRLOGIN42
sudo nano /etc/hosts                   # 127.0.1.1 THEIRLOGIN42
sudo reboot
# after boot:
hostname                               # must be THEIRLOGIN42
# restore:
sudo hostnamectl set-hostname casgarna42
sudo nano /etc/hosts
```

Partitions (mandatory example vs bonus example: if you did the bonus layout, compare to the **bonus** diagram):

```bash
lsblk
lsblk -o NAME,FSTYPE,TYPE,SIZE,MOUNTPOINT,FSAVAIL
sudo lsblk
sudo fdisk -l
sudo pvs; sudo vgs; sudo lvs
```

Explain LVM (PV → VG → LV, encryption, why it is useful: resize without repartitioning the whole disk).

### 6. sudo

```bash
dpkg -l | grep sudo                    # installed
sudo adduser evaluser sudo             # assign the new user to sudo
groups evaluser
sudo visudo -f /etc/sudoers.d/yourfile # show the subject rules
ls -l /var/log/sudo/                   # folder exists, at least one file
sudo ls /var/log/sudo/
sudo cat /var/log/sudo/*               # history of sudo I/O
sudo echo hello                        # then ls/cat the log again: it updated
```

Explain sudo with an example (`sudo apt update` vs staying root). Show `passwd_tries`, `badpass_message`, `requiretty`, `secure_path`, `iolog_dir`.

### 7. UFW

```bash
dpkg -l | grep ufw
sudo ufw status verbose                # working, rule for 4242
sudo ufw allow 8080
sudo ufw status
sudo ufw delete allow 8080
sudo ufw status                        # 8080 gone, 4242 still there
```

Explain: Uncomplicated Firewall, deny by default, only open what you need.

### 8. SSH

```bash
dpkg -l | grep openssh-server
sudo systemctl status ssh
sudo ss -tlnp | grep ssh               # only 4242, not 22
sudo grep -E '^Port|^PermitRootLogin' /etc/ssh/sshd_config
hostname -I                            # VM IP for the host
```

From the **host** (or another terminal):

```bash
ssh evaluser@<VM_IP> -p 4242           # must work (password or key)
ssh root@<VM_IP> -p 4242               # must fail
```

Explain: encrypted remote login, so you do not expose a GUI or telnet. Port 4242 instead of 22 reduces noisy scans. Root SSH off so a guessed root password cannot get a remote shell.

### 9. Script monitoring

Show the code: `nano /path/to/monitoring.sh` (or `cat`). Explain each `wall` line (see table above).

**What cron is:** a scheduler. Root’s crontab runs commands at boot (`@reboot`) and every 10 minutes (`*/10 * * * *`). That is how the script starts with the server.

```bash
sudo crontab -l
ls -l /path/to/monitoring.sh           # remember path and rights
```

Live tests:

1. Change to **every minute**: `sudo crontab -e` → `*/1 * * * * /path/to/monitoring.sh`. Confirm `wall` values change (open a second TTY, run `sudo echo x` so sudo count moves).
2. **Stop at startup without editing the script:** comment/remove the crontab lines (`sudo crontab -e`). Reboot. Check: file still at the same path, same permissions, same content, **no** broadcast. Restore cron after if needed.

### 10. Bonus (only if mandatory was perfect)

- Partitions like the bonus diagram: +2
- WordPress with lighttpd + MariaDB + PHP only: +2
- One extra service, **not** NGINX/Apache2: +1 (explain how and why)

---

## Bonus (only if mandatory is perfect)

If implemented, typical extras:

- Partition layout matching the subject diagram more closely
- WordPress with **lighttpd**, **MariaDB**, **PHP**
- One extra useful service (**not** NGINX or Apache2), justified in the defense
- Extra firewall ports only as needed for those services

Bonus is **not graded** unless the mandatory part is fully working.

---

## Resources

### Documentation

- [Debian Stable releases](https://www.debian.org/releases/)
- [OpenSSH `sshd_config`](https://man.openbsd.org/sshd_config)
- [UFW](https://help.ubuntu.com/community/UFW)
- [AppArmor](https://wiki.debian.org/AppArmor)
- [LVM](https://wiki.debian.org/LVM)
- [Linux Unified Key Setup (LUKS)](https://wiki.archlinux.org/title/Dm-crypt)
- [sudoers manual](https://www.sudo.ws/docs/man/sudoers.man/)
- [`pam_pwquality`](https://manpages.debian.org/stable/libpam-pwquality/pam_pwquality.8.en.html)
- [cron](https://manpages.debian.org/stable/cron/crontab.5.en.html)
- [wall(1)](https://manpages.debian.org/stable/bsdutils/wall.1.en.html)
- [VirtualBox manual](https://www.virtualbox.org/manual/)
- [UTM documentation](https://docs.getutm.app/)
- SELinux (for the comparison): [Red Hat SELinux docs](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/using_selinux/index)
- firewalld (for the comparison): [firewalld.org](https://firewalld.org/documentation/)

### Articles / tutorials

Guides I used while setting up the VM:

- [My experience with the Born2beroot project (m4nnb3ll)](https://m4nnb3ll.medium.com/my-experience-with-the-born2beroot-project-42-ad19d738ad4f)
- [Born2beroot (baigal)](https://baigal.medium.com/born2beroot-e6e26dfb50ac)
- [Operating systems overview (GeeksforGeeks)](https://www.geeksforgeeks.org/operating-systems/operating-systems/)

### AI usage

AI was used as a **learning and documentation aid**, not as a replacement for setting up the machine:

- **README:** structuring the file so it matches the subject’s README requirements (first italic line, Description, Instructions, Resources, Project description, comparisons).
- **Concepts:** clarifying differences (Debian vs Rocky, AppArmor vs SELinux, UFW vs firewalld, VirtualBox vs UTM, apt vs aptitude) and what the defense typically asks.

The VM, partitioning, SSH, firewall, sudo, and password policy were configured **on the machine**, by following the subject and man pages, not by pasting an AI “full install” guide blindly. During the defense I must be able to explain every command I used.
