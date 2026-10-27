# The YAML 1.1 types (yaml.org/type), for YAML written for 1.1 parsers.
#
# An untagged plain scalar is null (~, null, Null, NULL or nothing), a
# boolean (yes, no, true, false, on, off, each lowercase, capitalized or
# uppercase), an integer (decimal, 0b binary, 0 octal, 0x hex, or base 60
# as in 1:30:00, with "_" anywhere among the digits), a float (decimal,
# base 60 with a fraction, .inf, -.inf, .nan), a timestamp, or a string.
# A timestamp is Tagged{"tag:yaml.org,2002:timestamp", Str{text}}, the text
# as written. "<<" is the merge key, which the composer handles.
#
# y, Y, n and N are strings, as in most 1.1 parsers, though the 1.1 type
# list has them as booleans.

import Base

import ./value.bend as V

import ./re.bend as R

import ./num.bend as N

import ./core.bend as C

def when(-A: Type, hit: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match hit:
    case True{}:
      yes(Unit{})
    case False{}:
      no(Unit{})

def timestamp() -> String:
  C.yaml.tag("timestamp")

def is_true(+s: String) -> Bool:
  List.contains(~String, ~String.eq, ["yes", "Yes", "YES", "true", "True", "TRUE", "on", "On", "ON"], s)

def is_false(+s: String) -> Bool:
  List.contains(~String, ~String.eq, ["no", "No", "NO", "false", "False", "FALSE", "off", "Off", "OFF"], s)

# Patterns
# --------

def d() -> R.Pat:
  R.digit()

def digits_() -> R.Pat:
  R.Star{R.of("0123456789_")}

def bin.pat() -> List<&2, R.Pat>:
  [R.sign(), R.c('0'), R.c('b'), R.Plus{R.of("01_")}]

def oct.pat() -> List<&2, R.Pat>:
  [R.sign(), R.c('0'), R.Plus{R.of("01234567_")}]

def dec.pat() -> List<&2, R.Pat>:
  [R.sign(), R.Alt{[[R.c('0')], [R.One{R.Range{'1', '9'}}, digits_()]]}]

def hex.pat() -> List<&2, R.Pat>:
  [R.sign(), R.c('0'), R.c('x'), R.Plus{R.Alt{[[R.One{R.Hex{}}], [R.c('_')]]}}]

def sexa.part() -> R.Pat:
  R.seq([R.c(':'), R.Opt{R.One{R.Range{'0', '5'}}}, d()])

def sexa.int.pat() -> List<&2, R.Pat>:
  [R.sign(), R.One{R.Range{'1', '9'}}, digits_(), R.Plus{sexa.part()}]

def float.pat() -> List<&2, R.Pat>:
  [R.sign(), R.Opt{R.seq([d(), digits_()])}, R.c('.'), digits_(), R.Opt{R.seq([R.of("eE"), R.of("-+"), R.digits()])}]

def sexa.float.pat() -> List<&2, R.Pat>:
  [R.sign(), d(), digits_(), R.Plus{sexa.part()}, R.c('.'), digits_()]

def ymd.pat() -> List<&2, R.Pat>:
  [d(), d(), d(), d(), R.c('-'), d(), d(), R.c('-'), d(), d()]

def blank() -> R.Pat:
  R.of(" \t")

def time.pat() -> List<&2, R.Pat>:
  [d(), d(), d(), d(), R.c('-'), d(), R.Opt{d()}, R.c('-'), d(), R.Opt{d()},
   R.Alt{[[R.of("Tt")], [R.Plus{blank()}]]}, d(), R.Opt{d()}, R.c(':'), d(), d(), R.c(':'), d(), d(),
   R.Opt{R.seq([R.c('.'), R.Star{d()}])},
   R.Opt{R.seq([R.Star{blank()}, R.Alt{[[R.c('Z')], [R.of("-+"), d(), R.Opt{d()}, R.Opt{R.seq([R.c(':'), d(), d()])}]]}])}]

def is_timestamp(+s: String) -> Bool:
  Bool.or(R.matches(ymd.pat(), s), R.matches(time.pat(), s))

# Values
# ------

def no.seps(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      match c:
        case '_':
          no.seps(t)
        case _:
          SCon{c, no.seps(t)}

def has_digit(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+c, t}:
      Bool.or(Char.is_digit(c), has_digit(t))

# Base 60: each part is the next digit, "1:30" is 90.
def sexa.go(parts: List<&2, String>, acc: List<&2, Nat>) -> List<&2, Nat>:
  match parts:
    case Nil{}:
      acc
    case Con{p, rest}:
      sexa.go(rest, N.big.mul.add(acc, 60n, N.big.small(p, 0n)))

def sexa.big(parts: List<&2, String>) -> List<&2, Nat>:
  match parts:
    case Nil{}:
      []
    case Con{p, rest}:
      sexa.go(rest, N.big.read(p, 10n, []))

def int.of.digits(+ds: String) -> String:
  when(String, String.starts_with(ds, "0b"), u => N.big.show(N.big.read(String.drop(ds, 2n), 2n, [])),
    u => when(String, String.starts_with(ds, "0x"), u => N.big.show(N.big.read(String.drop(ds, 2n), 16n, [])),
      u => when(String, String.contains(ds, ":"), u => N.big.show(sexa.big(String.split(ds, ':'))),
        u => when(String, String.starts_with(ds, "0"), u => N.big.show(N.big.read(ds, 8n, [])), u => N.big.show(N.big.read(ds, 10n, []))))))

# An integer's decimal text; +s+ already matched one of the integer forms.
def int.text(+s: String) -> String:
  +t = no.seps(s)
  N.signed(C.is_neg(t), int.of.digits(C.unsigned(t)))

def is_int(+s: String) -> Bool:
  Bool.or(Bool.or(R.matches(dec.pat(), s), R.matches(oct.pat(), s)),
    Bool.or(Bool.or(R.matches(hex.pat(), s), R.matches(bin.pat(), s)), R.matches(sexa.int.pat(), s)))

def before.dot(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      match c:
        case '.':
          ""
        case _:
          SCon{c, before.dot(t)}

def after.dot(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      match c:
        case '.':
          t
        case _:
          after.dot(t)

# A base-60 float: the whole part in base 60, then the fraction.
def sexa.float(+s: String) -> String:
  +t = no.seps(s)
  +body = C.unsigned(t)
  N.dec.exact(Bool.pick(String, C.is_neg(t), "-", "") ++ N.big.show(sexa.big(String.split(before.dot(body), ':'))) ++ "." ++ after.dot(body))

def float.of(+s: String) -> Maybe<&2, String>:
  +body = C.unsigned(s)
  when(Maybe<&2, String>, C.is_inf(body), u => Some{Bool.pick(String, C.is_neg(s), "-.inf", ".inf")},
    u => when(Maybe<&2, String>, C.is_nan(s), u => Some{".nan"},
      u => when(Maybe<&2, String>, Bool.and(R.matches(float.pat(), s), has_digit(s)), u => Some{N.dec.exact(no.seps(s))},
        u => when(Maybe<&2, String>, R.matches(sexa.float.pat(), s), u => Some{sexa.float(s)}, u => None{}))))

def int.of(+s: String) -> Maybe<&2, String>:
  when(Maybe<&2, String>, is_int(s), u => Some{int.text(s)}, u => None{})

def or.int(m: Maybe<&2, String>, rest: Unit -> V.Yaml) -> V.Yaml:
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
  when(V.Yaml, C.is_null(s), u => V.Null{},
    u => when(V.Yaml, is_true(s), u => V.Boolean{True{}},
      u => when(V.Yaml, is_false(s), u => V.Boolean{False{}},
        u => or.int(int.of(s), u => or.float(float.of(s),
          u => when(V.Yaml, is_timestamp(s), u => V.Tagged{timestamp(), V.Str{s}}, u => V.Str{s}))))))

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
          Some{V.Float{N.dec.exact(t)}}
        case None{}:
          None{}

def bool.yaml(+s: String) -> Maybe<&2, V.Yaml>:
  Bool.pick(Maybe<&2, V.Yaml>, is_true(s), Some{V.Boolean{True{}}}, Bool.pick(Maybe<&2, V.Yaml>, is_false(s), Some{V.Boolean{False{}}}, None{}))

# A scalar with a tag: the standard types read the text in their 1.1 forms,
# !!merge is the merge key, "!" is a string; another tag is kept.
def tagged(+tag: String, +s: String) -> Result<&2, &2, String, V.Yaml>:
  when(Result<&2, &2, String, V.Yaml>, Bool.or(Bool.or(String.eq(tag, "!"), String.eq(tag, C.yaml.tag("str"))), String.eq(tag, C.yaml.tag("merge"))), u => Done{V.Str{s}},
    u => when(Result<&2, &2, String, V.Yaml>, String.eq(tag, C.yaml.tag("null")), u => C.must(Bool.pick(Maybe<&2, V.Yaml>, C.is_null(s), Some{V.Null{}}, None{}), "!!null", s),
      u => when(Result<&2, &2, String, V.Yaml>, String.eq(tag, C.yaml.tag("bool")), u => C.must(bool.yaml(s), "!!bool", s),
        u => when(Result<&2, &2, String, V.Yaml>, String.eq(tag, C.yaml.tag("int")), u => C.must(int.yaml(int.of(s)), "!!int", s),
          u => when(Result<&2, &2, String, V.Yaml>, String.eq(tag, C.yaml.tag("float")), u => C.must(float.yaml(float.of(s), int.of(s)), "!!float", s),
            u => Done{V.Tagged{tag, V.Str{s}}})))))
