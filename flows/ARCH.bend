# LawEditor: the harness as it is today, as a FLOW.bend flow (who acts where). Every window (the page, the
# terminal) goes through the same engine.
# The words that name a setting (modes, flags, tools, what the chat may never touch) are read
# from POLICY.bend, so they change when the code changes. DIAGRAMS.bend draws it.

import Base
import ./FLOW.bend as F
import ../harness/POLICY.bend as P

def modes() -> String:
  String.join([P.mode_name(0), P.mode_name(1), P.mode_name(2)], " / ")

def codex_asks.at(asks: Bool) -> String:
  match asks:
    case True{}:
      "asks before changes"
    case False{}:
      "cannot ask"

def codex_asks() -> String:
  codex_asks.at(P.can_ask(True{}))

def flow() -> List<&2, F.Step>:
  [
    F.Step{"You use the page or the terminal", F.Person{}, False{}, [F.Go{1n, ""}]},
    F.Step{"server.bend: the door. engine/TURN.bend conducts the turn", F.System{}, False{}, [F.Go{2n, "chat"}, F.Go{15n, "Debug"}]},
    F.Step{"POLICY.bend: " ++ modes(), F.System{}, False{}, [F.Go{3n, "Claude"}, F.Go{14n, "Codex"}]},
    F.Step{"Chat: claude, CHAT.md + HEAR.md", F.Skill{}, False{}, [F.Go{4n, "wants to act"}, F.Go{7n, "MODE: line"}, F.Go{9n, "LAW: lines"}]},
    F.Step{"GATE.bend decides (its own diagram)", F.System{}, False{}, [F.Go{6n, "allowed"}, F.Go{5n, "ask you"}]},
    F.Step{"Allow / Allow for this session / Don't allow", F.Person{}, False{}, [F.Go{6n, "Allow"}]},
    F.Step{"Chat writes in the project's folder, never " ++ String.join(P.never(), ", "), F.Skill{}, True{}, [F.Go{16n, ""}]},
    F.Step{"OFFER.bend reads the MODE: line", F.System{}, False{}, [F.Go{8n, ""}]},
    F.Step{"Switch / Stay", F.Person{}, False{}, []},
    F.Step{"HEAR.bend reads the LAW: lines", F.System{}, False{}, [F.Go{10n, ""}]},
    F.Step{"Add / Always add / Don't add", F.Person{}, False{}, [F.Go{11n, "Add"}]},
    F.Step{"engine/TURN.bend puts it in RULES.md", F.System{}, True{}, [F.Go{12n, ""}]},
    F.Step{"Law agent: claude " ++ P.claude_tools(P.law_agent()) ++ ", AGENT.md", F.Skill{}, True{}, [F.Go{13n, ""}]},
    F.Step{"bend LAWS.bend: green or red", F.System{}, False{}, []},
    F.Step{"Chat: codex --sandbox " ++ P.codex_sandbox(P.chat()) ++ ", " ++ codex_asks(), F.Skill{}, False{}, []},
    F.Step{"Debug: bend PROOF.bend", F.System{}, False{}, []},
    F.Step{"engine/BUILD.bend: bend checks every .bend file and bundles the page", F.System{}, False{}, [F.Go{3n, "an error: the chat fixes it"}]}
  ]
