#!/usr/bin/env python3
# Required Notice: Copyright 2026 stop-loss-enjoyer
# Plainlines is source-available under the PolyForm Shield License 1.0.0.
#
"""Checks the texts of the repository: the Markdown files in the root and the workflow files carry no long or medium
dash, and every relative link and picture in the Markdown files points to a file or folder that exists.

Links to the web, mail links and links to an anchor of the same page are left alone, a "#anchor" at the end of a path
is cut off, a link that leads out of the tree (../../releases) is a GitHub address. Fenced blocks and `inline code` are skipped. Standard library only.
Usage: python3 -I tests/texts/check_md.py   (run from anywhere; exit code 1 on a finding)
"""
import glob
import os
import re
import sys
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DASHES = ("—", "–")
LINK = re.compile(r"!?\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+[\"'][^)]*[\"'])?\s*\)")
HTML = re.compile(r"""(?:src|href)\s*=\s*["']([^"']+)["']""", re.I)
REF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s|$)")
SKIP = re.compile(r"^(?:[a-z][a-z0-9+.-]*:|//|#)", re.I)

problems = []


def report(path, no, text):
    problems.append("%s:%d: %s" % (os.path.relpath(path, ROOT), no, text))


def lines_of(path):
    with open(path, encoding="utf-8") as f:
        return f.read().split("\n")


def check_dashes(path):
    for no, line in enumerate(lines_of(path), 1):
        for d in DASHES:
            if d in line:
                report(path, no, "long or medium dash (use a comma or a full stop)")
                break


def check_links(path):
    base = os.path.dirname(path)
    fenced = False
    for no, line in enumerate(lines_of(path), 1):
        if line.lstrip().startswith(("```", "~~~")):
            fenced = not fenced
            continue
        if fenced:
            continue
        plain = re.sub(r"`[^`]*`", "", line)
        targets = LINK.findall(plain) + HTML.findall(plain)
        m = REF.match(plain)
        if m:
            targets.append(m.group(1))
        for t in targets:
            if SKIP.match(t):
                continue
            rel = unquote(t.split("#", 1)[0].split("?", 1)[0])
            if not rel:
                continue
            full = os.path.join(ROOT, rel.lstrip("/")) if rel.startswith("/") else os.path.join(base, rel)
            if os.path.relpath(os.path.normpath(full), ROOT).startswith(".."):
                continue    # "../../releases" and the like are GitHub addresses, they lead out of the tree
            if not os.path.exists(full):
                report(path, no, "the link target does not exist: %s" % t)


def main():
    md = sorted(p for p in glob.glob(os.path.join(ROOT, "*.md")) if os.path.basename(p) != "CLAUDE.md")
    wf = sorted(glob.glob(os.path.join(ROOT, ".github", "**", "*.y*ml"), recursive=True))
    if not md:
        print("check_md: no Markdown files found in", ROOT)
        return 1
    for p in md:
        check_dashes(p)
        check_links(p)
    for p in wf:
        check_dashes(p)
    for p in problems:
        print(p)
    print("check_md: %d Markdown and %d workflow files, %d problem(s)" % (len(md), len(wf), len(problems)))
    return 1 if problems else 0


sys.exit(main())
