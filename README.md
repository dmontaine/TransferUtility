# SD Core Transfer Utility

A desktop client that moves plain-text files between your computer and your own
account on an SD Core server over ssh/sftp. It works with all four SD Core editions (SD Core
Core and SD Core Solo, on Linux and on Windows) and uses only standard SD Core
commands. Written in Lazarus / Free Pascal.

## Layout

    src/              the program: one source tree for both platforms
    LinuxVersion/     Linux build script and notes
    WindowsVersion/   Windows build script and notes
    docs/             user guide, building, testing, SD Core server notes
    LICENSE           BSD 2-Clause

Both versions build from the same `src/`. The few platform differences are
small `{$IFDEF WINDOWS}` / `{$IFDEF UNIX}` blocks, so a fix made once reaches
both versions.

## Build

- Linux: `LinuxVersion/build.sh` (see `LinuxVersion/README.md`)
- Windows: `powershell -ExecutionPolicy Bypass -File WindowsVersion\build.ps1`
  (see `WindowsVersion/README.md`)

Both put `sd-transfer` and `sd-askpass` (`.exe` on Windows) in `bin/`. Keep the
two together. SD Core servers normally require an ssh key and then the account
password; `sd-askpass` is what hands ssh the password typed into the program.

See `docs/USER_GUIDE.md` to use it.
