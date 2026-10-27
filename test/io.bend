# Reading files, for the test programs.

import Base

def text.or(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{s}:
      s

def read.got(p: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, r) = p
  IO.bind(Unit, String, File.close(f), u => IO.pure(String, text.or(r)))

def read.opened(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, "")
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, String, File.read(f, 1073741824), read.got)

# A file's text, or "" when it can't be read.
def read(path: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, File>, String, File.open(path, "r"), read.opened)

# The first argument after the program, or +d+.
def arg(xs: List<String>, d: String) -> String:
  match xs:
    case Con{h, Con{p, t}}:
      p
    case _:
      d
