# The scanner: YAML text to tokens.
#
# It follows the design of libyaml's scanner. One step fetches the next
# token. Block collections open and close by indentation, so the scanner
# keeps a stack of indentations and adds BSeqStart, BMapStart and BEnd
# tokens as they change. A "simple key" (a key without "?") is only known to
# be a key when its ":" arrives, so the scanner remembers where each
# possible key started and, at the ":", inserts a KeyTok (and BMapStart)
# before the key's first token.
#
# It reads YAML 1.2 as the YAML test suite has it: tabs separate tokens
# but never indent, a flow collection's lines and a quoted scalar's indent
# past the block around them, a comment follows a blank, anchors take any
# character but blanks and flow indicators, ":" is a value indicator right
# after a JSON-like node in flow, and reserved directives are skipped.
#
# An error ends the tokens with a Broken token, so the parser still sees
# the tokens before it.

import Base

import ./token.bend as T

# The text left to read, where it starts, and how many characters are left.
type Cur is Data:
  Cur{s: String, at: T.Mark, left: Nat}

# A place a simple key may start: whether one still may, whether it must (a
# block key at the indentation), the number its first token has, and where.
# Each level also keeps where the oldest key still possible at or below it
# started (+low+), so finding stale keys needn't look at every level.
type SKey is Data:
  SKey{possible: Bool, required: Bool, number: Nat, at: T.Mark, tab: Bool, low: Maybe<&2, T.Mark>}

# The scanner: the cursor, the block indentation plus one (0 outside any
# block collection) and the ones it returns to, how deep in flow collections
# it is, whether a simple key may start here, one possible key per flow
# level (the block level last), the tokens so far (newest first) and their
# count, and how deep flow collections may nest.
type Sc is Data:
  Sc{cur: Cur, ind: Nat, inds: List<&2, Nat>, flow: Nat, allowed: Bool, tab: Bool, keys: List<&2, SKey>, out: List<&2, T.Token>, n: Nat, max: Nat}

# A step goes on, or stops: at the stream's end or at an error, as the last
# token says.
type Step is Data:
  Go{st: Sc}
  Stop{st: Sc}

type Lay is Data:
  Lay{ind: Nat, inds: List<&2, Nat>, out: List<&2, T.Token>, n: Nat}

# Between tokens
# --------------

type Skipped is Data:
  Skipped{cur: Cur, allowed: Bool, tab: Bool, nl: Bool, sp: Nat, bad: Bool}

# Plain scalars
# -------------

# Reading a plain scalar: the cursor, the text so far (reversed), where the
# last word ended, the blanks after it (reversed), whether a line break came
# since, how many more breaks did, and whether a word is being read.
type Pl is Data:
  Pl{cur: Cur, acc: String, end: T.Mark, ws: String, lead: Bool, brks: Nat, word: Bool, bad: Bool}
  PlDone{cur: Cur, acc: String, end: T.Mark, lead: Bool}
  PlBad{error: T.Error}

# Quoted scalars
# --------------

# Reading a quoted scalar: the cursor, the text so far (reversed), the
# blanks waiting (reversed), whether a line break came since the last text
# and how many more did, whether that break was escaped, and whether text
# (not blanks) is being read.
type Qs is Data:
  Qs{cur: Cur, acc: String, ws: String, lead: Bool, brks: Nat, esc: Bool, text: Bool, bad: Bool}
  QsDone{cur: Cur, acc: String}
  QsBad{error: T.Error}

# Block scalars
# -------------

type Chomp is Data:
  Clip{}
  Strip{}
  Keep{}

# A block scalar's header: how to chomp, the indentation indicator (0 when
# there's none), and the cursor after it; or an error.
type Head is Data:
  Head{chomp: Chomp, inc: Nat, cur: Cur}
  HeadBad{why: String}

type BPhase is Data:
  Breaks{}
  LineStart{}
  Content{}

# Reading a block scalar: the cursor, the text so far (reversed), the
# content's indentation plus one (0 until known), the deepest blank line, whether a
# line break waits, whether the last line started with a blank, how many
# more breaks wait, and the phase: blank lines, a line's start, or content.
type Bs is Data:
  Bs{cur: Cur, acc: String, ind: Nat, max: Nat, lead: Bool, lblank: Bool, brks: Nat, phase: BPhase}
  BsDone{acc: String, lead: Bool, brks: Nat, cur: Cur}
  BsBad{error: T.Error}

# Anchors, aliases and tags
# -------------------------

# What a scan took: the text it read and how many characters that was.
type Taken is Data:
  Taken{text: String, n: Nat}

# The step after +v+, when it goes on.
def then(v: Step, f: Sc -> Step) -> Step:
  match v:
    case Go{st}:
      f(st)
    case Stop{st}:
      Stop{st}

# +yes+ when +hit+, else +no+; only the one chosen runs.
def when(-A: Type, hit: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match hit:
    case True{}:
      yes(Unit{})
    case False{}:
      no(Unit{})

# Characters
# ----------

def code(c: Char) -> U32:
  match c:
    case Chr{x}:
      x

# The character +n+ places on, or NUL past the end.
def peek(s: String, n: Nat) -> Char:
  match s:
    case SNil{}:
      Chr{0}
    case SCon{c, t}:
      match n:
        case 0n:
          c
        case 1n+k:
          peek(t, k)

def is_blank(c: Char) -> Bool:
  match c:
    case ' ':
      True{}
    case '\t':
      True{}
    case _:
      False{}

def is_break(c: Char) -> Bool:
  Char.is_eq(c, '\n')

def is_end(c: Char) -> Bool:
  U32.is_eq(code(c), 0)

def is_blankz(+c: Char) -> Bool:
  Bool.or(is_blank(c), Bool.or(is_break(c), is_end(c)))

def is_breakz(+c: Char) -> Bool:
  Bool.or(is_break(c), is_end(c))

def is_flow.ind(c: Char) -> Bool:
  match c:
    case ',':
      True{}
    case '[':
      True{}
    case ']':
      True{}
    case '{':
      True{}
    case '}':
      True{}
    case _:
      False{}

def between(+x: U32, lo: U32, hi: U32) -> Bool:
  Bool.and(U32.is_ge(x, lo), U32.is_le(x, hi))

def is_digit(c: Char) -> Bool:
  Char.is_digit(c)

def is_hex(+c: Char) -> Bool:
  Bool.or(Char.is_digit(c), Bool.or(between(code(c), 65, 70), between(code(c), 97, 102)))

# A letter, digit or "-": what a tag handle's name is made of.
def is_word(+c: Char) -> Bool:
  Bool.or(Char.is_alpha(c), Bool.or(Char.is_digit(c), Char.is_eq(c, '-')))

def is_in(c: Char, s: String) -> Bool:
  String.contains(s, SCon{c, SNil{}})

# A URI character other than "%" (which starts an escape).
def is_uri(+c: Char) -> Bool:
  Bool.or(is_word(c), is_in(c, "#;/?:@&=+$,_.!~*'()[]"))

# A tag character: a URI character but "!" and the flow indicators.
def is_tag(+c: Char) -> Bool:
  Bool.or(is_word(c), is_in(c, "#;/?:@&=+$_.~*'()"))

# What YAML allows in a document: tab, line feed, and printable characters.
def is_printable(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.or(Bool.or(U32.is_eq(x, 9), U32.is_eq(x, 10)),
        Bool.or(between(x, 32, 126), Bool.or(U32.is_eq(x, 133), Bool.or(between(x, 160, 55295),
          Bool.or(between(x, 57344, 65533), between(x, 65536, 1114111))))))

def hex.digit(c: Char) -> U32:
  +x = code(c)
  U32.sub(x, Bool.pick(U32, U32.is_ge(x, 97), 87, Bool.pick(U32, U32.is_ge(x, 65), 55, 48)))

def hex.value(s: String, acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{c, t}:
      hex.value(t, U32.add(U32.mul(acc, 16), hex.digit(c)))

def all.hex(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{+c, t}:
      Bool.and(is_hex(c), all.hex(t))

# "---" or "..." (+c+ thrice) and then a blank, a break or the end.
def marker(+s: String, +c: Char) -> Bool:
  Bool.and(Bool.and(Char.is_eq(peek(s, 0n), c), Char.is_eq(peek(s, 1n), c)), Bool.and(Char.is_eq(peek(s, 2n), c), is_blankz(peek(s, 3n))))

def is_marker(+s: String) -> Bool:
  Bool.or(marker(s, '-'), marker(s, '.'))

# Line breaks as "\n": "\r\n" and a lone "\r" both become one, as YAML reads
# them.
def lf(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{c, t}:
      match c:
        case '\r':
          match t:
            case SCon{'\n', u}:
              SCon{'\n', lf(u)}
            case _:
              SCon{'\n', lf(t)}
        case _:
          SCon{c, lf(t)}

def strip.bom(s: String) -> String:
  match s:
    case SCon{c, +t}:
      match c:
        case Chr{+x}:
          Bool.pick(String, U32.is_eq(x, 65279), t, SCon{Chr{x}, t})
    case SNil{}:
      SNil{}

# The cursor
# ----------

def past(at: T.Mark, c: Char) -> T.Mark:
  match at:
    case T.Mark{line, col, idx}:
      match c:
        case '\n':
          T.Mark{1n+line, 0n, 1n+idx}
        case _:
          T.Mark{line, 1n+col, 1n+idx}

def adv(c: Cur) -> Cur:
  match c:
    case Cur{s, at, left}:
      match s:
        case SNil{}:
          Cur{SNil{}, at, left}
        case SCon{h, t}:
          Cur{t, past(at, h), Nat.sub(left, 1n)}

def adv.n(n: Nat, c: Cur) -> Cur:
  match n:
    case 0n:
      c
    case 1n+k:
      adv.n(k, adv(c))

def cur.s(c: Cur) -> String:
  match c:
    case Cur{s, at, left}:
      s

def cur.at(c: Cur) -> T.Mark:
  match c:
    case Cur{s, at, left}:
      at

def cur.left(c: Cur) -> Nat:
  match c:
    case Cur{s, at, left}:
      left

def cur.col(c: Cur) -> Nat:
  T.mark.col(cur.at(c))

# The scanner's state
# -------------------

def sc.cur(st: Sc) -> Cur:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      cur

def sc.s(st: Sc) -> String:
  cur.s(sc.cur(st))

def sc.at(st: Sc) -> T.Mark:
  cur.at(sc.cur(st))

def sc.col(st: Sc) -> Nat:
  cur.col(sc.cur(st))

def sc.ind(st: Sc) -> Nat:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      ind

def sc.flow(st: Sc) -> Nat:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      flow

def sc.in_flow(st: Sc) -> Bool:
  Nat.is_gt(sc.flow(st), 0n)

def sc.max(st: Sc) -> Nat:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      max

def sc.tab(st: Sc) -> Bool:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      tab

def sc.allowed(st: Sc) -> Bool:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      allowed

def sc.keys(st: Sc) -> List<&2, SKey>:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      keys

def sc.out(st: Sc) -> List<&2, T.Token>:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      out

def sc.with.cur(st: Sc, c: Cur) -> Sc:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      Sc{c, ind, inds, flow, allowed, tab, keys, out, n, max}

def sc.allow(st: Sc, b: Bool) -> Sc:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      Sc{cur, ind, inds, flow, b, tab, keys, out, n, max}

def sc.with.keys(st: Sc, ks: List<&2, SKey>) -> Sc:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      Sc{cur, ind, inds, flow, allowed, tab, ks, out, n, max}

def skip(+st: Sc, k: Nat) -> Sc:
  sc.with.cur(st, adv.n(k, sc.cur(st)))

# A token from +start+ to +end+.
def emit.span(st: Sc, tok: T.Tok, start: T.Mark, end: T.Mark) -> Sc:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      Sc{cur, ind, inds, flow, allowed, tab, keys, T.Token{tok, start, end} <> out, 1n+n, max}

# A token from +start+ to here.
def emit(+st: Sc, tok: T.Tok, start: T.Mark) -> Sc:
  emit.span(st, tok, start, sc.at(st))

# A one-character token here.
def single(+st: Sc, tok: T.Tok) -> Sc:
  emit(skip(st, 1n), tok, sc.at(st))

def fail(+st: Sc, why: String, +at: T.Mark) -> Step:
  Stop{emit(st, T.Broken{T.Error{why, at, T.Syntax{}}}, at)}

# A limit reached: the error names it.
def fail.limit(+st: Sc, why: String) -> Step:
  Stop{emit(st, T.Broken{T.Error{why, sc.at(st), T.Limit{}}}, sc.at(st))}

def fail.with(+st: Sc, e: T.Error) -> Step:
  match e:
    case T.Error{why, at, cause}:
      fail(st, why, at)

# "found character that cannot start any token"
def cannot(+st: Sc) -> Step:
  fail(st, "found character that cannot start any token while scanning for the next token", sc.at(st))

# The token before this one: whether it was a JSON-like node (a quoted
# scalar or a flow collection), after which ":" is a value indicator even
# without a space.
def json.tok(t: T.Tok) -> Bool:
  match t:
    case T.ScalarTok{text, style}:
      match style:
        case T.Single{}:
          True{}
        case T.Double{}:
          True{}
        case _:
          False{}
    case T.FSeqEnd{}:
      True{}
    case T.FMapEnd{}:
      True{}
    case _:
      False{}

def json.before(out: List<&2, T.Token>) -> Bool:
  match out:
    case Nil{}:
      False{}
    case Con{t, rest}:
      match t:
        case T.Token{tok, start, end}:
          json.tok(tok)

# Simple keys
# -----------

# The possible key on top, which a ":" would make a key.
def key.top(keys: List<&2, SKey>) -> SKey:
  match keys:
    case Nil{}:
      SKey{False{}, False{}, 0n, T.Mark{0n, 0n, 0n}, False{}, None{}}
    case Con{k, rest}:
      k

def key.or(r: Result<&2, &2, T.Error, List<&2, SKey>>, +st: Sc) -> Step:
  match r:
    case Fail{e}:
      fail.with(st, e)
    case Done{ks}:
      Go{sc.with.keys(st, ks)}

def low.of(keys: List<&2, SKey>) -> Maybe<&2, T.Mark>:
  match keys:
    case Nil{}:
      None{}
    case Con{k, rest}:
      match k:
        case SKey{possible, required, number, at, tab, low}:
          low

def key.removed(keys: List<&2, SKey>) -> Result<&2, &2, T.Error, List<&2, SKey>>:
  match keys:
    case Nil{}:
      Done{[]}
    case Con{k, +rest}:
      match k:
        case SKey{+possible, +required, number, +at, tab, low}:
          when(Result<&2, &2, T.Error, List<&2, SKey>>, Bool.and(possible, required),
            u => Fail{T.Error{"could not find expected ':' while scanning a simple key", at, T.Syntax{}}},
            u => Done{SKey{False{}, required, number, at, tab, low.of(rest)} <> rest})

# The key on top can no longer be; an error if it had to be.
def remove.key(+st: Sc) -> Step:
  key.or(key.removed(sc.keys(st)), st)

# A level's low: the one below it, or its own key when that is possible.
def low.with(below: Maybe<&2, T.Mark>, possible: Bool, at: T.Mark) -> Maybe<&2, T.Mark>:
  match below:
    case Some{m}:
      Some{m}
    case None{}:
      match possible:
        case True{}:
          Some{at}
        case False{}:
          None{}

def key.put(st: Sc, required: Bool) -> Sc:
  match st:
    case Sc{+cur, ind, inds, flow, allowed, +tab, keys, out, +n, max}:
      +rest = List.drop(&2, SKey, keys, 1n)
      Sc{cur, ind, inds, flow, allowed, tab, SKey{True{}, required, n, cur.at(cur), tab, low.with(low.of(rest), True{}, cur.at(cur))} <> rest, out, n, max}

def key.saved(r: Step, +required: Bool) -> Step:
  match r:
    case Go{st}:
      Go{key.put(st, required)}
    case Stop{st}:
      Stop{st}

# A simple key may start here. It must be one (no "?" can come later) when
# it starts a block line at the indentation.
def save.key(+st: Sc) -> Step:
  +required = Bool.and(Nat.is_eq(sc.flow(st), 0n), Nat.is_eq(sc.ind(st), 1n+sc.col(st)))
  when(Step, sc.allowed(st), u => key.saved(remove.key(st), required), u => Go{st})

# A simple key stays on one line and within 1024 characters.
def is_stale(+kat: T.Mark, +at: T.Mark) -> Bool:
  Bool.or(Nat.is_lt(T.mark.line(kat), T.mark.line(at)), Nat.is_lt(Nat.add(T.mark.idx(kat), 1024n), T.mark.idx(at)))

def low.stale(low: Maybe<&2, T.Mark>, +at: T.Mark) -> Bool:
  match low:
    case None{}:
      False{}
    case Some{m}:
      is_stale(m, at)

def stale.cons(+possible: Bool, required: Bool, number: Nat, +kat: T.Mark, tab: Bool, r: Result<&2, &2, T.Error, List<&2, SKey>>) -> Result<&2, &2, T.Error, List<&2, SKey>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+ks}:
      Done{SKey{possible, required, number, kat, tab, low.with(low.of(ks), possible, kat)} <> ks}

# Keys left behind are no longer possible. Keys go stale oldest first, so
# a level whose oldest possible key is still fresh has nothing stale at or
# below it, and the search stops there.
def stale.go(keys: List<&2, SKey>, +at: T.Mark) -> Result<&2, &2, T.Error, List<&2, SKey>>:
  match keys:
    case Nil{}:
      Done{[]}
    case Con{k, +rest}:
      match k:
        case SKey{+possible, +required, +number, +kat, +tab, +low}:
          +old = Bool.and(possible, is_stale(kat, at))
          when(Result<&2, &2, T.Error, List<&2, SKey>>, Bool.not(low.stale(low, at)), u => Done{SKey{possible, required, number, kat, tab, low} <> rest},
            u => when(Result<&2, &2, T.Error, List<&2, SKey>>, Bool.and(old, required),
              u => Fail{T.Error{"could not find expected ':' while scanning a simple key", kat, T.Syntax{}}},
              u => stale.cons(Bool.and(possible, Bool.not(old)), required, number, kat, tab, stale.go(rest, at))))

def stale(+st: Sc) -> Step:
  key.or(stale.go(sc.keys(st), sc.at(st)), st)

def key.cleared(keys: List<&2, SKey>) -> List<&2, SKey>:
  match keys:
    case Nil{}:
      []
    case Con{k, +rest}:
      match k:
        case SKey{possible, required, number, at, tab, low}:
          SKey{False{}, required, number, at, tab, low.of(rest)} <> rest

def flow.push(st: Sc) -> Sc:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, +keys, out, n, max}:
      Sc{cur, ind, inds, 1n+flow, allowed, tab, SKey{False{}, False{}, 0n, T.Mark{0n, 0n, 0n}, False{}, low.of(keys)} <> keys, out, n, max}

def flow.pop(st: Sc) -> Sc:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      match flow:
        case 0n:
          Sc{cur, ind, inds, 0n, allowed, tab, keys, out, n, max}
        case 1n+f:
          Sc{cur, ind, inds, f, allowed, tab, List.drop(&2, SKey, keys, 1n), out, n, max}

# Indentation
# -----------

def insert.at(d: Nat, out: List<&2, T.Token>, t: T.Token) -> List<&2, T.Token>:
  match d:
    case 0n:
      t <> out
    case 1n+k:
      match out:
        case Nil{}:
          [t]
        case Con{h, rest}:
          h <> insert.at(k, rest, t)

# A token at the end, or (+number+) before the token with that number.
def insert(out: List<&2, T.Token>, n: Nat, number: Maybe<&2, Nat>, t: T.Token) -> List<&2, T.Token>:
  match number:
    case None{}:
      t <> out
    case Some{k}:
      insert.at(Nat.sub(n, k), out, t)

def roll.do(st: Sc, col: Nat, number: Maybe<&2, Nat>, tok: T.Tok, +at: T.Mark) -> Sc:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, +n, max}:
      Sc{cur, 1n+col, ind <> inds, flow, allowed, tab, keys, insert(out, n, number, T.Token{tok, at, at}), 1n+n, max}

# A block collection starts at +col+ when that's deeper than the indentation.
def roll(+st: Sc, +col: Nat, number: Maybe<&2, Nat>, tok: T.Tok, at: T.Mark) -> Sc:
  when(Sc, Bool.and(Nat.is_eq(sc.flow(st), 0n), Nat.is_lt(sc.ind(st), 1n+col)), u => roll.do(st, col, number, tok, at), u => st)

def unroll.go(inds: List<&2, Nat>, +ind: Nat, +lim: Nat, +at: T.Mark, +out: List<&2, T.Token>, +n: Nat) -> Lay:
  match inds:
    case Nil{}:
      Lay{ind, [], out, n}
    case Con{+h, +t}:
      when(Lay, Nat.is_gt(ind, lim), u => unroll.go(t, h, lim, at, T.Token{T.BEnd{}, at, at} <> out, 1n+n), u => Lay{ind, h <> t, out, n})

def unrolled(l: Lay, cur: Cur, flow: Nat, allowed: Bool, tab: Bool, keys: List<&2, SKey>, max: Nat) -> Sc:
  match l:
    case Lay{ind, inds, out, n}:
      Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}

def unroll.do(st: Sc, +lim: Nat) -> Sc:
  match st:
    case Sc{+cur, ind, inds, flow, allowed, tab, keys, out, n, max}:
      unrolled(unroll.go(inds, ind, lim, cur.at(cur), out, n), cur, flow, allowed, tab, keys, max)

# Block collections deeper than +lim+ (a column plus one) end.
def unroll(+st: Sc, +lim: Nat) -> Sc:
  when(Sc, sc.in_flow(st), u => st, u => unroll.do(st, lim))

def skip.or(eat: Bool, more: Unit -> Skipped, stop: Skipped) -> Skipped:
  match eat:
    case True{}:
      more(Unit{})
    case False{}:
      stop

# Blanks, comments and line breaks before a token. A "#" starts a comment
# after a blank or at a line's start (+gap+). A line break in block context
# lets a simple key start. Along the way: whether a tab came on the token's
# line (+tab+), whether a line break came (+nl+), the spaces that start the
# token's line (+sp+, while +lead+), and whether a tab stood where block
# indentation belongs (+bad+).
def skip.go(s: String, +at: T.Mark, +left: Nat, +flow: Bool, +ind: Nat, +allowed: Bool, +comment: Bool, +gap: Bool,
            +tab: Bool, +nl: Bool, +lead: Bool, +sp: Nat, +bad: Bool) -> Skipped:
  match s:
    case SNil{}:
      Skipped{Cur{SNil{}, at, left}, allowed, tab, nl, sp, False{}}
    case SCon{+c, +t}:
      +brk = is_break(c)
      +space = Char.is_eq(c, ' ')
      +htab = Char.is_eq(c, '\t')
      +eat = Bool.or(Bool.or(brk, comment), Bool.or(Bool.or(space, htab), Bool.and(Char.is_eq(c, '#'), gap)))
      skip.or(eat,
        u => skip.go(t, past(at, c), Nat.sub(left, 1n), flow, ind, Bool.or(allowed, Bool.and(brk, Bool.not(flow))),
          Bool.and(Bool.not(brk), Bool.or(comment, Char.is_eq(c, '#'))), True{},
          Bool.and(Bool.not(brk), Bool.or(tab, htab)), Bool.or(nl, brk), Bool.or(brk, Bool.and(lead, Bool.or(space, htab))),
          Bool.pick(Nat, brk, 0n, Bool.pick(Nat, Bool.and(Bool.and(lead, space), Bool.not(tab)), 1n+sp, sp)),
          Bool.and(Bool.not(brk), Bool.or(bad, Bool.and(Bool.and(htab, lead), Bool.and(Bool.not(flow), Nat.is_lt(1n+sp, ind)))))),
        Skipped{Cur{SCon{c, t}, at, left}, allowed, tab, nl, sp, bad})

def skipped(k: Skipped, st: Sc) -> Sc:
  match k:
    case Skipped{cur, allowed, tab, nl, sp, bad}:
      match st:
        case Sc{c, ind, inds, flow, a, b, keys, out, n, max}:
          Sc{cur, ind, inds, flow, allowed, tab, keys, out, n, max}

# Whether the last token was a plain or block scalar, which end past the
# blanks after them, so a "#" here follows a blank.
def last.plain(out: List<&2, T.Token>) -> Bool:
  match out:
    case Nil{}:
      False{}
    case Con{t, rest}:
      match t:
        case T.Token{tok, start, end}:
          match tok:
            case T.ScalarTok{text, style}:
              match style:
                case T.Plain{}:
                  True{}
                case T.Literal{}:
                  True{}
                case T.Folded{}:
                  True{}
                case _:
                  False{}
            case _:
              False{}

# What the skipped whitespace allows: no tab where block indentation
# belongs, and in flow, lines indented past the block around them.
def skip.check(k: Skipped, +st: Sc) -> Step:
  match k:
    case Skipped{+cur, +allowed, +tab, +nl, +sp, +bad}:
      +content = Bool.not(is_end(peek(cur.s(cur), 0n)))
      +at = cur.at(cur)
      when(Step, Bool.and(bad, content), u => fail(st, "found a tab character where an indentation space is expected", at),
        u => when(Step, Bool.and(Bool.and(sc.in_flow(st), nl), Bool.and(content, Nat.is_lt(sp, sc.ind(st)))),
          u => fail(st, "did not find expected indentation in a flow collection", at),
          u => Go{skipped(Skipped{cur, allowed, tab, nl, sp, bad}, st)}))

def skip.ws.at(c: Cur, +st: Sc) -> Step:
  match c:
    case Cur{s, +at, left}:
      +lead = Nat.is_eq(T.mark.col(at), 0n)
      skip.check(skip.go(s, at, left, sc.in_flow(st), sc.ind(st), sc.allowed(st), False{}, Bool.or(lead, last.plain(sc.out(st))),
        False{}, False{}, lead, 0n, False{}), st)

def skip.ws(+st: Sc) -> Step:
  skip.ws.at(sc.cur(st), st)

# Folded line breaks: one break is a space, more are newlines (less one).
def folded.breaks(+brks: Nat) -> String:
  Bool.pick(String, Nat.is_eq(brks, 0n), " ", String.repeat("\n", brks))

# The blanks or breaks before a word join the text.
def flush(acc: String, ws: String, lead: Bool, +brks: Nat) -> String:
  match lead:
    case True{}:
      folded.breaks(brks) ++ acc
    case False{}:
      ws ++ acc

# In a word: a blank ends it; ": " or a flow indicator in flow ends the scalar.
def pl.word(cur: Cur, +acc: String, +end: T.Mark, +ws: String, +lead: Bool, +brks: Nat, +flow: Bool) -> Pl:
  match cur:
    case Cur{+s, +at, +left}:
      +c = peek(s, 0n)
      +c1 = peek(s, 1n)
      +stop = Bool.or(Bool.and(Char.is_eq(c, ':'), Bool.or(is_blankz(c1), Bool.and(flow, is_flow.ind(c1)))), Bool.and(flow, is_flow.ind(c)))
      Bool.pick(Pl, is_blankz(c), Pl{Cur{s, at, left}, acc, end, ws, lead, brks, False{}, False{}},
        Bool.pick(Pl, stop, PlDone{Cur{s, at, left}, acc, end, lead},
          Pl{Cur{String.drop(s, 1n), past(at, c), Nat.sub(left, 1n)}, SCon{c, flush(acc, ws, lead, brks)}, past(at, c), "", False{}, 0n, True{}, False{}}))

# Between words: blanks and breaks wait to join the text; then the next word
# starts, unless the scalar ended (less indented, a document marker, a
# comment, or the end). A tab may not stand where indentation belongs on a
# line that goes on.
def pl.blank(cur: Cur, +acc: String, +end: T.Mark, +ws: String, +lead: Bool, +brks: Nat, +bad: Bool, +ind: Nat, +flow: Bool, +start: T.Mark) -> Pl:
  match cur:
    case Cur{+s, +at, +left}:
      +c = peek(s, 0n)
      +next = {Cur{String.drop(s, 1n), past(at, c), Nat.sub(left, 1n)} : Cur}
      +here = {Cur{s, at, left} : Cur}
      +col = T.mark.col(at)
      +done = Bool.or(Bool.or(is_end(c), Bool.and(Bool.not(flow), Nat.is_lt(col, ind))),
        Bool.or(Bool.and(Nat.is_eq(col, 0n), is_marker(s)), Char.is_eq(c, '#')))
      +tabbed = Bool.and(Bool.and(lead, Char.is_eq(c, '\t')), Nat.is_lt(col, ind))
      Bool.pick(Pl, is_blank(c), Pl{next, acc, end, Bool.pick(String, lead, ws, SCon{c, ws}), lead, brks, False{}, Bool.or(bad, tabbed)},
        Bool.pick(Pl, is_break(c), Pl{next, acc, end, Bool.pick(String, lead, ws, ""), True{}, Bool.pick(Nat, lead, 1n+brks, brks), False{}, False{}},
          Bool.pick(Pl, done, PlDone{here, acc, end, lead},
            Bool.pick(Pl, bad, PlBad{T.Error{"found a tab character that violates indentation while scanning a plain scalar", start, T.Syntax{}}},
              Pl{here, acc, end, ws, lead, brks, True{}, False{}}))))

def pl.step(p: Pl, +ind: Nat, +flow: Bool, +start: T.Mark) -> Pl:
  match p:
    case Pl{cur, acc, end, ws, lead, brks, word, bad}:
      match word:
        case True{}:
          pl.word(cur, acc, end, ws, lead, brks, flow)
        case False{}:
          pl.blank(cur, acc, end, ws, lead, brks, bad, ind, flow, start)
    case _:
      p

def pl.run(fuel: Nat, +ind: Nat, +flow: Bool, +start: T.Mark, p: Pl) -> Pl:
  match fuel:
    case 0n:
      p
    case 1n+k:
      match p:
        case Pl{cur, acc, end, ws, lead, brks, word, bad}:
          pl.run(k, ind, flow, start, pl.step(Pl{cur, acc, end, ws, lead, brks, word, bad}, ind, flow, start))
        case _:
          p

def plain.done(p: Pl, +st: Sc, start: T.Mark) -> Step:
  match p:
    case PlDone{cur, acc, end, lead}:
      Go{sc.allow(emit.span(sc.with.cur(st, cur), T.ScalarTok{String.reverse(acc), T.Plain{}}, start, end), lead)}
    case PlBad{e}:
      fail.with(st, e)
    case Pl{cur, acc, end, ws, lead, brks, word, bad}:
      Go{sc.allow(emit.span(sc.with.cur(st, cur), T.ScalarTok{String.reverse(acc), T.Plain{}}, start, end), lead)}

def plain.scan(+st: Sc) -> Step:
  +cur = sc.cur(st)
  +at = cur.at(cur)
  plain.done(pl.run(Nat.add(Nat.mul(cur.left(cur), 2n), 4n), sc.ind(st), sc.in_flow(st), at, Pl{cur, "", at, "", False{}, 0n, True{}, False{}}), st, at)

def plain(+st: Sc) -> Step:
  then(save.key(st), st => plain.scan(sc.allow(st, False{})))

def q.text(cur: Cur, acc: String) -> Qs:
  Qs{cur, acc, "", False{}, 0n, False{}, True{}, False{}}

def simple.escape(e: Char) -> Maybe<&2, Char>:
  match e:
    case '0':
      Some{Chr{0}}
    case 'a':
      Some{Chr{7}}
    case 'b':
      Some{Chr{8}}
    case 't':
      Some{Chr{9}}
    case '\t':
      Some{Chr{9}}
    case 'n':
      Some{Chr{10}}
    case 'v':
      Some{Chr{11}}
    case 'f':
      Some{Chr{12}}
    case 'r':
      Some{Chr{13}}
    case 'e':
      Some{Chr{27}}
    case ' ':
      Some{' '}
    case '"':
      Some{'"'}
    case '/':
      Some{'/'}
    case '\\':
      Some{'\\'}
    case 'N':
      Some{Chr{133}}
    case '_':
      Some{Chr{160}}
    case 'L':
      Some{Chr{8232}}
    case 'P':
      Some{Chr{8233}}
    case _:
      None{}

def q.simple(m: Maybe<&2, Char>, cur: Cur, acc: String, start: T.Mark) -> Qs:
  match m:
    case None{}:
      QsBad{T.Error{"found unknown escape character while parsing a quoted scalar", start, T.Syntax{}}}
    case Some{c}:
      q.text(adv.n(2n, cur), SCon{c, acc})

# A code point that is a character: not a surrogate, and at most 10FFFF.
def is_scalar.value(+x: U32) -> Bool:
  Bool.and(Bool.not(between(x, 55296, 57343)), U32.is_le(x, 1114111))

# \x, \u or \U and +n+ hex digits.
def q.hex(+n: Nat, +cur: Cur, acc: String, +start: T.Mark) -> Qs:
  +digits = String.take(String.drop(cur.s(cur), 2n), n)
  +x = hex.value(digits, 0)
  Bool.pick(Qs, Bool.not(Bool.and(Nat.is_eq(String.length(digits), n), all.hex(digits))),
    QsBad{T.Error{"did not find expected hexdecimal number while parsing a quoted scalar", start, T.Syntax{}}},
    Bool.pick(Qs, Bool.not(is_scalar.value(x)),
      QsBad{T.Error{"found invalid Unicode character escape code while parsing a quoted scalar", start, T.Syntax{}}},
      q.text(adv.n(Nat.add(n, 2n), cur), SCon{Chr{x}, acc})))

def q.escape(e: Char, cur: Cur, acc: String, start: T.Mark) -> Qs:
  match e:
    case '\n':
      Qs{adv.n(2n, cur), acc, "", True{}, 0n, True{}, False{}, False{}}
    case 'x':
      q.hex(2n, cur, acc, start)
    case 'u':
      q.hex(4n, cur, acc, start)
    case 'U':
      q.hex(8n, cur, acc, start)
    case _:
      q.simple(simple.escape(e), cur, acc, start)

def q.char(double: Bool, c: Char, +c1: Char, +cur: Cur, +acc: String, start: T.Mark) -> Qs:
  match double:
    case False{}:
      match c:
        case '\'':
          Bool.pick(Qs, Char.is_eq(c1, '\''), q.text(adv.n(2n, cur), SCon{'\'', acc}), QsDone{adv(cur), acc})
        case _:
          q.text(adv(cur), SCon{c, acc})
    case True{}:
      match c:
        case '"':
          QsDone{adv(cur), acc}
        case '\\':
          q.escape(c1, cur, acc, start)
        case _:
          q.text(adv(cur), SCon{c, acc})

def q.in.text(+double: Bool, +cur: Cur, +acc: String, +start: T.Mark) -> Qs:
  +s = cur.s(cur)
  +c = peek(s, 0n)
  Bool.pick(Qs, Bool.and(Nat.is_eq(cur.col(cur), 0n), is_marker(s)),
    QsBad{T.Error{"found unexpected document indicator while scanning a quoted scalar", start, T.Syntax{}}},
    Bool.pick(Qs, is_end(c), QsBad{T.Error{"found unexpected end of stream while scanning a quoted scalar", start, T.Syntax{}}},
      Bool.pick(Qs, Bool.or(is_blank(c), is_break(c)), Qs{cur, acc, "", False{}, 0n, False{}, False{}, False{}},
        q.char(double, c, peek(s, 1n), cur, acc, start))))

# The blanks and breaks between text: kept, or folded, once text resumes.
def q.joined(+acc: String, ws: String, lead: Bool, +brks: Nat, esc: Bool) -> String:
  match lead:
    case False{}:
      ws ++ acc
    case True{}:
      Bool.pick(String, esc, String.repeat("\n", brks), folded.breaks(brks)) ++ acc

# Between text: blanks and breaks wait to join it. A line after a break
# must be indented past the block around it (+ind+), with spaces.
def q.in.blanks(+cur: Cur, +acc: String, +ws: String, +lead: Bool, +brks: Nat, +esc: Bool, +bad: Bool, +ind: Nat, +start: T.Mark) -> Qs:
  +c = peek(cur.s(cur), 0n)
  +shallow = Nat.is_lt(cur.col(cur), ind)
  Bool.pick(Qs, is_blank(c), Qs{adv(cur), acc, Bool.pick(String, lead, ws, SCon{c, ws}), lead, brks, esc, False{}, Bool.or(bad, Bool.and(lead, Bool.and(shallow, Char.is_eq(c, '\t'))))},
    Bool.pick(Qs, is_break(c), Qs{adv(cur), acc, "", True{}, Bool.pick(Nat, lead, 1n+brks, 0n), esc, False{}, False{}},
      Bool.pick(Qs, Bool.and(lead, Bool.and(Bool.not(is_end(c)), Bool.or(bad, shallow))),
        QsBad{T.Error{"found a line indented too little in a quoted scalar while scanning a quoted scalar", start, T.Syntax{}}},
        q.text(cur, q.joined(acc, ws, lead, brks, esc)))))

def q.step(q: Qs, +double: Bool, +ind: Nat, +start: T.Mark) -> Qs:
  match q:
    case Qs{cur, acc, ws, lead, brks, esc, text, bad}:
      match text:
        case True{}:
          q.in.text(double, cur, acc, start)
        case False{}:
          q.in.blanks(cur, acc, ws, lead, brks, esc, bad, ind, start)
    case _:
      q

def q.run(fuel: Nat, +double: Bool, +ind: Nat, +start: T.Mark, q: Qs) -> Qs:
  match fuel:
    case 0n:
      q
    case 1n+k:
      match q:
        case Qs{cur, acc, ws, lead, brks, esc, text, bad}:
          q.run(k, double, ind, start, q.step(Qs{cur, acc, ws, lead, brks, esc, text, bad}, double, ind, start))
        case _:
          q

def quoted.done(q: Qs, +st: Sc, +double: Bool, start: T.Mark) -> Step:
  match q:
    case QsDone{cur, acc}:
      Go{emit(sc.with.cur(st, cur), T.ScalarTok{String.reverse(acc), Bool.pick(T.Style, double, T.Double{}, T.Single{})}, start)}
    case QsBad{e}:
      fail.with(st, e)
    case _:
      fail(st, "found unexpected end of stream while scanning a quoted scalar", start)

def quoted.scan(+st: Sc, +double: Bool) -> Step:
  +cur = sc.cur(st)
  +at = cur.at(cur)
  quoted.done(q.run(Nat.add(Nat.mul(cur.left(cur), 2n), 4n), double, sc.ind(st), at, q.text(adv(cur), "")), st, double, at)

def quoted(+st: Sc, +double: Bool) -> Step:
  then(save.key(st), st => quoted.scan(sc.allow(st, False{}), double))

def digit.value(c: Char) -> Nat:
  U32.to_nat(U32.sub(code(c), 48))

def chomp.of(c: Char) -> Maybe<&2, Chomp>:
  match c:
    case '+':
      Some{Keep{}}
    case '-':
      Some{Strip{}}
    case _:
      None{}

def chomp.or(m: Maybe<&2, Chomp>, d: Chomp) -> Chomp:
  match m:
    case None{}:
      d
    case Some{c}:
      c

def is_some.chomp(m: Maybe<&2, Chomp>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{c}:
      True{}

# Past blanks and a comment (after a blank), to a line break or the end.
def head.tail(s: String, +at: T.Mark, +left: Nat, +comment: Bool, +gap: Bool) -> Cur:
  match s:
    case SNil{}:
      Cur{SNil{}, at, left}
    case SCon{+c, +t}:
      +hash = Bool.and(Char.is_eq(c, '#'), gap)
      when(Cur, Bool.or(is_break(c), Bool.not(Bool.or(comment, Bool.or(is_blank(c), hash)))), u => Cur{SCon{c, t}, at, left},
        u => head.tail(t, past(at, c), Nat.sub(left, 1n), Bool.or(comment, hash), is_blank(c)))

def head.check(chomp: Chomp, +inc: Nat, +cur: Cur) -> Head:
  Bool.pick(Head, is_breakz(peek(cur.s(cur), 0n)), Head{chomp, inc, adv(cur)}, HeadBad{"did not find expected comment or line break while scanning a block scalar"})

def head.end(chomp: Chomp, +inc: Nat, cur: Cur) -> Head:
  match cur:
    case Cur{s, at, left}:
      head.check(chomp, inc, head.tail(s, at, left, False{}, False{}))

# The indicators after "|" or ">", in either order.
def header(+cur: Cur) -> Head:
  +s = cur.s(cur)
  +c0 = peek(s, 0n)
  +c1 = peek(s, 1n)
  +ch0 = chomp.of(c0)
  +ch1 = chomp.of(c1)
  +d0 = Bool.and(Char.is_digit(c0), Bool.not(Char.is_eq(c0, '0')))
  +d1 = Bool.and(Char.is_digit(c1), Bool.not(Char.is_eq(c1, '0')))
  when(Head, Bool.or(Char.is_eq(c0, '0'), Bool.and(is_some.chomp(ch0), Char.is_eq(c1, '0'))),
    u => HeadBad{"found an indentation indicator equal to 0 while scanning a block scalar"},
    u => when(Head, Bool.and(is_some.chomp(ch0), d1), u => head.end(chomp.or(ch0, Clip{}), digit.value(c1), adv.n(2n, cur)),
      u => when(Head, is_some.chomp(ch0), u => head.end(chomp.or(ch0, Clip{}), 0n, adv(cur)),
        u => when(Head, Bool.and(d0, is_some.chomp(ch1)), u => head.end(chomp.or(ch1, Clip{}), digit.value(c0), adv.n(2n, cur)),
          u => when(Head, d0, u => head.end(Clip{}, digit.value(c0), adv(cur)), u => head.end(Clip{}, 0n, cur))))))

# Blank lines and the indentation before content. The first content line
# sets the indentation when the header didn't; no blank line before it may
# be deeper. A tab may start content but not indentation. A last line of
# spaces with no break after it still counts as a line.
def bs.breaks(+cur: Cur, +acc: String, +ind: Nat, +max: Nat, +lead: Bool, +lblank: Bool, +brks: Nat, +pind: Nat, +start: T.Mark) -> Bs:
  +c = peek(cur.s(cur), 0n)
  +col = cur.col(cur)
  +inside = Bool.or(Nat.is_eq(ind, 0n), Nat.is_lt(1n+col, ind))
  +first = Bool.and(Nat.is_eq(ind, 0n), Nat.is_ge(col, pind))
  +partial = Bool.and(Nat.is_gt(col, 0n), Nat.is_gt(T.mark.line(cur.at(cur)), T.mark.line(start)))
  Bool.pick(Bs, Bool.and(Char.is_eq(c, ' '), inside), Bs{adv(cur), acc, ind, max, lead, lblank, brks, Breaks{}},
    Bool.pick(Bs, is_break(c), Bs{adv(cur), acc, ind, Nat.max(col, max), lead, lblank, 1n+brks, Breaks{}},
      Bool.pick(Bs, is_end(c), Bs{cur, acc, ind, max, lead, lblank, Bool.pick(Nat, partial, 1n+brks, brks), LineStart{}},
        Bool.pick(Bs, Bool.and(Bool.and(Char.is_eq(c, '\t'), inside), Bool.not(first)),
          BsBad{T.Error{"found a tab character where an indentation space is expected while scanning a block scalar", start, T.Syntax{}}},
          Bool.pick(Bs, Bool.and(first, Nat.is_gt(max, col)),
            BsBad{T.Error{"found a leading blank line with more spaces than the first content line while scanning a block scalar", start, T.Syntax{}}},
            Bs{cur, acc, Bool.pick(Nat, Nat.is_eq(ind, 0n), 1n+Nat.max(col, pind), ind), max, lead, lblank, brks, LineStart{}})))))

# A content line starts at the indentation: what waits joins the text.
def bs.line(+cur: Cur, +acc: String, +ind: Nat, +max: Nat, +lead: Bool, +lblank: Bool, +brks: Nat, +folded: Bool) -> Bs:
  +s = cur.s(cur)
  +c = peek(s, 0n)
  +fold = Bool.and(Bool.and(folded, lead), Bool.and(Bool.not(lblank), Bool.not(is_blank(c))))
  +joined = String.repeat("\n", brks) ++ Bool.pick(String, fold, Bool.pick(String, Nat.is_eq(brks, 0n), " ", ""), Bool.pick(String, lead, "\n", "")) ++ acc
  Bool.pick(Bs, Bool.or(Bool.not(Nat.is_eq(1n+cur.col(cur), ind)), Bool.or(is_end(c), Bool.and(Nat.is_eq(cur.col(cur), 0n), is_marker(s)))),
    BsDone{acc, lead, brks, cur},
    Bs{cur, joined, ind, max, False{}, is_blank(c), 0n, Content{}})

def bs.content(+cur: Cur, +acc: String, +ind: Nat, +max: Nat, +lblank: Bool) -> Bs:
  +c = peek(cur.s(cur), 0n)
  Bool.pick(Bs, is_end(c), BsDone{acc, True{}, 0n, cur},
    Bool.pick(Bs, is_break(c), Bs{adv(cur), acc, ind, max, True{}, lblank, 0n, Breaks{}},
      Bs{adv(cur), SCon{c, acc}, ind, max, False{}, lblank, 0n, Content{}}))

def bs.step(b: Bs, +folded: Bool, +pind: Nat, +start: T.Mark) -> Bs:
  match b:
    case Bs{cur, acc, ind, max, lead, lblank, brks, phase}:
      match phase:
        case Breaks{}:
          bs.breaks(cur, acc, ind, max, lead, lblank, brks, pind, start)
        case LineStart{}:
          bs.line(cur, acc, ind, max, lead, lblank, brks, folded)
        case Content{}:
          bs.content(cur, acc, ind, max, lblank)
    case _:
      b

def bs.run(fuel: Nat, +folded: Bool, +pind: Nat, +start: T.Mark, b: Bs) -> Bs:
  match fuel:
    case 0n:
      b
    case 1n+k:
      match b:
        case Bs{cur, acc, ind, max, lead, lblank, brks, phase}:
          bs.run(k, folded, pind, start, bs.step(Bs{cur, acc, ind, max, lead, lblank, brks, phase}, folded, pind, start))
        case _:
          b

# The final line break and the blank lines after the text.
def chomped(chomp: Chomp, +acc: String, +lead: Bool, +brks: Nat) -> String:
  match chomp:
    case Clip{}:
      Bool.pick(String, lead, SCon{'\n', acc}, acc)
    case Strip{}:
      acc
    case Keep{}:
      String.repeat("\n", brks) ++ Bool.pick(String, lead, SCon{'\n', acc}, acc)

def block.done(b: Bs, chomp: Chomp, +st: Sc, +folded: Bool, start: T.Mark) -> Step:
  match b:
    case BsDone{acc, lead, brks, cur}:
      Go{emit(sc.with.cur(st, cur), T.ScalarTok{String.reverse(chomped(chomp, acc, lead, brks)), Bool.pick(T.Style, folded, T.Folded{}, T.Literal{})}, start)}
    case BsBad{e}:
      fail.with(st, e)
    case _:
      fail(st, "found unexpected end of stream while scanning a block scalar", start)

def block.body(h: Head, +st: Sc, +folded: Bool, +start: T.Mark) -> Step:
  match h:
    case Head{chomp, +inc, +cur}:
      +pind = sc.ind(st)
      +given = Nat.add(pind, inc)
      block.done(bs.run(Nat.add(Nat.mul(cur.left(cur), 3n), 4n), folded, pind, start,
        Bs{cur, "", Bool.pick(Nat, Nat.is_eq(inc, 0n), 0n, given), 0n, False{}, False{}, 0n, Breaks{}}), chomp, st, folded, start)
    case HeadBad{why}:
      fail(st, why, start)

def block.scan(+st: Sc, +folded: Bool) -> Step:
  +cur = sc.cur(st)
  block.body(header(adv(cur)), st, folded, cur.at(cur))

def block.scalar(+st: Sc, +folded: Bool) -> Step:
  then(remove.key(st), st => block.scan(sc.allow(st, True{}), folded))

def taken.cons(c: Char, +k: Nat, t: Taken) -> Taken:
  match t:
    case Taken{text, n}:
      Taken{SCon{c, text}, Nat.add(k, n)}

def took.or(stop: Bool, more: Unit -> Taken) -> Taken:
  match stop:
    case True{}:
      Taken{"", 0n}
    case False{}:
      more(Unit{})

# An anchor's name: anything up to a blank, a break or a flow indicator.
def anchor.name(s: String) -> Taken:
  match s:
    case SNil{}:
      Taken{"", 0n}
    case SCon{+c, t}:
      took.or(Bool.or(is_blankz(c), is_flow.ind(c)), u => taken.cons(c, 1n, anchor.name(t)))

def anchor.took(t: Taken, +st: Sc, +is_anchor: Bool, +at: T.Mark) -> Step:
  match t:
    case Taken{+name, +n}:
      when(Step, String.is_empty(name),
        u => fail(st, Bool.pick(String, is_anchor, "did not find expected alphabetic or numeric character while scanning an anchor",
          "did not find expected alphabetic or numeric character while scanning an alias"), at),
        u => Go{emit(skip(st, 1n+n), Bool.pick(T.Tok, is_anchor, T.AnchorTok{name}, T.AliasTok{name}), at)})

def anchor.scan(+st: Sc, +is_anchor: Bool) -> Step:
  +at = sc.at(st)
  anchor.took(anchor.name(String.drop(sc.s(st), 1n)), st, is_anchor, at)

def anchor(+st: Sc, +is_anchor: Bool) -> Step:
  then(save.key(st), st => anchor.scan(sc.allow(st, False{}), is_anchor))

# Tag characters, with %XX escapes decoded; +uri+ allows all URI characters
# (in a verbatim tag or a %TAG prefix).
def taken.skip(t: Taken) -> Taken:
  match t:
    case Taken{text, n}:
      Taken{text, 1n+n}

def tag.chars(s: String, +uri: Bool, +pending: Nat) -> Taken:
  match s:
    case SNil{}:
      Taken{"", 0n}
    case SCon{+c, +t}:
      match pending:
        case 1n+k:
          taken.skip(tag.chars(t, uri, k))
        case 0n:
          +esc = Bool.and(Char.is_eq(c, '%'), Bool.and(is_hex(peek(t, 0n)), is_hex(peek(t, 1n))))
          +ok = Bool.pick(Bool, uri, is_uri(c), is_tag(c))
          took.or(Bool.not(Bool.or(esc, ok)),
            u => taken.cons(Bool.pick(Char, esc, Chr{hex.value(String.take(t, 2n), 0)}, c), 1n,
              tag.chars(t, uri, Bool.pick(Nat, esc, 2n, 0n))))

# What may follow a tag: a blank, a break, the end, or in flow a flow
# indicator.
def tag.ends(+c: Char, +flow: Bool) -> Bool:
  Bool.or(is_blankz(c), Bool.and(flow, is_flow.ind(c)))

def tag.emit(+st: Sc, handle: String, suffix: String, +n: Nat, +at: T.Mark) -> Step:
  +st2 = skip(st, n)
  +next = peek(sc.s(st2), 0n)
  when(Step, tag.ends(next, sc.in_flow(st2)),
    u => Go{emit(st2, T.TagTok{handle, suffix}, at)},
    u => fail(st2, Bool.pick(String, Char.is_eq(next, '%'), "did not find URI escaped octet while parsing a tag",
      "did not find expected whitespace or line break while scanning a tag"), at))

# "!<uri>".
def tag.verbatim(t: Taken, +st: Sc, +at: T.Mark) -> Step:
  match t:
    case Taken{+uri, +n}:
      when(Step, Bool.or(String.is_empty(uri), Bool.not(Char.is_eq(peek(String.drop(sc.s(st), Nat.add(n, 2n)), 0n), '>'))),
        u => fail(st, "did not find the expected '>' while scanning a tag", at),
        u => tag.emit(st, "", uri, Nat.add(n, 3n), at))

def tag.suffix(t: Taken, +named: Bool, +word: String, +k: Nat, +st: Sc, +at: T.Mark) -> Step:
  match t:
    case Taken{+suffix, +n}:
      +handle = Bool.pick(String, named, "!" ++ word ++ "!", "!")
      +used = Nat.add(1n, Bool.pick(Nat, named, Nat.add(1n+k, n), n))
      when(Step, Bool.and(named, String.is_empty(suffix)),
        u => fail(st, "did not find expected tag URI while parsing a tag", at),
        u => when(Step, String.is_empty(suffix), u => tag.emit(st, "", "!", used, at), u => tag.emit(st, handle, suffix, used, at)))

# "!suffix", "!!suffix", "!name!suffix", or "!" alone.
def tag.short(w: Taken, +st: Sc, +at: T.Mark) -> Step:
  match w:
    case Taken{+word, +k}:
      +s = String.drop(sc.s(st), 1n)
      +named = Char.is_eq(peek(s, k), '!')
      tag.suffix(tag.chars(String.drop(s, Bool.pick(Nat, named, 1n+k, 0n)), False{}, 0n), named, word, k, st, at)

def word.chars(s: String) -> Taken:
  match s:
    case SNil{}:
      Taken{"", 0n}
    case SCon{+c, t}:
      took.or(Bool.not(is_word(c)), u => taken.cons(c, 1n, word.chars(t)))

def tag.scan(+st: Sc) -> Step:
  +s = sc.s(st)
  +at = sc.at(st)
  when(Step, Char.is_eq(peek(s, 1n), '<'),
    u => tag.verbatim(tag.chars(String.drop(s, 2n), True{}, 0n), st, at),
    u => tag.short(word.chars(String.drop(s, 1n)), st, at))

def tag(+st: Sc) -> Step:
  then(save.key(st), st => tag.scan(sc.allow(st, False{})))

# Directives
# ----------

def count.or(go: Bool, more: Unit -> Nat) -> Nat:
  match go:
    case True{}:
      more(Unit{})
    case False{}:
      0n

def blanks(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{+c, t}:
      count.or(is_blank(c), u => 1n+blanks(t))

def digits(s: String) -> Taken:
  match s:
    case SNil{}:
      Taken{"", 0n}
    case SCon{+c, t}:
      took.or(Bool.not(Char.is_digit(c)), u => taken.cons(c, 1n, digits(t)))

def nat.of(s: String, acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{c, t}:
      nat.of(t, Nat.add(Nat.mul(acc, 10n), digit.value(c)))

def directive.put(+st: Sc, tok: Maybe<&2, T.Tok>, at: T.Mark) -> Sc:
  match tok:
    case None{}:
      st
    case Some{t}:
      emit(st, t, at)

def directive.tail(+cur: Cur, +st: Sc, tok: Maybe<&2, T.Tok>, +at: T.Mark) -> Step:
  when(Step, is_breakz(peek(cur.s(cur), 0n)),
    u => Go{directive.put(sc.with.cur(st, cur), tok, at)},
    u => fail(st, "did not find expected comment or line break while scanning a directive", at))

# After a directive: blanks, a comment, then a line break or the end.
def directive.end(+st: Sc, tok: Maybe<&2, T.Tok>, at: T.Mark) -> Step:
  directive.tail(head.tail(sc.s(st), sc.at(st), cur.left(sc.cur(st)), False{}, False{}), st, tok, at)

def version.done(m: Taken, +st: Sc, major: String, +used: Nat, +at: T.Mark) -> Step:
  match m:
    case Taken{+minor, +k}:
      when(Step, Nat.is_eq(k, 0n), u => fail(st, "did not find expected digit or '.' character while scanning a %YAML directive", at),
        u => directive.end(skip(st, Nat.add(used, k)), Some{T.VersionDir{nat.of(major, 0n), nat.of(minor, 0n)}}, at))

def version.minor(m: Taken, +st: Sc, +b: Nat, +at: T.Mark) -> Step:
  match m:
    case Taken{+major, +k}:
      +rest = String.drop(sc.s(st), Nat.add(b, k))
      +minor = digits(String.drop(rest, 1n))
      when(Step, Nat.is_eq(b, 0n), u => fail(st, "did not find expected whitespace while scanning a %YAML directive", at),
        u => when(Step, Bool.or(Nat.is_eq(k, 0n), Bool.not(Char.is_eq(peek(rest, 0n), '.'))),
          u => fail(st, "did not find expected digit or '.' character while scanning a %YAML directive", at),
          u => version.done(minor, st, major, Nat.add(b, Nat.add(k, 1n)), at)))

# "%YAML 1.2".
def version.scan(+st: Sc, +at: T.Mark) -> Step:
  +s = sc.s(st)
  +b = blanks(s)
  +major = digits(String.drop(s, b))
  version.minor(major, st, b, at)

def tagdir.prefix(p: Taken, +st: Sc, handle: String, +used: Nat, +at: T.Mark) -> Step:
  match p:
    case Taken{+prefix, +k}:
      when(Step, Nat.is_eq(k, 0n), u => fail(st, "did not find expected tag URI while scanning a %TAG directive", at),
        u => directive.end(skip(st, Nat.add(used, k)), Some{T.TagDir{handle, prefix}}, at))

def tagdir.handle(w: Taken, +st: Sc, +b: Nat, +at: T.Mark) -> Step:
  match w:
    case Taken{+word, +k}:
      +rest = String.drop(sc.s(st), b)
      +closed = Char.is_eq(peek(rest, 1n+k), '!')
      +hlen = Nat.add(1n+k, Bool.pick(Nat, closed, 1n, 0n))
      +handle = String.take(rest, hlen)
      +b2 = blanks(String.drop(rest, hlen))
      +ok = Bool.and(Char.is_eq(peek(rest, 0n), '!'), Bool.or(closed, Nat.is_eq(k, 0n)))
      when(Step, Bool.or(Nat.is_eq(b, 0n), Bool.not(ok)), u => fail(st, "did not find expected '!' while scanning a %TAG directive", at),
        u => when(Step, Nat.is_eq(b2, 0n), u => fail(st, "did not find expected whitespace while scanning a %TAG directive", at),
          u => tagdir.prefix(tag.chars(String.drop(rest, Nat.add(hlen, b2)), True{}, 0n), st, handle, Nat.add(b, Nat.add(hlen, b2)), at)))

# "%TAG !e! prefix".
def tagdir.scan(+st: Sc, +at: T.Mark) -> Step:
  +s = sc.s(st)
  +b = blanks(s)
  +rest = String.drop(s, b)
  tagdir.handle(word.chars(String.drop(rest, 1n)), st, b, at)

# Past the rest of a line.
def line.rest(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{+c, t}:
      count.or(Bool.not(is_break(c)), u => 1n+line.rest(t))

# %YAML, %TAG, or a reserved directive, which is skipped.
def directive.named(+name: String, +st: Sc, +at: T.Mark) -> Step:
  when(Step, String.eq(name, "YAML"), u => version.scan(st, at),
    u => when(Step, String.eq(name, "TAG"), u => tagdir.scan(st, at),
      u => Go{skip(st, line.rest(sc.s(st)))}))

def directive.name(w: Taken, +st: Sc, +at: T.Mark) -> Step:
  match w:
    case Taken{+name, +k}:
      when(Step, Nat.is_eq(k, 0n), u => fail(st, "could not find expected directive name while scanning a directive", at),
        u => directive.named(name, skip(st, 1n+k), at))

def directive.scan(+st: Sc) -> Step:
  +at = sc.at(st)
  directive.name(word.chars(String.drop(sc.s(st), 1n)), st, at)

def directive(+st: Sc) -> Step:
  then(remove.key(unroll(st, 0n)), st => directive.scan(sc.allow(st, False{})))

# Tokens
# ------

# "[" or "{", unless flow collections already nest as deep as allowed.
def flow.start(+st: Sc, t: T.Tok) -> Step:
  when(Step, Nat.is_ge(sc.flow(st), sc.max(st)), u => fail.limit(st, "found nesting deeper than the depth limit of " ++ Nat.show(sc.max(st))),
    u => then(save.key(st), st => Go{single(sc.allow(flow.push(st), True{}), t)}))

def flow.end(+st: Sc, t: T.Tok) -> Step:
  then(remove.key(st), st => Go{single(sc.allow(flow.pop(st), False{}), t)})

def flow.entry(+st: Sc) -> Step:
  then(remove.key(st), st => Go{single(sc.allow(st, True{}), T.FEntry{})})

def block.entry.rest(+st: Sc) -> Step:
  then(remove.key(st), st => Go{single(sc.allow(st, True{}), T.BEntry{})})

# "- ": a block sequence's entry, which may open the sequence.
def block.entry(+st: Sc) -> Step:
  when(Step, sc.in_flow(st), u => block.entry.rest(st),
    u => when(Step, sc.tab(st), u => fail(st, "found a tab character that violates indentation", sc.at(st)),
    u => when(Step, sc.allowed(st), u => block.entry.rest(roll(st, sc.col(st), None{}, T.BSeqStart{}, sc.at(st))),
      u => fail(st, "block sequence entries are not allowed in this context", sc.at(st)))))

def key.tok(+st: Sc) -> Sc:
  single(sc.allow(st, Bool.not(sc.in_flow(st))), T.KeyTok{})

def key.rest(+st: Sc) -> Step:
  then(remove.key(st), st => Go{key.tok(st)})

# "? ": an explicit key.
def key(+st: Sc) -> Step:
  when(Step, sc.in_flow(st), u => key.rest(st),
    u => when(Step, sc.tab(st), u => fail(st, "found a tab character that violates indentation", sc.at(st)),
    u => when(Step, sc.allowed(st), u => key.rest(roll(st, sc.col(st), None{}, T.BMapStart{}, sc.at(st))),
      u => fail(st, "mapping keys are not allowed in this context", sc.at(st)))))

def value.rest(+st: Sc) -> Sc:
  single(sc.allow(st, Bool.not(sc.in_flow(st))), T.ValueTok{})

def value.alone(+st: Sc) -> Step:
  when(Step, sc.in_flow(st), u => Go{value.rest(st)},
    u => when(Step, sc.allowed(st), u => Go{value.rest(roll(st, sc.col(st), None{}, T.BMapStart{}, sc.at(st)))},
      u => fail(st, "mapping values are not allowed in this context", sc.at(st))))

def insert.key(st: Sc, number: Nat, +at: T.Mark) -> Sc:
  match st:
    case Sc{cur, ind, inds, flow, allowed, tab, keys, out, +n, max}:
      Sc{cur, ind, inds, flow, allowed, tab, key.cleared(keys), insert(out, n, Some{number}, T.Token{T.KeyTok{}, at, at}), 1n+n, max}

# ": ": a value. When a simple key waits, it becomes a key: a KeyTok goes
# before it, and a block mapping may start at its column.
def value.with(k: SKey, +st: Sc) -> Step:
  match k:
    case SKey{possible, required, +number, +at, tab, low}:
      +rolls = Bool.and(Nat.is_eq(sc.flow(st), 0n), Nat.is_lt(sc.ind(st), 1n+T.mark.col(at)))
      when(Step, possible,
        u => when(Step, Bool.and(tab, rolls), u => fail(st, "found a tab character that violates indentation", at),
          u => Go{single(sc.allow(roll(insert.key(st, number, at), T.mark.col(at), Some{number}, T.BMapStart{}, at), False{}), T.ValueTok{})}),
        u => value.alone(st))

def value(+st: Sc) -> Step:
  value.with(key.top(sc.keys(st)), st)

def marker.tok(+st: Sc, t: T.Tok) -> Sc:
  emit(skip(sc.allow(st, False{}), 3n), t, sc.at(st))

# The stream ends on a line of its own.
def end.mark(m: T.Mark) -> T.Mark:
  match m:
    case T.Mark{+line, +col, +idx}:
      Bool.pick(T.Mark, Nat.is_eq(col, 0n), T.Mark{line, col, idx}, T.Mark{1n+line, 0n, idx})

def end.tok(+st: Sc) -> Sc:
  +at = end.mark(sc.at(st))
  emit.span(sc.allow(st, False{}), T.StreamEnd{}, at, at)

def doc.end.check(+st: Sc, t: T.Tok) -> Step:
  match t:
    case T.DocEnd{}:
      when(Step, is_breakz(peek(cur.s(head.tail(sc.s(st), sc.at(st), cur.left(sc.cur(st)), False{}, False{})), 0n)), u => Go{st},
        u => fail(st, "did not find expected comment or line break after a document end marker", sc.at(st)))
    case _:
      Go{st}

def doc.indicator(+st: Sc, +t: T.Tok) -> Step:
  then(remove.key(unroll(st, 0n)), st => doc.end.check(marker.tok(st, t), t))

def stream.end(+st: Sc) -> Step:
  then(remove.key(unroll(st, 0n)), st => Stop{end.tok(st)})

def is_plain.start(+c: Char) -> Bool:
  Bool.and(is_printable(c), Bool.not(Bool.or(is_blankz(c), is_in(c, "-?:,[]{}#&*!|>'\"%@`"))))

# The token a character starts.
def fetch.char(c: Char, +c1: Char, +flow: Bool, +st: Sc) -> Step:
  match c:
    case '[':
      flow.start(st, T.FSeqStart{})
    case '{':
      flow.start(st, T.FMapStart{})
    case ']':
      flow.end(st, T.FSeqEnd{})
    case '}':
      flow.end(st, T.FMapEnd{})
    case ',':
      flow.entry(st)
    case '-':
      when(Step, is_blankz(c1), u => block.entry(st), u => when(Step, Bool.and(flow, is_flow.ind(c1)), u => cannot(st), u => plain(st)))
    case '?':
      when(Step, Bool.or(is_blankz(c1), Bool.and(flow, is_flow.ind(c1))), u => key(st), u => plain(st))
    case ':':
      when(Step, Bool.or(is_blankz(c1), Bool.and(flow, Bool.or(is_flow.ind(c1), json.before(sc.out(st))))), u => value(st), u => plain(st))
    case '*':
      anchor(st, False{})
    case '&':
      anchor(st, True{})
    case '!':
      tag(st)
    case '|':
      when(Step, flow, u => cannot(st), u => block.scalar(st, False{}))
    case '>':
      when(Step, flow, u => cannot(st), u => block.scalar(st, True{}))
    case '\'':
      quoted(st, False{})
    case '"':
      quoted(st, True{})
    case _:
      when(Step, is_plain.start(c), u => plain(st), u => cannot(st))

def fetch.next(+st: Sc) -> Step:
  +s = sc.s(st)
  +c = peek(s, 0n)
  +col0 = Nat.is_eq(sc.col(st), 0n)
  when(Step, String.is_empty(s), u => stream.end(st),
    u => when(Step, Bool.and(col0, Char.is_eq(c, '%')), u => directive(st),
      u => when(Step, Bool.and(col0, marker(s, '-')), u => doc.indicator(st, T.DocStart{}),
        u => when(Step, Bool.and(col0, marker(s, '.')), u => doc.indicator(st, T.DocEnd{}),
          u => fetch.char(c, peek(s, 1n), sc.in_flow(st), st)))))

def fetch.after(+st: Sc) -> Step:
  fetch.next(unroll(st, 1n+sc.col(st)))

# One token (and the block tokens before it).
def fetch(+st: Sc) -> Step:
  then(skip.ws(st), st => then(stale(st), st => fetch.after(st)))

def scan.run(fuel: Nat, s: Step) -> List<&2, T.Token>:
  match fuel:
    case 0n:
      []
    case 1n+k:
      match s:
        case Go{st}:
          scan.run(k, fetch(st))
        case Stop{st}:
          List.reverse(&2, T.Token, sc.out(st))

# Where the first character YAML doesn't allow is (a control character, a
# surrogate), if there is one.
def unprintable(s: String, +at: T.Mark) -> Maybe<&2, T.Mark>:
  match s:
    case SNil{}:
      None{}
    case SCon{+c, t}:
      when(Maybe<&2, T.Mark>, is_printable(c), u => unprintable(t, past(at, c)), u => Some{at})

def stream.start() -> T.Token:
  T.Token{T.StreamStart{}, T.Mark{0n, 0n, 0n}, T.Mark{0n, 0n, 0n}}

def scan.start(m: Maybe<&2, T.Mark>, +s: String, max: Nat) -> List<&2, T.Token>:
  match m:
    case Some{+at}:
      [stream.start(), T.Token{T.Broken{T.Error{"control characters are not allowed", at, T.Syntax{}}}, at, at}]
    case None{}:
      scan.run(Nat.add(String.length(s), 4n), Go{Sc{Cur{s, T.Mark{0n, 0n, 0n}, String.length(s)}, 0n, [], 0n, True{}, False{}, [SKey{False{}, False{}, 0n, T.Mark{0n, 0n, 0n}, False{}, None{}}], [stream.start()], 1n, max}})

# The tokens of +text+, from StreamStart to StreamEnd, or to a Broken token
# at the first error. Flow collections may nest +max+ deep.
def scan(text: String, max: Nat) -> List<&2, T.Token>:
  +s = strip.bom(lf(text))
  scan.start(unprintable(s, T.Mark{0n, 0n, 0n}), s, max)
