# Testing Notes

## Build verification

A clean build was performed with:

```bash
cd ~/SDCoreProject/TransferUtility
rm -rf build/units/x86_64-linux
LinuxVersion/build.sh
```

Result:

```text
Free Pascal Compiler version 3.2.2
Linking bin/sd-askpass
Compiling sdtransfer.lpr
Compiling uMain.pas ... uSftpClient.pas
Linking bin/sd-transfer
```

The project compiles and links successfully. Remaining compiler messages are
hints and two pointer/initialization warnings from ordinary FPC code patterns;
they do not affect the executable.

## Headless askpass check

```bash
SDTU_SSH_PASSWORD='test-secret' ./bin/sd-askpass
```

prints `test-secret` and exits 0 without opening a display. With the variable
unset the helper exits 1. This is the helper OpenSSH invokes for password and
key-passphrase prompts.

## SD command-session smoke test

`src/tests/run_smoke.sh` creates a fake `ssh` that runs the local SD binary
against the `don` account, then runs `src/tests/session_probe.lpr`.

Observed on this machine:

```text
start=TRUE error=
missing-source-send=FALSE error=File transfer is not turned on for this system (XFER is 0 in sd.conf)
```

This verifies:

- the PTY/`script` wrapper starts the SD terminal UI;
- the client recognizes the SD prompt;
- a carriage return, not a bare line feed, activates an SD command;
- the client reads the SD refusal text and exits instead of hanging.

## SFTP parser smoke test

`src/tests/sftp_probe.lpr` runs a fake `sftp` that returns a long listing:

```text
-rw-r--r--    1 1000     1000          11 Nov 26 01:00 hello.bas
-rw-r--r--    1 1000     1000          23 Nov 26 01:00 report with spaces.txt
```

Observed:

```text
entries=2
name0=hello.bas size0=11
name1=report with spaces.txt size1=23
```

This verifies that the parser handles the long-name format used by SD's SFTP
server, including file names containing spaces, and does not confuse the
`pwd`/prompt text with directory entries.

## Ready/close protocol smoke test

`src/tests/close_probe.lpr` runs against a tiny fake SD terminal. It verifies
that `receive` is accepted as ready and that pressing Enter produces and parses:

```text
close=TRUE summary=Transfer closed (closed here): 1 file(s), 11 bytes
```

This covers the `CloseTransfer` path that the live server would use after the
SFTP work.

## GUI launch check

The GTK3 executable was started on the active X11 display with the existing
window manager. The process remained running, produced no stderr output, and
created a window named `SD Transfer Utility` with client dimensions
1220 x 780. The two-pane layout and direction controls are constructed at
runtime by `uMain.pas`; the window and process remained healthy.

A headless GTK launch is not used for the normal application because the LCL
GUI needs a graphical display. The `sd-askpass` helper is deliberately a
separate, non-LCL FPC program so password prompts work without a display.

## What is not tested live

A real upload/download against the installed server was not performed because
the installed SD server has `XFER=0` and the account cannot open a transfer
slot. The client correctly reports the server's refusal. The complete
`TTransferEngine` upload and download paths were separately exercised against a
local fake SSH/SFTP slot harness; both verified remote/local sizes and the
server's one-file summary. Once an administrator enables:

```text
XFER=1
modify.account <user> xfer-on
```

the live acceptance sequence is:

1. Upload a small plain-text file; confirm the SD `Transfer closed` summary
   reports one incoming file and the file appears in `xfer.in`.
2. Download that staged record with `send`; confirm the local size matches and
   the server summary reports one outgoing file.
3. Repeat with overwrite on and off.
4. Try a file that already exists without overwrite; confirm the UI refuses or
   the server refuses without reporting success.
5. Try a name with a space, a forbidden character, a directory, and a binary
   file; confirm each is rejected with a useful message.

## Rerun

```bash
cd ~/SDCoreProject/TransferUtility
LinuxVersion/build.sh
./src/tests/run_smoke.sh
```

The smoke tests write only under `build/testbin`, `build/testbin-close` and
`build/tests`, and use a fake `PATH`; they do not alter the installed SD
configuration.
