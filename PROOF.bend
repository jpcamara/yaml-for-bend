# Proofs of the laws in LAWS.bend. `bend PROOF.bend` checks them.

import Base
import ./LAWS.bend as Laws
import ./src/token.bend as T
import ./src/value.bend as V
import ./src/emit.bend as E
import ./src/yaml.bend as Y
import ./src/compose.bend as C

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
