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

**SSH** = encrypted remote terminal (see [SSH](#ssh)). Subject: listen on **4242**, **no root over SSH**. Do **not** install Oh My Zsh / zsh — the eval expects bash.

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

If **host port 4242 is already taken** (common on 42 cluster PCs), map **host 4243 → guest 4242**. That is only VirtualBox **forwarding** (translation). Debian still listens on **4242**. From the Mac:

```bash
ssh casgarna@127.0.0.1 -p 4243
```

To reach a VM on **another** machine: do not lock Host IP to `127.0.0.1` (empty or `0.0.0.0`), then SSH to **that machine’s LAN IP** and the **host** port. Evaluation is usually on the same Mac as VirtualBox, so `127.0.0.1` is enough. Defense wording: Evaluation → SSH.

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
# or: sudo visudo -f /etc/sudoers.d/NAME   # NAME from: sudo ls /etc/sudoers.d/
```

Subject **Defaults**: `passwd_tries=3`, custom `badpass_message`, `requiretty`, `secure_path=…`, `log_input,log_output`, `iolog_dir="/var/log/sudo"`. Example block: [sudo](#sudo).

`secure_path` stops sudo from running a fake binary from your home. **TTY** = your current login session (VirtualBox window or SSH). `requiretty` = sudo only from that. Test a wrong password three times; then `ls -l /var/log/sudo/` must grow after a real `sudo` command.

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

**`verbose`** here is just “more detail,” not a second program. `ufw status` prints the rule table. `ufw status verbose` also prints **Status** (active/inactive), **Logging**, **Default** incoming/outgoing/routed, and **New profiles**. That is why the evaluation uses `verbose`: you prove the firewall is on and the defaults, not only that 4242 is listed.

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



**What SSH is:** **S**ecure **Sh**ell — remote terminal over the network, encrypted (not telnet). Client on the Mac (`ssh`), server on Debian (`openssh-server`, service name `ssh` / process `sshd`). Port **4242** instead of 22. `PermitRootLogin no` = no root **over the network**; local console root is still OK. Defense wording: Evaluation → SSH.

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

**`localhost` / `127.0.0.1` with NAT** means the **host PC**. VirtualBox forwards a **host** port into **guest 4242**. SSH inside Debian stays on 4242. If the **host** already uses 4242 (42 cluster), use host **4243** → guest **4242** and `ssh … -p 4243`. That is translation on the hypervisor, not a change of the subject port. Defense wording: Evaluation → SSH.

To SSH from a **different** computer than the one running VirtualBox: Host IP empty or `0.0.0.0`, then `ssh casgarna@LAN_IP_OF_THAT_PC -p <host_port>`. Eval is usually local, so `127.0.0.1` is enough.

If SSH complains that the host key changed after you change the forwarded port:

```bash
ssh-keygen -R "[127.0.0.1]:4242"
ssh-keygen -R "[127.0.0.1]:4243"
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



Do **not** edit `/etc/sudoers` with `nano` (a syntax error can lock sudo). Use **`visudo`**. Extra rules often live in **`/etc/sudoers.d/`** (one small file per drop-in). There is no file literally named `yourfile` — that was a placeholder.

```bash
sudo ls /etc/sudoers.d/              # real names on this VM (e.g. README leftover + your drop-in)
sudo visudo                          # main file /etc/sudoers
sudo visudo -f /etc/sudoers.d/NAME   # NAME = what ls just showed (not the word "yourfile")
sudo cat /etc/sudoers.d/*            # read-only view of drop-in rules
sudo ls -l /var/log/sudo/            # sudo I/O logs must exist
```

**TTY** = your current login session: the VirtualBox window or SSH.

`sudo` is installed; user `casgarna` is in group `sudo`. Subject **Defaults** (what they mean):

| Setting | What it does |
|---|---|
| `passwd_tries=3` | After **3** wrong sudo passwords, sudo gives up for that command. Slows guessing. |
| `badpass_message="…"` | Text shown on a **wrong** sudo password (you choose the sentence). Proves the policy is yours, not the default. |
| `log_input` + `log_output` | For **that sudo command only**: record what was typed on stdin (`log_input`) and what the command printed (`log_output`). Not the whole SSH session. |
| `iolog_dir="/var/log/sudo"` | Folder for those I/O recordings. Must exist (`mkdir -p`). After `sudo echo hello`, new files/dirs appear here. |
| `requiretty` | **TTY** = your current login session: the VirtualBox window or SSH. `requiretty` = sudo only from that. A process with no login (no console, no SSH) is refused. |
| `secure_path="…"` | When sudo runs a command, it searches **only** these directories for the program (example: `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin`). A fake `ls` in your home is not used. |

Example block (edit only with `visudo`):

```
Defaults        passwd_tries=3
Defaults        badpass_message="Wrong password."
Defaults        logfile="/var/log/sudo/sudo.log"
Defaults        log_input, log_output
Defaults        iolog_dir="/var/log/sudo"
Defaults        requiretty
Defaults        secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
```

`logfile=` is an extra text log of *that* sudo was used; `iolog_dir` is the detailed input/output capture the subject asks for. Create the dir: `sudo mkdir -p /var/log/sudo`.

This block is the **subject’s rules**. On the VM they live in `/etc/sudoers` and/or a file under `/etc/sudoers.d/` (edit only with `visudo`).

**What sudo is for (defense):** you stay a normal user and elevate **one command** instead of logging in as root all day. Example: `sudo apt update` vs `su -` (full root shell). Logs show who did what. Restricted `secure_path` stops a fake `ls` in your home from running as root. `requiretty` blocks sudo from some detached scripts. Limited tries slow brute force.

**Prove the logs (evaluation sheet):**

1. Folder exists and is not empty: `sudo ls -l /var/log/sudo/`
2. Open what is inside: `sudo ls -lR /var/log/sudo/` and `sudo cat` / `sudo tail` on a log file (or `logfile=/var/log/sudo/sudo.log` if you set that). You should see **past sudo commands**.
3. Run **one new** sudo command, then list the folder **again**. A new file or directory should appear, or the log file should be longer.

```bash
sudo ls -l /var/log/sudo/
sudo sudoreplay -d /var/log/sudo/ -l | tail -n 10
sudo ls -lR /var/log/sudo/ | grep '^d' | wc -l
sudo echo hello
sudo ls -lR /var/log/sudo/ | grep '^d' | wc -l    # e.g. 58 → 60
```

`echo hello` is not special. Any sudo command works (`sudo ls /root`). You run it so the evaluator **sees the folder change**. Reading `/var/log/sudo/` usually needs `sudo` too.

**If `ls` still looks the same:** `total 8` is **disk blocks**, not “8 log lines”. Owner `root root` is normal.

I/O logs (`iolog_dir`) are **nested folders** (`00/00/01/…`), not one new file in the top directory. The top `ls -l` often stays `total 8` with the same `00` directory.

```bash
sudo ls -lt /var/log/sudo/           # newest first (top folder)
sudo find /var/log/sudo -mmin -2     # files/dirs changed in the last 2 minutes
sudo ls -lt /var/log/sudo/00/00/     # last numbered session folder is the new one
sudo cat /var/log/sudo/sudo.log      # only if logfile= is set
```

After `sudo echo hello`, `find -mmin -2` should list a new session dir and files like `log`, `stdout` (stdout may contain `hello`).

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
| `ufw status verbose` | rules plus Status, Logging, Default policies |
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

The subject requires the script to be **interruptible without modifying the file**. Two different things:

| File | What it is | Eval “do not modify” |
|---|---|---|
| `/usr/local/bin/monitoring.sh` | The **script** (the program that prints `wall`) | Must stay: same path, same rights, same content. **No** `#` inside this file for the stop test. |
| Root **crontab** (`sudo crontab -e`) | The **schedule** (“run that path every 10 min and at boot”) | **This** is what you comment. `#` here does not change the script. |

Commenting crontab lines with `#` is how the job is stopped. Cron simply never launches `monitoring.sh` after reboot. The script still exists, still executable, still the same bytes.

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

**Run by hand:** yes — `sudo /usr/local/bin/monitoring.sh`. It does **not** `echo` to your prompt. It only **`wall`s**. Wait a few seconds (`journalctl` / `top` can be slow). Then a broadcast like `Broadcast message from root@…` plus the `#Architecture:` block. If the prompt comes back with **no** banner: `mesg y` (this TTY was refusing messages), or you are looking at the wrong window (VirtualBox vs SSH). Use the **full path**; `sudo monitoring.sh` fails if the file is not on sudo’s `secure_path`. Need `chmod +x`. Running as your user (no sudo) still `wall`s, but the sudo count from `journalctl` can be empty/wrong.

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

**What you see in `lsblk` (this VM)**

`lsblk` is a **tree**: indented = “lives inside the line above”. Columns (default `lsblk`):

| Column | Meaning |
|---|---|
| **NAME** | Device name (without `/dev/`) |
| **MAJ:MIN** | Kernel device numbers (ignore in the defense) |
| **RM** | Removable? `0` = fixed disk, `1` = CD/USB |
| **SIZE** | Size of that piece |
| **RO** | `0` = read/write, `1` = read-only |
| **TYPE** | `disk`, `part`, `crypt`, `lvm`, `rom` |
| **MOUNTPOINT(S)** | Where it is [mounted](#mount) (`/`, `/home`, `[SWAP]`, …) |

This machine (about **12G** total; names/sizes are yours, not the PDF examples):

```
NAME                      SIZE   TYPE   MOUNTPOINT
sda                       12G    disk
├─sda1                    791M   part   /boot
├─sda2                    1K     part
└─sda5                    11.2G  part
  └─sda5_crypt            11.2G  crypt
    ├─casgarna42--vg-root 7.1G   lvm    /
    ├─casgarna42--vg-swap_1 620M lvm    [SWAP]
    └─casgarna42--vg-home 3.4G   lvm    /home
sr0                       1024M  rom
```

**`sda` / `sda1` / `sda5`:** [naming](#sda) — `sd` = SCSI-style disk, `a` = first disk, numbers = partitions.

Line by line:

1. **`sda` (12G, `disk`)** — the whole virtual hard disk.
2. **`sda1` (791M, `part`, `/boot`)** — unencrypted **boot** partition so the system can start and then ask for the LUKS passphrase.
3. **`sda2` (1K, `part`)** — **extended** partition: a tiny MBR “frame”, not a filesystem. On old-style (MS-DOS) partition tables you only get four *primary* slots. Extra space is wrapped in an extended partition; real data then sits in **logical** partitions inside it (`sda5`, `sda6`, … — numbering starts at 5).
4. **`sda5` (11.2G, `part`)** — that logical partition; almost all remaining space. This is the **LUKS** container (locked until boot passphrase).
5. **`sda5_crypt` (11.2G, `crypt`)** — unlocked LUKS “vault” on `sda5`. LVM’s **PV** sits here.
6. **`casgarna42--vg-root` (7.1G, `lvm`, `/`)** — LV for the OS. The name is volume group `casgarna42-vg` + LV `root` (`--` is how `lsblk` prints a `-` in the name).
7. **`casgarna42--vg-swap_1` (620M, `lvm`, `[SWAP]`)** — swap (overflow for RAM), not a folder.
8. **`casgarna42--vg-home` (3.4G, `lvm`, `/home`)** — user files (`casgarna`, …).
9. **`sr0` (1024M, `rom`)** — virtual CD/DVD (Debian installer ISO). **RM=1**. Not part of LVM.

`pvs` / `vgs` / `lvs` list the same LVM layer: one PV (`sda5_crypt`), one VG (`casgarna42-vg`), three LVs (root, swap, home). That is more than the subject’s **minimum of two** encrypted LVs.

**What is LVM?** [PV](#lvm) (disk or unlocked LUKS) → VG (pool) → LV (what you [mount](#mount)). [LUKS](#luks) sits **under** LVM. Useful: grow an LV later without slicing the whole disk again.

</details>

<details id="sudo-1">
<summary>SUDO</summary>



Talk + rules: [sudo](#sudo). Installed / logs: [Check (VM)](#check-vm).

```bash
dpkg -l | grep sudo
sudo adduser evaluser sudo
sudo visudo                             # or: sudo visudo -f /etc/sudoers.d/NAME  (NAME from ls)

# 1) folder exists (needs sudo to read)
sudo ls -l /var/log/sudo/

# 2) history: last 10 I/O sessions
sudo sudoreplay -d /var/log/sudo/ -l | tail -n 10

# 3) count session dirs, run sudo, count again (expect +2: input + output)
sudo ls -lR /var/log/sudo/ | grep '^d' | wc -l
sudo echo hello
sudo ls -lR /var/log/sudo/ | grep '^d' | wc -l
sudo sudoreplay -d /var/log/sudo/ -l | tail -n 3
```

`sudoreplay -l` lists logged sudo sessions (`-d` = log directory). `tail -n 10` = last 10 lines.

`grep '^d'` keeps only **directory** lines from `ls -lR`. `wc -l` counts them. One sudo often adds **two** dirs (input + output), e.g. 58 → 60.

`echo hello` is only a dummy sudo so the count / list changes. Full log notes: [sudo](#sudo).

**Value of sudo:** stay a normal user; elevate **one** command (`sudo apt update`) instead of `su -` all day; logs who did what.

**Subject rules** (open them with `visudo`; meanings: [sudo](#sudo)):

**TTY** = your current login session: the VirtualBox window or SSH.

| Setting | In one sentence |
|---|---|
| `passwd_tries=3` | Only 3 wrong passwords per sudo command |
| `badpass_message` | Your custom error text |
| `log_input` / `log_output` + `iolog_dir=/var/log/sudo` | Record that command’s keyboard + output into `/var/log/sudo/` |
| `requiretty` | sudo only from a TTY (see the line above) |
| `secure_path` | sudo only looks for programs in that safe PATH |

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

**What it actually does:** the VM sits there with `sshd` **listening** on port **4242**. On the Mac you run `ssh casgarna@127.0.0.1 -p 4242`. That is a login request: username + password (or key). If it matches, Debian gives you a **normal shell** — same kind of prompt as in the VirtualBox window, but the window can stay closed. Every keystroke and every command output travels **encrypted** through that connection. Close the SSH client (`exit`) and that remote session ends. That is the whole job: **remote login**, not a website, not file sharing by itself (`scp`/`sftp` exist but you do not need them for the eval).

**What SSH is (defense):** **S**ecure **Sh**ell — a remote **terminal** over the network with **encryption**. You type on the evaluator’s Mac; Debian runs the commands. Without SSH you only have the VirtualBox window (or old **telnet**, which sent passwords in clear text).

Two programs: **client** on the host (`ssh user@host -p 4242`) and **server** on the VM (`openssh-server`). Debian’s **service** name is `ssh`; the listening process is often called `sshd`. Config is read at start (`/etc/ssh/sshd_config`), so after an edit you `systemctl restart ssh`.

Default port is **22**. Everyone scans 22. This subject uses **4242**, so a random scan of 22 does not find you. UFW must allow **4242/tcp** or the client never gets in. **`PermitRootLogin no`:** even if someone knows the root password, they cannot open a **remote** root shell. Local `su` / console as root in the VM window is still allowed. During eval they create a **new user** and SSH as that user; `ssh root@…` must fail.

Password login is enough here. An **SSH key** (optional) is a private key on the client and a public key on the server — the private key never travels on the wire.

```bash
dpkg -l | grep openssh-server
sudo ss -tlnp | grep ssh                    # 4242, not 22
ssh evaluser@<VM_IP> -p 4242                # from host: must work
ssh root@<VM_IP> -p 4242                    # must fail
```

NAT: often `ssh casgarna@127.0.0.1 -p 4242` with VirtualBox port forwarding.

**Host port 4243 (cluster PCs) — this is OK.** VirtualBox **NAT** does not give the Mac a usable guest IP (`10.0.2.15`). It **forwards**: a port on the **Mac** is mapped to a port **inside the VM**. Two numbers:

| Where | Port | What it is |
|---|---|---|
| **Guest** (Debian) | **4242** | Subject. `sshd_config`, `ufw`, `ss` / `systemctl status ssh`. Never change this for a busy host port. |
| **Host** (Mac / cluster PC) | **4242** or **4243** | Only VirtualBox’s “front door”. Not Debian. |

If `ssh … -p 4242` fails because **4242 is already taken on the host** (common on 42 pool Macs: leftover session, another VM), set the forwarding to **Host 4243 → Guest 4242**. Then:

```bash
ssh casgarna@127.0.0.1 -p 4243
```

VirtualBox **translates** that to guest **4242**. Packets still arrive on 4242 inside the VM. Proof for the evaluator (run **in the VM**):

```bash
sudo grep -E '^Port' /etc/ssh/sshd_config     # 4242
sudo systemctl status ssh                     # listening on 0.0.0.0 port 4242
sudo ufw status                               # 4242 ALLOW
```

The subject grades the **guest**. Host 4243 is a hypervisor workaround, not a config cheat.

**VM on another computer (LAN):** `Host IP` `127.0.0.1` in the forwarding rule means **only that Mac** can use the forward. Leave Host IP **empty** (or `0.0.0.0`) so other machines on the network can connect. From your Mac, SSH to the **LAN IP of the PC that runs VirtualBox**, same host port as in the rule (`4242` or `4243`):

```bash
ssh casgarna@IP_OF_THE_CLUSTER_PC -p 4243
```

Evaluation at 42 is usually **on the same Mac as VirtualBox**, so `127.0.0.1` is enough.

</details>

<details id="script-monitoring">
<summary>Script monitoring</summary>



Full fields, cron, interrupt: [`monitoring.sh`](#monitoringsh). Show the file: `cat` / `nano` the path on the VM (often `/usr/local/bin/monitoring.sh`).

| Scale question | Answer |
|---|---|
| How does the script work? | Bash: collect stats, then **`wall`** (not `echo`). Manual test: `sudo /usr/local/bin/monitoring.sh` — wait, then a broadcast. Table of each line in [`monitoring.sh`](#monitoringsh). |
| What is cron? | Scheduler. Five time fields + command. `@reboot` = at boot. `*/10 * * * *` = every 10 minutes. |
| How does it run from startup every 10 min? | **Root** crontab (`sudo crontab -e`), two lines, script `chmod +x`. Not a loop inside the script. |

Live tests (`monitoring.sh` is **not** edited — `#` goes in the **crontab**):

1. Every **minute:** `sudo crontab -e` → `*/1`. `wall` values change (`sudo echo x` for sudo count).
2. **Stop at boot without modifying the script** (subject wording): comment **both crontab lines** with `#`. That is **not** the script. Then `sudo reboot`. Evaluator checks: same path, same rights, same content of `monitoring.sh`, and **no** `wall`. Uncomment the crontab afterwards.

**Why `#` is allowed:** the subject forbids changing **the script file** (`/usr/local/bin/monitoring.sh`: bytes, chmod, location). Cron is a **separate** schedule (root’s crontab, `sudo crontab -e` / `sudo crontab -l`). `#` there means “do not run this line.” The file `monitoring.sh` is untouched. That is exactly how you “make the script stop running when the server has started up, but without modifying the script itself.”

`systemctl stop cron` does **not** count: after reboot, cron starts again and `@reboot` / `*/10` fire. Do not `chmod -x` or edit the `.sh` file for this test.

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
| <a id="ufw"></a>**UFW** | Uncomplicated Firewall (Debian). Simple allow/deny commands. A **frontend**: it writes [iptables](#iptables) / [nftables](#nftables) rules for you. This project: only **4242/tcp** open. `ufw status verbose` = extra output (active, defaults, logging), not a different firewall. |
| <a id="firewalld"></a>**firewalld** | Rocky’s firewall program. Same idea as UFW, but with **zones** (public, drop, …) and named services instead of only port numbers. |
| <a id="iptables"></a>**iptables** | Older tool to tell the Linux kernel which network packets to **accept** or **drop**. Example idea: “allow TCP port 4242, block everything else incoming.” The syntax is verbose. **UFW calls this for you.** |
| <a id="nftables"></a>**nftables** | Newer replacement for iptables (`nft` command). Same job: kernel packet filter. Many Debian versions use nftables **under** UFW. You still use `ufw`, not `nft`, in this project. |
| **packet / packet filter** | A **packet** is a small chunk of network data. A **packet filter** looks at each chunk (port, protocol, direction) and allows or blocks it. That is what a firewall does. |
| **frontend** | A simpler program on top of a harder one. UFW is a frontend for iptables/nftables: short command in, kernel rule out. |
| **NAT / port forwarding** | VirtualBox default network: the guest (often `10.0.2.15`) is not a real LAN IP. The host connects via **localhost** and a forwarded port. **Guest** port stays **4242**. **Host** port may be **4243** if 4242 is busy on the Mac — that is only translation, not a Debian change. Host IP `127.0.0.1` = this Mac only; empty / `0.0.0.0` = LAN. |
| **SSH key pair** | Private key stays on your PC, public key on the server. Login proves you have the private key; it never travels on the wire. Optional here (password is allowed). |
| **`ucredit=-1`** | PAM credit: a **negative** number means that class is **required** (at least one uppercase). Same idea for `lcredit` / `dcredit`. |
| <a id="ssh-lexicon"></a>**SSH** | **S**ecure **Sh**ell: encrypted remote terminal. Client on your Mac (`ssh user@host -p 4242`), server on Debian (`openssh-server`). Here: port **4242** (not 22), **no root login**. Longer: [SSH](#ssh). |
| **OpenSSH** | The SSH software on Debian. Server process often called `sshd`. Config: `/etc/ssh/sshd_config`. Service name: `ssh`. |
| **sudo** | Run one command as another user (usually root) without logging in as root. Config in `/etc/sudoers` and `/etc/sudoers.d/`. |
| **TTY** | **TTY** = your current login session: the VirtualBox window or SSH. `requiretty` = sudo only from that session. |
| **PAM** | Pluggable Authentication Modules. Hooks used for login/password rules (`pam_pwquality` = password complexity). |
| **password aging** | How long a password may live before it must be changed. Not complexity (length, A-z, digit): that is PAM/`pwquality`. Aging is: max 30 days, min 2 days between changes, warning 7 days before expiry. Set in `/etc/login.defs` (`PASS_MAX_DAYS`, `PASS_MIN_DAYS`, `PASS_WARN_AGE`). |
| **`chage`** | **ch**ange **age**. Show or set a user’s aging. `sudo chage -l casgarna` lists last change, min/max days, expiry, warning. |
| <a id="sda"></a>**`sda` / `sda1` / `sda5`** | Linux disk names under `/dev/`. **`sd`** = SCSI-style disk (VirtualBox). **`a`** = first disk. **`sda1`** = first partition (here `/boot`). **`sda2`** = extended partition (1K frame). **`sda5`** = first *logical* partition inside it (LUKS). `lsblk` omits `/dev/`. |
| **PV / VG / LV** | Physical Volume (real disk or unlocked LUKS), Volume Group (pool), Logical Volume (the slice you format and [mount](#mount), e.g. `/`, `/home`, swap). |
| <a id="mount"></a>**mount / mountpoint** | To **mount** is to attach a filesystem to a folder so you can use the files. The **mountpoint** is that folder (`/` , `/boot`, `/home`). Swap is mounted as `[SWAP]`, not as a directory. `lsblk` shows this in **MOUNTPOINT**. `/etc/fstab` lists what to mount at boot. `lsblk` is the live tree; `fstab` is the config. |
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
