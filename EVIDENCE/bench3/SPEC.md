# mdtoc — the contract
Build ./mdtoc.sh (bash + coreutils, awk allowed):
    ./mdtoc.sh toc <file>      print a markdown TOC of ## and ### headings (skip the # title):
                               "- [text](#anchor)" for ##, two-space-indented for ###;
                               anchors GitHub-style: lowercase, spaces->dashes, strip
                               everything but [a-z0-9-], collapse nothing else.
                               Headings inside fenced code blocks are NOT headings.
    ./mdtoc.sh insert <file>   idempotently insert/refresh the TOC between the markers
                               "<!-- toc -->" and "<!-- /toc -->" (in place, file rewritten);
                               running insert twice yields a byte-identical file.
    ./mdtoc.sh links <file>    print each broken RELATIVE link target (missing local file),
                               one per line; http(s) and #anchors are not checked;
                               exit 0 when none broken, exit 1 when any.
CRLF input behaves like LF. Unknown subcommand: usage to stderr, exit 2.
