"""Compares load.v11 with PyYAML's safe_load, which reads the YAML 1.1
types, on test/v11/cases.txt, and prints the cases where they differ.

    script/build test/v11.bend build/v11
    build/v11 test/v11/cases.txt > build/v11.txt
    python3 test/v11/compare.py test/v11/cases.txt build/v11.txt

Needs PyYAML. A timestamp counts as T, whatever its value. The cases in
DIFFERS differ from PyYAML on purpose and are counted apart.
"""
import datetime, math, sys
import yaml

def esc(s):
    out = []
    for c in s:
        if c == "\\": out.append("\\\\")
        elif c == "\n": out.append("\\n")
        elif c == "\t": out.append("\\t")
        elif c in "()": out.append("\\" + c)
        elif ord(c) < 32 or ord(c) == 127: out.append("\\x%02X" % ord(c))
        else: out.append(c)
    return "".join(out)

def dump(v):
    if v is None: return "null"
    if v is True: return "true"
    if v is False: return "false"
    if isinstance(v, int): return "I(%d)" % v
    if isinstance(v, float): return "F(%r)" % v
    if isinstance(v, str): return "S(%s)" % esc(v)
    if isinstance(v, (datetime.date, datetime.datetime)): return "T"
    if isinstance(v, bytes): return "B"
    if isinstance(v, list): return "[" + ",".join(dump(x) for x in v) + "]"
    if isinstance(v, dict): return "{" + ",".join("%s=%s" % (dump(k), dump(x)) for k, x in v.items()) + "}"
    return "?"

def num(t):
    t = {".inf": "inf", "-.inf": "-inf", ".nan": "nan"}.get(t, t)
    return float(t)

def norm(line):
    import re
    line = re.sub(r"T\(S\([^)]*\)\)", "T", line)
    line = re.sub(r"tag:yaml.org,2002:binary\(S\([^)]*\)\)", "B", line)
    def f(m):
        x = num(m.group(1))
        return "F(nan)" if math.isnan(x) else "F(%r)" % x
    return re.sub(r"F\(([^)]*)\)", f, line)

# What this library does differently from PyYAML, and why.
DIFFERS = {
    "x: -.5": "the 1.1 float form allows a sign before .5; PyYAML's doesn't",
    "x: +.5": "the 1.1 float form allows a sign before .5; PyYAML's doesn't",
    "x: ! 12": '"!" is the non-specific tag, a string; PyYAML resolves it as plain',
    "x: !foo bar": "an unknown tag is kept as Tagged; PyYAML refuses it",
    "a: &a {x: 1}\nb: &b {y: 2}\nc:\n  <<: [*a, *b]\n  z: 3": "merged keys keep the list's order; PyYAML reverses it",
    "a:\n  <<: {b: 1}\n  <<: {b: 2, c: 3}": "a key may appear once, \"<<\" too; PyYAML keeps the last",
    "a: 1\na: 2": "a key may appear once; PyYAML keeps the last",
}

cases = open(sys.argv[1]).read().split("§")
ours = open(sys.argv[2]).read().split("\n")
same = 0
known = 0
for i, c in enumerate(cases):
    try:
        theirs = dump(yaml.safe_load(c))
    except Exception:
        theirs = "ERR"
    mine = ours[i]
    if theirs == "ERR" and mine.startswith("ERR:"):
        same += 1
    elif norm(mine) == norm(theirs):
        same += 1
    elif c in DIFFERS:
        known += 1
        print("%d: %r differs on purpose: %s" % (i, c, DIFFERS[c]))
    else:
        print("%d: %r\n  pyyaml: %s\n  bend:   %s" % (i, c, theirs, mine))
print("%d/%d agree with PyYAML, %d differ on purpose" % (same, len(cases), known))
