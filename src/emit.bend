# The emitter: values to YAML text, in block style, indented two spaces.
#
# A string is plain when the Core schema reads it back as that string, and
# double-quoted otherwise. A sequence or mapping inside a sequence starts on
# the "- " line ("- - a", "- a: 1"). A key that is a collection is written
# after "? ". An empty collection is "[]" or "{}". A tag the schema knows
# is written "!!int", one starting "!" as it is, and any other "!<...>".
# load(dump(v)) is v for any value load returns.

import Base

import ./value.bend as V

import ./core.bend as C

# Where a node is written: at the start of a line, right after "- ", right
# after a key's ":" (or a tag), or as the later items of a collection, each
# on a line of its own.
type Pos is Data:
  Line{}
  Dash{}
  Colon{}
  More{}

def when(-A: Type, hit: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match hit:
    case True{}:
      yes(Unit{})
    case False{}:
      no(Unit{})

def code(c: Char) -> U32:
  match c:
    case Chr{x}:
      x

def is_in(c: Char, s: String) -> Bool:
  String.contains(s, SCon{c, SNil{}})

# Quoting
# -------

def hex.digit(+n: Nat) -> Char:
  Chr{U32.from_nat(Bool.pick(Nat, Nat.is_lt(n, 10n), Nat.add(n, 48n), Nat.add(n, 55n)))}

# +n+ in +width+ hex digits.
def hex.text(width: Nat, +n: Nat) -> String:
  match width:
    case 0n:
      ""
    case 1n+k:
      hex.text(k, Nat.div(n, 16n)) ++ SCon{hex.digit(Nat.mod(n, 16n)), SNil{}}

# What YAML may hold as it is: printable characters but the ones double
# quotes escape.
def is_plain.char(+x: U32) -> Bool:
  Bool.or(Bool.and(U32.is_ge(x, 32), U32.is_le(x, 126)),
    Bool.or(Bool.and(U32.is_ge(x, 160), U32.is_le(x, 55295)), Bool.or(Bool.and(U32.is_ge(x, 57344), U32.is_le(x, 65533)), U32.is_ge(x, 65536))))

def escape.other(c: Char) -> String:
  match c:
    case Chr{+x}:
      +n = U32.to_nat(x)
      Bool.pick(String, U32.is_eq(x, 133), "\\N",
        Bool.pick(String, U32.is_eq(x, 8232), "\\L",
          Bool.pick(String, U32.is_eq(x, 8233), "\\P",
            Bool.pick(String, is_plain.char(x), SCon{Chr{x}, SNil{}},
              Bool.pick(String, Nat.is_lt(n, 256n), "\\x" ++ hex.text(2n, n), "\\u" ++ hex.text(4n, n))))))

def escape(c: Char) -> String:
  match c:
    case '"':
      "\\\""
    case '\\':
      "\\\\"
    case '\n':
      "\\n"
    case '\t':
      "\\t"
    case '\r':
      "\\r"
    case _:
      escape.other(c)

def escaped(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      escape(c) ++ escaped(t)

def quoted(s: String) -> String:
  "\"" ++ escaped(s) ++ "\""

def all.plain(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(is_plain.char(code(c)), all.plain(t))

def last.char(s: String) -> Char:
  Maybe.default(&2, Char, String.get(String.reverse(s), 0n), ' ')

def first.char(s: String) -> Char:
  Maybe.default(&2, Char, String.get(s, 0n), ' ')

def is_str(v: V.Yaml) -> Bool:
  match v:
    case V.Str{t}:
      True{}
    case _:
      False{}

# Whether +s+ reads back as itself when written plain: it isn't empty, has
# no blank at either end, starts with no indicator, holds no ": ", " #" or
# character that needs escaping, and the Core schema reads it as a string.
def is_safe.plain(+s: String) -> Bool:
  Bool.and(Bool.and(Bool.not(String.is_empty(s)), all.plain(s)),
    Bool.and(Bool.and(Bool.not(is_in(first.char(s), " -?:,[]{}#&*!|>'\"%@`")), Bool.not(Char.is_eq(last.char(s), ' '))),
      Bool.and(Bool.and(Bool.not(String.contains(s, ": ")), Bool.not(String.contains(s, " #"))),
        Bool.and(Bool.not(String.ends_with(s, ":")), is_str(C.plain(s))))))

def str.text(+s: String) -> String:
  when(String, is_safe.plain(s), u => s, u => quoted(s))

def tag.text(+tag: String) -> String:
  +core = {"tag:yaml.org,2002:" : String}
  Bool.pick(String, String.starts_with(tag, core), "!!" ++ String.drop(tag, String.length(core)),
    Bool.pick(String, Bool.and(String.starts_with(tag, "!"), Bool.not(String.contains(tag, " "))), tag, "!<" ++ tag ++ ">"))

def spaces(n: Nat) -> String:
  String.repeat(" ", n)

# What goes before a node's first line: indentation at a line's start, a
# break and indentation after a key, nothing after "- ".
def lead(p: Pos, +ind: Nat) -> String:
  match p:
    case Line{}:
      spaces(ind)
    case Dash{}:
      ""
    case Colon{}:
      "\n" ++ spaces(ind)
    case More{}:
      spaces(ind)

# A scalar after its key gets a space; at a line's start, indentation.
def scalar.lead(p: Pos, +ind: Nat) -> String:
  match p:
    case Line{}:
      spaces(ind)
    case Dash{}:
      ""
    case Colon{}:
      " "
    case More{}:
      spaces(ind)

def is_more(p: Pos) -> Bool:
  match p:
    case More{}:
      True{}
    case _:
      False{}

def is_collection(v: V.Yaml) -> Bool:
  match v:
    case V.Seq{xs}:
      Bool.not(List.is_empty(&2, V.Yaml, xs))
    case V.Mapping{es}:
      Bool.not(List.is_empty(&2, V.Entry, es))
    case _:
      False{}

# A scalar's text, or an empty collection's.
def scalar.text(v: V.Yaml) -> String:
  match v:
    case V.Null{}:
      "null"
    case V.Boolean{on}:
      Bool.pick(String, on, "true", "false")
    case V.Int{t}:
      t
    case V.Float{t}:
      t
    case V.Str{t}:
      str.text(t)
    case V.Seq{xs}:
      "[]"
    case V.Mapping{es}:
      "{}"
    case V.Tagged{t, x}:
      ""

def is_tagged(v: V.Yaml) -> Bool:
  match v:
    case V.Tagged{t, x}:
      True{}
    case _:
      False{}

# +v+ written at +p+, its lines indented +ind+.
def emit(v: V.Yaml, +ind: Nat, +p: Pos) -> String:
  match v:
    case V.Seq{xs}:
      match xs:
        case Nil{}:
          Bool.pick(String, is_more(p), "", scalar.lead(p, ind) ++ "[]\n")
        case Con{x, rest}:
          lead(p, ind) ++ "- " ++ emit(x, Nat.add(ind, 2n), Dash{}) ++ emit(V.Seq{rest}, ind, More{})
    case V.Mapping{es}:
      match es:
        case Nil{}:
          Bool.pick(String, is_more(p), "", scalar.lead(p, ind) ++ "{}\n")
        case Con{V.Entry{+k, x}, rest}:
          when(String, is_collection(k) || is_tagged(k),
            u => lead(p, ind) ++ "? " ++ emit(k, Nat.add(ind, 2n), Dash{}) ++ spaces(ind) ++ ":",
            u => lead(p, ind) ++ scalar.text(k) ++ ":") ++
          emit(x, Nat.add(ind, 2n), Colon{}) ++ emit(V.Mapping{rest}, ind, More{})
    case V.Tagged{+tag, +x}:
      scalar.lead(p, ind) ++ tag.text(tag) ++ Bool.pick(String, is_collection(x), "", " ") ++
        emit(x, ind, Bool.pick(Pos, is_collection(x), Colon{}, Dash{}))
    case _:
      scalar.lead(p, ind) ++ scalar.text(v) ++ "\n"

# +v+ as a YAML document.
def dump(v: V.Yaml) -> String:
  emit(v, 0n, Line{})

# Values as a stream of documents, each after "---".
def dump.all(vs: List<&2, V.Yaml>) -> String:
  match vs:
    case Nil{}:
      ""
    case Con{v, rest}:
      "---\n" ++ dump(v) ++ dump.all(rest)
