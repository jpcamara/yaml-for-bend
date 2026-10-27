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

def when(-A: Type, hit: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match hit:
    case True{}:
      yes(Unit{})
    case False{}:
      no(Unit{})

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

# A text past the size limit is refused before it is read.
def sized(+lim: C.Limits, +text: String, read: Unit -> Result<&2, &2, T.Error, List<&2, C.Doc>>) -> Result<&2, &2, T.Error, List<&2, C.Doc>>:
  when(Result<&2, &2, T.Error, List<&2, C.Doc>>, C.longer(text, C.limits.size(lim)),
    u => Fail{C.limit.error("found a text longer than the size limit of " ++ Nat.show(C.limits.size(lim)) ++ " characters", T.Mark{0n, 0n, 0n})},
    read)

def docs(+s: C.Schema, +lim: C.Limits, +text: String) -> Result<&2, &2, T.Error, List<&2, C.Doc>>:
  sized(lim, text, u => C.compose(P.events(text, C.limits.depth(lim)), s, lim))

# Every document in +text+ under schema +s+, within limits +lim+.
def load.all.with(s: C.Schema, lim: C.Limits, text: String) -> Result<&2, &2, T.Error, List<&2, V.Yaml>>:
  all.of(docs(s, lim, text))

# The one document in +text+ under schema +s+, within limits +lim+: null
# when there is none, an error when there are more.
def load.with(s: C.Schema, lim: C.Limits, text: String) -> Result<&2, &2, T.Error, V.Yaml>:
  one.of(docs(s, lim, text))

# The one document in +text+ under the YAML 1.2 Core schema, within the
# default limits: null when there is none, an error when there are more.
# A repeated key is an error.
def load(text: String) -> Result<&2, &2, T.Error, V.Yaml>:
  load.with(C.Core{}, C.limits(), text)

# Every document in +text+, under the Core schema.
def load.all(text: String) -> Result<&2, &2, T.Error, List<&2, V.Yaml>>:
  load.all.with(C.Core{}, C.limits(), text)

# load, reading the YAML 1.1 types.
def load.v11(text: String) -> Result<&2, &2, T.Error, V.Yaml>:
  load.with(C.Yaml11{}, C.limits(), text)

# load.all, reading the YAML 1.1 types.
def load.all.v11(text: String) -> Result<&2, &2, T.Error, List<&2, V.Yaml>>:
  load.all.with(C.Yaml11{}, C.limits(), text)

# The default limits: C.Limits{size, depth, aliases, digits} with a text of
# at most 1048576 characters, collections nested at most 256 deep, aliases
# copying at most 100000 nodes into a document, and numbers in bases other
# than ten at most 1000 characters long.
def limits() -> C.Limits:
  C.limits()

# The events of +text+, as the parser emits them, and the error that ended
# them early, if one did. Flow collections nest at most 256 deep.
def events(text: String) -> P.Parsed:
  P.events(text, C.limits.depth(C.limits()))

# +v+ as YAML text in block style, which load reads back as +v+.
def dump(v: V.Yaml) -> String:
  E.dump(v)

# Values as a stream of documents, each after "---".
def dump.all(vs: List<&2, V.Yaml>) -> String:
  E.dump.all(vs)
