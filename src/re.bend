# A small regular-expression matcher, for the scalar forms schemas name as
# regexes. A pattern is data: a list of items, each a character class, an
# optional or repeated item, or a choice of sequences. Matching is anchored
# at both ends and backtracks. Each step eats a character or moves along the
# pattern, so fuel of the text's length times a constant bounds the work.

import Base

type Cls is Data:
  Digit{}
  Hex{}
  Range{lo: Char, hi: Char}
  Lit{c: Char}
  OneOf{chars: String}
  NoneOf{chars: String}
  Alpha{}
  Space{}
  Anything{}

type Pat is Data:
  One{cls: Cls}
  Opt{p: Pat}
  Star{p: Pat}
  Plus{p: Pat}
  Alt{alts: List<&2, List<&2, Pat>>}

def code(c: Char) -> U32:
  match c:
    case Chr{x}:
      x

def between(+x: U32, lo: U32, hi: U32) -> Bool:
  Bool.and(U32.is_ge(x, lo), U32.is_le(x, hi))

def in(c: Char, s: String) -> Bool:
  String.contains(s, SCon{c, SNil{}})

# [[:alpha:]] as Onigmo reads it: ASCII letters, and letters past ASCII.
def is_alpha(+x: U32) -> Bool:
  Bool.or(Bool.or(between(x, 65, 90), between(x, 97, 122)),
    Bool.or(between(x, 170, 170), Bool.or(between(x, 181, 181), Bool.or(between(x, 186, 186),
      Bool.and(U32.is_ge(x, 192), Bool.and(Bool.not(U32.is_eq(x, 215)), Bool.not(U32.is_eq(x, 247))))))))

def test(cls: Cls, +c: Char) -> Bool:
  match cls:
    case Digit{}:
      Char.is_digit(c)
    case Hex{}:
      Bool.or(Char.is_digit(c), Bool.or(between(code(c), 65, 70), between(code(c), 97, 102)))
    case Range{lo, hi}:
      between(code(c), code(lo), code(hi))
    case Lit{x}:
      Char.is_eq(c, x)
    case OneOf{chars}:
      in(c, chars)
    case NoneOf{chars}:
      Bool.not(in(c, chars))
    case Alpha{}:
      is_alpha(code(c))
    case Space{}:
      Char.is_space(c)
    case Anything{}:
      True{}

def or.else(hit: Bool, rest: Unit -> Bool) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      rest(Unit{})

def and.then(hit: Bool, rest: Unit -> Bool) -> Bool:
  match hit:
    case True{}:
      rest(Unit{})
    case False{}:
      False{}

def run(fuel: Nat, ps: List<&2, Pat>, +s: String) -> Bool:
  match fuel:
    case 0n:
      False{}
    case 1n+(+k):
      match ps:
        case Nil{}:
          String.is_empty(s)
        case Con{p, +rest}:
          match p:
            case One{cls}:
              match s:
                case SNil{}:
                  False{}
                case SCon{+c, t}:
                  and.then(test(cls, c), u => run(k, rest, t))
            case Opt{+q}:
              or.else(run(k, q <> rest, s), u => run(k, rest, s))
            case Star{+q}:
              or.else(run(k, q <> Star{q} <> rest, s), u => run(k, rest, s))
            case Plus{+q}:
              run(k, q <> Star{q} <> rest, s)
            case Alt{alts}:
              match alts:
                case Nil{}:
                  False{}
                case Con{a, others}:
                  or.else(run(k, List.append(&2, Pat, a, rest), s), u => run(k, Alt{others} <> rest, s))

# Whether all of +s+ matches +ps+.
def matches(ps: List<&2, Pat>, +s: String) -> Bool:
  run(Nat.mul(Nat.add(String.length(s), 2n), 64n), ps, s)

# Whether +s+ starts with a match of +ps+.
def starts(ps: List<&2, Pat>, +s: String) -> Bool:
  matches(List.append(&2, Pat, ps, [Star{One{Anything{}}}]), s)

# Builders, so a pattern reads close to the regex it comes from.
def c(x: Char) -> Pat:
  One{Lit{x}}

def digit() -> Pat:
  One{Digit{}}

def digits() -> Pat:
  Plus{One{Digit{}}}

def sign() -> Pat:
  Opt{One{OneOf{"-+"}}}

def of(chars: String) -> Pat:
  One{OneOf{chars}}

def seq(ps: List<&2, Pat>) -> Pat:
  Alt{[ps]}

def word(s: String) -> List<&2, Pat>:
  match s:
    case SNil{}:
      []
    case SCon{x, t}:
      c(x) <> word(t)
