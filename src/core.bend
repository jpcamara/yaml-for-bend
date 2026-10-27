# The YAML 1.2 Core schema: how a scalar's text and tag become a value.
#
# An untagged plain scalar is null (null, Null, NULL, ~ or nothing), a
# boolean (true/True/TRUE, false/False/FALSE), an integer (decimal, 0o
# octal, 0x hex), a float (decimal, .inf, -.inf, .nan) or else a string.
# A quoted or block scalar, or one tagged "!", is a string. A standard tag
# (!!str, !!null, !!bool, !!int, !!float) reads the text as that type, and
# fails when it can't; any other tag is kept as a Tagged value.

import Base

import ./value.bend as V

import ./re.bend as R

import ./num.bend as N

def yaml.tag(name: String) -> String:
  "tag:yaml.org,2002:" ++ name

def when(-A: Type, hit: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match hit:
    case True{}:
      yes(Unit{})
    case False{}:
      no(Unit{})

def is_null(+s: String) -> Bool:
  Bool.or(Bool.or(String.is_empty(s), String.eq(s, "~")), Bool.or(String.eq(s, "null"), Bool.or(String.eq(s, "Null"), String.eq(s, "NULL"))))

def is_true(+s: String) -> Bool:
  Bool.or(String.eq(s, "true"), Bool.or(String.eq(s, "True"), String.eq(s, "TRUE")))

def is_false(+s: String) -> Bool:
  Bool.or(String.eq(s, "false"), Bool.or(String.eq(s, "False"), String.eq(s, "FALSE")))

def dec.pat() -> List<&2, R.Pat>:
  [R.sign(), R.digits()]

def oct.pat() -> List<&2, R.Pat>:
  [R.c('0'), R.c('o'), R.Plus{R.One{R.Range{'0', '7'}}}]

def hex.pat() -> List<&2, R.Pat>:
  [R.c('0'), R.c('x'), R.Plus{R.One{R.Hex{}}}]

# [-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?
def float.pat() -> List<&2, R.Pat>:
  [R.sign(), R.Alt{[[R.c('.'), R.digits()], [R.digits(), R.Opt{R.seq([R.c('.'), R.Star{R.digit()}])}]]},
   R.Opt{R.seq([R.of("eE"), R.sign(), R.digits()])}]

def is_inf(+s: String) -> Bool:
  Bool.or(String.eq(s, ".inf"), Bool.or(String.eq(s, ".Inf"), String.eq(s, ".INF")))

def is_nan(+s: String) -> Bool:
  Bool.or(String.eq(s, ".nan"), Bool.or(String.eq(s, ".NaN"), String.eq(s, ".NAN")))

def unsigned(s: String) -> String:
  match s:
    case SCon{c, t}:
      match c:
        case '-':
          t
        case '+':
          t
        case _:
          SCon{c, t}
    case SNil{}:
      ""

def is_neg(s: String) -> Bool:
  String.starts_with(s, "-")

# An integer's decimal text, if +s+ is one.
def int.of(+s: String) -> Maybe<&2, String>:
  when(Maybe<&2, String>, R.matches(dec.pat(), s), u => Some{N.int.text(is_neg(s), unsigned(s), 10n)},
    u => when(Maybe<&2, String>, R.matches(oct.pat(), s), u => Some{N.int.text(False{}, String.drop(s, 2n), 8n)},
      u => when(Maybe<&2, String>, R.matches(hex.pat(), s), u => Some{N.int.text(False{}, String.drop(s, 2n), 16n)}, u => None{})))

# A float's text, if +s+ is one: as written, or ".inf", "-.inf", ".nan".
def float.of(+s: String) -> Maybe<&2, String>:
  +u = unsigned(s)
  Bool.pick(Maybe<&2, String>, is_inf(u), Some{Bool.pick(String, is_neg(s), "-.inf", ".inf")},
    Bool.pick(Maybe<&2, String>, is_nan(s), Some{".nan"},
      Bool.pick(Maybe<&2, String>, R.matches(float.pat(), s), Some{s}, None{})))

def or.int(m: Maybe<&2, String>, s: String, rest: Unit -> V.Yaml) -> V.Yaml:
  match m:
    case Some{t}:
      V.Int{t}
    case None{}:
      rest(Unit{})

def or.float(m: Maybe<&2, String>, rest: Unit -> V.Yaml) -> V.Yaml:
  match m:
    case Some{t}:
      V.Float{t}
    case None{}:
      rest(Unit{})

# An untagged plain scalar.
def plain(+s: String) -> V.Yaml:
  when(V.Yaml, is_null(s), u => V.Null{},
    u => when(V.Yaml, is_true(s), u => V.Boolean{True{}},
      u => when(V.Yaml, is_false(s), u => V.Boolean{False{}},
        u => or.int(int.of(s), s, u => or.float(float.of(s), u => V.Str{s})))))

def must(m: Maybe<&2, V.Yaml>, +tag: String, +s: String) -> Result<&2, &2, String, V.Yaml>:
  match m:
    case Some{v}:
      Done{v}
    case None{}:
      Fail{"found a value that isn't a " ++ tag ++ ": " ++ s}

def int.yaml(m: Maybe<&2, String>) -> Maybe<&2, V.Yaml>:
  match m:
    case Some{t}:
      Some{V.Int{t}}
    case None{}:
      None{}

# !!float: a float, or an integer written as one ("3" is 3.0).
def float.yaml(m: Maybe<&2, String>, i: Maybe<&2, String>) -> Maybe<&2, V.Yaml>:
  match m:
    case Some{t}:
      Some{V.Float{t}}
    case None{}:
      match i:
        case Some{t}:
          Some{V.Float{t ++ ".0"}}
        case None{}:
          None{}

# A scalar with a tag: !!str, !!null, !!bool, !!int and !!float read the
# text; "!" is a string; another tag is kept.
def tagged(+tag: String, +s: String) -> Result<&2, &2, String, V.Yaml>:
  when(Result<&2, &2, String, V.Yaml>, Bool.or(String.eq(tag, "!"), String.eq(tag, yaml.tag("str"))), u => Done{V.Str{s}},
    u => when(Result<&2, &2, String, V.Yaml>, String.eq(tag, yaml.tag("null")), u => must(Bool.pick(Maybe<&2, V.Yaml>, is_null(s), Some{V.Null{}}, None{}), "!!null", s),
      u => when(Result<&2, &2, String, V.Yaml>, String.eq(tag, yaml.tag("bool")),
        u => must(Bool.pick(Maybe<&2, V.Yaml>, is_true(s), Some{V.Boolean{True{}}}, Bool.pick(Maybe<&2, V.Yaml>, is_false(s), Some{V.Boolean{False{}}}, None{})), "!!bool", s),
        u => when(Result<&2, &2, String, V.Yaml>, String.eq(tag, yaml.tag("int")), u => must(int.yaml(int.of(s)), "!!int", s),
          u => when(Result<&2, &2, String, V.Yaml>, String.eq(tag, yaml.tag("float")), u => must(float.yaml(float.of(s), int.of(s)), "!!float", s),
            u => Done{V.Tagged{tag, V.Str{s}}})))))

# A collection with a tag: "!", !!seq and !!map are plain; another is kept.
def collection(+tag: String, +v: V.Yaml) -> V.Yaml:
  Bool.pick(V.Yaml, Bool.or(String.eq(tag, "!"), Bool.or(String.eq(tag, yaml.tag("seq")), String.eq(tag, yaml.tag("map")))), v, V.Tagged{tag, v})
