# Numbers kept as text. Bend's Nat stops at 2^48, so an integer of any size
# is a list of decimal digits, and a float is exact decimal text.

import Base

# The exponent after "e": its sign and digits, as an offset point shift.
type Exp is Data:
  Exp{neg: Bool, n: Nat}

def when(-A: Type, hit: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match hit:
    case True{}:
      yes(Unit{})
    case False{}:
      no(Unit{})

def code(c: Char) -> U32:
  match c:
    case Chr{x}:
      x

# A digit's value, for digits up to base 36 ("a" and "A" are 10).
def digit(c: Char) -> Nat:
  +x = code(c)
  U32.to_nat(U32.sub(x, Bool.pick(U32, U32.is_ge(x, 97), 87, Bool.pick(U32, U32.is_ge(x, 65), 55, 48))))

def digit.char(n: Nat) -> Char:
  Chr{U32.add(48, U32.from_nat(n))}

# Big numbers
# -----------

# A natural number's decimal digits, least significant first, with no
# zeros at the end of the list. Zero is the empty list.

def big.chars(s: String) -> List<&2, Nat>:
  match s:
    case SNil{}:
      []
    case SCon{c, t}:
      digit(c) <> big.chars(t)

def big.trim.go(ds: List<&2, Nat>) -> List<&2, Nat>:
  match ds:
    case Nil{}:
      []
    case Con{+d, +rest}:
      when(List<&2, Nat>, Nat.is_eq(d, 0n), u => big.trim.go(rest), u => d <> rest)

def big.trim(ds: List<&2, Nat>) -> List<&2, Nat>:
  List.reverse(&2, Nat, big.trim.go(List.reverse(&2, Nat, ds)))

# A Nat that fits, as a big number.
def big.of.nat(+n: Nat) -> List<&2, Nat>:
  big.trim(List.reverse(&2, Nat, big.chars(Nat.show(n))))

# +ds+ times +base+, plus +carry+.
def big.mul.add(ds: List<&2, Nat>, +base: Nat, carry: Nat) -> List<&2, Nat>:
  match ds:
    case Nil{}:
      big.of.nat(carry)
    case Con{d, rest}:
      +x = Nat.add(Nat.mul(d, base), carry)
      Nat.mod(x, 10n) <> big.mul.add(rest, base, Nat.div(x, 10n))

# The digits of +s+ in +base+ (each a digit of that base) as a big number.
def big.read(s: String, +base: Nat, acc: List<&2, Nat>) -> List<&2, Nat>:
  match s:
    case SNil{}:
      acc
    case SCon{c, t}:
      big.read(t, base, big.mul.add(acc, base, digit(c)))

def big.digits(ds: List<&2, Nat>) -> String:
  match ds:
    case Nil{}:
      ""
    case Con{d, rest}:
      SCon{digit.char(d), big.digits(rest)}

def big.show(+ds: List<&2, Nat>) -> String:
  Bool.pick(String, List.is_empty(&2, Nat, ds), "0", String.reverse(big.digits(ds)))

# An integer's text: "-" when negative and not zero.
def signed(+neg: Bool, +digits: String) -> String:
  Bool.pick(String, Bool.and(neg, Bool.not(String.eq(digits, "0"))), "-" ++ digits, digits)

# +s+, digits of +base+, as decimal text with the sign.
def int.text(+neg: Bool, s: String, +base: Nat) -> String:
  signed(neg, big.show(big.read(s, base, [])))

# Exact decimals
# --------------

def zeros(n: Nat) -> String:
  String.repeat("0", n)

def drop.zeros(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      match c:
        case '0':
          drop.zeros(t)
        case _:
          SCon{c, t}

def take.digits(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+c, t}:
      when(String, Char.is_digit(c), u => SCon{c, take.digits(t)}, u => "")

# The decimal whose digits are +ds+ (no zeros at either end) with the point
# +point+ places from their left, written "12.5", "0.001" or "300.0". The
# point is offset by +off+ so it can be negative.
def dec.place(+ds: String, +point: Nat, +off: Nat) -> String:
  +n = String.length(ds)
  when(String, String.is_empty(ds), u => "0.0",
    u => when(String, Nat.is_le(point, off), u => "0." ++ zeros(Nat.sub(off, point)) ++ ds,
      u => when(String, Nat.is_ge(Nat.sub(point, off), n), u => ds ++ zeros(Nat.sub(Nat.sub(point, off), n)) ++ ".0",
        u => String.take(ds, Nat.sub(point, off)) ++ "." ++ String.drop(ds, Nat.sub(point, off)))))

# Where a decimal's point is counted from, so it can go left of the
# digits; an exponent is capped below it.
def dec.off() -> Nat:
  1000n

def big.small(s: String, acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{c, t}:
      big.small(t, Nat.add(Nat.mul(acc, 10n), digit(c)))

# Exponent digits as a Nat, capped past where a double ends (about 308).
def exp.nat(+s: String) -> Nat:
  +n = big.small(s, 0n)
  when(Nat, Bool.or(Nat.is_gt(String.length(s), 3n), Nat.is_gt(n, 999n)), u => 999n, u => n)

def exp.read(s: String) -> Exp:
  match s:
    case SCon{c, t}:
      match c:
        case '-':
          Exp{True{}, exp.nat(t)}
        case '+':
          Exp{False{}, exp.nat(t)}
        case _:
          Exp{False{}, exp.nat(SCon{c, t})}
    case SNil{}:
      Exp{False{}, 0n}

def after.e(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      match c:
        case 'e':
          t
        case 'E':
          t
        case _:
          after.e(t)

def after.dot(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      match c:
        case '.':
          t
        case _:
          after.dot(t)

def point.at(+ip: Nat, e: Exp) -> Nat:
  match e:
    case Exp{neg, +n}:
      Bool.pick(Nat, neg, Nat.sub(Nat.add(dec.off(), ip), n), Nat.add(Nat.add(dec.off(), ip), n))

def strip.end.zeros(s: String) -> String:
  String.reverse(drop.zeros(String.reverse(s)))

# The value of a decimal literal ("1_000.5" without the "_", ".5", "1.",
# "2.5e-3"), written exactly: "1000.5", "0.5", "1.0", "0.0025". Past what a
# double holds it is ".inf"; under, zero.
def dec.exact(+s: String) -> String:
  +neg = String.starts_with(s, "-")
  +body = Bool.pick(String, Bool.or(neg, String.starts_with(s, "+")), String.drop(s, 1n), s)
  +ip = take.digits(body)
  +fp = take.digits(after.dot(body))
  +e = exp.read(after.e(body))
  +all = ip ++ fp
  +lead = Nat.sub(String.length(all), String.length(drop.zeros(all)))
  +ds = strip.end.zeros(drop.zeros(all))
  +point = Nat.sub(point.at(String.length(ip), e), lead)
  +sign = Bool.pick(String, neg, "-", "")
  when(String, Bool.and(Bool.not(String.is_empty(ds)), Nat.is_gt(point, Nat.add(dec.off(), 309n))), u => sign ++ ".inf",
    u => when(String, Bool.or(String.is_empty(ds), Nat.is_lt(Nat.add(point, 330n), dec.off())), u => sign ++ "0.0",
      u => sign ++ dec.place(ds, point, dec.off())))
