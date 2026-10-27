# Prints each YAML file named in a list as JSON under the Core schema, one
# document per line, after a "### path" line. test/suite.rb compares it
# with the test suite's in.json.

import Base

import ./io.bend as F

import ../src/token.bend as T

import ../src/value.bend as V

import ../src/yaml.bend as Y

def lines(vs: List<&2, V.Yaml>) -> String:
  match vs:
    case Nil{}:
      ""
    case Con{v, rest}:
      V.json(v) ++ "\n" ++ lines(rest)

def shown(r: Result<&2, &2, T.Error, List<&2, V.Yaml>>) -> String:
  match r:
    case Fail{e}:
      "ERROR " ++ T.error.show(e) ++ "\n"
    case Done{vs}:
      lines(vs)

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
