# LawEditor's engine: a terminal in a project. A real shell (the person's own: $SHELL), running in the
# project's folder on a pseudo-terminal, as in any terminal window. It is the person's: the chat neither
# sees it nor types in it, and no mode holds it back.
#
# Bend runs a program and waits for it to end; it can't hold a shell open and talk to it. So a small helper
# holds the pseudo-terminal (python3's pty, a few lines below), and the engine only moves text: what the
# person types goes into a named pipe the shell reads (term.in), and what the shell prints is added to a
# file (term.out) that a window reads from where it stopped. One terminal per project; it lives until the
# shell exits, the person stops it, or the server starts again.

import Base
import ./SYS.bend as Sys
import ./PLACES.bend as Places

# The helper: python3 opens the pseudo-terminal, starts the shell in it, and writes all it prints to the
# file named by its argument. TERM is dumb: the page draws lines and colors, not a full screen (no vim).
def helper() -> String:
  "import os, pty, sys\nlog = open(sys.argv[1], 'ab', buffering=0)\ndef read(fd):\n    data = os.read(fd, 65536)\n    log.write(data)\n    return data\npty.spawn([os.environ.get('SHELL', '/bin/sh'), '-i'], read)\n"

# $0 the project's folder, $1 the helper. The pipe is opened for reading and writing by this script itself,
# so it never closes while the shell lives; its process id is kept, so stop can end it.
def start_sh() -> String:
  "cd \"$0\" || exit 1; d=.laweditor; [ -f $d/term.pid ] && kill -0 \"$(cat $d/term.pid)\" 2>/dev/null && exit 0; command -v python3 >/dev/null 2>&1 || exit 0; rm -f $d/term.in; mkfifo $d/term.in || exit 1; : > $d/term.out; exec 3<>$d/term.in; echo $$ > $d/term.pid; TERM=dumb python3 -c \"$1\" $d/term.out <&3 >/dev/null 2>&1; rm -f $d/term.pid $d/term.in"

def started(+up: String) -> String:
  Sys.pick(String.eq(String.trim(up), "up"), "ok", "nopython")

# POST /api/p/<key>/term/start: the project's terminal, started if it isn't running. Answers "ok", or
# "nopython" where the helper can't run.
def start(+dir: String) -> IO(String):
  do IO<String>:
    IO.spawn(U32 & String, Sys.run("sh", ["-c", start_sh(), dir, helper()], 4294967295))
    IO.sleep(300)
    up : String <- Sys.sh("[ -f \"$0/.laweditor/term.pid\" ] && kill -0 \"$(cat \"$0/.laweditor/term.pid\")\" 2>/dev/null && printf up", [dir], 5000)
    return started(up)

# POST /api/p/<key>/term/in, body: what the person typed, as a terminal would send it. Nothing is written
# when no shell is there to read it.
def keys(+dir: String, keys: String) -> IO(String):
  Sys.sh("d=\"$0/.laweditor\"; [ -p \"$d/term.in\" ] && [ -f \"$d/term.pid\" ] && kill -0 \"$(cat \"$d/term.pid\")\" 2>/dev/null && printf '%s' \"$1\" > \"$d/term.in\"; printf ok", [dir, keys], 5000)

# GET /api/p/<key>/term/out/<n>: what the shell printed after its first n bytes. The first line says how
# many bytes it has printed in all, a tab, and "up" while the shell lives; the rest is the text.
def out(+dir: String, from: String) -> IO(String):
  Sys.sh("d=\"$0/.laweditor\"; f=\"$d/term.out\"; s=0; [ -f \"$f\" ] && s=$(wc -c < \"$f\" | tr -d ' '); n=$1; [ \"$n\" -gt \"$s\" ] 2>/dev/null && n=0; u=down; [ -f \"$d/term.pid\" ] && kill -0 \"$(cat \"$d/term.pid\")\" 2>/dev/null && u=up; printf '%s\\t%s\\n' \"$s\" \"$u\"; [ \"$s\" -gt \"$n\" ] && tail -c +$((n+1)) \"$f\" | head -c $((s-n)); true", [dir, Places.safe(from)], 5000)

# POST /api/p/<key>/term/stop: the shell ends.
def stop(+dir: String) -> IO(String):
  Sys.sh("d=\"$0/.laweditor\"; p=$(cat \"$d/term.pid\" 2>/dev/null); [ -n \"$p\" ] && { pkill -P \"$p\" 2>/dev/null; kill \"$p\" 2>/dev/null; }; rm -f \"$d/term.pid\" \"$d/term.in\"; printf ok", [dir], 5000)
