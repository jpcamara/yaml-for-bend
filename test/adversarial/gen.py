"""Writes adversarial YAML inputs into a directory, each family at a few
sizes so the timings show how the cost grows:

    python3 test/adversarial/gen.py build/adversarial

Each file is named family-size.yaml, where the size is the text's length
in characters or, for nesting, its depth. The largest of each family stays
under the default size limit (1048576 characters), so it is read, not
refused; a few inputs go past a limit on purpose. Files named v11-* are
read with the YAML 1.1 types.
"""
import os, sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
sizes = (250000, 500000, 1000000)

def put(name, data):
    path = os.path.join(out, name + ".yaml")
    with open(path, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode("utf-8"))

# Lines from line(i) for i = 0, 1, ... until the text has n characters.
def lines(n, line, head=""):
    parts, size, i = [head], len(head), 0
    while True:
        s = line(i)
        if size + len(s) > n:
            return "".join(parts)
        parts.append(s)
        size += len(s)
        i += 1

# Alias bombs: each level is nine copies of the one before.
laughs = ["a0: &a0 [lol, lol, lol, lol, lol, lol, lol, lol, lol]"]
for i in range(1, 10):
    laughs.append("a%d: &a%d [%s]" % (i, i, ", ".join(["*a%d" % (i - 1)] * 9)))
put("billion-laughs-9", "\n".join(laughs) + "\n")
put("alias-wide-1000", "big: &big [%s]\nrefs: [%s]\n" % (", ".join(["x"] * 1000), ", ".join(["*big"] * 1000)))
put("alias-nested-100", "a: &a [x]\n" + "".join("b%d: &b%d [*%s, *%s]\n" % (i, i, "a" if i == 0 else "b%d" % (i - 1), "a" if i == 0 else "b%d" % (i - 1)) for i in range(100)))

# Merge bombs: each mapping merges the one before, many times over.
merges = ["m0: &m0 {k0: v}"]
for i in range(1, 30):
    merges.append("m%d: &m%d {<<: [%s], k%d: v}" % (i, i, ", ".join(["*m%d" % (i - 1)] * 4), i))
put("v11-merge-bomb-30", "\n".join(merges) + "\n")
put("v11-merge-wide-1000", "base: &b {%s}\n%s" % (", ".join("k%d: %d" % (i, i) for i in range(1000)),
    "".join("m%d: {<<: *b}\n" % i for i in range(1000))))
put("v11-merge-self", "a: &a {x: 1}\nb: &b {<<: *a, <<: *b}\n")
put("v11-merge-chain-50", "".join("m%d: &m%d {<<: %s, k%d: v}\n" % (i, i, "{}" if i == 0 else "*m%d" % (i - 1), i) for i in range(50)))

# Nesting: at the depth limit it loads; past it, it is refused at once.
for n in (256, 100000):
    put("deep-flow-seq-%d" % n, "[" * n + "]" * n)
    put("deep-flow-map-%d" % n, "{a: " * n + "1" + "}" * n)
    put("deep-block-seq-%d" % n, "- " * n + "x\n")
    put("deep-mixed-%d" % n, "[{a: " * (n // 2) + "x" + "}]" * (n // 2))
put("v11-deep-merge-200", "".join("m%d: &m%d {<<: %s}\n" % (i, i, "{a: 1}" if i == 0 else "[*m%d, {b: 2}]" % (i - 1)) for i in range(200)))
put("deep-block-map-256", "".join(" " * i + "a:\n" for i in range(256)) + " " * 256 + "x\n")
put("deep-block-map-1400", "".join(" " * i + "a:\n" for i in range(1400)) + " " * 1400 + "x\n")

for n in sizes:
    put("long-plain-%d" % n, "a" * n)
    put("long-decimal-%d" % n, "1" * n)
    put("long-negative-%d" % n, "-" + "0" * (n - 2) + "7")
    put("v11-long-decimal-%d" % n, "1" + "_1" * ((n - 1) // 2))
    put("many-colons-%d" % n, "a:" * (n // 2 - 1) + "a")
    put("many-dashes-%d" % n, "a- " * (n // 3))
    put("quotes-double-%d" % n, '"' + '\\"' * (n // 2 - 1) + '"')
    put("quotes-single-%d" % n, "'" + "''" * (n // 2 - 1) + "'")
    put("quotes-many-%d" % n, lines(n, lambda i: "- 'a''b'\n- \"c\\\"d\"\n"))
    put("escapes-%d" % n, '"' + "\\u00e9\\x41\\t" * (n // 12 - 1) + '"')
    put("giant-explicit-key-%d" % n, "? " + "k" * (n - 10) + "\n: v\n")
    put("giant-float-%d" % n, "1." + "5" * (n - 2))
    put("giant-exponent-%d" % n, "1.5e" + "9" * (n - 4))
    put("v11-giant-float-%d" % n, "1_0." + "5" * (n - 4))
    put("long-comment-%d" % n, "# " + "c" * (n - 10) + "\na: 1\n")
    put("long-anchor-%d" % n, "&" + "a" * (n - 4) + " x\n")
    put("long-tag-%d" % n, "!" + "t" * (n - 4) + " x\n")
    put("long-uri-tag-%d" % n, "!<" + "%41" * ((n - 6) // 3) + "> x\n")
    put("folded-lines-%d" % n, lines(n, lambda i: " line\n", ">\n"))
    put("flat-map-%d" % n, lines(n, lambda i: "k%d: %d\n" % (i, i)))
    put("prefix-keys-%d" % n, lines(n, lambda i: "%s%d: %d\n" % ("p" * 1000, i, i)))
    anchors = lines(n // 2, lambda i: "- &a%d %d\n" % (i, i))
    count = anchors.count("&")
    put("many-anchors-%d" % n, anchors + lines(n - len(anchors), lambda i: "- *a%d\n" % (i % count)))
    put("dup-giant-key-%d" % n, ("? " + "k" * (n // 2 - 10) + "\n: 1\n") * 2)
    put("many-docs-%d" % n, lines(n, lambda i: "---\na: 1\n"))
    put("giant-simple-key-%d" % n, "k" * (n - 4) + ": v\n")
    put("deep-then-wide-line-%d" % n, "[" * 200 + "a," * ((n - 400) // 2) + "]" * 200)
    put("deep-then-wide-lines-%d" % n, "[" * 200 + "\n" + "a,\n" * ((n - 402) // 3) + "]" * 200)
    put("flow-many-%d" % n, "[" + lines(n - 2, lambda i: "{k: %d}, " % i) + "]")
    put("flow-keys-%d" % n, "{" + lines(n - 2, lambda i: "k%d: [a, b], " % i) + "}")
    put("chain-keys-%d" % n, lines(n, lambda i: "? %s\n: %d\n" % ("k" * (i + 1), i)))
    put("dup-keys-late-%d" % n, lines(n - 10, lambda i: "k%d: %d\n" % (i, i)) + "k0: dup\n")

# Numbers in other bases: at the digits limit they load; past it, refused.
for n in (1000, 1000000):
    put("long-hex-%d" % n, "0x" + "f" * (n - 2))
    put("long-octal-%d" % n, "0o" + "7" * (n - 2))
    put("v11-long-binary-%d" % n, "0b" + "1" * (n - 2))
    put("v11-long-octal-%d" % n, "0" + "7" * (n - 1))
    put("v11-base60-parts-%d" % n, "1" + ":30" * ((n - 1) // 3))
    put("v11-base60-float-%d" % n, "1" + ":30" * ((n - 4) // 3) + ".5")
    put("quoted-hex-%d" % n, "'0x" + "f" * (n - 4) + "'")

# Past the size limit, the text is refused before it is read.
put("oversize-1048577", "a" * 1048577)
put("oversize-16777216", "a" * 16777216)

# Encodings: invalid UTF-8 is read as U+FFFD; NUL and other controls are
# refused; a BOM is allowed only at the start.
put("utf8-invalid-byte", b"a: \xff\xfe\n")
put("utf8-surrogate", b"a: \xed\xa0\x80\n")
put("utf8-overlong", b"a: \xc0\xaf\n")
put("utf8-truncated", b"a: \xe2\x82\n")
put("nul-byte", b"a: b\x00c\n")
put("bom-twice", "\ufeff\ufeffa: 1\n")
put("bom-inside", "a: \ufeffb\n")
put("bom-each-doc", "\ufeffa: 1\n...\n\ufeff--- b\n")
put("utf16-bom", "\ufeffa: 1\n".encode("utf-16"))

# Tags that other libraries turn into objects are only data here.
put("object-tags", "- !ruby/object:Gem::Installer {i: x}\n- !!python/object/apply:os.system [id]\n"
    "- !!javax.script.ScriptEngineManager [!!java.net.URLClassLoader [[!!java.net.URL [\"http://x\"]]]]\n"
    "- !<tag:yaml.org,2002:python/name:os.system> ''\n")
