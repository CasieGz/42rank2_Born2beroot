*This project has been created as part of the 42 curriculum by casgarna*

# Born2beRoot

<details id="description">
<summary>Description</summary>



Born2beRoot is a system-administration project from the 42 curriculum. The goal is to create a virtual machine, install a minimal Linux server (no graphical interface), and harden it with strict security rules.

This repository does **not** contain the virtual machine. It contains:

- this `README.md`
- `monitoring.sh` (the required system-info script)
- `signature.txt` (SHA-1 hash of the VM disk, submitted separately)

The VM itself is set up in VirtualBox (or UTM) and evaluated by comparing the disk signature and by a peer defense.

</details>

<details id="my-journey">
<summary>My journey</summary>

How this VM was actually set up, in order, and what each step taught. Full rules and defense answers live in [Mandatory setup](#mandatory-setup-what-the-vm-must-do) and [Evaluation](#evaluation). This section is the **why** and the exact commands used.

<table><tr><td>

<details>
<summary>1. Why sudo was the first step</summary>

After the Debian install there is **root** and a normal user (`casgarna`). Working as root all day is dangerous: one typo can break the disk. **Least privilege:** stay a normal user, raise rights only for one command (`sudo apt install …`).

If you set a **root password** during Debian’s installer, Debian often **does not** install `sudo`. Then `casgarna` cannot run admin commands at all. You must:

1. `su -` (become root once)
2. Install the **sudo program**
3. Put `casgarna` in the **sudo group**

After that, never log in as root for daily work. Use `sudo`.

**Why `sudo` is not always preinstalled:** Debian stays small. A root password means “you will use `su -`”. If the root password is **left empty** in the installer, Debian typically installs sudo and makes the first user an admin.

**What `apt install sudo` does:** puts `/usr/bin/sudo` and `/etc/sudoers` on disk. It does **not** make you an admin by itself.

**Why the group `sudo` already exists:** Debian already lists standard groups in `/etc/group` (`sudo`, `audio`, …) as placeholders. The group is the “club”; the package is the “doorman”. Membership is a line in `/etc/group`. `/etc/sudoers` says: members of group `sudo` may run commands as root.

```bash
su -
apt-get update -y
apt-get upgrade -y          # recommended, not strictly required for sudo to work
apt install sudo
usermod -aG sudo casgarna
getent group sudo           # casgarna must appear on that line
```

`apt update` refreshes the package **index**. `upgrade` updates already installed packages. Use **`apt install`**, not `aptitude` (aptitude is not installed yet and is not required).

**`usermod`:** change an existing account. **`-G`:** secondary groups. **`-a` (append):** add to the group **without removing** the others. `usermod -G sudo casgarna` **without `-a`** would drop every other group.

**`getent group sudo`:** print that group from the system databases (`/etc/group`).

Log out and back in (or `su - casgarna`) so the new group applies.

</details>

<details>
<summary>2. Groups `user42` and `sudo`</summary>

The subject needs login `casgarna` in **`user42` and `sudo`**. `user42` is only a subject group; it grants no extra rights. `sudo` is the one that may elevate.

As the normal user (after step 1):

```bash
sudo groupadd user42
sudo usermod -aG user42 casgarna
getent group user42
id casgarna
```

As root, `sudo` in front of `groupadd` is redundant but harmless. `usermod -aG sudo,user42 casgarna` can set both groups in one go.

A **new** evaluation user is created later with `sudo adduser …` (PAM then enforces the password policy).

</details>

<details>
<summary>3. SSH on 4242, no root login</summary>

Subject: SSH on **4242**, **no root over SSH**. Do **not** install Oh My Zsh / zsh — the eval expects bash.

```bash
sudo apt update
sudo apt install openssh-server
sudo nano /etc/ssh/sshd_config
```

- `Port 4242` (uncomment; not `#Port 22`)
- `PermitRootLogin no`

```bash
sudo systemctl restart ssh    # config is read at start, not live
sudo systemctl status ssh     # active (running)
```

`apt update` = refresh package list. `openssh-server` = daemon that **listens** for SSH. Debian’s service name is **`ssh`**, not always `sshd`.

</details>

<details>
<summary>4. UFW: only 4242</summary>

```bash
sudo apt install ufw -y       # -y = assume yes on the install prompt
sudo ufw status               # inactive at first
sudo ufw allow 4242
sudo ufw enable
sudo ufw status               # active, 4242 ALLOW
```

Default deny incoming is the point: only ports you allow. More: [Firewall (UFW)](#firewall-ufw).

</details>

<details>
<summary>5. SSH from the Mac (NAT + port forwarding)</summary>

VirtualBox **NAT** gives the guest something like `10.0.2.15`. The Mac often **cannot** SSH there directly. Forward a **host** port into **guest 4242**.

VirtualBox → VM Settings → Network → Adapter 1 → Advanced → **Port Forwarding**:

| Name | Protocol | Host IP | Host Port | Guest IP | Guest Port |
|---|---|---|---|---|---|
| SSH | TCP | `127.0.0.1` | `4242` | (empty) | `4242` |

- **Host IP `127.0.0.1`:** only **this Mac** may use the forward (not the whole LAN). `127.0.0.1` = localhost.
- **Guest IP empty:** VirtualBox fills in the guest’s NAT address.
- **Guest Port `4242`:** must match `sshd` inside Debian. Do not leave it empty.

On the Mac (not inside the VM):

```bash
ssh casgarna@127.0.0.1 -p 4242
# first time: yes to the host key; then the VM user password
exit
```

Inside the VM, `who` / `tty`: **`pts/0`** is the SSH session; **`tty1`** is the VirtualBox console. `whoami` is only the username.

If **host port 4242 is already taken** (common on 42 cluster PCs), map **host 4243 → guest 4242**. In the VM, SSH is still 4242 (`sshd_config`, `ufw`, `ss`). From the Mac:

```bash
ssh casgarna@127.0.0.1 -p 4243
```

To reach a VM on **another** machine, do not lock Host IP to `127.0.0.1` (empty or `0.0.0.0`), and SSH to **that machine’s LAN IP**. Evaluation is usually on the same Mac as VirtualBox, so `127.0.0.1` is enough.

Copy files the same way (`scp` uses **`-P`** for the port):

```bash
scp -P 4242 ./monitoring.sh casgarna@127.0.0.1:/home/casgarna/
```

Then on the VM: `sudo mv … /usr/local/bin/monitoring.sh` and `sudo chmod +x`.

</details>

<details>
<summary>6. Password policy (`login.defs`, PAM, `chage`, `/etc/shadow`)</summary>

Aging (30 / 2 / 7 days) is **not** the same as complexity (length, classes). Full table: [Password policy](#password-policy).

`/etc/login.defs` applies when an account is **created**. **Existing** `root` and `casgarna` need `chage` (writes `/etc/shadow`). Only **root/sudo** may run `chage` on others; a normal user gets `Permission denied`.

```bash
sudo nano /etc/login.defs          # PASS_MAX_DAYS 30, PASS_MIN_DAYS 2, PASS_WARN_AGE 7
sudo apt install libpam-pwquality -y
sudo nano /etc/pam.d/common-password
```

`pam_pwquality.so` line (example):

```
password requisite pam_pwquality.so retry=3 minlen=10 ucredit=-1 lcredit=-1 dcredit=-1 maxrepeat=3 usercheck=1 difok=7 enforce_for_root
```

Then:

```bash
sudo chage -M 30 -m 2 -W 7 casgarna
sudo chage -M 30 -m 2 -W 7 root
sudo chage -l casgarna
passwd                  # casgarna: new password must pass PAM
sudo passwd root
```

**`/etc/passwd`:** public account list; password field is `x`. **`/etc/shadow`:** hashes + aging, root-only. `chage -M/-m/-W` fills the min/max/warn fields there. It does **not** check whether the **current** password is complex — that is why `passwd` must be run after PAM is set.

LUKS (disk unlock) is **not** this policy; only login accounts.

</details>

<details>
<summary>7. Strict sudo (`visudo`, logs)</summary>

Do not `nano /etc/sudoers`. Use **`visudo`** (syntax check on save). Log dir:

```bash
sudo mkdir -p /var/log/sudo
sudo visudo
# or: sudo visudo -f /etc/sudoers.d/yourfile
```

Subject **Defaults**: `passwd_tries=3`, custom `badpass_message`, `requiretty`, `secure_path=…`, `log_input,log_output`, `iolog_dir="/var/log/sudo"`. Example block: [sudo](#sudo).

`secure_path` stops sudo from running a fake binary from your home. `requiretty` needs a real terminal. Test a wrong password three times; then `ls -l /var/log/sudo/` must grow after a real `sudo` command.

</details>

<details>
<summary>8. `monitoring.sh` and cron</summary>

Script in `/usr/local/bin/monitoring.sh`, executable, run as **root** cron so it can read logs and `wall` everyone.

```bash
sudo crontab -e
```

```cron
@reboot /usr/local/bin/monitoring.sh
*/10 * * * * /usr/local/bin/monitoring.sh
```

`@reboot` = once at boot. `*/10 * * * *` = every 10 minutes. `wall` is inside the script. After reboot, SSH sessions drop, so you may not see `wall` until you log in again. Proof cron ran:

```bash
sudo journalctl -u cron
# (CRON) INFO (Running @reboot jobs)
# (root) CMD (/usr/local/bin/monitoring.sh)
```

**Interrupt without editing the script:** comment **both crontab lines** (`sudo crontab -e`). That survives a reboot. `sudo systemctl stop cron` only stops cron **until the next boot** — then `@reboot` and `*/10` run again. See [`monitoring.sh`](#monitoringsh).

</details>

</td></tr></table>

</details>

<details id="project-description">
<summary>Project description</summary>



<table><tr><td>

<details id="goal">
<summary>Goal</summary>



Set up a first server that:

- runs a **minimal** Debian (or Rocky) install with no X.org / Wayland / GUI
- uses **encrypted LVM** partitions
- runs **SSH on port 4242**, with **root login disabled**
- uses a **firewall** that only allows the ports you need (4242 for mandatory)
- enforces a **strong password policy** and a **strict sudo configuration**
- broadcasts system stats every 10 minutes via `monitoring.sh`

</details>

<details id="how-a-virtual-machine-works-defense">
<summary>How a virtual machine works (defense)</summary>



A **[hypervisor](#hypervisor)** (VirtualBox or UTM) runs on the **host** (your Mac) and **[emulates](#emulate)** hardware: CPU, RAM, disk, network card. The **guest** OS (Debian) runs inside that fake machine and thinks it has real hardware. The guest disk is just a file (`.vdi` / `.qcow2`) on the host.

**Why use a VM**

- Isolation: if the server is misconfigured, the host stays intact.
- No extra physical machine needed for a Linux server.
- Snapshots / copies: you can freeze a state (but evaluations start with **no** snapshots).
- Reproducible: peers check a **signature** of the disk instead of shipping the whole VM in Git.

**This project:** VirtualBox (or UTM) + Debian guest, no GUI, encrypted disk.

</details>

<details id="operating-system-choice-debian">
<summary>Operating system choice: Debian</summary>



I chose **Debian** (latest stable, not testing/unstable).

| | Debian | Rocky Linux |
|---|---|---|
| Origin | Community-driven, Debian Project | Community rebuild of RHEL (Red Hat family) |
| Package manager | `apt` / `aptitude` (`.deb`) | `dnf` (`.rpm`) |
| Mandatory MAC | **AppArmor** | **SELinux** |
| Firewall in this subject | **UFW** | **firewalld** |
| Difficulty | Easier for beginners, huge docs | Closer to enterprise RHEL, more complex |
| Release model | Stable, conservative | RHEL-compatible, longer enterprise cycle |

**Rocky Linux in one sentence:** a free community rebuild of **RHEL** (Red Hat Enterprise Linux, a paid “enterprise” distro). Same tools and behaviour as RHEL, without the support contract. **DNF** is Rocky’s package manager (like `apt`). **SELinux** is Rocky’s MAC (like AppArmor).

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

</details>

<details id="main-design-choices">
<summary>Main design choices</summary>



**Hypervisor:** VirtualBox on macOS or Linux (UTM if VirtualBox is not available). The VM has **no GUI**; everything is done in the TTY / over SSH.

**Hostname:** `casgarna42` (login + `42`). During evaluation this hostname must be changeable.

**Users**

- `root`: local console only; **SSH root login forbidden**
- `casgarna`: belongs to `user42` and `sudo`

`sudo` is the group that may run admin commands. **`user42` is only required by the subject**; it does not add extra rights by itself.

**Partitions:** at least **two encrypted LVM partitions**. Sizes are chosen so the system boots and runs without wasting disk. Encrypted LVM means: physical disk → encrypted volume → LVM volume group → logical volumes (`/`, `/home`, swap, …). You unlock with a passphrase at boot.

**Services (mandatory)**

- OpenSSH listening on **4242**, `PermitRootLogin no`
- **UFW** enabled at boot, default deny incoming, **4242/tcp** allowed
- **AppArmor** enabled at boot
- **cron** + `wall` for `monitoring.sh` every 10 minutes
- **sudo** with custom policy (see below)

**No graphics stack** (`xorg`, `wayland`, desktop environments): installing one is an automatic 0.

</details>

<details id="comparisons-required-by-the-subject">
<summary>Comparisons required by the subject</summary>



<table><tr><td>

<details id="debian-vs-rocky-linux">
<summary>Debian vs Rocky Linux</summary>



Linux is the **kernel** (the core). **Debian** and **Rocky** are two complete **operating systems** built on that kernel: different “shops” with different tools, not two different kernels.

Think of two kitchens that both cook food (run a server), but the drawers are labelled differently.

**Debian** (this VM)

- Made by a **community** (the Debian Project), not a company.
- You install software with **`apt`** (and `.deb` packages). Example: `sudo apt install sudo`.
- The extra security layer is **[AppArmor](#apparmor-vs-selinux)** (rules per program, by file path).
- The firewall you use here is **[UFW](#ufw-vs-firewalld)** (simple allow/deny).
- **Stable** means: updates are careful and a bit older, but predictable. The subject wants this *stable* line, not testing/unstable.

**Rocky Linux**

- A **free copy of RHEL** (Red Hat Enterprise Linux). Companies pay Red Hat for support; Rocky aims to behave the same without that contract.
- You install software with **`dnf`** (and `.rpm` packages). Same idea as `apt`, different command.
- The extra security layer is **[SELinux](#apparmor-vs-selinux)** (labels on files, ports, processes). Stricter and more to configure.
- The firewall is **[firewalld](#ufw-vs-firewalld)** (zones like “public”, not just `ufw allow 4242`).
- Feels closer to **enterprise** servers. The subject says Rocky is harder; **KDump** (crash dumps) is not required, but **SELinux must be on at boot**.

**What stays the same in this project**

Same homework: no GUI, encrypted LVM, SSH on **4242**, no root SSH, strong passwords, sudo rules, hostname `login42`, `monitoring.sh`. Only the **tool names** change.

**Why Debian here:** the subject recommends it for a first server; AppArmor + UFW + `apt` are fewer moving parts. Full table and pros/cons: [Operating system choice: Debian](#operating-system-choice-debian).

</details>

<details id="apparmor-vs-selinux">
<summary>AppArmor vs SELinux</summary>



Normal Linux permissions (`chmod`, “this file is mine”) are **DAC** (Discretionary Access Control): the **owner** of a file decides who may read it. **Root** can ignore that and read almost everything.

**[MAC](#mac)** (Mandatory Access Control) is an extra lock **in the kernel**. The **system** decides what a program may do. Even **root** is limited. If `sshd` is hacked, it still cannot open files its policy forbids.

AppArmor and SELinux are two MAC implementations. Same job, different way of writing the rules. Both must be **running when the VM starts**.

| | AppArmor (Debian) | SELinux (Rocky) |
|---|---|---|
| Model | Path-based profiles | Label/type-based (files, ports, processes) |
| Default feel | Easier: profiles per application | Stricter and more granular |
| Typical commands | `aa-status`, `aa-enforce` | `getenforce`, `sestatus`, `semanage` |
| Subject rule | Must run at startup | Must run at startup; config adapted |

**AppArmor (Debian) — “which paths may this program touch?”**

Each program gets a **profile** (a text list). The profile names **file paths**, for example: `sshd` may read `/etc/ssh/sshd_config`, may not read `/home/casgarna/secret`.

It asks: “May **this binary** (`/usr/sbin/sshd`) access **this path**?”

Check: `sudo aa-status` (profiles loaded / in enforce mode). Profiles live in `/etc/apparmor.d/`.

That is easier to picture: one list per app.

**SELinux (Rocky) — “may this type talk to that type?”**

Everything gets a **label** (a type): the `sshd` process, port 4242, files under `/etc/ssh`. Policy says which types may interact, not mainly “this path string”.

It asks: “Does type **A** have permission to use type **B**?”

Check: `getenforce` (should be `Enforcing`), `sestatus`. On Rocky the subject wants SELinux **on at boot** and the config **adapted** (SSH port 4242 is not the default 22, so the port’s type often needs a rule).

More precise, also easier to break if a label is wrong.

**This VM:** Debian, so AppArmor. Rocky’s SELinux is only for the comparison in the defense.

</details>

<details id="ufw-vs-firewalld">
<summary>UFW vs firewalld</summary>



| | UFW (Debian) | firewalld (Rocky) |
|---|---|---|
| Meaning | Uncomplicated Firewall | Dynamic firewall daemon |
| Style | Simple allow/deny rules | Zones (public, drop, …) + services |
| Persistence | `ufw enable` + rules in `/etc/ufw` | `firewall-cmd --permanent` then `--reload` |
| This project | Leave **4242** open | Same idea with `firewalld` |

Both must be **active when the VM starts**. Default policy: deny incoming, allow outgoing, except the ports you explicitly open.

A **firewall** is a gate for network traffic: by default nobody from the internet may connect in; you open only the ports you need (here **4242** for SSH).

Linux does that filtering **in the kernel**. Two command families exist to write those kernel rules:

- **[iptables](#iptables)** — older interface
- **[nftables](#nftables)** — newer interface (same job)

Those raw rules are long. **[UFW](#ufw)** and **[firewalld](#firewalld)** are simpler **frontends**: you type `ufw allow 4242`, UFW translates it into the kernel rule. This project does not use `iptables` or `nft` by hand.

</details>

<details id="virtualbox-vs-utm">
<summary>VirtualBox vs UTM</summary>



| | VirtualBox | UTM |
|---|---|---|
| Typical use | Intel Mac / Windows / Linux | Apple Silicon Mac (also Intel) |
| Disk format | `.vdi` | `.qcow2` (inside the `.utm` bundle) |
| Signature | `shasum file.vdi` | `shasum …/Images/disk-0.qcow2` |
| Subject | Mandatory if you can use it | Allowed if you cannot use VirtualBox |

The VM is **never** committed to Git. Only the SHA-1 of the disk goes into `signature.txt`. **Starting the VM changes the disk**, so the hash changes. For evaluations: keep a copy of the disk **or** use a snapshot workflow (see Submission).

</details>

<details id="apt-vs-aptitude-debian-defense-question">
<summary>`apt` vs `aptitude` (Debian defense question)</summary>



- **`apt`**: the usual command-line tool (`apt update`, `apt install`). Talks to `apt-get` / `dpkg`.
- **`aptitude`**: another frontend with a TUI, better at **dependency conflict resolution** (can suggest solutions when packages conflict).
- Both use the same `.deb` packages and `/etc/apt/sources.list`.
- `apt-get` is the older, more stable scripting interface; `apt` is friendlier for humans.

</details>



</td></tr></table>
</details>



</td></tr></table>
</details>

<details id="mandatory-setup-what-the-vm-must-do">
<summary>Mandatory setup (what the VM must do)</summary>



<table><tr><td>

To **read** a config file: `cat`, `less`, or `grep`. To **edit**: `sudo nano /path/to/file` (or `vim`). Files under `/etc` need `sudo`. In nano: `Ctrl+W` search, `Ctrl+O` save, `Ctrl+X` quit.

<details id="firewall-ufw">
<summary>Firewall (UFW)</summary>



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

</details>

<details id="ssh">
<summary>SSH</summary>



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

**`localhost` / `127.0.0.1` with NAT** means the **host PC**. VirtualBox forwards a host port into guest **4242**. SSH inside the VM stays on 4242. Only if **host** port 4242 is already taken, forward a free host port (example `2222`) → guest `4242` and connect with that host port. That is a host/VirtualBox setting, not a change inside Debian.

If SSH complains that the host key changed after you change the forwarded port:

```bash
ssh-keygen -R "[127.0.0.1]:4242"
ssh-keygen -R "[localhost]:2222"
```

**Password vs SSH key:** the subject allows either. A key pair is a **private** key (stays on your machine) and a **public** key (on the server). Login proves you hold the private key; the private key is never sent. Stronger than a guessable password. This project can use a normal password.

On the host you can also try: `ping <VM_IP>` or VirtualBox → Machine → Session Information.

Root over SSH must fail. During defense a **new account** is created and SSH is tested with it.

</details>

<details id="password-policy">
<summary>Password policy</summary>



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

Typical `pwquality` settings: `minlen=10`, `ucredit=-1`, `lcredit=-1`, `dcredit=-1`, `maxrepeat=3`, `usercheck=1`, `difok=7`, `enforce_for_root`.

The subject says **`difok` does not apply to root**. `enforce_for_root` still makes length/classes apply to root (required). If both `difok=7` and `enforce_for_root` are set, root may also be forced to change 7 characters; that is **stricter** than the subject, which is usually fine.

A **negative** credit (`ucredit=-1`) means “at least one of that class is **required**”. Positive credits are optional bonuses toward `minlen` (man `pam_pwquality`). Example PAM line:

```
password requisite pam_pwquality.so retry=3 minlen=10 ucredit=-1 lcredit=-1 dcredit=-1 maxrepeat=3 usercheck=1 difok=7 enforce_for_root
```

| Option | Meaning |
|---|---|
| `retry=3` | give up after 3 bad new passwords |
| `minlen=10` | at least 10 characters |
| `ucredit=-1` | at least 1 uppercase |
| `lcredit=-1` | at least 1 lowercase |
| `dcredit=-1` | at least 1 digit |
| `maxrepeat=3` | no 4 identical characters in a row |
| `usercheck=1` | must not contain the username |
| `difok=7` | at least 7 characters not in the old password (not for root) |
| `enforce_for_root` | complexity also for root |

`/etc/login.defs` aging (`PASS_MAX_DAYS` / `MIN` / `WARN`) is used **when an account is created**. Debian `login.defs(5)`: changes there do **not** update existing accounts. Those values live in `/etc/shadow`. For `root` and `casgarna` you apply them with `chage`:

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
sudo chage -M 30 -m 2 -W 7 casgarna   # max / min / warn, if login.defs was edited later
sudo chage -M 30 -m 2 -W 7 root
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
- Strict PAM can lock the account if `common-password` is broken.
- Complexity rules do not replace a password manager or 2FA.

</details>

<details id="sudo">
<summary>sudo</summary>



Do **not** edit `/etc/sudoers` with `nano` (a syntax error can lock sudo). Use `visudo`. Extra rules usually live in `/etc/sudoers.d/`.

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

Example block (edit only with `visudo`; put it in `/etc/sudoers.d/`):

```
Defaults        passwd_tries=3
Defaults        badpass_message="Wrong password."
Defaults        logfile="/var/log/sudo/sudo.log"
Defaults        log_input, log_output
Defaults        iolog_dir="/var/log/sudo"
Defaults        requiretty
Defaults        secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
```

`log_input` / `log_output` record **that sudo command**: what was typed on stdin and what the command printed, not the whole SSH login. Files go under `/var/log/sudo/` (`iolog_dir`). `secure_path` stops sudo from running a fake `ls` from your home. `requiretty` needs a real terminal. Create the log dir if needed: `sudo mkdir -p /var/log/sudo`.

This block is the **subject’s rules**. On the VM they live in `/etc/sudoers.d/` (edit with `visudo`).

**What sudo is for (defense):** you stay a normal user and elevate **one command** instead of logging in as root all day. Example: `sudo apt update` vs `su -` (full root shell). Logs show who did what. Restricted `secure_path` stops a fake `ls` in your home from running as root. `requiretty` blocks sudo from some detached scripts. Limited tries slow brute force.

Show that a sudo command is logged:

```bash
ls -l /var/log/sudo/
sudo cat /var/log/sudo/*          # or ls the latest file in there
sudo echo test                    # then check the log again: it should grow / get a new entry
```

</details>

<details id="groups-users-hostname">
<summary>Groups, users, hostname</summary>



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
cat /etc/hostname                     # persisted by hostnamectl
hostnamectl
sudo hostnamectl set-hostname newname42
```

`hostnamectl set-hostname` updates the **kernel hostname** and **`/etc/hostname`** (so the name survives reboot). It does **not** always rewrite **`/etc/hosts`**.

`/etc/hosts` is local name resolution (IP → name, like a tiny DNS file). On Debian the machine’s own name is usually on **`127.0.1.1`** (loopback). `127.0.0.1` stays **`localhost`**.

```
127.0.0.1       localhost
127.0.1.1       casgarna42
```

After a rename, that second line must use the **new** name, then reboot (the scale checks that the hostname **sticks**):

```
127.0.0.1       localhost
127.0.1.1       newname42
```

If `/etc/hosts` still has the old name, `sudo` and other tools may try to resolve the current hostname, wait, and print `unable to resolve host`. Check: `getent hosts $(hostname)` or `ping -c1 $(hostname)` — they should map to `127.0.1.1`. Restore both `hostnamectl` and `/etc/hosts` to `casgarna42` afterwards.

</details>

<details id="apparmor">
<summary>AppArmor</summary>



Must be **running at startup**. Profiles live in `/etc/apparmor.d/`.

```bash
sudo aa-status
systemctl status apparmor
systemctl is-enabled apparmor         # enabled at boot?
ls /etc/apparmor.d/
```

</details>

<details id="encrypted-lvm">
<summary>Encrypted LVM</summary>



At least **two encrypted LVM volumes**. The evaluator wants to **see** the disk layout, not only hear the theory.

**The stack (bottom → top)**

1. Real virtual disk (`sda`) — a file on the host, looks like a disk inside the VM.
2. Usually a small **`/boot`** partition **without** encryption (the machine must start far enough to ask for the passphrase).
3. The rest is **[LUKS](#luks)** encryption: locked until you type the passphrase at boot.
4. After unlock, **[LVM](#lvm)** sits on that decrypted device: **PV** (the unlocked disk) → **VG** (one pool) → **LVs** (the “partitions” you actually use: `/`, swap, maybe `/home`). You need **at least two LVs**.

**What each command is for**

```bash
lsblk
```

Tree of disks and what sits on them. Look for `crypt` / `lvm` under the big partition, and **two or more** LVs with mountpoints (e.g. `/` and `[SWAP]`).

```bash
sudo lsblk -o NAME,FSTYPE,TYPE,SIZE,MOUNTPOINT
```

Same tree, extra columns: **FSTYPE** (`crypto_LUKS`, `LVM2_member`, `ext4`, `swap`), **TYPE** (`disk`, `part`, `crypt`, `lvm`), size, where it is mounted.

```bash
sudo pvs          # Physical Volumes: the unlocked LUKS device feeding LVM
sudo vgs          # Volume Groups: the pool (name + size)
sudo lvs          # Logical Volumes: the slices — count them; need ≥ 2
```

```bash
sudo cat /etc/crypttab
```

Which devices to **unlock at boot** (name, UUID of the LUKS partition). If this file is empty, encryption would not come up automatically.

```bash
sudo cat /etc/fstab
```

What to **mount** after unlock (`/` , swap, `/home`, …). `lsblk` is the live view; `fstab` is the config that survives reboot.

`monitoring.sh` prints `LVM use: yes` if `lsblk` contains `lvm`.

The subject’s partition picture uses **example sizes**. Pick sizes so the system boots without wasting disk. Typical: `/boot` unencrypted, then at least two encrypted LVs (e.g. `/` and swap, or `/` and `/home`).

**How LVM works (defense):** LVM sits between the disk and the filesystem. A **Physical Volume** (PV) is the real disk or LUKS device. A **Volume Group** (VG) is a pool of PVs. A **Logical Volume** (LV) is a slice of that pool that you format and mount (`/`, `/home`, swap). You can grow an LV later without repartitioning the whole disk. Here the PV is **encrypted (LUKS)**, so you unlock it at boot, then LVM and the filesystems appear.

</details>

<details id="command-cheat-sheet">
<summary>Command cheat sheet</summary>



<table><tr><td>

Quick reference for the defense (most admin commands need `sudo`).

<details id="users">
<summary>Users</summary>



| Command | What it does |
|---|---|
| `useradd -m <user>` | create user (home directory) |
| `userdel -r <user>` | delete user (and home) |
| `passwd <user>` | set password |
| `id <user>` | show user info (uid, groups) |
| `cut -d: -f1 /etc/passwd` | list users |

Debian often uses `adduser` instead of `useradd` (interactive, applies `login.defs` aging).

</details>

<details id="groups">
<summary>Groups</summary>



| Command | What it does |
|---|---|
| `groupadd <group>` | create group |
| `groupdel <group>` | delete group |
| `usermod -aG <group> <user>` | add user to group (`-a` = append) |
| `gpasswd -d <user> <group>` | remove user from group |
| `getent group <group>` | show group members |

`addgroup` / `adduser <user> <group>` are the Debian-friendly equivalents.

</details>

<details id="hostname">
<summary>Hostname</summary>



| Command | What it does |
|---|---|
| `hostnamectl` | show hostname |
| `hostnamectl set-hostname <new>` | set hostname (also update `127.0.1.1` in `/etc/hosts`) |

</details>

<details id="ssh--ufw">
<summary>SSH / UFW</summary>



| Command | What it does |
|---|---|
| `systemctl status ssh` | SSH service status |
| `ufw status numbered` | firewall rules with numbers |
| `ufw allow <port>` | open a port |
| `ufw deny <port>` | deny a port |

After changing UFW, check with `ufw status`. After editing `sshd_config`, `systemctl restart ssh`.

</details>

<details id="system-info">
<summary>System info</summary>



| Command | What it does |
|---|---|
| `uname -a` | kernel / architecture |
| `lsblk` | block devices / LVM |
| `df -h` | disk usage |
| `free -m` | memory usage |
| `ss -tunlp` | open ports |
| `crontab -e` | edit cron |
| `crontab -l` | list cron |

Root cron for monitoring: `sudo crontab -e` / `sudo crontab -l`.

</details>

<details id="key-files">
<summary>Key files</summary>



| Path | What it is |
|---|---|
| `/etc/passwd` | users |
| `/etc/shadow` | passwords (hashes, aging) |
| `/etc/group` | groups |
| `/etc/login.defs` | password aging policy |
| `/etc/sudoers` | sudo rules (edit with `visudo` only) |
| `/etc/ssh/sshd_config` | SSH |
| `/etc/hostname` | hostname |
| `/var/log/auth.log` | auth log |

</details>



</td></tr></table>
</details>



</td></tr></table>
</details>

<details id="instructions">
<summary>Instructions</summary>



<table><tr><td>

<details id="what-to-submit">
<summary>What to submit</summary>



At the **root of the Git repository**:

1. `README.md` (this file)
2. `signature.txt`: **only** the SHA-1 of the VM disk (one hash, no extra text)

Do **not** put the `.vdi` / `.qcow2` / VM folder in Git.

</details>

<details id="how-to-get-signaturetxt">
<summary>How to get `signature.txt`</summary>



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

</details>

<details id="running-the-virtual-machine">
<summary>Running the virtual machine</summary>



1. Open VirtualBox (or UTM).
2. Confirm **no snapshots** at the start of an evaluation.
3. Start the VM. Unlock encrypted volumes if asked.
4. Log in on TTY as `casgarna` (or root on the console only).
5. Confirm hostname, UFW, SSH, AppArmor, LVM.

There is **no compilation**. `monitoring.sh` is a bash script; it must be executable and scheduled, not compiled.

</details>

<details id="monitoringsh">
<summary>`monitoring.sh`</summary>



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

Subject example (`wall` to all TTYs; banner optional):

```
#Architecture: Linux wil 4.19.0-16-amd64 ... x86_64 GNU/Linux
#Physical CPU: 1
#vCPU: 1
#Memory Usage: 74/987MB (7.50%)
#Disk Usage: 1009/2Gb (49%)
#CPU load: 6.7%
#Last boot: 2021-04-25 14:45
#LVM use: yes
#TCP Connections: 1 ESTABLISHED
#User log: 1
#Network: IP 10.0.2.15 (08:00:27:51:9b:a5)
#Sudo: 42 cmd
```

Wording of labels may differ slightly; every **field** above must appear, with **no error output**.

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
*/10 * * * * /usr/local/bin/monitoring.sh
@reboot /usr/local/bin/monitoring.sh
```

Cron has **five time fields**, then the command: **minute hour day-of-month month weekday**.

- `*/10 * * * *` = every 10 minutes
- `*/1 * * * *` or `* * * * *` = every minute (evaluation live test)
- `@reboot` = once when the machine starts

Put the script in a fixed path (often `/usr/local/bin/monitoring.sh`) and `sudo chmod +x` it. Root crontab: `sudo crontab -e`.

The subject requires the script to be **interruptible without modifying the file**. That means `monitoring.sh` stays the same (path, permissions, content). The **crontab** is the schedule, not the script. Commenting those lines with `#` is how the job is stopped.

`systemctl stop cron` only stops the daemon until the next boot. `cron` is enabled by default, so after `reboot` the `@reboot` and `*/10` entries run again and `wall` returns.

`systemctl disable cron` would persist across reboot but would disable **every** cron job. The usual approach is to edit the crontab only.

**Stop the job:** `sudo crontab -e`, prefix **both** lines (`*/10` and `@reboot`) with `#`, save. `sudo crontab -r` removes the entire crontab (all jobs for that user).

**Run every minute:** in `sudo crontab -e`, change `*/10` to `*/1` (or `* * * * *`). `wall` should show updated values (RAM, CPU; `sudo echo x` changes the sudo count). Restore `*/10` afterwards, or comment the lines to stop the job.

**Stop at next boot without changing the script:**

```bash
ls -l /usr/local/bin/monitoring.sh    # note path, size, permissions (e.g. -rwxr-xr-x)
sudo crontab -e                       # comment both lines — crontab, not the script
sudo reboot
# after login: same path, same rights, same content; no wall
ls -l /usr/local/bin/monitoring.sh
sudo crontab -e                       # uncomment both lines when done
```

**Stop at next boot, without touching the script:**

```bash
ls -l /usr/local/bin/monitoring.sh    # note path, size, permissions (e.g. -rwxr-xr-x)
sudo crontab -e                       # # both lines — crontab, not the script
sudo reboot
# after login: same path, same rights, same content; no wall
ls -l /usr/local/bin/monitoring.sh
sudo crontab -e                       # uncomment both lines when done
```

`wall` writes a broadcast to every logged-in TTY, so the banner appears on the console and over SSH.

</details>

<details id="check-vm">
<summary>Check (VM)</summary>



Commands to verify the mandatory setup. Run **inside the guest** as `casgarna`.

**Host (before start):** no snapshots; `README.md` + `signature.txt` at repo root; `shasum` of the `.vdi` / `.qcow2` matches `signature.txt`; VM not already running.

```bash
# OS / no GUI
cat /etc/os-release
echo $XDG_SESSION_TYPE          # not x11/wayland
whoami                          # not root

# Hostname
hostname                        # casgarna42

# User + groups
id casgarna                     # user42 and sudo
getent group user42
getent group sudo

# AppArmor at boot
sudo aa-status
systemctl is-enabled apparmor

# Encrypted LVM, at least 2 LVs
lsblk
sudo pvs; sudo vgs; sudo lvs
sudo cat /etc/crypttab

# SSH
sudo systemctl status ssh
sudo grep -E '^Port|^PermitRootLogin' /etc/ssh/sshd_config   # 4242, no
sudo ss -tlnp | grep 4242

# UFW
sudo ufw status verbose         # active, 4242 ALLOW
systemctl is-enabled ufw

# Password aging 30 / 2 / 7
sudo grep -E '^PASS_MAX_DAYS|^PASS_MIN_DAYS|^PASS_WARN_AGE' /etc/login.defs
sudo chage -l casgarna
sudo chage -l root

# Complexity
grep pam_pwquality /etc/pam.d/common-password
# minlen=10, ucredit/lcredit/dcredit=-1, maxrepeat=3, usercheck, difok, enforce_for_root

# sudo
sudo visudo -c
ls -l /var/log/sudo/
# passwd_tries=3, badpass_message, log_input/output, requiretty, secure_path

# monitoring + cron
ls -l /usr/local/bin/monitoring.sh    # adjust path; must be executable
sudo crontab -l                       # */10 and @reboot
```

**From the host** (after UFW + SSH look good):

```bash
ssh casgarna@<VM_IP> -p 4242                 # must work
ssh root@<VM_IP> -p 4242                     # must fail
```

**Live tests** (new user, group, hostname, UFW 8080, sudo log, cron interval):

```bash
# 1) new user + weak password must be rejected; strong one accepted
sudo adduser testdude

# 2) new group
sudo addgroup evaluating
sudo adduser testdude evaluating
getent group evaluating

# 3) hostname: hostnamectl + /etc/hosts 127.0.1.1, reboot, then restore
sudo hostnamectl set-hostname test42
sudo nano /etc/hosts                  # 127.0.1.1 test42
# reboot, check hostname, then set both back to casgarna42

# 4) UFW open 8080, show it, delete it; 4242 stays
sudo ufw allow 8080
sudo ufw status numbered
sudo ufw delete allow 8080

# 5) put testdude in sudo, show sudo log grows
sudo adduser testdude sudo
sudo echo test
ls -l /var/log/sudo/

# 6) cron: change */10 to */1, then comment cron lines, reboot,
#    script file unchanged, no wall — without editing monitoring.sh
sudo crontab -e
```

Clean up test users/groups/hostname afterwards so the machine matches the subject again.

</details>



</td></tr></table>
</details>

<details id="evaluation">
<summary>Evaluation</summary>



<table><tr><td>

Peer-evaluation walkthrough in the same order as the Intra scale. Short answers sit here; longer explanations are linked. Status commands: [Check (VM)](#check-vm).

The subject may also request a small change to `monitoring.sh` (a few lines or a display tweak).

<details id="preliminaries--general-instructions">
<summary>Preliminaries / general instructions</summary>



- The evaluated student is present. The repository is cloned with `git clone` into an **empty** folder; only that clone is graded.
- Files: [What to submit](#what-to-submit) — `README.md` + `signature.txt` at repo root, **no** VM in Git.
- Signatures must match: [How to get `signature.txt`](#how-to-get-signaturetxt). Compare `signature.txt` with `shasum` of the `.vdi` (or `.qcow2` for UTM) using `diff`.
- **No snapshots** at the start. The VM is **not** already running. Then [Running the virtual machine](#running-the-virtual-machine).
- Protect the original disk: a cold snapshot (removed afterwards) **or** boot a **copy**. Starting the VM changes the hash.

```bash
cat signature.txt
shasum "/path/to/your.vdi"    # first field = hash; UTM: disk-0.qcow2
diff signature.txt /tmp/disk.hash
```

</details>

<details id="readmemd-check">
<summary>README.md check</summary>



Required README contents:

| Scale item | Where it is |
|---|---|
| First line italic, `… by casgarna` | [top of this file](#born2beroot) |
| Description (goal + overview) | [Description](#description) |
| Project description | [Project description](#project-description) |
| OS choice + pros/cons | [Operating system choice: Debian](#operating-system-choice-debian) |
| Design: partitions, security, users, services | [Main design choices](#main-design-choices) |
| Debian vs Rocky | [Debian vs Rocky Linux](#debian-vs-rocky-linux) |
| AppArmor vs SELinux | [AppArmor vs SELinux](#apparmor-vs-selinux) |
| UFW vs firewalld | [UFW vs firewalld](#ufw-vs-firewalld) |
| VirtualBox vs UTM | [VirtualBox vs UTM](#virtualbox-vs-utm) |
| Instructions + Resources + AI | [Instructions](#instructions), [Resources](#resources), [AI usage](#ai-usage) |

</details>

<details id="project-overview-talk">
<summary>Project overview (talk)</summary>



`wall` from `monitoring.sh` runs every 10 minutes.

| Scale question | Answer | More |
|---|---|---|
| How does a VM work? | A **[hypervisor](#hypervisor)** (VirtualBox/UTM) on the host **[emulates](#emulate)** CPU, RAM, disk, NIC. The **guest** OS runs in a disk file and thinks it is real hardware. | [How a virtual machine works](#how-a-virtual-machine-works-defense) |
| Purpose of VMs? | Isolation, no extra machine, snapshots, safe testing. | same section |
| Choice of OS? | **Debian** stable: subject recommends it; AppArmor + UFW + `apt` are simpler for a first server. | [Operating system choice: Debian](#operating-system-choice-debian) |
| Debian vs Rocky? | Debian: `apt` / `.deb`, AppArmor, UFW. Rocky: `dnf` / `.rpm`, SELinux, firewalld. | [Debian vs Rocky Linux](#debian-vs-rocky-linux) |
| `apt` vs `aptitude`? (Debian) | Same `.deb` repos. `apt` is the daily CLI. `aptitude` is better at **dependency conflicts** (TUI). | [`apt` vs `aptitude`](#apt-vs-aptitude-debian-defense-question) |
| What is AppArmor? | **MAC**: path-based profiles; even root is limited. Check: `aa-status`. | [AppArmor vs SELinux](#apparmor-vs-selinux), [AppArmor](#apparmor) |
| SELinux / DNF? (only if Rocky) | SELinux = label-based MAC. DNF = Rocky package manager. We chose Debian, so this is comparison only. | [Lexicon](#lexicon) |

</details>

<details id="simple-setup">
<summary>Simple setup</summary>



Commands: [Check (VM)](#check-vm) — OS / no GUI, UFW, SSH.

| Scale check | What they want | Answer / where |
|---|---|---|
| No graphical environment | No X.org / Wayland | [Goal](#goal). `echo $XDG_SESSION_TYPE` is not x11/wayland. |
| Login not root | User `casgarna` | Password follows [Password policy](#password-policy). |
| UFW started | `sudo ufw status verbose` active | [Firewall (UFW)](#firewall-ufw) |
| SSH started | `sudo systemctl status ssh` | [SSH](#ssh) |
| OS is Debian or Rocky | `cat /etc/os-release` | Debian |

</details>

<details id="user-step-1">
<summary>User step 1</summary>



Commands: [Check (VM)](#check-vm) — User + groups.

| Scale check | What to do / say |
|---|---|
| Login user exists, in `sudo` and `user42` | `id casgarna`. Why `user42`: subject group, **no extra rights**. `sudo` = may elevate. [Groups, users, hostname](#groups-users-hostname) |
| Create a **new user** | `sudo adduser evaluser` — evaluator’s password must match the policy. Weak password must be **rejected**. |
| Explain the policy files | **Aging:** `/etc/login.defs` (`PASS_MAX_DAYS=30`, `PASS_MIN_DAYS=2`, `PASS_WARN_AGE=7`). **Complexity:** PAM `pam_pwquality` in `/etc/pam.d/common-password` and/or `/etc/security/pwquality.conf`. Existing accounts: `chage`. Full table and “why”: [Password policy](#password-policy). |

</details>

<details id="user-step-2">
<summary>User step 2</summary>



```bash
sudo addgroup evaluating
sudo adduser evaluser evaluating
getent group evaluating
id evaluser
```

**Advantages / disadvantages of the password policy:** [Password policy](#password-policy) — expiry limits how long a stolen password stays valid; min 2 days blocks instant reuse; 7-day warning; length + character classes make guessing harder. Downsides: people write passwords down; min 2 days is inconvenient; a broken PAM file can lock the account.

</details>

<details id="hostname-and-partitions">
<summary>Hostname and partitions</summary>



Hostname commands: [Check (VM)](#check-vm) and [Groups, users, hostname](#groups-users-hostname).

```bash
hostname                                    # casgarna42
sudo hostnamectl set-hostname THEIRLOGIN42
sudo nano /etc/hosts                        # 127.0.0.1 localhost; 127.0.1.1 → THEIRLOGIN42
sudo reboot
hostname                                    # THEIRLOGIN42
getent hosts $(hostname)                    # 127.0.1.1
sudo hostnamectl set-hostname casgarna42
sudo nano /etc/hosts                        # 127.0.1.1 casgarna42
```

**Partitions:** `lsblk` (and `sudo pvs; sudo vgs; sudo lvs`). Compare to the example in the subject. Sizes in the PDF are examples. [Encrypted LVM](#encrypted-lvm).

**What is LVM?** PV (disk/LUKS) → VG (pool) → LV (what you mount). Encryption (LUKS) sits under LVM. Useful: grow volumes later without repartitioning the whole disk.

</details>

<details id="sudo-1">
<summary>SUDO</summary>



Talk + rules: [sudo](#sudo). Installed / logs: [Check (VM)](#check-vm).

```bash
dpkg -l | grep sudo
sudo adduser evaluser sudo
sudo visudo -f /etc/sudoers.d/yourfile      # your real filename
ls -l /var/log/sudo/                        # folder + at least one file
sudo echo hello                             # then check the log grew
```

**Value of sudo:** stay a normal user; elevate **one** command (`sudo apt update`) instead of `su -` all day; logs who did what.

**Subject rules to show:** `passwd_tries=3`, custom `badpass_message`, `log_input`/`log_output` + `iolog_dir=/var/log/sudo`, `requiretty`, restricted `secure_path`.

</details>

<details id="ufw--firewalld">
<summary>UFW / Firewalld</summary>



Talk: [UFW vs firewalld](#ufw-vs-firewalld) and [Firewall (UFW)](#firewall-ufw). Status: [Check (VM)](#check-vm).

**What UFW is:** Uncomplicated Firewall — simple frontend for iptables/nftables. Default deny incoming; only **4242** open so SSH is not on 22 and nothing else is exposed.

```bash
dpkg -l | grep ufw
sudo ufw status verbose                     # 4242 ALLOW
sudo ufw allow 8080
sudo ufw status numbered
sudo ufw delete allow 8080                  # or delete by rule number
sudo ufw status                             # 8080 gone, 4242 still there
```

</details>

<details id="ssh-1">
<summary>SSH</summary>



Talk + how to connect: [SSH](#ssh). Status/port: [Check (VM)](#check-vm).

**What SSH is:** encrypted remote shell. Value: no GUI/telnet on the wire. Port **4242** instead of 22 = less noisy scanning. `PermitRootLogin no` = a guessed root password cannot get a **remote** shell (root console locally is still OK).

```bash
dpkg -l | grep openssh-server
sudo ss -tlnp | grep ssh                    # 4242, not 22
ssh evaluser@<VM_IP> -p 4242                # from host: must work
ssh root@<VM_IP> -p 4242                    # must fail
```

NAT: often `ssh casgarna@127.0.0.1 -p 4242` with VirtualBox port forwarding — see [SSH](#ssh).

</details>

<details id="script-monitoring">
<summary>Script monitoring</summary>



Full fields, cron, interrupt: [`monitoring.sh`](#monitoringsh). Show the file: `cat` / `nano` the path on the VM (often `/usr/local/bin/monitoring.sh`).

| Scale question | Answer |
|---|---|
| How does the script work? | Bash: collect stats (`uname`, `/proc/cpuinfo`, `free`, `df`, `top`, `who -b`, `lsblk`, `ss`, `users`, IP/MAC, `journalctl` sudo), then `wall` to all TTYs. Table of each line in that section. |
| What is cron? | Scheduler. Five time fields + command. `@reboot` = at boot. `*/10 * * * *` = every 10 minutes. |
| How does it run from startup every 10 min? | **Root** crontab (`sudo crontab -e`), two lines, script `chmod +x`. Not a loop inside the script. |

Live tests (`monitoring.sh` is not edited):

1. Every **minute:** `sudo crontab -e` → `*/1`. `wall` values change (`sudo echo x` for sudo count).
2. **Stop at boot without modifying the script:** comment **both crontab lines** (`#`). `systemctl stop cron` does not persist across reboot. Then `sudo reboot`. Same path, same rights, same content, no `wall`. Uncomment the crontab afterwards.

The script is started by **root’s crontab**, not by a loop in the file. Commenting those two lines stops `wall` after boot; the script file is unchanged.

</details>



</td></tr></table>
</details>

<details id="resources">
<summary>Resources</summary>



<table><tr><td>

<details id="documentation">
<summary>Documentation</summary>



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

</details>

<details id="articles--tutorials">
<summary>Articles / tutorials</summary>



Guides I used while setting up the VM:

- [My experience with the Born2beroot project (m4nnb3ll)](https://m4nnb3ll.medium.com/my-experience-with-the-born2beroot-project-42-ad19d738ad4f)
- [Born2beroot (baigal)](https://baigal.medium.com/born2beroot-e6e26dfb50ac)
- [Operating systems overview (GeeksforGeeks)](https://www.geeksforgeeks.org/operating-systems/operating-systems/)

</details>

<details id="ai-usage">
<summary>AI usage</summary>



The subject treats AI as a learning aid: reason first, do not paste unexplained answers.

AI was used as a **learning and documentation aid**, not as a replacement for setting up the machine:

- **README:** structuring the file so it matches the subject’s README requirements (first italic line, Description, Instructions, Resources, Project description, comparisons).
- **Concepts:** clarifying differences (Debian vs Rocky, AppArmor vs SELinux, UFW vs firewalld, VirtualBox vs UTM, apt vs aptitude).
- **monitoring.sh comments:** explaining bash constructs already used on the VM (`awk`, `wall`, cron).

The VM, partitioning, SSH, firewall, sudo, and password policy were configured **on the machine by the learner**, following the subject and man pages.

</details>



</td></tr></table>
</details>

## Lexicon

<a id="lexicon"></a>

Short explanations of the terms used in this project (useful for the defense).

| Term | What it is |
|---|---|
| <a id="mac"></a>**MAC** (Mandatory Access Control) | Kernel security model: the system (not the file owner) decides what a process may do. Even **root** is limited. Opposite of DAC (Discretionary Access Control), where the owner of a file sets `chmod`/`chown`. AppArmor and SELinux are MAC. |
| **AppArmor** | Debian’s MAC. Each program gets a **profile** that lists allowed **file paths**. Simpler: “may `sshd` read `/etc/ssh`?” Check: `aa-status`. |
| **SELinux** | Rocky/RHEL’s MAC. Everything has a **label/type** (file, port, process). Stricter and more granular: “may this *type* talk to that *type*?” Check: `getenforce` / `sestatus`. Must be on at boot on Rocky. |
| **`.deb`** | Debian package file (like an installer). Installed by `dpkg`; `apt`/`aptitude` fetch them and resolve dependencies. |
| **`.rpm`** | Red Hat package file. Same idea as `.deb`, used on Rocky/RHEL/Fedora. Installed via `dnf` / `rpm`. |
| **`apt`** | Default Debian package manager for humans: `apt update`, `apt install`. Uses `.deb` packages. |
| **`apt-get`** | Older, more stable `apt` backend. Preferred in scripts. Same packages as `apt`. |
| **`aptitude`** | Another Debian frontend (CLI + TUI). Better at **solving dependency conflicts** (can propose several solutions). Same `.deb` repos as `apt`. |
| **`dpkg`** | Low-level Debian tool that actually installs/removes a `.deb`. `apt` calls `dpkg`. |
| **`dnf`** | Rocky/RHEL package manager (successor of `yum`). Installs `.rpm` packages, resolves dependencies. |
| <a id="ufw"></a>**UFW** | Uncomplicated Firewall (Debian). Simple allow/deny commands. A **frontend**: it writes [iptables](#iptables) / [nftables](#nftables) rules for you. This project: only **4242/tcp** open. |
| <a id="firewalld"></a>**firewalld** | Rocky’s firewall program. Same idea as UFW, but with **zones** (public, drop, …) and named services instead of only port numbers. |
| <a id="iptables"></a>**iptables** | Older tool to tell the Linux kernel which network packets to **accept** or **drop**. Example idea: “allow TCP port 4242, block everything else incoming.” The syntax is verbose. **UFW calls this for you.** |
| <a id="nftables"></a>**nftables** | Newer replacement for iptables (`nft` command). Same job: kernel packet filter. Many Debian versions use nftables **under** UFW. You still use `ufw`, not `nft`, in this project. |
| **packet / packet filter** | A **packet** is a small chunk of network data. A **packet filter** looks at each chunk (port, protocol, direction) and allows or blocks it. That is what a firewall does. |
| **frontend** | A simpler program on top of a harder one. UFW is a frontend for iptables/nftables: short command in, kernel rule out. |
| **NAT / port forwarding** | VirtualBox default network: the guest (often `10.0.2.15`) is not a real LAN IP. The host connects via **localhost** and a forwarded port (host 4242 → guest 4242). |
| **SSH key pair** | Private key stays on your PC, public key on the server. Login proves you have the private key; it never travels on the wire. Optional here (password is allowed). |
| **`ucredit=-1`** | PAM credit: a **negative** number means that class is **required** (at least one uppercase). Same idea for `lcredit` / `dcredit`. |
| **SSH** | Secure Shell: encrypted remote login. Here: port **4242**, **no root login**. Client: `ssh user@ip -p 4242`. |
| **OpenSSH** | The SSH server/client used on Debian (`sshd`). Config: `/etc/ssh/sshd_config`. |
| **sudo** | Run one command as another user (usually root) without logging in as root. Config in `/etc/sudoers` and `/etc/sudoers.d/`. |
| **TTY** | A real text terminal (console or SSH session). `requiretty` means sudo only works if you have one, not from a detached script without a terminal. |
| **PAM** | Pluggable Authentication Modules. Hooks used for login/password rules (`pam_pwquality` = password complexity). |
| **password aging** | How long a password may live before it must be changed. Not complexity (length, A-z, digit): that is PAM/`pwquality`. Aging is: max 30 days, min 2 days between changes, warning 7 days before expiry. Set in `/etc/login.defs` (`PASS_MAX_DAYS`, `PASS_MIN_DAYS`, `PASS_WARN_AGE`). |
| **`chage`** | **ch**ange **age**. Show or set a user’s aging. `sudo chage -l casgarna` lists last change, min/max days, expiry, warning. |
| <a id="lvm"></a>**LVM** | Logical Volume Manager. Disk is split into **PV → VG → LV**, so you can resize volumes later. This project: **encrypted** LVM, at least two LVs. |
| **PV / VG / LV** | Physical Volume (real disk/partition), Volume Group (pool), Logical Volume (the “partition” you format, e.g. `/`, `/home`, swap). |
| <a id="luks"></a>**LUKS** | Linux disk encryption. You type a passphrase at boot; then LVM volumes become readable. |
| **cron** | Scheduler: run a command at a time or interval (`*/10 * * * *` = every 10 minutes, `@reboot` = at startup). How `monitoring.sh` is launched. Stop it here without editing the script. |
| **`wall`** | Write a message to **all** logged-in terminals. That is how the monitoring banner appears everywhere. |
| **hostname** | Machine name on the network. Must be `login` + `42` (e.g. `casgarna42`). Change with `hostnamectl`. |
| <a id="hypervisor"></a>**hypervisor** | The program on your real PC (**host**) that runs virtual machines. VirtualBox and UTM are hypervisors. |
| <a id="emulate"></a>**emulate** | To **imitate** hardware in software. The VM has no real extra CPU or disk; VirtualBox *pretends* there are some, so Debian can boot as if it were a physical PC. |
| **host / guest** | **Host** = your Mac. **Guest** = Debian inside the VM. |
| **VirtualBox** | Oracle hypervisor: runs a full VM (`.vdi` disk). Mandatory if you can use it. |
| **UTM** | Hypervisor for Mac (esp. Apple Silicon). Disk is `.qcow2`. Allowed if VirtualBox is not usable. |
| **SHA-1 / signature** | Fingerprint of the VM disk file. Pasted into `signature.txt`. Changes as soon as the VM is started. |
| **snapshot** | Frozen copy of VM state. Evaluations must **start with none**; you may create one during defense and delete it after. |
| **X.org / Wayland** | Graphical display servers (GUI). **Forbidden** in this project: no desktop. |
| **KDump** | Kernel crash dump service on Rocky. The subject says you do **not** have to set it up. |
