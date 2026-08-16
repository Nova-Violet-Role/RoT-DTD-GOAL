#!/usr/bin/env bash
# judge.sh <dir> -- the held-out accuracy judge: same criteria both arms.
cd "$1" || exit 9
p=0; t=0
run(){ t=$((t+1)); if bash -c "$1" >/dev/null 2>&1; then p=$((p+1)); echo "PASS $2"; else echo "FAIL $2"; fi; }
run 'bash -n mdtoc.sh && test -x mdtoc.sh'                                              C1-parses
run 'diff <(./mdtoc.sh toc fixtures/doc.md) expected/toc.txt'                           C2-toc
run 'diff <(./mdtoc.sh toc fixtures/crlf.md) expected/toc_crlf.txt'                     C3-crlf
run 'cp fixtures/marked.md t4.md && ./mdtoc.sh insert t4.md && grep -q "#usage--flags" t4.md' C4-insert
run 'cp fixtures/marked.md t5.md && ./mdtoc.sh insert t5.md && cp t5.md t5b.md && ./mdtoc.sh insert t5.md && cmp -s t5.md t5b.md' C5-idempotent
run 'diff <(./mdtoc.sh links fixtures/links.md) expected/broken.txt'                    C6-links
run './mdtoc.sh links fixtures/links.md >/dev/null 2>&1; test $? -eq 1 && ./mdtoc.sh links fixtures/clean.md >/dev/null 2>&1' C7-exitcodes
run './mdtoc.sh frob 2>e8.log; test $? -eq 2 && grep -qi usage e8.log'                  C8-usage
echo "SCORE $p/$t"
