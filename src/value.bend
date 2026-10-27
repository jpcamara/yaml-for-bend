# A YAML value: what a document holds once its scalars are resolved.

import Base

# A value. An integer is its decimal text ("-26"), so any size fits. A float
# is decimal text too, since Bend has no 64-bit floats: as written under the
# Core schema ("1e3", "+.5"), and exact under YAML 1.1 ("1_000.50" is
# "1000.5"); infinity and NaN are ".inf", "-.inf" and ".nan". A mapping keeps its entries in order.
# Tagged is a value whose tag the schema doesn't resolve: "!point", or
# "tag:yaml.org,2002:binary".
type Yaml is Data:
  Null{}
  Boolean{on: Bool}
  Int{text: String}
  Float{text: String}
  Str{text: String}
  Seq{items: List<&2, Yaml>}
  Mapping{entries: List<&2, Entry>}
  Tagged{tag: String, val: Yaml}

type Entry is Data:
  Entry{key: Yaml, val: Yaml}

def same.bool(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}:
      b
    case False{}:
      Bool.not(b)

# Whether two values are the same: same kinds, same texts, same items and
# entries in the same order.
def eq(a: Yaml, b: Yaml) -> Bool:
  match a:
    case Null{}:
      match b:
        case Null{}:
          True{}
        case _:
          False{}
    case Boolean{x}:
      match b:
        case Boolean{y}:
          same.bool(x, y)
        case _:
          False{}
    case Int{x}:
      match b:
        case Int{y}:
          String.eq(x, y)
        case _:
          False{}
    case Float{x}:
      match b:
        case Float{y}:
          String.eq(x, y)
        case _:
          False{}
    case Str{x}:
      match b:
        case Str{y}:
          String.eq(x, y)
        case _:
          False{}
    case Seq{xs}:
      match xs:
        case Nil{}:
          match b:
            case Seq{ys}:
              List.is_empty(&2, Yaml, ys)
            case _:
              False{}
        case Con{x, xt}:
          match b:
            case Seq{ys}:
              match ys:
                case Nil{}:
                  False{}
                case Con{y, yt}:
                  Bool.and(eq(x, y), eq(Seq{xt}, Seq{yt}))
            case _:
              False{}
    case Mapping{xs}:
      match xs:
        case Nil{}:
          match b:
            case Mapping{ys}:
              List.is_empty(&2, Entry, ys)
            case _:
              False{}
        case Con{Entry{xk, xv}, xt}:
          match b:
            case Mapping{ys}:
              match ys:
                case Nil{}:
                  False{}
                case Con{Entry{yk, yv}, yt}:
                  Bool.and(Bool.and(eq(xk, yk), eq(xv, yv)), eq(Mapping{xt}, Mapping{yt}))
            case _:
              False{}
    case Tagged{s, x}:
      match b:
        case Tagged{t, y}:
          Bool.and(String.eq(s, t), eq(x, y))
        case _:
          False{}

# A value as text that two values share only when they are the same, to
# look keys up by. A string is its length and text; "[" goes before each
# item of a sequence and "]" after them, and "{" before each entry of a
# mapping and "}" after them.
def canon(v: Yaml) -> String:
  match v:
    case Null{}:
      "~"
    case Boolean{on}:
      Bool.pick(String, on, "t", "f")
    case Int{t}:
      "i" ++ t ++ ";"
    case Float{t}:
      "d" ++ t ++ ";"
    case Str{+t}:
      "s" ++ Nat.show(String.length(t)) ++ ":" ++ t
    case Seq{xs}:
      match xs:
        case Nil{}:
          "]"
        case Con{x, rest}:
          "[" ++ canon(x) ++ canon(Seq{rest})
    case Mapping{es}:
      match es:
        case Nil{}:
          "}"
        case Con{Entry{k, x}, rest}:
          "{" ++ canon(k) ++ canon(x) ++ canon(Mapping{rest})
    case Tagged{+tag, x}:
      "!" ++ Nat.show(String.length(tag)) ++ ":" ++ tag ++ canon(x)

def get.hit(hit: Bool, v: Yaml, more: Unit -> Maybe<&2, Yaml>) -> Maybe<&2, Yaml>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      more(Unit{})

def is_text(k: Yaml, +key: String) -> Bool:
  match k:
    case Str{t}:
      String.eq(t, key)
    case _:
      False{}

def get.go(es: List<&2, Entry>, +key: String) -> Maybe<&2, Yaml>:
  match es:
    case Nil{}:
      None{}
    case Con{e, rest}:
      match e:
        case Entry{k, v}:
          get.hit(is_text(k, key), v, u => get.go(rest, key))

# The value under the string key +key+, if +v+ is a mapping that has it.
def get(v: Yaml, key: String) -> Maybe<&2, Yaml>:
  match v:
    case Mapping{es}:
      get.go(es, key)
    case _:
      None{}

def find.go(es: List<&2, Entry>, +key: Yaml) -> Maybe<&2, Yaml>:
  match es:
    case Nil{}:
      None{}
    case Con{e, rest}:
      match e:
        case Entry{k, v}:
          get.hit(eq(k, key), v, u => find.go(rest, key))

# The value under any key: get(v, "a") is find(v, Str{"a"}).
def find(v: Yaml, key: Yaml) -> Maybe<&2, Yaml>:
  match v:
    case Mapping{es}:
      find.go(es, key)
    case _:
      None{}

# The value under +key+, or null.
def at(v: Yaml, key: String) -> Yaml:
  Maybe.default(&2, Yaml, get(v, key), Null{})

def items(v: Yaml) -> List<&2, Yaml>:
  match v:
    case Seq{xs}:
      xs
    case _:
      []

def entries(v: Yaml) -> List<&2, Entry>:
  match v:
    case Mapping{es}:
      es
    case _:
      []

def keys.go(es: List<&2, Entry>) -> List<&2, Yaml>:
  match es:
    case Nil{}:
      []
    case Con{e, rest}:
      match e:
        case Entry{k, v}:
          k <> keys.go(rest)

def keys(v: Yaml) -> List<&2, Yaml>:
  keys.go(entries(v))

# A string's text.
def text(v: Yaml) -> Maybe<&2, String>:
  match v:
    case Str{t}:
      Some{t}
    case _:
      None{}

def is_null(v: Yaml) -> Bool:
  match v:
    case Null{}:
      True{}
    case _:
      False{}

# JSON
# ----

def hex.digit(+n: Nat) -> Char:
  Chr{U32.from_nat(Bool.pick(Nat, Nat.is_lt(n, 10n), Nat.add(n, 48n), Nat.add(n, 87n)))}

def json.char(c: Char) -> String:
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
    case Chr{+x}:
      Bool.pick(String, U32.is_lt(x, 32), "\\u00" ++ SCon{hex.digit(U32.to_nat(U32.div(x, 16))), SCon{hex.digit(U32.to_nat(U32.mod(x, 16))), SNil{}}},
        SCon{Chr{x}, SNil{}})

def json.chars(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      json.char(c) ++ json.chars(t)

# A JSON string.
def json.str(s: String) -> String:
  "\"" ++ json.chars(s) ++ "\""

def zero.point(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      match c:
        case '.':
          match t:
            case SNil{}:
              ".0"
            case SCon{+d, +u}:
              Bool.pick(String, Char.is_digit(d), SCon{'.', SCon{d, u}}, ".0" ++ SCon{d, u})
        case _:
          SCon{c, zero.point(t)}

# A float in JSON's form: "+.5e3" is 0.5e3; infinity and NaN stay as YAML
# writes them, since JSON has no word for them.
def json.float(+t: String) -> String:
  +neg = String.starts_with(t, "-")
  +body = Bool.pick(String, Bool.or(neg, String.starts_with(t, "+")), String.drop(t, 1n), t)
  Bool.pick(String, String.starts_with(body, "."), Bool.pick(String, Char.is_digit(Maybe.default(&2, Char, String.get(body, 1n), ' ')), Bool.pick(String, neg, "-0", "0") ++ zero.point(body), t),
    Bool.pick(String, neg, "-", "") ++ zero.point(body))

# A key's JSON: a string as it is, anything else as a string of its JSON.
def key.json(str: Bool, +text: String) -> String:
  match str:
    case True{}:
      text
    case False{}:
      json.str(text)

def is_str(v: Yaml) -> Bool:
  match v:
    case Str{t}:
      True{}
    case _:
      False{}

def json.go(v: Yaml, +first: Bool) -> String:
  match v:
    case Null{}:
      "null"
    case Boolean{on}:
      Bool.pick(String, on, "true", "false")
    case Int{t}:
      t
    case Float{t}:
      json.float(t)
    case Str{t}:
      json.str(t)
    case Seq{xs}:
      match xs:
        case Nil{}:
          Bool.pick(String, first, "[]", "]")
        case Con{x, rest}:
          Bool.pick(String, first, "[", ",") ++ json.go(x, True{}) ++ json.go(Seq{rest}, False{})
    case Mapping{es}:
      match es:
        case Nil{}:
          Bool.pick(String, first, "{}", "}")
        case Con{Entry{+k, x}, rest}:
          Bool.pick(String, first, "{", ",") ++ key.json(is_str(k), json.go(k, True{})) ++ ":" ++ json.go(x, True{}) ++ json.go(Mapping{rest}, False{})
    case Tagged{tag, x}:
      json.go(x, True{})

# A value as JSON text, on one line. A key that isn't a string is written
# as a string of its JSON, and a tag is dropped.
def json(v: Yaml) -> String:
  json.go(v, True{})
