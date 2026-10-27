# Prints the tokens of a YAML file, one per line: script/remote 'bend
# test/tokens.bend x.yaml'.

import Base

import ../src/token.bend as T

import ../src/scan.bend as S

def style(s: T.Style) -> String:
  match s:
    case T.Plain{}:
      ":"
    case T.Single{}:
      "'"
    case T.Double{}:
      "\""
    case T.Literal{}:
      "|"
    case T.Folded{}:
      ">"

def tok(t: T.Tok) -> String:
  match t:
    case T.StreamStart{}:
      "STREAM-START"
    case T.StreamEnd{}:
      "STREAM-END"
    case T.VersionDir{a, b}:
      "VERSION " ++ Nat.show(a) ++ "." ++ Nat.show(b)
    case T.TagDir{h, p}:
      "TAG-DIR " ++ h ++ " " ++ p
    case T.DocStart{}:
      "DOC-START"
    case T.DocEnd{}:
      "DOC-END"
    case T.BSeqStart{}:
      "BLOCK-SEQ-START"
    case T.BMapStart{}:
      "BLOCK-MAP-START"
    case T.BEnd{}:
      "BLOCK-END"
    case T.FSeqStart{}:
      "["
    case T.FSeqEnd{}:
      "]"
    case T.FMapStart{}:
      "{"
    case T.FMapEnd{}:
      "}"
    case T.BEntry{}:
      "-"
    case T.FEntry{}:
      ","
    case T.KeyTok{}:
      "KEY"
    case T.ValueTok{}:
      "VALUE"
    case T.AliasTok{n}:
      "*" ++ n
    case T.AnchorTok{n}:
      "&" ++ n
    case T.TagTok{h, s}:
      "TAG " ++ h ++ " " ++ s
    case T.ScalarTok{text, s}:
      "SCALAR " ++ style(s) ++ text
    case T.Broken{e}:
      "ERROR " ++ T.error.show(e)

def show(ts: List<&2, T.Token>) -> String:
  match ts:
    case Nil{}:
      ""
    case Con{t, rest}:
      match t:
        case T.Token{k, start, end}:
          tok(k) ++ " @" ++ T.mark.show(start) ++ "\n" ++ show(rest)

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

def read(path: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, File>, String, File.open(path, "r"), read.opened)

def path(xs: List<String>) -> String:
  match xs:
    case Con{h, Con{p, t}}:
      p
    case _:
      "in.yaml"

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    s : String <- read(path(args))
    IO.write(show(S.scan(s, 256n)))
