# Ideas: a first product in Bend

Written on 2026-11-18. A working list, still open: what we looked at, what we dropped and why.

## Goal

We want one product, written in Bend, that real people use without knowing it is Bend, and that starts bringing in revenue. Bend's libraries should then grow from what that product needs, not the other way around.

Bend's edge is not what it can prove: Lean can prove the same things. Its edge is what proving costs, since checks finish in under a second, the syntax is easy for AI, and one toolchain proves, runs natively and compiles to JS. So the product must need new proofs all the time.

## Every idea so far

Sixteen ideas, in the order we had them. Four are alive; the rest taught us the filters in the next section.

| # | Idea | Status | Why |
| --- | --- | --- | --- |
| 1 | A top-tier harness written in Bend (like Hermes), from LawEditor | Discarded | Crowded. A harness is mostly IO, Bend's weakest area. Nobody picks a harness for its language. |
| 2 | Move UniiChat to Bend | Discarded | UniiChat has no active users, so moving it gains nothing. |
| 3 | App builder for small Bend web apps and games | Merged | Nothing in it needed Bend. Became #7. |
| 4 | Bailiff: a general permission gate for agents | Discarded | Free hook plugins, agentjail and Sondera exist. The hard part is what rules mean, not proofs. |
| 5 | Plugin for Bend users: protect LAWS.bend, proof gate, plain-English review | Parked | Makes Bend more usable but earns nothing. Reused in #15. |
| 6 | HTTPS and JSON libraries on BendHub | Parked | Useful, but libraries are not a focus. |
| 7 | Small-business app builder with proved rules, built from a catalog of pre-proved modules | Alive | Strongest revenue candidate. App builders are crowded, so it needs a sharp niche. |
| 8 | Safety monitor for robots such as harvesters | Parked | Real value, but certification, real-time limits, floats and embedded chips put it years away. |
| 9 | "Bug-free" crypto wallet | Discarded | Most losses are not logic bugs. Writing crypto in Bend is risky, and timing cannot be proved. |
| 9b | "What you see is what you sign" | Parked | Proved once, and Lean already has the pieces (evm-abi-lean). Little edge for Bend. |
| 10 | Proved Shopify discount functions | Unvalidated | Market exists, but one function cannot control the final price. Size limits unknown. |
| 11 | Sales commission plans | Unexplored | Fixed laws while plans change every quarter. B2B, slower sales. |
| 12 | Data access rules for SaaS apps | Unexplored | Crowded: Cedar, Oso, Permit.io. |
| 13 | Cashback, like Méliuz | Discarded | Wins on partnerships and tracking. The logic is trivial. |
| 14 | Personal money rules over Open Finance and Pix Automático | Alive | Best consumer fit. Moving money needs a Banco Central license, so it goes through a bank or fintech. |
| 15 | "Trust layer" plugin: UniiChat memory plus laws | Alive | A funnel for users and data, not revenue. Local memory and opt-in data only. |
| 16 | The strongest guardrail, with enforcement proved | Alive | Needs our own harness, since a plugin cannot prove it is always called. No one has proved enforcement yet. |

## Filters we learned

An idea has to pass all of these before we build it.

1. **The four tests.** The failure costs real money or real harm. Logic causes it, not people, hardware or the network. That logic is small and pure. The guarantee shows on screen.
2. **Bend versus Lean.** Bend wins only where proofs are needed all the time: the laws stay fixed while AI keeps changing the code. A proof that experts write once is Lean's ground.
3. **Nobody buys a language.** Users never pick a product for what it is written in. Distribution and trust decide.
4. **Say exactly what is proved.** "Bug-free" and "never" backfire the first time something outside the proof goes wrong. Name what the proof covers and what it does not.

## Still standing

The small-business app builder (#7) is the best bet for first revenue. Each idea below has a check that costs days, not months.

| Idea | Role | Cheap check |
| --- | --- | --- |
| #7 Small-business app builder | First revenue | Write one pre-proved module (Permissions or History) and measure the time and how often the AI proves it alone. Then build one template, such as bookings that cannot double-book, and talk to 10 businesses. |
| #14 Personal money rules | Consumer side, through a partner | Ask 2 or 3 banks or fintechs with a payment license whether they would offer proved automations. |
| #11 Sales commission plans | B2B option | Talk to 5 sales or finance leads about payout disputes and how often their plans change. |
| #15 Trust-layer plugin | Funnel for users and data | Ship the free version and count installs and opt-ins after 4 weeks. |
| #16 Harness with proved enforcement | Long-term goal | Write the pure core (state plus event in, new state plus effects out) and the law that every effect passed the gate. |

## Open questions

- [ ] Which niche does the app builder start with: bookings, a CRM, or inventory?
- [ ] Can a model write Bend proofs for a pre-proved module without help, and how often does it fail?
- [ ] Do agents weaken or delete laws in LAWS.bend when a proof gets hard? Bend's own evals/ are the place to test it.
- [ ] What stays open on BendHub, and what stays private as our catalog of proofs?
- [ ] Is there an idea we have not had yet that passes all four tests and needs proofs every week?
