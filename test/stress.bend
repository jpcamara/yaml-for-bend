# Loads one file within the default limits and prints how many nodes its
# documents hold, or the error: the adversarial tests time this on each
# generated input. A second argument "v11" reads the YAML 1.1 types.
#
#   build/stress in.yaml [v11]

import Base

import ./io.bend as F

import ../src/token.bend as T

import ../src/value.bend as V

import ../src/yaml.bend as Y

def push.items(xs: List<&2, V.Yaml>, rest: List<&2, V.Yaml>) -> List<&2, V.Yaml>:
  List.append(&2, V.Yaml, xs, rest)

def push.entries(es: List<&2, V.Entry>, rest: List<&2, V.Yaml>) -> List<&2, V.Yaml>:
  match es:
    case Nil{}:
      rest
    case Con{e, more}:
      match e:
        case V.Entry{k, v}:
          k <> v <> push.entries(more, rest)

def children(v: V.Yaml, rest: List<&2, V.Yaml>) -> List<&2, V.Yaml>:
  match v:
    case V.Seq{xs}:
      push.items(xs, rest)
    case V.Mapping{es}:
      push.entries(es, rest)
    case V.Tagged{t, x}:
      x <> rest
    case _:
      rest

# Nodes counted with a work list, a node at a time, so no deep recursion.
def count(fuel: Nat, todo: List<&2, V.Yaml>, +n: Nat) -> Nat:
  match fuel:
    case 0n:
      n
    case 1n+k:
      match todo:
        case Nil{}:
          n
        case Con{v, rest}:
          count(k, children(v, rest), 1n+n)

def shown(r: Result<&2, &2, T.Error, List<&2, V.Yaml>>) -> String:
  match r:
    case Fail{e}:
      "error: " ++ String.take(T.error.show(e), 160n)
    case Done{vs}:
      "nodes: " ++ Nat.show(count(4000000000n, vs, 0n))

# The file and the schema from the arguments after the program.
def picked(xs: List<String>) -> String & String:
  match xs:
    case Con{h, Con{p, Con{s, t}}}:
      (p, s)
    case Con{h, Con{p, t}}:
      (p, "")
    case _:
      ("in.yaml", "")

def when(-A: Type, hit: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match hit:
    case True{}:
      yes(Unit{})
    case False{}:
      no(Unit{})

def load(+schema: String, +s: String) -> Result<&2, &2, T.Error, List<&2, V.Yaml>>:
  when(Result<&2, &2, T.Error, List<&2, V.Yaml>>, String.eq(schema, "v11"), u => Y.load.all.v11(s), u => Y.load.all(s))

def run(ps: String & String) -> IO(Unit):
  (path, schema) = ps
  do IO<Unit>:
    s : String <- F.read(path)
    IO.print(shown(load(schema, s)))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(picked(args))
