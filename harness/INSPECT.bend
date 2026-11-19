# LawEditor: the person reads the page the chat built, and points at it. Pure; the server and the page ask it.
#
# The project's page opens inside the app, in a frame that is always the same, with three tools on its bar:
#   Comment   click a part of the page and say what should change there: the message goes to the chat with
#             the part it points at.
#   Measures  the space inside each part, around it and between its children, drawn with its number.
#   Inspect   click a part and read its values, each with its name on the scale or "off the scale".
# None of them needs the chat to write anything: they read the page as it is drawn. So they are the same on
# every page, and a page can't leave them out.
#
# The page is served from another address than the app's (the pages door, server.bend), so the app can't
# read it. A small script, the probe (engine/probe.js), is added to the page only when the app asks for it
# (the address ends in ?inspect): it reads the boxes of the page and sends them to the frame around it, and
# the app draws them (Bend-UI's inspect). The probe only reads and tells: it changes nothing in the page.
#
# Ideas from: the comment mode of Claude's artifacts (a tool on the page's bar, a comment tied to a part),
# the box model overlay of Chrome DevTools, the measures of Figma's Dev Mode.

import Base
import ../flows/FLOW.bend as F

# ---------- The tools ----------
# The order they have on the bar.

type PageTool is Data:
  PageTool.Comment{}
  PageTool.Measures{}
  PageTool.Inspect{}

def tools() -> List<&2, PageTool>:
  [PageTool.Comment{}, PageTool.Measures{}, PageTool.Inspect{}]

def name(t: PageTool) -> String:
  match t:
    case PageTool.Comment{}:
      "Comment"
    case PageTool.Measures{}:
      "Measures"
    case PageTool.Inspect{}:
      "Inspect"

# What a tool is called between the page and the probe.
def word(t: PageTool) -> String:
  match t:
    case PageTool.Comment{}:
      "comment"
    case PageTool.Measures{}:
      "measures"
    case PageTool.Inspect{}:
      "inspect"

# A tool that takes the pointer: while it is on, a click on the page picks a part and does nothing else.
# Only one of them is on at a time; Measures only draws, so it goes with either.
def takes_pointer(t: PageTool) -> Bool:
  match t:
    case PageTool.Comment{}:
      True{}
    case PageTool.Measures{}:
      False{}
    case PageTool.Inspect{}:
      True{}

# Does a tool need the page to say anything about itself? None does: that is what makes them the same on
# every page.
def needs_page(t: PageTool) -> Bool:
  False{}

# ---------- The probe ----------

# What the app adds to the page's address to ask for the probe.
def query() -> String: "inspect"

def asks(+q: String) -> Bool:
  String.eq(q, query())

# The probe's own address at the pages door. No project is named like it (a project's name has no "~").
def probe_name() -> String: "~probe.js"

# Where the probe is, inside LawEditor's own folder.
def probe_file() -> String: "/engine/probe.js"

# The page with the probe: its script goes after everything the page has, so the page is whole when it runs.
def with_probe(html: String) -> String:
  html ++ "\n<script src=\"/" ++ probe_name() ++ "\"></script>\n"

# Only a page gets the probe (never a script, a style or an image of it).
def probed(ask: Bool, +file: String) -> Bool:
  ask && String.ends_with(file, ".html")

# ---------- A comment ----------
# What the chat reads before the person's words: the part the comment points at, by its name (its tag and
# first class) and the words it shows, cut short. The person writes the rest.

def words_max() -> Nat: 60n

def short.at(long: Bool, +text: String) -> String:
  match long:
    case True{}:
      String.take(text, words_max()) ++ "…"
    case False{}:
      text

def short(+text: String) -> String:
  short.at(Nat.is_gt(String.length(String.trim(text)), words_max()), String.trim(text))

def said.at(empty: Bool, +part: String, +text: String) -> String:
  match empty:
    case True{}:
      "On the page, at " ++ part ++ ": "
    case False{}:
      "On the page, at " ++ part ++ " (\"" ++ text ++ "\"): "

def points_at(+part: String, +text: String) -> String:
  said.at(String.is_empty(short(text)), part, short(text))

# ---------- The flow (FLOW.bend), drawn as the diagram ----------

def flow() -> List<&2, F.Step>:
  [
    F.Step{"The chat builds; Bend checks and bundles the page", F.System{}, False{}, [F.Go{1n, ""}]},
    F.Step{"You open the page: it shows in the frame, beside the chat", F.Person{}, False{}, [F.Go{2n, ""}]},
    F.Step{"The page is served with the probe, which reads its boxes", F.System{}, False{}, [F.Go{3n, "Measures"}, F.Go{4n, "Inspect"}, F.Go{5n, "Comment"}]},
    F.Step{"Every padding, margin and gap is drawn with its number", F.System{}, False{}, []},
    F.Step{"You click a part: its values show, each with its name on the scale", F.System{}, False{}, []},
    F.Step{"You click a part: a pin marks it, and your message starts with what it points at", F.System{}, False{}, [F.Go{6n, ""}]},
    F.Step{"You write what should change and send it", F.Person{}, False{}, [F.Go{7n, ""}]},
    F.Step{"The chat reads which part you mean and answers", F.Skill{}, False{}, []}
  ]
