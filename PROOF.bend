# Proofs of the laws in LAWS.bend. `bend PROOF.bend` checks them.

import Base
import ./LAWS.bend as Laws
import ./src/token.bend as T
import ./src/value.bend as V
import ./src/emit.bend as E
import ./src/yaml.bend as Y
import ./src/compose.bend as C
import ./src/core.bend as Core
import ./src/yaml11.bend as Y11

# Joining texts is associative.
def append.assoc(x: String, -y: String, -z: String) -> {String.append(String.append(x, y), z) == String.append(x, String.append(y, z)) : String}:
  match x:
    case SNil{}:
      {==}
    case SCon{h, t}:
      %append.assoc(t, y, z) : {SCon{h, String.append(String.append(t, y), z)} == SCon{h, _} : String}
      {==}

def Laws.bool_round_trip(b):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.int_text(t):
  {==}

def Laws.escape_append(a, b):
  match a:
    case SNil{}:
      {==}
    case SCon{c, t}:
      %Equal.sym(String, String.append(String.append(E.escape(c), E.escaped(t)), E.escaped(b)), String.append(E.escape(c), String.append(E.escaped(t), E.escaped(b))), append.assoc(E.escape(c), E.escaped(t), E.escaped(b))) : {String.append(E.escape(c), E.escaped(String.append(t, b))) == _ : String}
      %Laws.escape_append(t, b) : {String.append(E.escape(c), E.escaped(String.append(t, b))) == String.append(E.escape(c), _) : String}
      {==}

def Laws.null_round_trip():
  {==}

def Laws.core_ints():
  {==}

def Laws.core_yes():
  {==}

def Laws.core_float():
  {==}

def Laws.core_duplicate():
  {==}

def Laws.alias_copies():
  {==}








def Laws.aliases_limited():
  {==}

def Laws.aliases_allowed():
  {==}

def Laws.core_syntax_error():
  {==}

def Laws.core_date():
  {==}

def Laws.v11_yes():
  {==}

def Laws.v11_base60():
  {==}

def Laws.v11_float():
  {==}

def Laws.v11_timestamp():
  {==}

def Laws.v11_merge():
  {==}

def Laws.core_no_merge():
  {==}

def Laws.core_unknown_tag(tag, s, unknown):
  %Equal.sym(Bool, Core.known(tag), False{}, unknown) : {Core.read.or.keep(_, tag, s) == Done{V.Tagged{tag, V.Str{s}}} : Result<&2, &2, String, V.Yaml>}
  {==}

def Laws.v11_unknown_tag(tag, s, unknown):
  %Equal.sym(Bool, Y11.known(tag), False{}, unknown) : {Y11.read.or.keep(_, tag, s) == Done{V.Tagged{tag, V.Str{s}}} : Result<&2, &2, String, V.Yaml>}
  {==}

def Laws.unknown_collection_tag(tag, v, unknown):
  %Equal.sym(Bool, Core.known.collection(tag), False{}, unknown) : {Core.collection.or.keep(_, tag, v) == V.Tagged{tag, v} : V.Yaml}
  {==}


def Laws.size_limited():
  {==}

def Laws.depth_limited_block():
  {==}

def Laws.depth_limited_flow():
  {==}

def Laws.depth_allowed():
  {==}

def Laws.digits_limited():
  {==}

def Laws.digits_quoted():
  {==}

def Laws.object_tag_is_data():
  {==}
