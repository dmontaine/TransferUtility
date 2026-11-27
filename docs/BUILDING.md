# Building SD Core Transfer Utility

This page covers the Linux build. For Windows, see `WindowsVersion/README.md`
(`powershell -ExecutionPolicy Bypass -File WindowsVersion\build.ps1`).

## 1. Requirements

- Lazarus IDE with LCL and the GTK3 widgetset.
  This project was built with Lazarus 5.0.0 and FPC 3.2.2.
- Free Pascal compiler (`fpc`, `lazbuild`).
- OpenSSH client (`ssh`, `sftp`).
- util-linux `script` command.
- GTK3 runtime libraries and headers/libraries needed by Lazarus.

The project uses only standard Lazarus LCL controls and FPC units:
`Forms`, `Controls`, `StdCtrls`, `ComCtrls`, `ExtCtrls`, `Buttons`,
`Process`, `IniFiles`, `RegExpr`, `BaseUnix`, `DateUtils`.

## 2. Normal build

```bash
cd ~/SDCoreProject/TransferUtility
LinuxVersion/build.sh
```

The script:

1. Creates `build/lib` and creates unversioned GTK linker names when only
   versioned runtime libraries are installed by the distribution.
2. Builds the small headless `sd-askpass` helper into `bin/`.
3. Builds the Lazarus project with `lazbuild --ws=gtk3` into
   `bin/sd-transfer`.

The two runtime files are:

```text
bin/sd-transfer     GUI executable
bin/sd-askpass      headless OpenSSH askpass helper
```

Keep `sd-askpass` in the same directory as `sd-transfer`. The application looks
for the helper beside its own executable. If it is missing, a password login is
refused with a message saying so, and key-only logins run ssh in batch mode so
they fail at once instead of waiting on a prompt. `LinuxVersion/build.sh` strips both
binaries after building.

## 3. Lazarus project

Open:

```text
src/sdtransfer.lpi
```

The GUI is constructed in code in `uMain.pas`; there is intentionally no `.lfm`
form resource. The project targets GTK3 and writes its executable to
`../bin/sd-transfer`.

A manual build with an explicit Lazarus directory:

```bash
cd ~/SDCoreProject/TransferUtility
lazbuild --lazarusdir=/usr/share/lazarus/5.0.0 --ws=gtk3 src/sdtransfer.lpi
```

or:

```bash
LAZARUS_DIR=/path/to/lazarus LinuxVersion/build.sh
```

The `build/lib` directory is a local linker-shim directory. It is created by
`LinuxVersion/build.sh` from `ldconfig` entries such as `libgtk-3.so.0 -> libgtk-3.so`. This
avoids altering system packages when the GTK3 runtime is installed but the
development symlinks are absent. If the target system has `libgtk-3-dev`
installed, the normal system linker paths work as well.

## 4. Build the askpass helper separately

```bash
cd ~/SDCoreProject/TransferUtility
mkdir -p build/askpass
fpc -O2 -FUbuild/askpass -FEbin -obin/sd-askpass src/sd-askpass.lpr
```

`sd-askpass` reads `SDTU_SSH_PASSWORD` from its environment and writes the
password to standard output. It does not link LCL, so OpenSSH can call it from a
non-graphical child process. No password is written to a file or passed on a
command line.

## 5. Smoke tests

The test programs use a fake `ssh` command that invokes the installed SD Core binary
locally, and a fake `sftp` command that returns a controlled long listing. They
do not need the GUI or a live password.

```bash
cd ~/SDCoreProject/TransferUtility
./src/tests/run_smoke.sh
```

The test output should show:

- the SD Core prompt is reached;
- `send` with a deliberately nonexistent source is refused with an SD Core error
  (on this server, `File transfer is not turned on ...`);
- the SFTP long-listing parser returns the expected entries, including a file
  name containing spaces;
- a fake SD Core terminal accepts `receive`, closes on Enter, and the client parses
  `Transfer closed (...): 1 file(s), 11 bytes`.

A live upload/download test additionally requires the SD Core server's `XFER` switch
and the account's `xfer-on` flag. See [SD_SERVER_NOTES.md](SD_SERVER_NOTES.md).

## 6. Running from a desktop

```bash
cd ~/SDCoreProject/TransferUtility
./bin/sd-transfer
```

The app requires a graphical session (X11 or a GTK Broadway/Wayland-capable
display). The command session itself is terminal-only and is opened by the app.

## 7. Deploying to another machine or server

TransferUtility is a desktop client. It is not an SD Core server daemon and does not
go into `/usr/local/sdsys`. If the target is a headless server, run the GUI on a
desktop instead; a GTK3 application needs a display.

Build on the target machine, or on a distribution with a compatible glibc.
The current binary was built on Ubuntu 26.10 and should not be assumed to run
on Debian 13 or an older release.

```bash
# On a compatible Linux desktop/server with a GUI:
cd ~/SDCoreProject/TransferUtility
LinuxVersion/build.sh
./bin/sd-transfer
```

Keep `bin/sd-transfer` and `bin/sd-askpass` together. The destination can be a
normal user directory; no root install is needed. The connection profiles and
remote endpoint are documented in [INSTALL.md](INSTALL.md).

## 8. Cleaning

```bash
rm -rf build/units build/tests build/testbin build/testbin-close build/askpass
```

`LinuxVersion/build.sh` recreates what it needs. Do not remove `bin/sd-transfer` or
`bin/sd-askpass` unless you intend to rebuild.
