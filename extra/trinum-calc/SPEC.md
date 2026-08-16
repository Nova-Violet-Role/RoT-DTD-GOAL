# trinum — an advanced calculator across three ancient numeral systems

A Rust workspace with two crates:

  engine/  (lib + small CLI `trinum`)   the calculator core — no UI deps
  ui/      (bin `trinum-ui`)            a Slint graphical front-end

## The numeral systems (engine/src/…)

ROMAN    — standard subtractive notation, I V X L C D M, values 1..3999.
           Parse accepts canonical forms (MCMXCIV=1994); format emits canonical.
GREEK    — Ionian alphabetic numerals: α β γ δ ε ϛ ζ η θ (1..9),
           ι κ λ μ ν ξ ο π ϟ (10..90), ρ σ τ υ φ χ ψ ω ϡ (100..900),
           ͵ prefix multiplies the NEXT letter by 1000 (͵α = 1000);
           values 1..9999. Keraia (ʹ) on output is NOT emitted (bare letters).
GYPTIAN  — Egyptian hieroglyphic, additive, symbols repeated up to 9 times:
           𓏺=1  𓎆=10  𓍢=100  𓆼=1000  𓂭=10000; values 1..99999;
           canonical output orders largest→smallest.

## The engine API + CLI

- parse(s) -> u32: auto-DETECTS the system of a token.
- format(n, system) -> String for any of the three systems.
- eval(expr) -> u32: + - * / ( ) with tokens from ANY system mixed freely,
  e.g. "XIV + ͵α - 𓎆𓏺" is legal. Integer arithmetic; division truncates;
  underflow/overflow or 0 results are an Err (these systems have no zero).
- CLI: echo "<expr>" | trinum --out roman|greek|egyptian  prints the result
  formatted in the requested system; a parse/eval error prints to stderr and
  exits nonzero with the offending token named.

## The UI (ui/)

Slint window: expression input, three output rows (one per system) updated on
Enter, and a keypad of numeral buttons for all three systems. It must COMPILE
on all three OSes (CI proves the matrix); the engine holds all logic so the
UI stays a thin shell.

## Quality bar

cargo test covers: round-trips for all three systems across representative
values (incl. MCMXCIV, ͵θϡϟθ=9999, 𓂭×9+…=99999 boundaries), mixed-system
eval, canonical formatting, and every error path. No panics reachable from
parse/eval — errors are Results.
