# bend-yaml's laws: facts the code must keep. PROOF.bend proves each one,
# and `bend PROOF.bend` prints ALL PROOFS CHECK while they all hold.

import Base
import ./src/token.bend as T
import ./src/value.bend as V
import ./src/emit.bend as E
import ./src/yaml.bend as Y
import ./src/compose.bend as C

# Writing
# -------

# A boolean written by dump is read back by load.
law bool_round_trip:
  for b: Bool
  {Y.load(Y.dump(V.Boolean{b})) == Done{V.Boolean{b}} : Result<&2, &2, T.Error, V.Yaml>}

# An integer is written as its text.
law int_text:
  for t: String
  {E.dump(V.Int{t}) == t ++ "\n" : String}

# Escaping for double quotes goes a character at a time: escaping two texts
# joined is joining them escaped.
law escape_append:
  for a: String
  for b: String
  {E.escaped(a ++ b) == E.escaped(a) ++ E.escaped(b) : String}

# Null is written as "null" and read back.
law null_round_trip:
  {Y.load(Y.dump(V.Null{})) == Done{V.Null{}} : Result<&2, &2, T.Error, V.Yaml>}

# The Core schema
# ---------------

# Integers are decimal text whatever base they're written in.
law core_ints:
  {Y.load("[0x1A, 0o17, -007, +5]") == Done{V.Seq{[V.Int{"26"}, V.Int{"15"}, V.Int{"-7"}, V.Int{"5"}]}} : Result<&2, &2, T.Error, V.Yaml>}

# YAML 1.1's yes and 010 are a string and ten under the Core schema.
law core_yes:
  {Y.load("{x: yes, y: 010}") == Done{V.Mapping{[V.Entry{V.Str{"x"}, V.Str{"yes"}}, V.Entry{V.Str{"y"}, V.Int{"10"}}]}} : Result<&2, &2, T.Error, V.Yaml>}

# A float keeps its text.
law core_float:
  {Y.load("1.50e3") == Done{V.Float{"1.50e3"}} : Result<&2, &2, T.Error, V.Yaml>}

# A key may appear once.
law core_duplicate:
  {Result.is_fail(&2, &2, T.Error, V.Yaml, Y.load("a: 1\na: 2")) == True{} : Bool}

# An alias is a copy of its anchored node.
law alias_copies:
  {Y.load("a: &x [1]\nb: *x") == Done{V.Mapping{[V.Entry{V.Str{"a"}, V.Seq{[V.Int{"1"}]}}, V.Entry{V.Str{"b"}, V.Seq{[V.Int{"1"}]}}]}} : Result<&2, &2, T.Error, V.Yaml>}

# A syntax error says what and where.
law core_syntax_error:
  {Y.load("a: b: c") == Fail{T.Error{"mapping values are not allowed in this context", T.Mark{0n, 4n, 4n}, T.Syntax{}}} : Result<&2, &2, T.Error, V.Yaml>}

# A date is a string under the Core schema.
law core_date:
  {Y.load("2001-12-14") == Done{V.Str{"2001-12-14"}} : Result<&2, &2, T.Error, V.Yaml>}

# The YAML 1.1 types
# ------------------

# yes is true, and 010 is octal.
law v11_yes:
  {Y.load.v11("{x: yes, y: 010}") == Done{V.Mapping{[V.Entry{V.Str{"x"}, V.Boolean{True{}}}, V.Entry{V.Str{"y"}, V.Int{"8"}}]}} : Result<&2, &2, T.Error, V.Yaml>}

# Base 60: 190:20:30 is 190 * 3600 + 20 * 60 + 30.
law v11_base60:
  {Y.load.v11("190:20:30") == Done{V.Int{"685230"}} : Result<&2, &2, T.Error, V.Yaml>}

# "_" goes anywhere among digits, and a float is exact decimal text.
law v11_float:
  {Y.load.v11("1_000.50") == Done{V.Float{"1000.5"}} : Result<&2, &2, T.Error, V.Yaml>}

# A timestamp keeps its text, tagged.
law v11_timestamp:
  {Y.load.v11("2001-12-14") == Done{V.Tagged{"tag:yaml.org,2002:timestamp", V.Str{"2001-12-14"}}} : Result<&2, &2, T.Error, V.Yaml>}

# "<<" merges a mapping in; the mapping's own keys win.
law v11_merge:
  {Y.load.v11("b: &b {x: 1, y: 2}\nc:\n  <<: *b\n  y: 3") ==
    Done{V.Mapping{[V.Entry{V.Str{"b"}, V.Mapping{[V.Entry{V.Str{"x"}, V.Int{"1"}}, V.Entry{V.Str{"y"}, V.Int{"2"}}]}},
      V.Entry{V.Str{"c"}, V.Mapping{[V.Entry{V.Str{"x"}, V.Int{"1"}}, V.Entry{V.Str{"y"}, V.Int{"3"}}]}}]}} : Result<&2, &2, T.Error, V.Yaml>}

# Under the Core schema, "<<" is just a key.
law core_no_merge:
  {Y.load("<<: {a: 1}") == Done{V.Mapping{[V.Entry{V.Str{"<<"}, V.Mapping{[V.Entry{V.Str{"a"}, V.Int{"1"}}]}}]}} : Result<&2, &2, T.Error, V.Yaml>}

# Aliases
# -------

# Aliases can't make a small text a huge tree: past the limit, it fails.
# With its aliases copied, this document is 20 nodes: the mapping, two
# keys, a list of four and a list of three copies of it.
law aliases_limited:
  {Result.is_fail(&2, &2, T.Error, V.Yaml, Y.load.with(C.Core{}, 12n, "a: &a [x, x, x]\nb: [*a, *a, *a]")) == True{} : Bool}

# At the limit, the same text loads.
law aliases_allowed:
  {Result.is_done(&2, &2, T.Error, V.Yaml, Y.load.with(C.Core{}, 20n, "a: &a [x, x, x]\nb: [*a, *a, *a]")) == True{} : Bool}
