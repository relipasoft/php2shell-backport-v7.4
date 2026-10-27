# Drop hunks already present in ondrej patch 0062-Introduce-max_multipart_body_parts-INI.patch:
# main/main.c hunk 1, main/rfc1867.c hunks 5,6,7.
import sys, re
DROP = {"main/main.c": {1}, "main/rfc1867.c": {5, 6, 7}}
src = open(sys.argv[1]).read().split("\n")
out, cur, hunk, skip, in_body = [], None, 0, False, False
for line in src:
    if line.startswith("diff --git "):
        cur = line.split(" b/")[-1]; hunk = 0; skip = False; in_body = True
    elif in_body and line.startswith("@@"):
        hunk += 1; skip = hunk in DROP.get(cur, set())
    elif line.startswith("-- ") and line.strip() == "--":
        skip = False
    if not skip:
        out.append(line)
open(sys.argv[2], "w").write("\n".join(out).rstrip("\n") + "\n")
