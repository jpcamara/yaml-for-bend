# Prints the events of each YAML file named in a list, as the YAML test
# suite writes them, each after a "### path" line. test/suite.rb runs it.

import Base

import ./io.bend as F

import ../src/parse.bend as P

def each(paths: List<&2, String>) -> IO(Unit):
  match paths:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+p, rest}:
      do IO<Unit>:
        s : String <- F.read(p)
        IO.write("### " ++ p ++ "\n" ++ P.parsed.text(P.events(s, 256n)))
        each(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    list : String <- F.read(F.arg(args, "paths.txt"))
    each(String.lines(list))
