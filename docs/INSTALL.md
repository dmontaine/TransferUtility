# Installing and connecting

SD Core Transfer Utility is a **desktop client**. It runs on the computer you work
at and reaches your account on an SD Core server over ssh/sftp. Nothing is installed
on the SD Core server, and no root or administrator rights are needed on the client.

## 1. What the server needs

| Server type (in the program) | ssh port |
|---|---|
| SD Core for Linux | 22 (the machine's sshd) |
| SD Core for Windows | 22 (the machine's sshd) |
| SD Core Solo for Linux | 4251 (Solo's own sshd) |
| SD Core Solo for Windows | 4251; 24251 is tried if 4251 does not answer |

File transfer must be turned on twice by the SD Core administrator:

```text
XFER=1                           in the [sd] section of sd.conf (off in a new installation)
modify.account <account> xfer-on   signed in as the SD Core administrator
```

Until both are on, SD Core refuses `receive` and `send` and the program shows SD Core's
message (for example `File transfer is not turned on for this system (XFER is
0 in sd.conf)`).

The default transfer limits (an administrator may change them):

- plain-text files only (no NUL byte and no SD Core mark byte);
- no folders and no paths; a name may not begin with `.` or `~` and may not
  contain any of `* , = > < % / + : ; ? " \`;
- 10 MB per file, 100 MB per transfer;
- 10 minutes to connect, 2 minutes idle, 60 minutes in all.

A name with a space can be uploaded, but SD Core's `send` cannot name it, so such a
file must be renamed (right-click > Rename...) before it can be downloaded.

## 2. Connection details

| Where the program runs | Host | User |
|---|---|---|
| On another computer | the SD Core server's name or address | your own SD Core account |
| On the SD Core server itself | `127.0.0.1` | your own SD Core account |

SD Core servers normally ask for an ssh key **and** the account password. The
password typed into the program is handed to ssh by `sd-askpass`, which must
sit beside `sd-transfer`. Neither the password nor a key passphrase is ever
saved.

The first time you connect to a server the program shows its host-key
fingerprints and asks whether to trust it. If your administrator gave you the
fingerprints, compare them before answering yes. You can read them yourself
with:

```bash
ssh-keyscan -T 5 -p <port> <host> 2>/dev/null | ssh-keygen -lf -
```

## 3. Installing on Linux

On Debian 13 or Ubuntu 24.04 and later, install the package (it pulls in
what it needs):

```bash
sudo apt install ./transfer-utility.deb
```

and start **SD Core Transfer Utility** from the applications menu, or run
`sd-transfer`. `sudo apt remove transfer-utility` removes it and leaves your
settings and ssh keys alone.

To build it yourself instead, the requirements are:

- x86-64 Linux desktop with the GTK3 runtime libraries;
- the OpenSSH client (`ssh`, `sftp`, `ssh-keygen`, `ssh-keyscan`);
- util-linux `script` (normally installed);
- to build: Lazarus 5.0 with the GTK3 widgetset and FPC 3.2.2.

Build on the machine that will run it (or on one with the same distribution;
a binary built on a newer glibc will not run on an older one):

```bash
LinuxVersion/build.sh
./bin/sd-transfer
```

Copying elsewhere: keep `sd-transfer` and `sd-askpass` in the same folder.
Settings are kept in `~/.config/sd-transfer-utility/settings.ini`
(see [settings.example.ini](settings.example.ini)).

A headless server cannot show the window: run the program on a desktop that
can reach the server over ssh.

## 4. Installing on Windows

See [../WindowsVersion/README.md](../WindowsVersion/README.md).

## 5. Checking a server by hand

```bash
ssh -p <port> <your-sd-user>@<host>
```

then, at the SD Core prompt:

```text
receive
```

`Ready to receive into xfer.in...` means both transfer gates are on (press
Enter to close the slot again). `File transfer is not turned on...` means the
system `XFER` gate is off; `Account ... may not move files...` means the
account's `xfer-on` gate is off.
