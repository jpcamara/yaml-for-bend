# YAML for Bend: read YAML text into values and write values back as YAML.
#
#   import ./yaml.bend as Y
#   import ./value.bend as V
#
#   Y.load("a: [1, 2]")    # Done{V.Mapping{[V.Entry{V.Str{"a"}, V.Seq{...}}]}}
#
# load reads under the YAML 1.2 Core schema; load.v11 reads the YAML 1.1
# types (yes/no booleans, 0 octal, base 60, timestamps, "<<" merges).
# Errors say what went wrong and where: T.error.show(e) is "mapping values
# are not allowed in this context at line 1 column 5".

import Base

import ./token.bend as T

import ./parse.bend as P

import ./value.bend as V

import ./compose.bend as C

import ./emit.bend as E

def doc.vals(ds: List<&2, C.Doc>) -> List<&2, V.Yaml>:
  match ds:
    case Nil{}:
      []
    case Con{d, rest}:
      match d:
        case C.Doc{v, at}:
          v <> doc.vals(rest)

def all.of(r: Result<&2, &2, T.Error, List<&2, C.Doc>>) -> Result<&2, &2, T.Error, List<&2, V.Yaml>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{ds}:
      Done{doc.vals(ds)}

def one.of(r: Result<&2, &2, T.Error, List<&2, C.Doc>>) -> Result<&2, &2, T.Error, V.Yaml>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{ds}:
      match ds:
        case Nil{}:
          Done{V.Null{}}
        case Con{d, rest}:
          match d:
            case C.Doc{v, at}:
              match rest:
                case Nil{}:
                  Done{v}
                case Con{other, more}:
                  match other:
                    case C.Doc{w, second}:
                      Fail{T.Error{"found a second document where load expects one; use load.all", second, T.Content{}}}

# Every document in +text+ under schema +s+, with aliases making at most
# +limit+ nodes in a document.
def load.all.with(s: C.Schema, limit: Nat, text: String) -> Result<&2, &2, T.Error, List<&2, V.Yaml>>:
  all.of(C.compose.limited(P.events(text), s, limit))

# The one document in +text+ under schema +s+: null when there is none, an
# error when there are more.
def load.with(s: C.Schema, limit: Nat, text: String) -> Result<&2, &2, T.Error, V.Yaml>:
  one.of(C.compose.limited(P.events(text), s, limit))

# The one document in +text+ under the YAML 1.2 Core schema: null when
# there is none, an error when there are more. A repeated key is an error,
# and so is a document whose aliases make more than 100000 nodes.
def load(text: String) -> Result<&2, &2, T.Error, V.Yaml>:
  load.with(C.Core{}, C.alias.limit(), text)

# Every document in +text+, under the Core schema.
def load.all(text: String) -> Result<&2, &2, T.Error, List<&2, V.Yaml>>:
  load.all.with(C.Core{}, C.alias.limit(), text)

# load, reading the YAML 1.1 types.
def load.v11(text: String) -> Result<&2, &2, T.Error, V.Yaml>:
  load.with(C.Yaml11{}, C.alias.limit(), text)

# load.all, reading the YAML 1.1 types.
def load.all.v11(text: String) -> Result<&2, &2, T.Error, List<&2, V.Yaml>>:
  load.all.with(C.Yaml11{}, C.alias.limit(), text)

# The events of +text+, as the parser emits them, and the error that ended
# them early, if one did.
def events(text: String) -> P.Parsed:
  P.events(text)

# +v+ as YAML text in block style, which load reads back as +v+.
def dump(v: V.Yaml) -> String:
  E.dump(v)

# Values as a stream of documents, each after "---".
def dump.all(vs: List<&2, V.Yaml>) -> String:
  E.dump.all(vs)
