# The pieces the scanner hands the parser, and the errors both report.

import Base

# A place in the text: the line and column (each from 0, a column counted in
# characters) and the character's index from the start.
type Mark is Data:
  Mark{line: Nat, col: Nat, idx: Nat}

# How a scalar was written.
type Style is Data:
  Plain{}
  Single{}
  Double{}
  Literal{}
  Folded{}

# A token, as libyaml names them. A scanner error ends the tokens with Broken.
type Tok is Data:
  StreamStart{}
  StreamEnd{}
  VersionDir{major: Nat, minor: Nat}
  TagDir{handle: String, prefix: String}
  DocStart{}
  DocEnd{}
  BSeqStart{}
  BMapStart{}
  BEnd{}
  FSeqStart{}
  FSeqEnd{}
  FMapStart{}
  FMapEnd{}
  BEntry{}
  FEntry{}
  KeyTok{}
  ValueTok{}
  AliasTok{name: String}
  AnchorTok{name: String}
  TagTok{handle: String, suffix: String}
  ScalarTok{text: String, style: Style}
  Broken{error: Error}

type Token is Data:
  Token{tok: Tok, start: Mark, end: Mark}

# Why a text didn't load: it isn't YAML, or it is but the schema can't
# load it (a bad !!int, an unknown alias, a repeated key).
type Cause is Data:
  Syntax{}
  Content{}

# What went wrong, where, and why. A syntax error reads as a problem and
# what was being read: "did not find expected key while parsing a block
# mapping".
type Error is Data:
  Error{why: String, at: Mark, cause: Cause}

def mark.line(m: Mark) -> Nat:
  match m:
    case Mark{line, col, idx}:
      line

def mark.col(m: Mark) -> Nat:
  match m:
    case Mark{line, col, idx}:
      col

def mark.idx(m: Mark) -> Nat:
  match m:
    case Mark{line, col, idx}:
      idx

# "at line 2 column 5", counting from 1.
def mark.show(m: Mark) -> String:
  match m:
    case Mark{line, col, idx}:
      "line " ++ Nat.show(1n+line) ++ " column " ++ Nat.show(1n+col)

# The error as one line: "mapping values are not allowed in this context at
# line 1 column 5".
def error.show(e: Error) -> String:
  match e:
    case Error{why, at, cause}:
      why ++ " at " ++ mark.show(at)

def error.why(e: Error) -> String:
  match e:
    case Error{why, at, cause}:
      why

def error.at(e: Error) -> Mark:
  match e:
    case Error{why, at, cause}:
      at
