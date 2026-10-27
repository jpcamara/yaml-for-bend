# Loads each YAML file named in a list, writes each document back with
# dump, loads that, and prints whether the values match, after a "### path"
# line: "same", "differs" with the text dump wrote, or the error.

import Base

import ./io.bend as F

import ../src/token.bend as T

import ../src/value.bend as V

import ../src/yaml.bend as Y

def again(r: Result<&2, &2, T.Error, V.Yaml>, v: V.Yaml, +text: String) -> String:
  match r:
    case Fail{e}:
      "differs: " ++ T.error.show(e) ++ " in:\n" ++ text ++ "\n"
    case Done{w}:
      Bool.pick(String, V.eq(v, w), "same\n", "differs:\n" ++ text ++ "\n")

def each.doc(vs: List<&2, V.Yaml>) -> String:
  match vs:
    case Nil{}:
      ""
    case Con{+v, rest}:
      +text = Y.dump(v)
      again(Y.load(text), v, text) ++ each.doc(rest)

def shown(r: Result<&2, &2, T.Error, List<&2, V.Yaml>>) -> String:
  match r:
    case Fail{e}:
      "ERROR " ++ T.error.show(e) ++ "\n"
    case Done{vs}:
      each.doc(vs)

def each(paths: List<&2, String>) -> IO(Unit):
  match paths:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+p, rest}:
      do IO<Unit>:
        s : String <- F.read(p)
        IO.write("### " ++ p ++ "\n" ++ shown(Y.load.all(s)))
        each(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    list : String <- F.read(F.arg(args, "paths.txt"))
    each(String.lines(list))
