# Loads each "§"-separated case in a file with load.v11 and prints one line
# per case: a compact dump of the value, or ERR: and the error.
# test/v11/expected.txt holds what each case in test/v11/cases.txt gives.

import Base

import ./io.bend as F

import ../src/token.bend as T

import ../src/value.bend as V

import ../src/yaml.bend as Y

def hex(+n: Nat) -> Char:
  Chr{U32.from_nat(Bool.pick(Nat, Nat.is_lt(n, 10n), Nat.add(n, 48n), Nat.add(n, 55n)))}

def esc.other(c: Char) -> String:
  match c:
    case Chr{+x}:
      Bool.pick(String, Bool.or(U32.is_lt(x, 32), U32.is_eq(x, 127)),
        "\\x" ++ SCon{hex(U32.to_nat(U32.div(x, 16))), SCon{hex(U32.to_nat(U32.mod(x, 16))), SNil{}}}, SCon{Chr{x}, SNil{}})

# Backslashes, breaks, tabs and parentheses escaped; other control
# characters as \xNN.
def esc(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      match c:
        case '\\':
          "\\\\" ++ esc(t)
        case '\n':
          "\\n" ++ esc(t)
        case '\t':
          "\\t" ++ esc(t)
        case '(':
          "\\(" ++ esc(t)
        case ')':
          "\\)" ++ esc(t)
        case _:
          esc.other(c) ++ esc(t)

# null, true, false, I(..), F(..), S(..), T(..) for a timestamp,
# !tag(..) for another tag, [a,b] and {k=v,..}.
def dump(v: V.Yaml, +first: Bool) -> String:
  match v:
    case V.Null{}:
      "null"
    case V.Boolean{on}:
      Bool.pick(String, on, "true", "false")
    case V.Int{t}:
      "I(" ++ t ++ ")"
    case V.Float{t}:
      "F(" ++ t ++ ")"
    case V.Str{t}:
      "S(" ++ esc(t) ++ ")"
    case V.Seq{xs}:
      match xs:
        case Nil{}:
          Bool.pick(String, first, "[]", "]")
        case Con{x, rest}:
          Bool.pick(String, first, "[", ",") ++ dump(x, True{}) ++ dump(V.Seq{rest}, False{})
    case V.Mapping{es}:
      match es:
        case Nil{}:
          Bool.pick(String, first, "{}", "}")
        case Con{V.Entry{k, x}, rest}:
          Bool.pick(String, first, "{", ",") ++ dump(k, True{}) ++ "=" ++ dump(x, True{}) ++ dump(V.Mapping{rest}, False{})
    case V.Tagged{+tag, x}:
      Bool.pick(String, String.eq(tag, "tag:yaml.org,2002:timestamp"), "T", tag) ++ "(" ++ dump(x, True{}) ++ ")"

def one(r: Result<&2, &2, T.Error, V.Yaml>) -> String:
  match r:
    case Fail{e}:
      "ERR:" ++ esc(T.error.show(e))
    case Done{v}:
      dump(v, True{})

def all(cs: List<&2, String>) -> String:
  match cs:
    case Nil{}:
      ""
    case Con{c, rest}:
      one(Y.load.v11(c)) ++ "\n" ++ all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    s : String <- F.read(F.arg(args, "test/v11/cases.txt"))
    IO.write(all(String.split(s, '§')))
