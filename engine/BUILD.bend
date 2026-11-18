# LawEditor's engine: Bend's own pipeline, run on a project after the chat changed it. What the chat
# writes is only text until Bend has read it: here a project meets the compiler, as a step of the system
# and not a promise of the model.
#
#   check  every .bend file at the project's top, with `bend <file> --check-only` (what a file imports is
#          checked with it). A law with no proof yet is a TODO, and fine; an error names its Location.
#   page   a project with an index.html is bundled as Bend bundles a page (`bend index.html -o <folder>`),
#          into LawEditor's own folder in the project (PLACES.page). The pages door serves it (server.bend).
#          A page that imports no .bend file is bundled too, and said to be so: its logic is outside Bend.
#
# engine/TURN.bend writes what each answers as an event (EVENTS.bend: check, page): the windows draw it,
# and the chat reads what went wrong in its next turn.

import Base
import ./SYS.bend as Sys
import ./PLACES.bend as Places

# ---------- What a run answered ----------
# Its first line is its state: ok, warn or error ("" when there was nothing to do). The rest is its text.

def state(+out: String) -> String:
  String.trim(Sys.nth(String.lines(out), 0n))

def text(+out: String) -> String:
  String.trim(String.drop(out, String.length(Sys.nth(String.lines(out), 0n))))

def ran(+out: String) -> Bool:
  Bool.not(String.is_empty(state(out)))

def failed(+out: String) -> Bool:
  String.eq(state(out), "error")

# ---------- The check ----------
# $0 the project's folder. ok: the files checked, then how many claims wait for a proof. error: the file,
# then what Bend said. Bend answers "ALL PROOFS CHECK", or counts the TODOs, or gives an error with its
# Location; anything else (bend isn't installed, it stopped) is an error too.
def check_sh() -> String:
  "cd \"$0\" || exit 0; set -- *.bend; [ -e \"$1\" ] || exit 0; names=; todo=0; for f in \"$@\"; do out=$(bend \"$f\" --check-only 2>&1); case \"$out\" in *Location:*) printf 'error\\n%s\\n%s\\n' \"$f\" \"$out\"; exit 0;; *'ALL PROOFS CHECK'*|*'TODO found'*|*'TODOs found'*) ;; *) printf 'error\\n%s\\n%s\\n' \"$f\" \"$out\"; exit 0;; esac; n=$(printf '%s' \"$out\" | sed -n 's/^Error: \\([0-9][0-9]*\\) TODOs\\{0,1\\} found.*/\\1/p' | head -n 1); todo=$((todo + ${n:-0})); names=\"${names:+$names, }$f\"; done; printf 'ok\\n%s\\n%s\\n' \"$names\" \"$todo\""

def check(+dir: String) -> IO(String):
  Sys.sh(check_sh(), [dir], 120000)

# ---------- The page ----------
# $0 the project's folder, $1 where the bundle goes, inside it. ok: the page's file. warn: the same, with why.
# error: the file, then what Bend said.
def page_sh() -> String:
  "cd \"$0\" || exit 0; [ -f index.html ] || exit 0; rm -rf \"$1\"; if out=$(bend index.html -o \"$1\" 2>&1); then if find . -type f \\( -name '*.html' -o -name '*.js' -o -name '*.mjs' \\) -not -path '*/.*' -not -path '*/node_modules/*' -exec grep -lE \"[.]bend[\\\"']\" {} + 2>/dev/null | grep -q .; then printf 'ok\\nindex.html\\n'; else printf 'warn\\nThe page imports no .bend file: what it does is written outside Bend, and no law checks it.\\n'; fi; else printf 'error\\nindex.html\\n%s\\n' \"$out\"; fi"

def page(+dir: String) -> IO(String):
  Sys.sh(page_sh(), [dir, Places.page_in()], 120000)
