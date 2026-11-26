# SD Transfer Utility — Windows version

The Windows build of SD Transfer Utility. The program's source is shared with the
Linux version and lives in `..\src\`; Windows differences are small
`{$IFDEF WINDOWS}` blocks there. This folder holds what is Windows-only.

## Requirements

- Windows 10 1809 or later, 64-bit.
- The Windows **OpenSSH Client** (Settings > System > Optional features). The
  program uses `%SystemRoot%\System32\OpenSSH\ssh.exe`, `sftp.exe`,
  `ssh-keygen.exe` and `ssh-keyscan.exe`, and falls back to PATH only if they
  are missing. Tested with OpenSSH_for_Windows 9.5p2.

## Build

Needs Lazarus 5.0 and FPC 3.2.2 (64-bit), installed in `C:\lazarus` (or set
`LAZARUS_DIR`).

    powershell -ExecutionPolicy Bypass -File WindowsVersion\build.ps1

It builds `bin\sd-transfer.exe` and `bin\sd-askpass.exe` at the repository root
and strips them.

## Running

Keep `sd-transfer.exe` and `sd-askpass.exe` in the same folder. SD servers
normally require an ssh key **and** the account password; ssh asks for the
password after the key is accepted, and `sd-askpass.exe` is what hands it the
password typed into the Password box (and a key passphrase, if the key has
one). Without the helper only a key-only login could work.

## How it differs from Linux

| Linux | Windows |
|---|---|
| ssh runs inside `script` for a 160x50 terminal | `ssh.exe -tt` runs directly with pipes (no console window) |
| `$HOME/.ssh` | `%USERPROFILE%\.ssh` |
| `~/.config/sd-transfer-utility/settings.ini` | `%LOCALAPPDATA%\sd-transfer-utility\settings.ini` |
| Move to Trash (`gio trash`) | Move to Recycle Bin (`SHFileOperation`, undoable) |
| New key's passphrase typed into ssh-keygen through a PTY | ssh-keygen asks `sd-askpass.exe` (`SSH_ASKPASS_REQUIRE=force`); the passphrase never appears on a command line |
| `chmod 600/700` on `.ssh` files | none: files in the user's own `.ssh` inherit its ACL |
| Font `Monospace` | Font `Consolas` |

## Checked on Windows (26 Nov 2026)

- Builds with Lazarus 5.0RC1 / FPC 3.2.2, win32 widgetset; the window opens.
- Windows OpenSSH 9.5p2 takes the password from `sd-askpass.exe` with
  `SSH_ASKPASS_REQUIRE=force` while its standard input is a pipe
  (`read_passphrase: requested to askpass`, then the password is sent).
- Creating a key through `sd-askpass.exe`, with and without a passphrase.
- `ssh -G` known-hosts paths (`C:\Users\...\/.ssh/known_hosts`,
  `__PROGRAMDATA__\ssh/...`) are mapped to real Windows paths.
- Against SD Core for Windows WC2.0-0 (key + password login): Connect reaches
  the SD prompt through `ssh.exe -tt`, creates `xfer.in` and `xfer.out`
  (data-only directory files, VOC `F` / name, as SD's `receive`/`send` make
  them), and lists `xfer.in` and `xfer.out`.
- Upload to `xfer.in` and download from `xfer.out` by drag and drop under the
  win32 widgetset; upload into `bp` (`receive overwrite`, then
  `COPY ... DELETING`) and download from `bp` (`send bp`, then the transit copy
  deleted from `xfer.out`); Move to Recycle Bin. A file with no final line ending comes
  back with CR LF added: SD Core for Windows writes CR LF when a directory
  file has no line-ending mode set (SD's behaviour, not the client's).
- `ssh.exe` runs in a hidden console of 160x30 (asked for 160x50; conhost keeps
  30 rows), wide enough for the 130-column listing. No window appears.

## Not yet checked on Windows

- An account that starts at the SD home screen: it needs at least 140x43, and
  with 30 rows SD starts at the prompt instead.
- The Windows Solo 24251 fallback.
- Smoke tests: `src/tests/run_smoke.sh` is bash with `/bin/sh` fakes; Windows
  fakes still need writing.
- A user profile path containing spaces: the known-hosts list from `ssh -G` is
  split on spaces.
