# LawEditor: how the chat gets permission to act, today and two ways to fix it (a proposal, not built yet).
# Today a command made of parts ("a | b > file && c") asks forever: the person allows the whole line,
# Claude's CLI checks each part alone, finds none on its list, and refuses again.
# DIAGRAMS.bend draws each flow.

import Base
import ./FLOW.bend as F

# Today (0.1.7): ASK.bend allows the whole command as one line, Bash(<whole command>).
def today() -> List<&2, F.Step>:
  [
    F.Step{"The chat wants to run a command made of parts", F.Skill{}, False{}, [F.Go{1n, ""}]},
    F.Step{"Claude's CLI checks each part alone against its list (--allowedTools)", F.Cli{}, False{}, [F.Go{2n, "a part isn't on it"}, F.Go{6n, "every part is on it"}]},
    F.Step{"ASK.bend: the refusal becomes a question", F.System{}, False{}, [F.Go{3n, ""}]},
    F.Step{"Allow / Always allow / Don't allow", F.Person{}, False{}, [F.Go{4n, "Allow"}]},
    F.Step{"ASK.bend adds ONE line to the list: the whole command", F.System{}, False{}, [F.Go{5n, ""}]},
    F.Step{"The chat tries again (--resume)", F.Skill{}, False{}, [F.Go{1n, "the whole line never matches a part: asks again, forever"}]},
    F.Step{"The command runs", F.Cli{}, True{}, []}
  ]

# Option A: write the list the way the CLI reads it. One line per part, and each file a > writes as Edit(...).
# Bend still only writes the list; the CLI still decides.
def list() -> List<&2, F.Step>:
  [
    F.Step{"The chat wants to run a command made of parts", F.Skill{}, False{}, [F.Go{1n, ""}]},
    F.Step{"Claude's CLI checks each part alone against its list (--allowedTools)", F.Cli{}, False{}, [F.Go{2n, "a part isn't on it"}, F.Go{7n, "every part is on it"}]},
    F.Step{"ASK.bend: asked this already? Then stop and say so", F.System{}, False{}, [F.Go{3n, "first time"}, F.Go{8n, "asked already"}]},
    F.Step{"Allow / Always allow / Don't allow", F.Person{}, False{}, [F.Go{4n, "Allow"}]},
    F.Step{"ASK.bend cuts the command into parts, as the CLI does", F.System{}, False{}, [F.Go{5n, ""}]},
    F.Step{"ASK.bend adds one line per part, and Edit(file) for each file a > writes", F.System{}, False{}, [F.Go{6n, ""}]},
    F.Step{"The chat tries again (--resume)", F.Skill{}, False{}, [F.Go{1n, "if Bend cut it like the CLI"}]},
    F.Step{"The command runs", F.Cli{}, True{}, []},
    F.Step{"The chat says what was blocked", F.Skill{}, False{}, []}
  ]

# Option B: the CLI asks Bend at each action (--permission-prompts host, --permission-prompt-tool).
# Bend sees the whole action and decides with POLICY.bend and the laws; the CLI only obeys. No retry.
def ask_bend() -> List<&2, F.Step>:
  [
    F.Step{"The chat wants to run a command made of parts", F.Skill{}, False{}, [F.Go{1n, ""}]},
    F.Step{"Claude's CLI: not on its list, so it asks our tool and waits (--permission-prompt-tool)", F.Cli{}, False{}, [F.Go{2n, ""}]},
    F.Step{"Bend decides on the whole action, with POLICY.bend and the laws", F.System{}, False{}, [F.Go{5n, "allowed already"}, F.Go{3n, "new: ask you"}, F.Go{6n, "a law forbids it"}]},
    F.Step{"Allow / Always allow / Don't allow", F.Person{}, False{}, [F.Go{4n, "Allow"}, F.Go{6n, "Don't allow"}]},
    F.Step{"Bend keeps your answer, then tells the CLI yes", F.System{}, False{}, [F.Go{5n, ""}]},
    F.Step{"The command runs, in the same turn", F.Cli{}, True{}, []},
    F.Step{"The CLI refuses; the chat goes on without it", F.Cli{}, False{}, []}
  ]
