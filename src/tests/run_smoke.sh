#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTBIN="$ROOT/build/testbin"
TESTBIN_CLOSE="$ROOT/build/testbin-close"
TESTEXE="$ROOT/build/tests"
mkdir -p "$TESTBIN" "$TESTBIN_CLOSE" "$TESTEXE"

# The local SD binary is used only for the PTY/prompt/error probe.
cat > "$TESTBIN/ssh" <<'EOF'
#!/bin/sh
cd /home/sd/user_accounts/don
exec /usr/local/sdsys/bin/sd -adon
EOF
chmod +x "$TESTBIN/ssh"

# Controlled SFTP long-listing output for the parser probe.
# The batch arrives on stdin ("sftp -b -"); it is echoed back as real sftp
# does.  "Failure notes.txt" checks that a file name is never read as an error,
# and the link row checks that links are skipped.
cat > "$TESTBIN/sftp" <<'EOF'
#!/bin/sh
# Real sftp turns -b into "-oBatchMode=yes" where it reads it, and ssh keeps
# the first value: a BatchMode=no after -b is ignored and password logins
# fail.  Fail the same way so that ordering can never come back.
seen_b=0
for a in "$@"; do
  case "$a" in
    -b) seen_b=1 ;;
    BatchMode=no) if [ "$seen_b" = 1 ]; then
        echo "don@fake-sd: Permission denied (publickey,password)."; exit 255; fi ;;
  esac
done
while IFS= read -r cmd; do printf 'sftp> %s\n' "$cmd"; done
cat <<'LIST'
Remote working directory: /
-rw-r--r--    1 1000     1000          11 Nov 26 01:00 hello.bas
-rw-r--r--    1 1000     1000          23 Nov 26 01:00 report with spaces.txt
-rw-r--r--    1 1000     1000           5 Nov 26 01:00 Failure notes.txt
lrwxrwxrwx    1 1000     1000           5 Nov 26 01:00 link -> hello.bas
LIST
exit 0
EOF
chmod +x "$TESTBIN/sftp"

# A tiny fake SD terminal that is enough to verify the ready/close protocol.
cat > "$TESTBIN_CLOSE/ssh" <<'EOF'
#!/bin/sh
# The banner holds an SD error phrase: it must not count as an error.
printf 'Welcome. Permission denied means ask the admin.\r\nSD fake\r\n:'
slot=0
while IFS= read -r line; do
  case "$line" in
    # SD's syntax: RECEIVE [OVERWRITE] and SEND file id [id ...].
    "receive "[!o]*) printf 'Command Syntax: receive {overwrite}\r\n:' ;;
    "send xfer.out") printf 'Command Syntax: send <file> <record id> {<record id> ...}\r\n:' ;;
    "send xfer.out "*) slot=1; printf 'Ready to send from xfer.out. Connect an sftp client to fake port 22 as don and get the files.  Press Enter here when done.\r\n:' ;;
    receive*) slot=1; printf 'Ready to receive into xfer.in. Connect an sftp client to fake port 22 as don and put the files.  Press Enter here when done.\r\n:' ;;
    quit) exit 0 ;;
    "") if [ "$slot" -eq 1 ]; then slot=0; printf 'Transfer closed (closed here): 1 file(s), 11 bytes\r\n:'; else printf ':'; fi ;;
    *) printf ':' ;;
  esac
done
EOF
chmod +x "$TESTBIN_CLOSE/ssh"

fpc -O- -Fu"$ROOT/src" -FU"$TESTEXE" -FE"$TESTEXE" \
  "$ROOT/src/tests/session_probe.lpr"
fpc -O- -Fu"$ROOT/src" -FU"$TESTEXE" -FE"$TESTEXE" \
  "$ROOT/src/tests/sftp_probe.lpr"
fpc -O- -Fu"$ROOT/src" -FU"$TESTEXE" -FE"$TESTEXE" \
  "$ROOT/src/tests/close_probe.lpr"

# A throwaway file in the local account's xfer.in for the COPY-into-bp check;
# the probe copies it into bp with DELETING and then deletes it from bp.
ACCOUNT=/home/sd/user_accounts/don
printf 'PRINT "SDTU PROBE"\nEND\n' > "$ACCOUNT/xfer.in/ZZ_SDTU_PROBE"
PATH="$TESTBIN:$PATH" "$TESTEXE/session_probe"
if [ -e "$ACCOUNT/xfer.in/ZZ_SDTU_PROBE" ] || [ -e "$ACCOUNT/bp/ZZ_SDTU_PROBE" ] ||
   [ -e "$ACCOUNT/bp/ZZ SDTU RENAMED" ]; then
  echo "probe record left behind"; exit 1
fi
# With the helper beside the probe, sftp runs with BatchMode=no (the
# password path), which is the one the ordering bug broke.
cp "$ROOT/bin/sd-askpass" "$TESTEXE/"
PATH="$TESTBIN:$PATH" "$TESTEXE/sftp_probe"
PATH="$TESTBIN_CLOSE:$PATH" "$TESTEXE/close_probe"

# Host-key check against this machine: 127.0.0.1 must already be trusted; the
# machine's own name, if not yet trusted, is asked about and refused (the
# probe answers No, so known_hosts is not changed).
if ssh-keygen -F 127.0.0.1 >/dev/null 2>&1 && ! ssh-keygen -F "$(hostname)" >/dev/null 2>&1; then
  fpc -O- -Fu"$ROOT/src" -FU"$TESTEXE" -FE"$TESTEXE" "$ROOT/src/tests/hostkey_probe.lpr" >/dev/null
  "$TESTEXE/hostkey_probe" 127.0.0.1 "$(hostname)" | grep -E '^(known|unknown)-host='
else
  echo "hostkey probe skipped (needs 127.0.0.1 trusted and $(hostname) not)"
fi
