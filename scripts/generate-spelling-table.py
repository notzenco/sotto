#!/usr/bin/env python3
"""Generate Core/SpellingTable.swift from VarCon.

Development-time only; not part of the app. Takes the path to an extracted
VarCon directory (one holding varcon.txt, for example varcon/ from
https://github.com/en-wl/wordlist) and writes Swift to stdout. It never
touches the network.

usage: python3 -I scripts/generate-spelling-table.py VARCON_DIR > Core/SpellingTable.swift
       python3 -I scripts/generate-spelling-table.py VARCON_DIR --stats
"""
import os
import re
import sys
from collections import defaultdict

# SCOWL level 60 is SCOWL's recommended size for spell checking.
MAX_LEVEL = 60

# VarCon's noun line gives programme; its verb line keeps program, which would
# drop the pair. Dictation can't tell them apart, so the noun wins.
OVERRIDES = {"program": "programme", "programs": "programmes"}

# Swearing and slurs are kept exactly as said, in every variety, and no
# respelling may produce one. A pair is dropped when either side is listed.
SWEARING = {
    "arse", "arses", "arsehole", "arseholes", "ass", "asses", "asshole", "assholes",
    "fag", "fags", "fagot", "fagoted", "fagoting", "fagots", "faggot", "faggoted",
    "faggoting", "faggots", "perv", "perve", "perved", "perves", "perving", "prev",
    "bloody", "bugger", "buggered", "buggering", "buggers", "piss", "pissed",
    "pisses", "pissing",
}

# Pairs that VarCon gives but that are wrong, change meaning, or are only one
# of two accepted British forms. A pair is dropped when either side is listed.
EXCLUDED = {
    # -ed and -t are both British; "a learned colleague" must stay learned.
    "burned", "burnt", "dreamed", "dreamt", "dwelled", "dwelt", "kneeled", "knelt",
    "leaned", "leant", "leaped", "leapt", "learned", "learnt", "smelled", "smelt",
    "spelled", "spelt", "spilled", "spilt", "spoiled", "spoilt",
    # Different words, not spellings of one word.
    "among", "amongst", "sweepstake", "sweepstakes", "unbeknown", "unbeknownst",
    "fayer", "fayre", "arbores", "arboures", "whiskey", "whiskeys", "whisky", "whiskies",
    # Both forms are British, and adapter is a programming term.
    "adapter", "adapters", "adaptor", "adaptors",
    # Capitalised, it is the city: Manila must not become Manilla.
    "manila", "manilla",
}

path = os.path.join(sys.argv[1], "varcon.txt")
stats = "--stats" in sys.argv
word_re = re.compile(r"^[a-z]+$")


def lines():
    """Yields (cluster, level, verified, usage, {category: preferred words}, all words)."""
    cluster, level, verified = None, 999, False
    for raw in open(path, encoding="latin-1"):
        line = raw.rstrip("\n")
        if line.startswith("#"):
            cluster = line[1:].split()[0]
            m = re.search(r"\(level (\d+)\)", line)
            level = int(m.group(1)) if m else 999
            verified = "<verified>" in line
            continue
        if not line.strip():
            continue
        body, _, usage = line.partition(" | ")
        preferred, equal, words, has_d = defaultdict(set), set(), set(), False
        for part in body.split(" / "):
            tags, word = part.split(": ", 1)
            word = word.strip()
            words.add(word)
            for tag in tags.split():
                if tag.isdigit():
                    continue
                if tag[0] == "D":
                    has_d = True
                if len(tag) == 1:
                    preferred[tag].add(word)
                elif tag[1] == "." and tag[0] in "AB":
                    equal.add(tag[0])
        if not has_d and "B" in preferred:
            preferred["D"] = preferred["B"]
        yield cluster, level, verified, usage, preferred, equal, words


# Every outcome each word has, across all lines at every level, so a common
# word with an uncommon sense that changes (tire, story, draft) is never
# respelled. Rare or archaic senses, marked (-), don't count (gray the unit).
forward = defaultdict(set)
inverse = defaultdict(set)
clusters_of = defaultdict(set)
candidates = []  # (cluster, us, uk, australian)
for cluster, level, verified, usage, pref, equal, words in lines():
    for word in words:
        clusters_of[word].add(cluster)
    if usage.startswith("(-)"):
        continue
    a, b = pref.get("A", set()), pref.get("B", set())
    if len(a) != 1 or len(b) != 1:
        continue
    a, b = next(iter(a)), next(iter(b))
    # An "equal" tag means American or British has no single preference
    # (among and amongst), so the word can stay as it is.
    if equal:
        forward[a].add(a)
        inverse[b].add(b)
    forward[a].add(b)
    inverse[b].add(a)
    if level <= MAX_LEVEL and verified and a != b and word_re.match(a) and word_re.match(b):
        d = pref.get("D", set())
        candidates.append((cluster, a, b, d == {a}))


def ambiguous(word):
    return len(forward.get(word, {word})) > 1 or len(inverse.get(word, {word})) > 1


# A whole family (VarCon cluster) goes when any member is ambiguous, so prize
# takes prized and prizing with it, and mom takes moms.
tainted = {c for word in set(forward) | set(inverse) if ambiguous(word) for c in clusters_of[word]}
blocked = SWEARING | EXCLUDED

pairs, au_keeps = {}, set()
for cluster, us, uk, australian_keeps in candidates:
    if us in blocked or uk in blocked:
        continue
    if clusters_of[us] & tainted or clusters_of[uk] & tainted:
        continue
    pairs[us] = uk
    if australian_keeps:
        au_keeps.add(us)
pairs.update(OVERRIDES)
au_keeps |= set(OVERRIDES)  # Australian English keeps program.

assert len(set(pairs.values())) == len(pairs), "British spellings must map back uniquely"

if stats:
    print("pairs", len(pairs), "australianKeeps", sorted(au_keeps))
    sys.exit()

LICENCE = """\
Copyright 2000-2019 by Kevin Atkinson

Permission to use, copy, modify, distribute and sell this array, the
associated software, and its documentation for any purpose is hereby
granted without fee, provided that the above copyright notice appears
in all copies and that both that copyright notice and this permission
notice appear in supporting documentation. Kevin Atkinson makes no
representations about the suitability of this array for any
purpose. It is provided "as is" without express or implied warranty.

Copyright 2016 by Benjamin Titze

Permission to use, copy, modify, distribute and sell this array, the
associated software, and its documentation for any purpose is hereby
granted without fee, provided that the above copyright notice appears
in all copies and that both that copyright notice and this permission
notice appear in supporting documentation. Benjamin Titze makes no
representations about the suitability of this array for any
purpose. It is provided "as is" without express or implied warranty.

Since the original words lists come from the Ispell distribution:

Copyright 1993, Geoff Kuenning, Granada Hills, CA
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. All modifications to the source code must be clearly marked as
   such.  Binary redistributions based on modified source code
   must be clearly marked as modified versions in the documentation
   and/or other materials provided with the distribution.
(clause 4 removed with permission from Geoff Kuenning)
5. The name of Geoff Kuenning may not be used to endorse or promote
   products derived from this software without specific prior
   written permission.

THIS SOFTWARE IS PROVIDED BY GEOFF KUENNING AND CONTRIBUTORS ``AS IS'' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL GEOFF KUENNING OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE."""

header = """\
Generated from VarCon; do not edit by hand.

Source: VarCon 2020.12.07 by Kevin Atkinson and Benjamin Titze,
  varcon/varcon.txt from https://github.com/en-wl/wordlist (http://wordlist.aspell.net/).
Regenerate from the repository root with an extracted varcon/ directory:
  python3 -I scripts/generate-spelling-table.py path/to/varcon > Core/SpellingTable.swift
The script's comments give the rules: verified clusters at SCOWL level %d or below,
single lowercase words, each line's preferred American (A) spelling paired with its
preferred British "ise" (B) spelling, whole families dropped when any word depends on
meaning, plus swearing and hand-checked exclusions. This file is a modified extract
of VarCon.

""" % MAX_LEVEL

out = ["// " + l if l else "//" for l in (header + LICENCE).split("\n")]
out += ["", "enum SpellingTable {",
        "    /// Preferred American spelling to preferred British spelling.",
        "    static let americanToBritish: [String: String] = ["]
out += ['        "%s": "%s",' % (k, pairs[k]) for k in sorted(pairs)]
out += ["    ]", "",
        "    /// American spellings Australian English keeps, such as program.",
        "    static let australianKeeps: Set<String> = ["]
out += ['        "%s",' % k for k in sorted(au_keeps)]
out += ["    ]", "}"]
print("\n".join(out))
