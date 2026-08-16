# Security Policy

## What this software actually does to your machine

Be clear-eyed about the threat model before reading anything else.

**RoT DTD GOAL runs shell commands you wrote, on your machine, without asking
each time.** That is not a vulnerability — it is the entire feature. An
acceptance criterion *is* a shell command; the Stop hook re-runs every one of
them when a session tries to end. If you write `rm -rf /` as a criterion, the
gate will run `rm -rf /`.

Two consequences follow, and neither is a bug report:

* **Never accept a `.claude/goal/` directory from someone else.** It contains
  the criteria — that is, commands — that the gate will execute on your
  machine. Treat it exactly as you would treat a shell script sent by a
  stranger.
* **Never paste criteria you have not read.** A goal file from a blog post, a
  model, or a screenshot is untrusted code.

## Supported versions

| version | supported |
|---------|-----------|
| 1.0.x   | yes       |
| < 1.0   | no — unpublished development line (`v2` → `v3.6`) |

## Reporting a vulnerability

Use GitHub's **private vulnerability reporting** on this repository:

> Security → Report a vulnerability

That opens a private advisory visible only to the maintainers. Please do not
open a public issue for anything in the categories below until it has been
triaged.

There is deliberately no email address in this file. An address here is a claim
that somebody is reading that inbox; this project does not publish claims it
cannot back.

### What we consider a vulnerability

The interesting attacks against this design are about **who gets to decide a
goal is complete**, and about text that escapes the fence:

* **Gate evasion** — any way to make the Stop hook return `allow` while an
  acceptance criterion is failing, or to make a criterion appear to pass when
  the thing it checks is broken.
* **Fence escape** — verify-command output is untrusted data and is quarantined
  before it is rendered. A payload that escapes that fence and is read as an
  instruction by the model is a real finding. The declared untrusted channels
  are listed as `<!NOTATION>` entries in `hooks/trust_contract.dtd`; a
  *rendering site that skips the fence* is the bug class to hunt.
* **Record forgery** — anything that lets a ledger, journal or queue row be
  rewritten rather than appended (LAW.15), or that makes `attest.sh --verify`
  pass over a tree it should reject.
* **Attestation confusion** — a tree whose contents differ from the attested
  digest while verification still exits 0.
* **Injection through hook payloads** — hook stdin is declared untrusted; a
  payload that reaches `eval`, an unquoted expansion, or a command substitution
  is a finding.

### What is not a vulnerability

* A criterion you wrote running as you wrote it. See the top of this file.
* The plugin reading and writing inside `.claude/goal/` in your own project.
* `ATTESTATION.txt` being a **digest, not a signature** — it detects accidental
  drift, and it is documented as unable to stop an attacker who can also
  rewrite the attestation. That limit is stated in `docs/REVIEW.md` and in the
  README; reporting it as news is welcome but it is a known, disclosed bound.
* Anything requiring an attacker who already has write access to your working
  tree. At that point they can edit the criteria directly, and no gate helps.

## Response

Reports are triaged as time allows — this is a small project, not a vendor with
an on-call rotation, and saying so plainly is more useful than promising a
24-hour SLA nobody is staffed to meet. A confirmed gate-evasion or fence-escape
finding will get a regression test with a **negative control** — a test that has
been observed to fail before it passes — because a fix without one is a claim,
not a repair.
