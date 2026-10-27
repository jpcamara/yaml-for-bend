# Loads YAML texts and prints them as JSON, or prints the error.

import Base

import ../src/yaml.bend as Y

import ../src/value.bend as V

import ../src/token.bend as T

def shown(r: Result<&2, &2, T.Error, V.Yaml>) -> String:
  match r:
    case Done{v}:
      V.json(v)
    case Fail{e}:
      T.error.show(e)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(shown(Y.load("name: bend\ntags: [yaml, 1.2]")))
    IO.print(shown(Y.load("a: b: c")))
    IO.print(shown(Y.load.v11("on: yes")))
