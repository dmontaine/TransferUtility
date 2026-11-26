# SD Transfer Utility — User Guide

## 1. What the window shows

The window has three working areas:

- **SSH connection** at the top: server type (which decides the port), host,
  user, password and **Connect**. The **☰** button at the top right opens
  **Help**, **SSH key setup...** and **About**. The program is used entirely
  with the mouse; there are no keyboard shortcuts.
- **Direction bar:** **Upload** or **Download** and **Overwrite existing**.
  Files are moved only by dragging them from one pane to the other.
- **Two file panes** with an activity log below them.

The pane order is intentional:

| Direction | Left pane | Right pane |
|---|---|---|
| Upload | Local computer | SD `xfer.in` or `bp` |
| Download | SD `xfer.out` or `bp` | Local computer |

The two buttons above the SD list choose whether it shows the transfer folder
or your `bp` file (see section 7a).

Changing direction re-parents the same two browsers; local selection and
history are retained.

## 2. Connect

1. Choose the **Server** type, the edition of SD the server runs. There is no
   port to enter; the server type decides it:

   | Server | Port |
   |---|---|
   | SD Core for Linux | 22 (the machine's sshd) |
   | SD Core for Windows | 22 (the machine's sshd) |
   | SD Core Solo for Linux | 4251 (Solo's own sshd) |
   | SD Core Solo for Windows | 4251; 24251 is used automatically if 4251 does not answer (Windows reserved it) |
2. Enter the SD server address. `127.0.0.1` is correct when the client runs on
   the SD server itself; for the documented public server enter
   `data.sdcoredb.org`. See [SERVER.md](SERVER.md).
3. Enter your own SD user name, and your password, or leave the password empty
   if you sign in with an ssh key.
4. Click **Connect**. It is available once a
   server type, host and user are filled in; the password may stay empty if
   you sign in with a key. Connect checks the login (asking about the host
   key the first time) and then makes the rest of the window available; until
   then the direction buttons and both panes are grayed.
   While connected the connection details are locked; **Disconnect** unlocks
   them and clears the SD lists. Each listing and transfer still signs in for
   its own short SD session, as SD transfers require.

**New servers.** The first time the computer reaches a server, the client
reads its host key and shows the fingerprint in a dialog, asking whether to
trust it (the same question `ssh` asks). On **Yes** the key is added to
`~/.ssh/known_hosts`; on **No** nothing is saved and nothing connects. If a
saved key later changes, the connection is refused and the message explains
how to remove the old key (`ssh-keygen -R ...`) if the change is expected.

**SSH keys.** Keys you already use (`~/.ssh/id_ed25519` and so on, or
`ssh-agent`) work with nothing to set. **☰ > SSH key setup...** lets you:

- choose a particular private key (shown in the connection box's title);
- give the key's passphrase (memory only, never saved);
- create a new Ed25519 key, with or without a passphrase; an existing key is
  never overwritten;
- copy your public key to give to the SD administrator, who adds it to your
  account's `~/.ssh/authorized_keys` (the SD login cannot install it itself).

The password and key passphrase are kept in memory only. They reach OpenSSH
through the small `sd-askpass` helper using environment variables, not as
command-line arguments, and are **not** written to the settings file.

For a copyable settings file, see [settings.example.ini](settings.example.ini).
The application reads `~/.config/sd-transfer-utility/settings.ini`; the host
and user are saved there, but the password is not.

## 3. Upload

Upload moves files from the local computer on the left into the SD server's
single upload directory, `xfer.in`, on the right.

1. Select **Upload**.
2. Browse the local pane: double-click a folder, use **Up**, or use
   **Browse...**.
3. The SD list loads by itself after Connect. Each list has its own
   **Refresh** button beside it: the one above the SD list lists SD again;
   the one beside the local path re-reads the local folder. After a
   download the local folder is re-read automatically.
4. Select one or more plain files.
5. Drag the selected files onto the SD pane.
6. The activity log shows:
   - SSH login and SD prompt;
   - the `receive` command (or `receive overwrite`);
   - the SFTP upload;
   - the remote size verification;
   - the server's `Transfer closed (...)` summary.

If **Overwrite existing** is off, the client preflights the remote listing and
refuses to start when one of the selected names already exists. If it is on,
the server receives with `receive overwrite`.

Directories cannot be uploaded. SD accepts plain files only; the client checks
for NUL bytes and bytes 248–255 before uploading.

## 4. Download

Download moves files from SD on the left to the local computer on the right.
Files are picked in the SD list; nothing is typed.

1. Select **Download**. The panes reverse: SD on the left, local on the right.
2. Choose the SD view above the list:
   - **xfer.out** lists the files already waiting in `xfer.out` (put there by
     an earlier `send`, or by an SD program);
   - **bp** lists the records of your `bp` file (see section 7a).
   Each list loads by itself the first time it is shown after Connect;
   **Refresh** loads it again. Listing is done at the SD prompt and does
   not open a transfer.
3. Choose the local destination folder in the right pane.
4. Select the SD files and drag them onto the local pane.
5. The client opens the outgoing slot (`send xfer.out <names>`, or
   `send bp <ids>` in the bp view), fetches the selected files through SFTP,
   verifies local sizes, closes the slot and lists `xfer.out` again. Files
   whose names contain a space cannot be named in `send`; rename them in SD.

## 5. Drag and drop

Drag and drop follows the current direction:

- **Upload mode:** drag local files from the left pane onto the SD pane on the
  right.
- **Download mode:** drag SD files from the left pane onto the local pane on the
  right.

Dropping in the opposite direction is rejected; switch direction first.
Dragging is the only way to start a transfer; there is no transfer button.

## 5a. Rename and delete

Right-click a file in either list for **Rename...** and **Delete...**; the
menu is the only way to do either. Right-clicking a row that is not selected
selects just that row. Rename works on one item; delete on any number.

- **SD list:** acts on the file the pane shows (`xfer.in`, `xfer.out` or
  `bp`) with SD's own commands at the prompt, `CNAME <file> "old" TO "new"`
  and `DELETE <file> "name" ...`. New names are checked against SD's name
  rules first. Deleting on SD is permanent, so the client always asks,
  listing the files. Changing `bp` needs the same permission as editing it in
  SD; if SD refuses, its message is shown. Rename is also how to download a
  file whose name contains a space, which `send` cannot name.
- **Local list:** renames files or folders. **Delete** (shown as **Move to
  Trash...**) moves them to the desktop Trash with `gio trash`, after asking;
  they can be restored from there. Trash is not available on some system
  folders such as `/tmp`; the message then says so.

## 6. Overwrite behavior

| Operation | Overwrite off | Overwrite on |
|---|---|---|
| Upload | `receive`; preflight refuses a name that already exists | `receive overwrite`; server may replace the name |
| Download | refuse to replace an existing local file | allow SFTP to replace the local file |

The server summary count is checked after every transfer. If SD reports fewer
files than expected, the job is treated as failed even when a file with the
right size happens to be present from an earlier run.

## 7. Activity log and status

The log records connection steps, SD commands, SFTP errors, verification,
server summaries, and the final result. The status line below the panes shows
the last result. Buttons are disabled while a background job runs.

There are no keyboard shortcuts; everything is done with the mouse.

## 8. Errors you may see

- `File transfer is not turned on for this system (XFER is 0 in sd.conf)` —
  enable `XFER` in `sd.conf` (administrator action).
- `Account ... may not move files over its ssh login` — the account needs
  `modify.account <user> xfer-on`.
- `Cannot open ...` or `has no record ...` — a bp record named in `send bp`
  could not be read.
- `Nothing was copied, so no transfer was opened` — none of the requested
  records was eligible for transfer.
- `Permission denied`, `Host key verification failed`, `Connection timed out`,
  or `No such file` — SSH/SFTP/network or local destination problems. The log
  preserves the client's response text.
- A size or file-count mismatch — the client reports the job as failed; inspect
  the log and the SD `Transfer closed` line.

## 7a. Working with bp

For programmers who edit in another editor: the **bp** button above the SD
list switches the SD side to your `bp` file. `xfer.in` and `xfer.out` are then
only transit folders.

- **Upload into bp:** select local files and drag them onto the bp list. The
  files go into `xfer.in` with `receive`; then, in the same SD session, the
  client runs `COPY FROM xfer.in TO bp "<name>" ... DELETING` for exactly
  those files. Only they reach `bp` and only they leave `xfer.in`; anything
  else in `xfer.in` is left alone. With **Overwrite** off, a name bp already
  has is refused before anything is sent (and `COPY` would refuse it too:
  "already exists - not copied"); with it on, `OVERWRITING` is added. Copying
  into a program file needs the same permission as editing it in SD; if SD
  refuses, the file stays in `xfer.in` and the message says so.
- **Download from bp:** select programs and drag them to the local pane. The client sends `send bp <ids>`, fetches the
  files from `xfer.out`, then deletes those transit copies from `xfer.out`.
  A record whose name contains a space cannot be named in `send` and is
  refused.
- Listing bp uses an SD `SORT` at the prompt and needs no transfer slot.
- These are the standard `receive`, `send`, `COPY`, `DELETE` and `SORT`
  commands, the same in all four SD editions.

## 9. Security and settings

- Settings are stored in
  `${XDG_CONFIG_HOME:-$HOME/.config}/sd-transfer-utility/settings.ini`.
- Server type, host, user, key path, direction, the xfer/bp view, local
  folder and overwrite choice are saved.
- The password and key passphrase are not saved.
- ssh and sftp always run with `StrictHostKeyChecking=yes`; unknown host keys
  are confirmed in the client's own dialog first (see section 2).
- The GUI never constructs a shell command from an unchecked host, user, source
  file or record ID. Host/user/key/path values are shell-quoted; SD commands are
  built as validated tokens.

## 10. Development server

The SD server on the development machine has `XFER=1` and the account has
`xfer-on`. The smoke tests list its `bp` and `xfer.out`, and copy a throwaway
record into `bp` and delete it again. See
[SD_SERVER_NOTES.md](SD_SERVER_NOTES.md).
