# SD Server Notes

This document records what the client relies on, based on the current
development tree and the installed SD binary. The relevant source is:

- `sdb_ai/sd64/sdsys/gpl.bp/xfer` — the SD `receive`/`send` commands, gates,
  slot lifecycle and transfer summary.
- `sdb_ai/sd64/gplsrc/sd_sftp.c` and `sd_sftp.h` — the restricted SFTP server
  and the single-directory wall.
- `SDCore4LinuxDocs/User/markdown/29e-sd-tcl-moving-files-in-and-out.md` —
  the user-facing file-transfer description.
- `sdb_ai/sd64/sdsys/gpl.bp/xfersrv` — the per-connection slot lookup.

## 1. Commands and sequence

### Upload

```text
ssh -p <port> <user>@<host>
receive
# or
receive overwrite
```

SD answers with:

```text
Ready to receive into xfer.in.  Connect an sftp client to <host> port <port> as <user> and put the files.  Press Enter here when done.
```

The client then opens a second SSH connection for SFTP, uploads the selected
plain files, closes SFTP, and presses Enter in the first session. SD answers:

```text
Transfer closed (closed here): N file(s), B bytes
```

If an incoming name already exists and `receive overwrite` was not used, SD
refuses that file. The client preflights the remote listing and refuses the job
before uploading when **Overwrite existing** is off.

### Download

```text
ssh -p <port> <user>@<host>
send <source-file> <record-id> {<record-id> ...}
```

SD copies those records into `xfer.out` and answers:

```text
Ready to send from xfer.out.  Connect an sftp client to <host> port <port> as <user> and get the files.  Press Enter here when done.
```

The client opens SFTP, gets the selected files from the one remote directory,
closes SFTP, and presses Enter. The same `Transfer closed` summary is checked.

The record IDs are part of the `send` command; the client cannot ask SD for an
arbitrary directory listing before the slot exists. That is why the Download
tab has explicit **source file** and **Record id(s)** fields.

## 2. Gates checked by SD

From `xfer`:

```text
if config('XFER') # 1 then
   File transfer is not turned on for this system (XFER is 0 in sd.conf)

if downcase(@who) # acct then
   A transfer is opened from your own account ...

if acc.rec<ACC$XFER> # 'YES' then
   Account ... may not move files over its ssh login ...
```

The account must also be a user account (`sdu_...`), and the session must be a
terminal session. The server re-checks the gate at every SFTP connection.

Required server setup:

```text
# sd.conf
XFER=1

# SD administrator
modify.account <user> xfer-on
```

The client does not modify either setting. Those are administrator actions.

## 3. The single directory

The only remote paths exposed to SFTP are:

- `xfer.in` for `receive` (uploads);
- `xfer.out` for `send` (downloads).

The directories are created on first use if necessary. `sd_sftp.c` confines
operations to this one directory, rejects links, and removes the server's own
partial files. Nested directories are not transferable. The client shows `/` as
the remote path because that is the one directory root exposed by the server.

SD accepts plain files only. The upload path rejects NUL bytes and bytes
248–255. File names are subject to SD's name rules (no leading `.` or `~`, and
no `* , = > < % / + : ; ? " \` characters). Spaces in ordinary file names are
supported and are quoted for the SFTP client; source file and record IDs used
in the SD `send` command are single tokens and cannot contain spaces.

## 4. Why the client uses two SSH sessions

The SD login is not a normal shell. It starts SD and exposes its command
language. `receive` and `send` keep that SD session waiting while a separate
SFTP subsystem connection performs the file I/O. The client therefore:

1. opens the SD command session and activates the slot;
2. opens a separate SFTP connection with the same host, port and account;
3. transfers and closes SFTP;
4. sends Enter to the SD command session to close the slot;
5. closes the SD session.

The slot is not kept open between UI clicks. Preview/refresh opens a slot,
lists, closes it, and returns; the actual transfer repeats the activation. This
avoids leaving a live slot when a user pauses or closes the window.

## 5. Terminal handling

SD is an interactive terminal application. The client invokes `script` to
allocate a PTY with a 160x50 window, then runs `ssh -tt`. The SD prompt is
detected after ANSI screen output is normalized. If the account is configured
to start at the SD home screen, the client sends Alt-T to open the terminal
tile before issuing the transfer command. The Enter key is sent as a carriage
return (`#13`), as a real terminal does; sending only a line feed is not enough
for the SD line editor.

## 6. Download directory persistence

`send` copies records into `xfer.out`; it does not clear unrelated files that
are already there. After the slot closes, `xfer.out` remains an ordinary
directory. The client's Download preview shows the current contents, which may
include files from an earlier staging operation. Select only the files you
want. This is also why the client verifies the selected file names against the
actual `xfer.out` listing before downloading.

## 7. Server summary and verification

After the slot closes, SD prints a summary such as:

```text
Transfer closed (closed here): 2 file(s), 43 bytes
```

and may print SHA-256 lines for incoming files. The client:

- checks the remote listing before and after an upload;
- checks local sizes after a download;
- parses the server's `N file(s)` count and rejects a job if the count does not
  match the selected file count.

This is important because a pre-existing file with a matching size must not
make a failed upload look successful.

## 8. Documented public server

The project documentation identifies the public SD endpoint as:

```text
Host:      data.sdcoredb.org
IPv4:      104.237.11.81
Port:      22 (SSH/SFTP)
Example:   deepa@data.sdcoredb.org
Package:   SD Core for Linux L2.0-0
```

The host resolves and port 22 is reachable; the SSH banner reports
OpenSSH on Debian. The actual transfer account, remote SD release and remote
`XFER`/`xfer-on` state were not verified because no remote credentials were
available. The public host-key fingerprints and installation notes are in
[SERVER.md](SERVER.md).

## 9. This installed server

The installed SD server on this machine reports:

```text
File transfer is not turned on for this system (XFER is 0 in sd.conf)
```

as verified by `src/tests/session_probe.lpr`. The login and SD prompt work, but
live upload/download is intentionally blocked until an administrator enables
`XFER=1` and grants the account `xfer-on`.

Once those two gates are enabled, the existing client needs no source change:
it will use the same `receive`/`send` sequence and SFTP flow.
