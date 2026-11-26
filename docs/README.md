# SD Transfer Utility

SD Transfer Utility is a Lazarus/Free Pascal desktop client for moving plain-text
files between the computer running the client and an SD server over SSH. Its
two-pane layout follows WinSCP/FileZilla conventions, with the pane order
reversed according to the selected direction:

- **Upload:** local computer on the left, SD `xfer.in` on the right.
- **Download:** SD `xfer.out` on the left, local computer on the right.

The client does not leave an SD transfer slot open between operations. Each
operation starts a fresh SSH session, enters the SD command that opens the
server-side slot, starts a separate SFTP session to move the files, verifies the
result, presses Enter to close the slot, and disconnects.

## Project layout

```text
~/SDCoreProject/TransferUtility/
├── src/                         Lazarus/FPC source
│   ├── sdtransfer.lpr           GUI program
│   ├── sdtransfer.lpi           Lazarus project
│   ├── sd-askpass.lpr           small headless OpenSSH askpass helper
│   ├── uMain.pas                window, panes, drag and drop, worker thread
│   ├── uLocalPane.pas           local file browser
│   ├── uRemotePane.pas          SD directory view
│   ├── uTransferEngine.pas      receive/send + SFTP orchestration
│   ├── uSDSession.pas           PTY-backed SD terminal session
│   ├── uSftpClient.pas          OpenSSH sftp list/put/get adapter
│   ├── uProcessUtil.pas         process, shell quoting, environment helpers
│   ├── uConfig.pas              settings persistence (no password)
│   ├── uModels.pas              shared types and validation
│   └── tests/                   local smoke probes
├── bin/
│   ├── sd-transfer              GUI executable
│   └── sd-askpass               headless OpenSSH password helper
├── docs/
│   ├── README.md                this overview
│   ├── USER_GUIDE.md            daily use
│   ├── BUILDING.md              build instructions
│   ├── SERVER.md                server profile and connection facts
│   ├── settings.example.ini     copyable client settings
│   ├── SD_SERVER_NOTES.md       SD protocol notes
│   ├── TESTING.md               smoke-test results
│   └── HANDOFF.md               developer/session handoff
└── build/                       generated units, link shims and test output
```

## Quick start

```bash
cd ~/SDCoreProject/TransferUtility
LinuxVersion/build.sh
./bin/sd-transfer
```

In the window:

1. Choose the server type (this sets the port), then enter the SD host, your
   SD user and password (or leave it empty to use your ssh keys; see
   **☰ > SSH key setup**). For the documented public server use
   `data.sdcoredb.org` and your own SD account; for a client running on the
   SD server itself use `127.0.0.1`. See [SERVER.md](SERVER.md).
2. Select **Upload** or **Download**.
3. Press **Connect**. The SD list (xfer.in, xfer.out or bp) loads by itself;
   **Refresh** loads it again.
4. Select files and drag them to the other pane (the only way to transfer).
5. Watch the activity log. The client closes the SD slot and both connections
   when the job ends.

The SD transfer commands used by the client are:

```text
receive {overwrite}
send xfer.out <name> ...                 (files already in xfer.out)
send bp <record id> ...                  (programs from bp)
SORT <file> ...                          (listing at the SD prompt; no slot)
COPY FROM xfer.in TO bp "<name>" ... {OVERWRITING} DELETING
                                         (after an upload into bp)
DELETE xfer.out "<name>" ...             (after a download from bp)
CNAME <file> "<old>" TO "<new>"          (right-click Rename in the SD list)
DELETE <file> "<name>" ...               (right-click Delete in the SD list)
```

These commands are documented in the SD source tree at
`sdb_ai/sd64/sdsys/gpl.bp/xfer` and are exercised by
`src/tests/`.

## Server prerequisite

SD allows file transfer only when both the server switch and the account
permission are on:

```text
XFER=1                       in sd.conf
modify.account <user> xfer-on
```

The public server's current `XFER`/`xfer-on` state was not verified because no
remote credentials were provided. The SD installation on this development
computer currently has `XFER=0`, so the client can reach the SD prompt and list
the SD command surface, but a real upload/download is refused by SD with:

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
- util-linux `script` (used to allocate a PTY for the SD terminal session).
- GTK3 runtime libraries. `LinuxVersion/build.sh` creates local unversioned linker shims when
  only versioned runtime libraries are installed.

## Further documentation

- [USER_GUIDE.md](USER_GUIDE.md) — daily use, drag and drop, source records,
  errors and security notes.
- [BUILDING.md](BUILDING.md) — build details, Lazarus/FPC requirements and
  manual commands.
- [SERVER.md](SERVER.md) — identified server endpoint, connection profile,
  host-key fingerprints, installation and deployment notes.
- [SD_SERVER_NOTES.md](SD_SERVER_NOTES.md) — what the server expects and why the
  client uses two SSH connections.
- [TESTING.md](TESTING.md) — smoke-test results and how to rerun them.
- [HANDOFF.md](HANDOFF.md) — developer/session handoff: current state, key
  decisions, server facts, known limitations, and next-session checklist.

## License

BSD 2-Clause License, Copyright (c) 2026 Donald Montaine. See
[LICENSE](../LICENSE).
