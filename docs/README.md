# SD Core Transfer Utility

SD Core Transfer Utility is a Lazarus/Free Pascal desktop client for moving plain-text
files between the computer running the client and an SD Core server over SSH. Its
two-pane layout follows WinSCP/FileZilla conventions, with the pane order
reversed according to the selected direction:

- **Upload:** local computer on the left, SD Core `xfer.in` on the right.
- **Download:** SD Core `xfer.out` on the left, local computer on the right.

The client does not leave an SD Core transfer slot open between operations. Each
operation starts a fresh SSH session, enters the SD Core command that opens the
server-side slot, starts a separate SFTP session to move the files, verifies the
result, presses Enter to close the slot, and disconnects.

## Project layout

```text
TransferUtility/
├── src/                         Lazarus/FPC source, shared by both platforms
│   ├── sdtransfer.lpr / .lpi    GUI program and Lazarus project
│   ├── sd-askpass.lpr           small headless OpenSSH askpass helper
│   ├── uMain.pas                window, panes, drag and drop, worker thread
│   ├── uDialogs.pas             host-key, SSH key setup, Help and About windows
│   ├── uLocalPane.pas           local file browser
│   ├── uRemotePane.pas          SD Core file view (xfer.in, xfer.out or bp)
│   ├── uTransferEngine.pas      receive/send + SFTP orchestration
│   ├── uSDSession.pas           SD Core terminal session over ssh -tt
│   ├── uSftpClient.pas          OpenSSH sftp list/put/get adapter
│   ├── uHostKey.pas             host-key check before ssh runs
│   ├── uProcessUtil.pas         process, quoting, environment helpers
│   ├── uConfig.pas              settings persistence (no password)
│   ├── uModels.pas              shared types and validation
│   └── tests/                   smoke probes
├── LinuxVersion/                Linux build script and notes
├── WindowsVersion/              Windows build script and notes
├── docs/
│   ├── README.md                this overview
│   ├── INSTALL.md               installing, server types, connecting
│   ├── USER_GUIDE.md            daily use
│   ├── BUILDING.md              build instructions
│   ├── settings.example.ini     copyable client settings
│   ├── SD_SERVER_NOTES.md       SD Core protocol notes
│   └── TESTING.md               smoke tests
└── bin/                         sd-transfer and sd-askpass (built)
```

## Quick start

```bash
cd ~/SDCoreProject/TransferUtility
LinuxVersion/build.sh
./bin/sd-transfer
```

In the window:

1. Choose the server type (this sets the port), then enter the SD Core host, your
   SD Core user and password (or leave it empty to use your ssh keys; see
   **☰ > SSH key setup**). For the documented public server use
   `data.sdcoredb.org` and your own SD Core account; for a client running on the
   SD Core server itself use `127.0.0.1`. See [INSTALL.md](INSTALL.md).
2. Select **Upload** or **Download**.
3. Press **Connect**. It creates `xfer.in` and `xfer.out` in your account if
   they are missing; the SD Core list (xfer.in, xfer.out or bp) then loads by
   itself, and **Refresh** loads it again.
4. Select files and drag them to the other pane (the only way to transfer).
5. Watch the activity log. The client closes the SD Core slot and both connections
   when the job ends.

The SD Core transfer commands used by the client are:

```text
CREATE.FILE DATA xfer.in DIRECTORY       (on Connect; also xfer.out)
receive {overwrite}
send xfer.out <name> ...                 (files already in xfer.out)
send bp <record id> ...                  (programs from bp)
SORT <file> ...                          (listing at the SD Core prompt; no slot)
COPY FROM xfer.in TO bp "<name>" ... {OVERWRITING} DELETING
                                         (after an upload into bp)
DELETE xfer.out "<name>" ...             (after a download from bp)
CNAME <file> "<old>" TO "<new>"          (right-click Rename in the SD Core list)
DELETE <file> "<name>" ...               (right-click Delete in the SD Core list)
```

These commands are documented in the SD Core source tree at
`sdb_ai/sd64/sdsys/gpl.bp/xfer` and are exercised by
`src/tests/`.

## Server prerequisite

SD Core allows file transfer only when both the server switch and the account
permission are on:

```text
XFER=1                       in sd.conf
modify.account <user> xfer-on
```

When either is off, SD Core refuses the transfer with its own message, for example:

```text
File transfer is not turned on for this system (XFER is 0 in sd.conf)
```

The utility deliberately reports that server response instead of hiding it.
See [SD_SERVER_NOTES.md](SD_SERVER_NOTES.md) for the full server-side sequence
and the exact source evidence.

## Requirements

- Lazarus with the LCL and GTK3 widgetset (the project targets GTK3).
- Free Pascal 3.2 or later.
- OpenSSH `ssh` and `sftp` clients.
- On Linux, util-linux `script` (gives the SD Core terminal session a 160x50 PTY).
- GTK3 runtime libraries. `LinuxVersion/build.sh` creates local unversioned linker shims when
  only versioned runtime libraries are installed.

## Further documentation

- [USER_GUIDE.md](USER_GUIDE.md) — daily use, drag and drop, rename and
  delete, errors and security notes.
- [BUILDING.md](BUILDING.md) — build details, Lazarus/FPC requirements and
  manual commands.
- [INSTALL.md](INSTALL.md) — server types and ports, transfer gates and limits,
  installing and connecting.
- [SD_SERVER_NOTES.md](SD_SERVER_NOTES.md) — what the server expects and why the
  client uses two SSH connections.
- [TESTING.md](TESTING.md) — smoke-test results and how to rerun them.

## License

BSD 2-Clause License, Copyright (c) 2026 Donald Montaine. See
[LICENSE](../LICENSE).
