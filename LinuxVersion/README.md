# SD Core Transfer Utility — Linux version

The Linux build of SD Core Transfer Utility. The program's source is shared with the
Windows version and lives in `../src/`; this folder holds what is Linux-only.

## Build

Needs Lazarus 5.0 and FPC 3.2.2 with the GTK3 widgetset.

    LinuxVersion/build.sh

It builds `bin/sd-transfer` and `bin/sd-askpass` at the repository root. Set
`LAZARUS_DIR` if Lazarus is not in `/usr/share/lazarus/5.0.0`.

## Linux-only pieces

- `build.sh` — GTK3 link-time library shims, `fpc` for the helper, `lazbuild --ws=gtk3`, `strip`.
- The SD Core command session runs ssh inside `script` (util-linux) to give it a 160x50 terminal.
- Local files are moved to the desktop Trash with `gio trash`.
- Settings: `~/.config/sd-transfer-utility/settings.ini`.
- Smoke tests: `src/tests/run_smoke.sh` (bash, with fake `ssh`/`sftp` scripts).

## Running

Keep `sd-transfer` and `sd-askpass` in the same folder. SD Core servers normally
require an ssh key **and** the account password; ssh asks for the password after
the key is accepted, and `sd-askpass` is what hands it the password typed into
the Password box (and a key passphrase, if the key has one). Without the helper
only a key-only login could work.

See `../docs/` for the user guide and the SD Core server notes.
