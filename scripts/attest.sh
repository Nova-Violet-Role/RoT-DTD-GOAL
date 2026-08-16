#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL (formerly goal-forge).
#
# THE NEW CAPABILITY (v3.5): what is the gate's word worth outside this room?
#
# Everything the engine proves, it proves to someone who is already here: the
# suite runs on this machine, the ledger is sealed in this directory, the
# journal is readable by whoever owns the terminal. A stranger -- CI, another
# machine, the next maintainer, someone who downloaded a zip -- has none of
# that. For them "343 tests pass" is a sentence in a README, which is exactly
# the kind of claim this project exists to refuse.
#
# An attestation is the answer: a machine-checkable statement of WHAT WAS
# MEASURED and WHERE, that anyone can re-verify on their own hardware and that
# FAILS LOUDLY when the tree it describes is no longer the tree they have.
#
#   attest.sh              human-readable attestation for this tree + machine
#   attest.sh --facts      just the portable KEY=VALUE facts (docs embed these)
#   attest.sh --verify F   recompute and compare against F; exit 1 on drift,
#                          naming every field that moved
#
# DESIGN NOTE, because the obvious version is circular: the facts block that
# documentation embeds contains COUNTS ONLY, never the tree digest. A digest of
# the tree, embedded in a file that is part of the tree, changes itself every
# time it is written and can never be stable. The digest therefore lives in the
# attestation output alone, where it is computed over the shipped code and read
# by --verify.
#
# WHAT THIS DOES NOT CLAIM: it is not a signature. It proves nothing about who
# produced the tree, and a hostile publisher can regenerate it at will. It
# proves that the tree in front of you is the tree that was measured, and that
# your environment can run what it claims. That is a smaller claim than a
# signature, and it is the claim that is actually true.
#
# DECIDED, 1.0.0 -- this stays unsigned, and here is the reasoning rather than a
# promise to revisit it:
#
#   an attestation binds a TREE.        A signature binds an AUTHOR to a tree.
#
# What a signature would add is exactly one thing: it would let you distinguish
# "this tree is internally consistent" from "this tree came from the person you
# think it came from". That second question cannot be answered by anything
# inside the archive -- it needs a key you already trust, obtained through some
# channel that is not this archive. Shipping a signature without that channel
# would move the trust problem one step and dress it as solved, which is the
# failure this whole engine is built to refuse.
#
# So the honest boundary: verify the tree with `--verify`, and get the archive
# itself from a source you have reason to trust. If you need author binding,
# sign the archive with your own key at the point where your trust actually
# begins; nothing here prevents that, and nothing here pretends to be it.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------- the facts
# Deterministic and environment-independent: the same tree yields the same
# lines on any machine, which is what makes them safe to embed in docs.
gf_facts() {
  local v cases events rows scripts modules theorems
  v="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')"
  cases="$(bash "$ROOT/tests/run_tests.sh" --list 2>/dev/null | grep -c '^test_' | head -n1)"
  # Event keys are the four-space-indented ones. A looser pattern counts the
  # nested "hooks": [ arrays too and reports 62 for 31 events -- measured, and
  # exactly the fabricated constant this file exists to prevent.
  events="$(grep -cE '^    "[A-Za-z]+": \[' "$ROOT/hooks/hooks.json" 2>/dev/null | head -n1)"
  # Rows are counted by their CLASSIFICATION, so the header and the comments
  # cannot inflate the number.
  rows="$(awk -F'\t' '$2 == "decision" || $2 == "forensic" {n++} END {print n+0}' "$ROOT/hooks/event_consumers.tsv" 2>/dev/null)"
  scripts="$(ls "$ROOT/scripts"/*.sh 2>/dev/null | wc -l | tr -d ' ')"
  modules="$(ls "$ROOT/EVIDENCE/lean"/*.lean 2>/dev/null | wc -l | tr -d ' ')"
  theorems="$(grep -ch '^theorem ' "$ROOT/EVIDENCE/lean"/*.lean 2>/dev/null | awk '{s+=$1} END {print s+0}')"
  printf 'GF_VERSION=%s\n'        "${v:-unknown}"
  printf 'GF_SCRIPTS=%s\n'        "$scripts"
  printf 'GF_TEST_CASES=%s\n'     "$cases"
  printf 'GF_HOOK_EVENTS=%s\n'    "$events"
  printf 'GF_CONSUMER_ROWS=%s\n'  "$rows"
  printf 'GF_LEAN_MODULES=%s\n'   "$modules"
  printf 'GF_LEAN_THEOREMS=%s\n'  "$theorems"
}

# PORTABLE SHA-256, and why this is not a nicety.
#
# `sha256sum` is GNU coreutils. Stock macOS does not have it; it has `shasum`,
# which BSD ships. The fourth review caught this as a label defect rather than a
# code defect: README claimed "bash and coreutils, that is the entire list",
# lib.sh already fell back to shasum, and attest.sh did not -- so a Mac user
# could run the engine but could not VERIFY it. An attestation that only the
# author's platform can check is an attestation of nothing.
#
# Both tools print "<hex>  <name>"; taking field 1 is identical for both, so the
# digest is byte-identical across platforms. That is what makes tree.sha256
# comparable at all, and it is asserted by the suite, not assumed here.
gf_sha256() { # reads stdin -> bare hex digest
  if command -v sha256sum > /dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum > /dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  elif command -v openssl > /dev/null 2>&1; then openssl dgst -sha256 | sed 's/.*= *//'
  else echo "NO-SHA256-TOOL"; fi
}

# Digest over the SHIPPED CODE only -- scripts, hooks, tests, lean, manifest of
# the plugin itself. Documentation is deliberately excluded: prose changes are
# not code changes, and a digest that moves when a typo is fixed teaches the
# reader to ignore it.
gf_tree_digest() {
  { find "$ROOT/scripts" "$ROOT/hooks" "$ROOT/tests" "$ROOT/EVIDENCE/lean" -type f 2>/dev/null
    echo "$ROOT/.claude-plugin/plugin.json"; } \
    | LC_ALL=C sort \
    | while IFS= read -r f; do [ -f "$f" ] && gf_sha256 < "$f"; done \
    | gf_sha256
}

# What this machine can actually do. A stranger needs to know whether their
# floor is the floor the engine assumes -- and each line must be able to say NO.
gf_environment() {
  local t
  printf 'bash=%s\n' "${BASH_VERSION:-unknown}"
  printf 'uname=%s\n' "$(uname -s 2>/dev/null || echo unknown)"
  for t in awk sed grep find sort; do
    if command -v "$t" > /dev/null 2>&1; then printf 'tool.%s=present\n' "$t"
    else printf 'tool.%s=MISSING\n' "$t"; fi
  done
  # The three GNU-isms, each reported by WHICH implementation was found rather
  # than as present/MISSING. A Mac has none of the GNU names and is still a
  # supported floor; saying "MISSING" there would be a false alarm, and a false
  # alarm teaches a reader to skip the whole block.
  if command -v sha256sum > /dev/null 2>&1;   then printf 'hash.tool=sha256sum\n'
  elif command -v shasum > /dev/null 2>&1;    then printf 'hash.tool=shasum -a 256\n'
  elif command -v openssl > /dev/null 2>&1;   then printf 'hash.tool=openssl dgst\n'
  else printf 'hash.tool=NONE (attestation cannot be verified on this machine)\n'; fi
  if command -v timeout > /dev/null 2>&1;     then printf 'watchdog=timeout\n'
  elif command -v gtimeout > /dev/null 2>&1;  then printf 'watchdog=gtimeout\n'
  else printf 'watchdog=portable fallback (background kill; see gf_run_with_timeout)\n'; fi
  if date -d '2000-01-01 00:00:00' +%s > /dev/null 2>&1; then
    printf 'date.arithmetic=present\n'
  else
    # Not fatal: the rate limiter degrades toward journalling MORE. Named so a
    # stranger can see which behaviour they are getting.
    printf 'date.arithmetic=MISSING (event rate limiting degrades to off)\n'
  fi
}

case "${1:-}" in
  --facts)
    gf_facts
    ;;
  --write-docs)
    # Regeneration is a COMMAND, not a habit. A block that has to be pasted by
    # hand is a typed number with extra steps, and typed numbers are what this
    # whole mechanism exists to remove.
    facts_file="$(mktemp "${TMPDIR:-/tmp}/gf-facts.XXXXXX")"
    gf_facts > "$facts_file"
    for doc in README.md docs/REVIEW.md; do
      [ -f "$ROOT/$doc" ] || continue
      grep -q 'GF:FACTS BEGIN' "$ROOT/$doc" || { echo "skip $doc (no facts block)"; continue; }
      awk -v ff="$facts_file" '
        /GF:FACTS BEGIN/ { print; while ((getline l < ff) > 0) print l; close(ff); skip = 1; next }
        /GF:FACTS END/   { skip = 0 }
        !skip            { print }
      ' "$ROOT/$doc" > "$ROOT/$doc.gfnew" && mv "$ROOT/$doc.gfnew" "$ROOT/$doc"
      echo "regenerated facts block in $doc"
    done
    rm -f "$facts_file"
    ;;
  --verify)
    ref="${2:-}"
    [ -n "$ref" ] && [ -f "$ref" ] || { echo "usage: attest.sh --verify <attestation-file>" >&2; exit 2; }
    drift=0
    # Compare only the portable facts and the tree digest. Environment lines
    # are expected to differ between machines -- that is the point of them.
    while IFS= read -r line; do
      case "$line" in GF_*|tree.sha256=*) ;; *) continue ;; esac
      key="${line%%=*}"; want="${line#*=}"
      if [ "$key" = "tree.sha256" ]; then got="$(gf_tree_digest)"; else got="$(gf_facts | grep "^$key=" | cut -d= -f2-)"; fi
      if [ "$want" != "$got" ]; then
        echo "DRIFT $key: attested [$want] but this tree measures [$got]"
        drift=1
      fi
    done < "$ref"
    if [ "$drift" -ne 0 ]; then
      echo
      echo "ATTESTATION FAILED. The tree you have is not the tree that was measured."
      echo "Either it was modified after the attestation, or the attestation is stale."
      exit 1
    fi
    echo "ATTESTATION OK: every attested fact still holds in this tree."
    ;;
  ""|--full)
    echo "# RoT DTD GOAL attestation"
    echo "# Generated by scripts/attest.sh. Re-check it on your own machine with:"
    echo "#   bash scripts/attest.sh --verify <this file>"
    echo "# It attests what was MEASURED, not that anyone should trust the author."
    echo
    gf_facts
    printf 'tree.sha256=%s\n' "$(gf_tree_digest)"
    echo
    echo "# environment measured at generation time -- expected to differ on"
    echo "# your machine, and not compared by --verify"
    gf_environment
    echo
    echo "# NOT ATTESTED, deliberately: that the suite passes. A number typed"
    echo "# into a file is the failure mode this replaces -- run it yourself:"
    echo "#   bash tests/run_tests.sh   (exit 0 is the claim, nothing else is)"
    ;;
  *)
    echo "usage: attest.sh [--full] | --facts | --verify <file>" >&2
    exit 2
    ;;
esac
