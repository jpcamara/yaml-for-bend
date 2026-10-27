# The composer: events to values, through a schema.
#
# It reads the events in order with a stack of the collections still open.
# A scalar is resolved as it arrives; a collection is finished at its end
# event, where a mapping's keys are checked and merged. An anchored node is
# kept by name, and an alias is a copy of it. Every alias adds the size of
# its node to a count, and past a limit the document is refused, so a
# small text can't expand into a huge tree ("billion laughs").
#
# A key may appear once in a mapping; a repeat is an error. Under YAML 1.1,
# "<<" merges a mapping, or a list of them, into the mapping it's in: the
# mapping's own keys win, and among merged mappings the earlier wins.

import Base

import ./token.bend as T

import ./parse.bend as P

import ./value.bend as V

import ./core.bend as C

import ./yaml11.bend as Y11

# How scalars resolve: the YAML 1.2 Core schema, or the YAML 1.1 types.
type Schema is Data:
  Core{}
  Yaml11{}

# A finished node, and whether it is the merge key "<<".
type Item is Data:
  Item{val: V.Yaml, merge: Bool}

# A collection still open: its anchor and tag, its items so far (newest
# first; a mapping's alternate keys and values), how many nodes came before
# it, and where it starts.
type Open is Data:
  OSeq{anchor: Maybe<&2, String>, tag: P.Tag, items: List<&2, V.Yaml>, start: Nat, at: T.Mark}
  OMap{anchor: Maybe<&2, String>, tag: P.Tag, items: List<&2, Item>, start: Nat, at: T.Mark}

# An anchored node and how many nodes it holds.
type Anchored is Data:
  Anchored{val: V.Yaml, size: Nat}

# A document and where it starts.
type Doc is Data:
  Doc{val: V.Yaml, at: T.Mark}

# The composer: the open collections, the anchors, how many nodes the
# document has (aliases counted in full), the document's value once it has
# one, the documents so far (newest first), and where the document started.
type Co is Data:
  Co{stack: List<&2, Open>, anchors: Map<&2, Anchored>, count: Nat, root: Maybe<&2, V.Yaml>, docs: List<&2, Doc>, opened: T.Mark}

# Keys in order, and each key's entry, looked up by its canon text.
type Ord is Data:
  Ord{index: Map<&2, V.Entry>, order: List<&2, String>}

def when(-A: Type, hit: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match hit:
    case True{}:
      yes(Unit{})
    case False{}:
      no(Unit{})

def content(why: String, at: T.Mark) -> T.Error:
  T.Error{why, at, T.Content{}}

# Ordered mappings
# ----------------

def ord.new() -> Ord:
  Ord{Map.new(&2, V.Entry), []}

def ord.has(o: Ord, +key: V.Yaml) -> Bool:
  match o:
    case Ord{index, order}:
      Pair.snd(Map<&2, V.Entry>, Bool, Map.has(&2, V.Entry, index, V.canon(key)))

def ord.put.at(hm: Map<&2, V.Entry> & Bool, +order: List<&2, String>, +c: String, key: V.Yaml, val: V.Yaml) -> Ord:
  (m, has) = hm
  Ord{Map.set(&2, V.Entry, m, c, V.Entry{key, val}), Bool.pick(List<&2, String>, has, order, c <> order)}

# Puts +key+'s value: in its place when it's there, else at the end.
def ord.put(o: Ord, +key: V.Yaml, val: V.Yaml) -> Ord:
  match o:
    case Ord{index, order}:
      +c = V.canon(key)
      ord.put.at(Map.has(&2, V.Entry, index, c), order, c, key, val)

# Each entry put in turn.
def ord.merge(es: List<&2, V.Entry>, o: Ord) -> Ord:
  match es:
    case Nil{}:
      o
    case Con{e, rest}:
      match e:
        case V.Entry{k, v}:
          ord.merge(rest, ord.put(o, k, v))

# The entries whose keys aren't there yet.
def ord.fill(es: List<&2, V.Entry>, +o: Ord) -> Ord:
  match es:
    case Nil{}:
      o
    case Con{e, rest}:
      match e:
        case V.Entry{+k, v}:
          ord.fill(rest, Bool.pick(Ord, ord.has(o, k), o, ord.put(o, k, v)))

def ord.list(order: List<&2, String>, +m: Map<&2, V.Entry>) -> List<&2, V.Entry>:
  match order:
    case Nil{}:
      []
    case Con{c, rest}:
      Pair.snd(Map<&2, V.Entry>, V.Entry, Map.get(V.Entry, V.Entry{V.Null{}, V.Null{}}, m, c)) <> ord.list(rest, m)

def ord.entries(o: Ord) -> List<&2, V.Entry>:
  match o:
    case Ord{index, order}:
      ord.list(List.reverse(&2, String, order), index)

# Mappings
# --------

def key.text(v: V.Yaml) -> String:
  match v:
    case V.Str{t}:
      t
    case _:
      V.canon(v)

def item.val(i: Item) -> V.Yaml:
  match i:
    case Item{v, m}:
      v

def item.merge(i: Item) -> Bool:
  match i:
    case Item{v, m}:
      m

# A list of mappings merged, the earlier winning.
def merge.list(xs: List<&2, V.Yaml>, +o: Ord) -> Result<&2, &2, String, Ord>:
  match xs:
    case Nil{}:
      Done{o}
    case Con{x, rest}:
      match x:
        case V.Mapping{es}:
          merge.list(rest, ord.fill(es, o))
        case _:
          Fail{"found a merge value that isn't a mapping or a list of mappings"}

# What a "<<" brings in: a mapping's entries, or each of a list's.
def merge.value(v: V.Yaml, +o: Ord) -> Result<&2, &2, String, Ord>:
  match v:
    case V.Mapping{es}:
      Done{ord.fill(es, o)}
    case V.Seq{xs}:
      merge.list(xs, o)
    case _:
      Fail{"found a merge value that isn't a mapping or a list of mappings"}

def merge.step(r: Result<&2, &2, String, Ord>, +k: Item, v: Item, +seen: Bool) -> Result<&2, &2, String, Ord>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+o}:
      when(Result<&2, &2, String, Ord>, Bool.and(item.merge(k), seen), u => Fail{"found a duplicate key: <<"},
        u => when(Result<&2, &2, String, Ord>, item.merge(k), u => merge.value(item.val(v), o), u => Done{o}))

# The merged entries, from the mapping's "<<" (it may have one).
def merges(items: List<&2, Item>, r: Result<&2, &2, String, Ord>, +seen: Bool) -> Result<&2, &2, String, Ord>:
  match items:
    case Nil{}:
      r
    case Con{+k, more}:
      match more:
        case Nil{}:
          r
        case Con{v, rest}:
          merges(rest, merge.step(r, k, v, seen), Bool.or(seen, item.merge(k)))

def own.step(r: Result<&2, &2, String, Ord>, +k: Item, v: Item) -> Result<&2, &2, String, Ord>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+o}:
      +key = item.val(k)
      when(Result<&2, &2, String, Ord>, item.merge(k), u => Done{o},
        u => when(Result<&2, &2, String, Ord>, ord.has(o, key), u => Fail{"found a duplicate key: " ++ key.text(key)},
          u => Done{ord.put(o, key, item.val(v))}))

# The mapping's own entries, each key once.
def owns(items: List<&2, Item>, r: Result<&2, &2, String, Ord>) -> Result<&2, &2, String, Ord>:
  match items:
    case Nil{}:
      r
    case Con{k, more}:
      match more:
        case Nil{}:
          r
        case Con{v, rest}:
          owns(rest, own.step(r, k, v))

def joined(merged: Result<&2, &2, String, Ord>, own: Result<&2, &2, String, Ord>) -> Result<&2, &2, String, V.Yaml>:
  match merged:
    case Fail{e}:
      Fail{e}
    case Done{m}:
      match own:
        case Fail{e}:
          Fail{e}
        case Done{o}:
          Done{V.Mapping{ord.entries(ord.merge(ord.entries(o), m))}}

# A mapping from its keys and values, oldest first: merged entries first,
# then its own, which replace any merged ones with the same key.
def map.value(+items: List<&2, Item>) -> Result<&2, &2, String, V.Yaml>:
  joined(merges(items, Done{ord.new()}, False{}), owns(items, Done{ord.new()}))

# Scalars and collections
# -----------------------

def is_plain(s: T.Style) -> Bool:
  match s:
    case T.Plain{}:
      True{}
    case _:
      False{}

def scalar.value(s: Schema, t: P.Tag, +text: String, +plain: Bool) -> Result<&2, &2, String, V.Yaml>:
  match s:
    case Core{}:
      match t:
        case P.NoTag{}:
          Done{when(V.Yaml, plain, u => C.plain(text), u => V.Str{text})}
        case P.Tag{n}:
          C.tagged(n, text)
    case Yaml11{}:
      match t:
        case P.NoTag{}:
          Done{when(V.Yaml, plain, u => Y11.plain(text), u => V.Str{text})}
        case P.Tag{n}:
          Y11.tagged(n, text)

# Whether a scalar is YAML 1.1's merge key: "<<" plain, or tagged !!merge.
def is_merge(s: Schema, t: P.Tag, +text: String, +plain: Bool) -> Bool:
  match s:
    case Core{}:
      False{}
    case Yaml11{}:
      match t:
        case P.NoTag{}:
          Bool.and(plain, String.eq(text, "<<"))
        case P.Tag{n}:
          String.eq(n, C.yaml.tag("merge"))

def collection(t: P.Tag, v: V.Yaml) -> V.Yaml:
  match t:
    case P.NoTag{}:
      v
    case P.Tag{n}:
      C.collection(n, v)

# The composer's steps
# --------------------

def co.count(co: Co) -> Nat:
  match co:
    case Co{stack, anchors, count, root, docs, opened}:
      count

def co.docs(co: Co) -> List<&2, Doc>:
  match co:
    case Co{stack, anchors, count, root, docs, opened}:
      docs

# A finished node goes to the collection it's in, or is the document.
def attach(co: Co, item: Item) -> Co:
  match co:
    case Co{stack, anchors, count, root, docs, opened}:
      match stack:
        case Nil{}:
          Co{[], anchors, count, Some{item.val(item)}, docs, opened}
        case Con{top, rest}:
          match top:
            case OSeq{anchor, tag, items, start, at}:
              Co{OSeq{anchor, tag, item.val(item) <> items, start, at} <> rest, anchors, count, root, docs, opened}
            case OMap{anchor, tag, items, start, at}:
              Co{OMap{anchor, tag, item <> items, start, at} <> rest, anchors, count, root, docs, opened}

def name.anchor(m: Map<&2, Anchored>, anchor: Maybe<&2, String>, v: V.Yaml, size: Nat) -> Map<&2, Anchored>:
  match anchor:
    case None{}:
      m
    case Some{n}:
      Map.set(&2, Anchored, m, n, Anchored{v, size})

# A node of +size+ nodes is finished: its anchor names it, and the count
# grows by +more+ (the nodes not counted yet: a collection's items were).
def finish(co: Co, anchor: Maybe<&2, String>, +item: Item, +size: Nat, more: Nat) -> Co:
  match co:
    case Co{stack, anchors, count, root, docs, opened}:
      attach(Co{stack, name.anchor(anchors, anchor, item.val(item), size), Nat.add(count, more), root, docs, opened}, item)

def co.push(co: Co, o: Open) -> Co:
  match co:
    case Co{stack, anchors, count, root, docs, opened}:
      Co{o <> stack, anchors, count, root, docs, opened}

def node.done(r: Result<&2, &2, String, V.Yaml>, co: Co, anchor: Maybe<&2, String>, +merge: Bool, +size: Nat, more: Nat, at: T.Mark) -> Result<&2, &2, T.Error, Co>:
  match r:
    case Fail{why}:
      Fail{content(why, at)}
    case Done{v}:
      Done{finish(co, anchor, Item{v, merge}, size, more)}

def is_name(m: Maybe<&2, String>, +name: String) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{n}:
      String.eq(n, name)

# Whether a collection still open has the anchor +name+.
def opens(stack: List<&2, Open>, +name: String) -> Bool:
  match stack:
    case Nil{}:
      False{}
    case Con{o, rest}:
      match o:
        case OSeq{anchor, tag, items, start, at}:
          Bool.or(is_name(anchor, name), opens(rest, name))
        case OMap{anchor, tag, items, start, at}:
          Bool.or(is_name(anchor, name), opens(rest, name))

def found(hm: Map<&2, Anchored> & Bool) -> Bool:
  Pair.snd(Map<&2, Anchored>, Bool, hm)

def alias.got(ma: Map<&2, Anchored> & Anchored, +co: Co, +limit: Nat, at: T.Mark) -> Result<&2, &2, T.Error, Co>:
  (m, a) = ma
  match a:
    case Anchored{v, +size}:
      when(Result<&2, &2, T.Error, Co>, Nat.is_gt(Nat.add(co.count(co), size), limit),
        u => Fail{content("found more than " ++ Nat.show(limit) ++ " nodes through aliases", at)},
        u => Done{finish(co, None{}, Item{v, False{}}, size, size)})

# An alias: a copy of its node, counted at the node's full size. An alias
# inside the node it names would make a cycle, which a tree can't hold.
def co.alias(co: Co, +name: String, +limit: Nat, +at: T.Mark) -> Result<&2, &2, T.Error, Co>:
  match co:
    case Co{+stack, +anchors, count, root, docs, opened}:
      when(Result<&2, &2, T.Error, Co>, opens(stack, name),
        u => Fail{content("found an alias to a node that holds it: " ++ name ++ " is recursive, and a tree can't hold a cycle", at)},
        u => when(Result<&2, &2, T.Error, Co>, Bool.not(found(Map.has(&2, Anchored, anchors, name))),
          u => Fail{content("found an alias to an unknown anchor: " ++ name, at)},
          u => alias.got(Map.get(Anchored, Anchored{V.Null{}, 0n}, anchors, name), Co{stack, anchors, count, root, docs, opened}, limit, at)))

def co.doc.start(co: Co, at: T.Mark) -> Co:
  match co:
    case Co{stack, anchors, count, root, docs, opened}:
      Co{[], Map.new(&2, Anchored), 0n, None{}, docs, at}

def co.doc.end(co: Co) -> Co:
  match co:
    case Co{stack, anchors, count, root, docs, +opened}:
      Co{stack, anchors, count, None{}, Doc{Maybe.default(&2, V.Yaml, root, V.Null{}), opened} <> docs, opened}

def map.tagged(r: Result<&2, &2, String, V.Yaml>, t: P.Tag) -> Result<&2, &2, String, V.Yaml>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{v}:
      Done{collection(t, v)}

# The collection on top ends.
def co.close(co: Co) -> Result<&2, &2, T.Error, Co>:
  match co:
    case Co{stack, anchors, +count, root, docs, opened}:
      match stack:
        case Nil{}:
          Fail{content("found the end of a collection that never started", T.Mark{0n, 0n, 0n})}
        case Con{top, rest}:
          match top:
            case OSeq{anchor, tag, items, start, +at}:
              node.done(Done{collection(tag, V.Seq{List.reverse(&2, V.Yaml, items)})}, Co{rest, anchors, count, root, docs, opened}, anchor, False{}, 1n+Nat.sub(count, start), 1n, at)
            case OMap{anchor, tag, items, start, +at}:
              node.done(map.tagged(map.value(List.reverse(&2, Item, items)), tag), Co{rest, anchors, count, root, docs, opened}, anchor, False{}, 1n+Nat.sub(count, start), 1n, at)

def co.step(e: P.Evt, +co: Co, +s: Schema, +limit: Nat) -> Result<&2, &2, T.Error, Co>:
  match e:
    case P.Evt{ev, +at}:
      match ev:
        case P.StreamStartEv{}:
          Done{co}
        case P.StreamEndEv{}:
          Done{co}
        case P.DocStartEv{explicit}:
          Done{co.doc.start(co, at)}
        case P.DocEndEv{explicit}:
          Done{co.doc.end(co)}
        case P.AliasEv{name}:
          co.alias(co, name, limit, at)
        case P.ScalarEv{anchor, +tag, +text, style}:
          +plain = is_plain(style)
          node.done(scalar.value(s, tag, text, plain), co, anchor, is_merge(s, tag, text, plain), 1n, 1n, at)
        case P.SeqStartEv{anchor, tag, flow}:
          Done{co.push(co, OSeq{anchor, tag, [], co.count(co), at})}
        case P.SeqEndEv{}:
          co.close(co)
        case P.MapStartEv{anchor, tag, flow}:
          Done{co.push(co, OMap{anchor, tag, [], co.count(co), at})}
        case P.MapEndEv{}:
          co.close(co)

def co.run(evs: List<&2, P.Evt>, +s: Schema, +limit: Nat, r: Result<&2, &2, T.Error, Co>) -> Result<&2, &2, T.Error, Co>:
  match evs:
    case Nil{}:
      r
    case Con{e, rest}:
      match r:
        case Fail{err}:
          Fail{err}
        case Done{+co}:
          co.run(rest, s, limit, co.step(e, co, s, limit))

# How many nodes aliases may make a document: past this, it's refused.
def alias.limit() -> Nat:
  100000n

def co.new() -> Co:
  Co{[], Map.new(&2, Anchored), 0n, None{}, [], T.Mark{0n, 0n, 0n}}

def composed.ok(r: Result<&2, &2, T.Error, Co>) -> Result<&2, &2, T.Error, List<&2, Doc>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{co}:
      Done{List.reverse(&2, Doc, co.docs(co))}

# A text that isn't YAML is a syntax error, before anything its values do
# wrong.
def composed(r: Result<&2, &2, T.Error, Co>, error: Maybe<&2, T.Error>) -> Result<&2, &2, T.Error, List<&2, Doc>>:
  match error:
    case None{}:
      composed.ok(r)
    case Some{e}:
      Fail{e}

# The documents the events hold, through schema +s+, with aliases making at
# most +limit+ nodes in a document.
def compose.limited(p: P.Parsed, +s: Schema, +limit: Nat) -> Result<&2, &2, T.Error, List<&2, Doc>>:
  match p:
    case P.Parsed{events, error}:
      composed(co.run(events, s, limit, Done{co.new()}), error)
