# Testing

## Running the smoke tests (Linux)

```bash
LinuxVersion/build.sh
src/tests/run_smoke.sh
```

The script builds five probes and runs them with fake `ssh` and `sftp`
programs first in `PATH`. It needs a local SD Core for Linux installation with
an SD Core account of the same name as the Linux user (or set `SDTU_TEST_ACCOUNT`
to the account's directory). It writes under `build/` only, apart from a
throwaway record `ZZ_SDTU_PROBE` that it puts in the account and removes again
(the script fails if any copy is left behind). It changes no SD Core or ssh
configuration.

| Probe | Against | Checks |
|---|---|---|
| `conpty_probe` | nothing (offline) | SD Core for Windows' ConPTY output: cursor moves read as line breaks and spaces, one-byte reads, plain CR LF unchanged, a glued prompt rejected; the echo rules (`IsEchoOf`: plain, squeezed, a piece of the command, SD Core's answers not taken as echo) |
| `session_probe` | the local SD Core, run directly by a fake `ssh` | prompt reached; `CREATE.FILE` leaves existing `xfer.in`/`xfer.out` alone; a refused `send`; bp and xfer.out listing; `COPY ... DELETING` into bp (twice: the second finds nothing); `CNAME` (and of a missing record); `DELETE`; listing a missing file |
| `sftp_probe` | a fake `sftp` | listing parser (names with spaces, a file called `Failure notes.txt`, a link row); `-o` options before `-b -` (the fake refuses the wrong order, as real sftp does) |
| `close_probe` | a fake SD Core terminal | `receive` accepted as ready, the close summary parsed, `send xfer.out <names>` |
| `hostkey_probe` | this machine's sshd | a known host passes without a question; an unknown host is asked about and refused (the probe answers No, so `known_hosts` is not changed). Skipped unless `127.0.0.1` is trusted and the machine's own name is not |

Expected output ends with `ALL PASS` from `conpty_probe`, the probe lines
(`start=TRUE`, `ensure-xfer-files=TRUE`, `copy-to-bp=TRUE copied=1`, ...) and
exit code 0.

## What the smoke tests cannot cover

SD Core counts a transfer's files through its own sftp server, so a fake `sftp`
always gets `0 file(s)` in the close summary. Real uploads and downloads (and
so the bp flows, which ride on them) need a real ssh login and are checked by
hand in the GUI:

1. Connect; `xfer.in`/`xfer.out` are created if missing.
2. Upload a small text file to `xfer.in`, then again without Overwrite
   (refused) and with it.
3. Switch the SD Core pane to bp; upload a file (it must reach bp and leave
   `xfer.in` empty); upload it again without Overwrite (refused).
4. Download from bp (the transit copy must leave `xfer.out`).
5. Rename and Delete in the SD Core pane; Rename and Move to Trash locally.
6. A file whose name has a space: upload works, download is refused with a
   request to rename; after a rename it downloads.

On Windows the same probes are portable Pascal but the fakes are `/bin/sh`
scripts; `conpty_probe` runs on its own (`fpc -Fusrc src/tests/conpty_probe.lpr`).
