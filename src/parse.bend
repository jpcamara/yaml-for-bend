# The parser: tokens to events.
#
# It follows libyaml's parser: a state machine with a stack of the states to
# return to. Each step looks at the next token and may take it and may emit
# an event. Where libyaml looks at two tokens in one call, this parser takes
# two steps, with a state in between, so a step never looks past one token.
# Where YAML 1.2 and libyaml disagree, it reads YAML 1.2: ": value" with no
# key has an empty key, a flow mapping's key may end on an earlier line
# than its ":", a stream may start with "...", and a bare document may
# follow "...".

import Base

import ./token.bend as T

import ./scan.bend as S

# A node's tag, resolved: none, or its full name ("!" when non-specific).
type Tag is Data:
  NoTag{}
  Tag{name: String}

# An event, as libyaml's are.
type Ev is Data:
  StreamStartEv{}
  StreamEndEv{}
  DocStartEv{explicit: Bool}
  DocEndEv{explicit: Bool}
  AliasEv{name: String}
  ScalarEv{anchor: Maybe<&2, String>, tag: Tag, text: String, style: T.Style}
  SeqStartEv{anchor: Maybe<&2, String>, tag: Tag, flow: Bool}
  SeqEndEv{}
  MapStartEv{anchor: Maybe<&2, String>, tag: Tag, flow: Bool}
  MapEndEv{}

# An event and where its node starts.
type Evt is Data:
  Evt{ev: Ev, at: T.Mark}

# A tag as written: its handle and suffix.
type Written is Data:
  Written{handle: String, suffix: String}

# A %TAG directive: a handle and the prefix it stands for.
type Prefix is Data:
  Prefix{handle: String, prefix: String}

# The parser's states. A collection's state keeps where it started, for
# errors; "After" states have just taken an indicator and keep where it
# ended, where an empty node would be.
type St is Data:
  SStreamStart{}
  SFirstDoc{}
  SDocStart{ended: Bool}
  SDocContent{}
  SDocEnd{}
  SNode{block: Bool, indentless: Bool, anchor: Maybe<&2, String>, tag: Maybe<&2, Written>, start: Maybe<&2, T.Mark>}
  SBSeqFirst{}
  SBSeqEntry{m: T.Mark}
  SBSeqAfter{m: T.Mark, e: T.Mark}
  SIndentless{m: T.Mark}
  SIndentlessAfter{m: T.Mark, e: T.Mark}
  SBMapFirst{}
  SBMapKey{m: T.Mark}
  SBMapAfterKey{m: T.Mark, e: T.Mark}
  SBMapValue{m: T.Mark}
  SBMapAfterValue{m: T.Mark, e: T.Mark}
  SFSeqFirst{}
  SFSeqEntry{m: T.Mark, first: Bool}
  SFSeqMapKey{m: T.Mark}
  SFSeqMapValue{m: T.Mark}
  SFSeqMapAfterValue{m: T.Mark, e: T.Mark}
  SFSeqMapEnd{m: T.Mark}
  SFMapFirst{}
  SFMapKey{m: T.Mark, first: Bool}
  SFMapAfterKey{m: T.Mark, e: T.Mark}
  SFMapValue{m: T.Mark}
  SFMapAfterValue{m: T.Mark, e: T.Mark}
  SFMapEmpty{m: T.Mark}
  SEnd{}

# The parser: the tokens left, the state, the states to return to, the
# document's tag prefixes, and the events so far (newest first).
type Ps is Data:
  Ps{toks: List<&2, T.Token>, state: St, states: List<&2, St>, tags: List<&2, Prefix>, out: List<&2, Evt>}

type PStep is Data:
  PGo{ps: Ps}
  PStop{ps: Ps, error: Maybe<&2, T.Error>}

# The events, and the error that ended them early, if one did.
type Parsed is Data:
  Parsed{events: List<&2, Evt>, error: Maybe<&2, T.Error>}

# Directives
# ----------

# The directives before a document: its %TAG prefixes (over the defaults),
# checking that %YAML comes at most once and is 1.x and that no handle
# repeats.
type Dirs is Data:
  Dirs{toks: List<&2, T.Token>, tags: List<&2, Prefix>}
  DirsBad{error: T.Error}

def when(-A: Type, hit: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match hit:
    case True{}:
      yes(Unit{})
    case False{}:
      no(Unit{})

# The parser's state
# ------------------

def ps.out(ps: Ps) -> List<&2, Evt>:
  match ps:
    case Ps{toks, state, states, tags, out}:
      out

def ps.tags(ps: Ps) -> List<&2, Prefix>:
  match ps:
    case Ps{toks, state, states, tags, out}:
      tags

def ps.state(ps: Ps) -> St:
  match ps:
    case Ps{toks, state, states, tags, out}:
      state

# Takes the next token.
def take(ps: Ps) -> Ps:
  match ps:
    case Ps{toks, state, states, tags, out}:
      Ps{List.drop(&2, T.Token, toks, 1n), state, states, tags, out}

def emit(ps: Ps, ev: Ev, at: T.Mark) -> Ps:
  match ps:
    case Ps{toks, state, states, tags, out}:
      Ps{toks, state, states, tags, Evt{ev, at} <> out}

def goto(ps: Ps, s: St) -> Ps:
  match ps:
    case Ps{toks, state, states, tags, out}:
      Ps{toks, s, states, tags, out}

def push(ps: Ps, s: St) -> Ps:
  match ps:
    case Ps{toks, state, states, tags, out}:
      Ps{toks, state, s <> states, tags, out}

# Returns to the state on the stack.
def pop(ps: Ps) -> Ps:
  match ps:
    case Ps{toks, state, states, tags, out}:
      match states:
        case Nil{}:
          Ps{toks, SEnd{}, [], tags, out}
        case Con{s, rest}:
          Ps{toks, s, rest, tags, out}

def with.tags(ps: Ps, ts: List<&2, Prefix>) -> Ps:
  match ps:
    case Ps{toks, state, states, tags, out}:
      Ps{toks, state, states, ts, out}

def fail(ps: Ps, why: String, at: T.Mark) -> PStep:
  PStop{ps, Some{T.Error{why, at, T.Syntax{}}}}

def empty(ps: Ps, at: T.Mark) -> Ps:
  emit(ps, ScalarEv{None{}, NoTag{}, "", T.Plain{}}, at)

# Tokens
# ------

def tok.kind(t: T.Token) -> T.Tok:
  match t:
    case T.Token{tok, start, end}:
      tok

def tok.start(t: T.Token) -> T.Mark:
  match t:
    case T.Token{tok, start, end}:
      start

def tok.end(t: T.Token) -> T.Mark:
  match t:
    case T.Token{tok, start, end}:
      end

# A token's kind as a number, to test it against a few.
def kind.index(t: T.Tok) -> Nat:
  match t:
    case T.StreamStart{}:
      0n
    case T.StreamEnd{}:
      1n
    case T.VersionDir{a, b}:
      2n
    case T.TagDir{h, p}:
      3n
    case T.DocStart{}:
      4n
    case T.DocEnd{}:
      5n
    case T.BSeqStart{}:
      6n
    case T.BMapStart{}:
      7n
    case T.BEnd{}:
      8n
    case T.FSeqStart{}:
      9n
    case T.FSeqEnd{}:
      10n
    case T.FMapStart{}:
      11n
    case T.FMapEnd{}:
      12n
    case T.BEntry{}:
      13n
    case T.FEntry{}:
      14n
    case T.KeyTok{}:
      15n
    case T.ValueTok{}:
      16n
    case T.AliasTok{n}:
      17n
    case T.AnchorTok{n}:
      18n
    case T.TagTok{h, s}:
      19n
    case T.ScalarTok{t, s}:
      20n
    case T.Broken{e}:
      21n

def tok.is(+t: T.Token, k: Nat) -> Bool:
  Nat.is_eq(kind.index(tok.kind(t)), k)

def tok.any(+t: T.Token, ks: List<&2, Nat>) -> Bool:
  List.contains(~Nat, ~Nat.is_eq, ks, kind.index(tok.kind(t)))

def STREAM_END() -> Nat:
  1n

def VERSION() -> Nat:
  2n

def TAG_DIR() -> Nat:
  3n

def DOC_START() -> Nat:
  4n

def DOC_END() -> Nat:
  5n

def BEND() -> Nat:
  8n

def FSEQ_END() -> Nat:
  10n

def FMAP_END() -> Nat:
  12n

def BENTRY() -> Nat:
  13n

def FENTRY() -> Nat:
  14n

def KEY() -> Nat:
  15n

def VALUE() -> Nat:
  16n

# Tags
# ----

def defaults() -> List<&2, Prefix>:
  [Prefix{"!", "!"}, Prefix{"!!", "tag:yaml.org,2002:"}]

def prefix.find(ts: List<&2, Prefix>, +handle: String) -> Maybe<&2, String>:
  match ts:
    case Nil{}:
      None{}
    case Con{p, rest}:
      match p:
        case Prefix{h, +prefix}:
          when(Maybe<&2, String>, String.eq(h, handle), u => Some{prefix}, u => prefix.find(rest, handle))

def tag.found(m: Maybe<&2, String>, suffix: String, at: T.Mark) -> Result<&2, &2, T.Error, Tag>:
  match m:
    case None{}:
      Fail{T.Error{"found undefined tag handle while parsing a node", at, T.Syntax{}}}
    case Some{p}:
      Done{Tag{p ++ suffix}}

# A written tag's full name, through the document's %TAG prefixes.
def tag.resolve(w: Maybe<&2, Written>, ts: List<&2, Prefix>, at: T.Mark) -> Result<&2, &2, T.Error, Tag>:
  match w:
    case None{}:
      Done{NoTag{}}
    case Some{x}:
      match x:
        case Written{+handle, +suffix}:
          when(Result<&2, &2, T.Error, Tag>, String.is_empty(handle), u => Done{Tag{suffix}},
            u => tag.found(prefix.find(ts, handle), suffix, at))

def is_found(m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      True{}

def dirs.go(toks: List<&2, T.Token>, +user: List<&2, Prefix>, +seen: Bool) -> Dirs:
  match toks:
    case Nil{}:
      Dirs{[], user}
    case Con{t, +rest}:
      match t:
        case T.Token{tok, +start, +end}:
          match tok:
            case T.VersionDir{+major, minor}:
              +bad = Bool.not(Nat.is_eq(major, 1n))
              when(Dirs, seen, u => DirsBad{T.Error{"found duplicate %YAML directive", start, T.Syntax{}}},
                u => when(Dirs, bad, u => DirsBad{T.Error{"found incompatible YAML document", start, T.Syntax{}}},
                  u => dirs.go(rest, user, True{})))
            case T.TagDir{+h, p}:
              when(Dirs, is_found(prefix.find(user, h)), u => DirsBad{T.Error{"found duplicate %TAG directive", start, T.Syntax{}}},
                u => dirs.go(rest, Prefix{h, p} <> user, seen))
            case _:
              Dirs{Con{T.Token{tok, start, end}, rest}, user}

def toks.with(ps: Ps, ts: List<&2, T.Token>) -> Ps:
  match ps:
    case Ps{toks, state, states, tags, out}:
      Ps{ts, state, states, tags, out}

def ps.toks(ps: Ps) -> List<&2, T.Token>:
  match ps:
    case Ps{toks, state, states, tags, out}:
      toks

def head.is(ts: List<&2, T.Token>, k: Nat) -> Bool:
  match ts:
    case Nil{}:
      False{}
    case Con{+t, rest}:
      tok.is(t, k)

def head.start(ts: List<&2, T.Token>) -> T.Mark:
  match ts:
    case Nil{}:
      T.Mark{0n, 0n, 0n}
    case Con{t, rest}:
      tok.start(t)

# After the directives, "---" must start the document.
def dirs.done(d: Dirs, +ps: Ps) -> PStep:
  match d:
    case DirsBad{e}:
      PStop{ps, Some{e}}
    case Dirs{+toks, user}:
      when(PStep, head.is(toks, DOC_START()),
        u => PGo{goto(push(emit(take(with.tags(toks.with(ps, toks), List.append(&2, Prefix, user, defaults()))), DocStartEv{True{}}, head.start(toks)), SDocEnd{}), SDocContent{})},
        u => fail(ps, "did not find expected <document start>", head.start(toks)))

def block.node() -> St:
  SNode{True{}, False{}, None{}, None{}, None{}}

# A document starts: bare, when nothing came before or the last one ended
# with "..."; or with directives and "---"; or the stream ends.
def h.doc.start(+ended: Bool, +t: T.Token, +ps: Ps) -> PStep:
  +start = tok.start(t)
  +bare = Bool.not(tok.any(t, [VERSION(), TAG_DIR(), DOC_START(), STREAM_END()]))
  when(PStep, tok.is(t, DOC_END()), u => PGo{take(ps)},
    u => when(PStep, tok.is(t, STREAM_END()), u => PGo{goto(emit(take(ps), StreamEndEv{}, start), SEnd{})},
      u => when(PStep, Bool.and(bare, ended), u => PGo{goto(push(emit(with.tags(ps, defaults()), DocStartEv{False{}}, start), SDocEnd{}), block.node())},
        u => when(PStep, Bool.or(bare, Bool.and(Bool.not(ended), Bool.not(tok.is(t, DOC_START())))), u => fail(ps, "did not find expected <document start>", start),
          u => dirs.done(dirs.go(ps.toks(ps), [], False{}), ps)))))

def h.doc.end(+t: T.Token, +ps: Ps) -> PStep:
  +explicit = tok.is(t, DOC_END())
  PGo{goto(emit(Bool.pick(Ps, explicit, take(ps), ps), DocEndEv{explicit}, tok.start(t)), SDocStart{explicit})}

# Nodes
# -----

def mark.or(m: Maybe<&2, T.Mark>, d: T.Mark) -> T.Mark:
  match m:
    case None{}:
      d
    case Some{x}:
      x

def is_none.s(m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{x}:
      False{}

def is_none.w(m: Maybe<&2, Written>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{x}:
      False{}

# No content: an empty scalar, when the node has an anchor or a tag.
def content.none(+block: Bool, +props: Bool, anchor: Maybe<&2, String>, tag: Tag, +at: T.Mark, +ps: Ps) -> PStep:
  when(PStep, props, u => PGo{emit(pop(ps), ScalarEv{anchor, tag, "", T.Plain{}}, at)},
    u => fail(ps, Bool.pick(String, block, "did not find expected node content while parsing a block node",
      "did not find expected node content while parsing a flow node"), at))

# The node's content, after its anchor and tag.
def content(k: T.Tok, +block: Bool, +indentless: Bool, +anchor: Maybe<&2, String>, +tag: Tag, +props: Bool, +at: T.Mark, +ps: Ps) -> PStep:
  match k:
    case T.BEntry{}:
      when(PStep, indentless, u => PGo{emit(goto(ps, SIndentless{at}), SeqStartEv{anchor, tag, False{}}, at)},
        u => content.none(block, props, anchor, tag, at, ps))
    case T.ScalarTok{text, style}:
      PGo{take(emit(pop(ps), ScalarEv{anchor, tag, text, style}, at))}
    case T.FSeqStart{}:
      PGo{emit(goto(ps, SFSeqFirst{}), SeqStartEv{anchor, tag, True{}}, at)}
    case T.FMapStart{}:
      PGo{emit(goto(ps, SFMapFirst{}), MapStartEv{anchor, tag, True{}}, at)}
    case T.BSeqStart{}:
      when(PStep, block, u => PGo{emit(goto(ps, SBSeqFirst{}), SeqStartEv{anchor, tag, False{}}, at)},
        u => content.none(block, props, anchor, tag, at, ps))
    case T.BMapStart{}:
      when(PStep, block, u => PGo{emit(goto(ps, SBMapFirst{}), MapStartEv{anchor, tag, False{}}, at)},
        u => content.none(block, props, anchor, tag, at, ps))
    case _:
      content.none(block, props, anchor, tag, at, ps)

def content.tagged(r: Result<&2, &2, T.Error, Tag>, +k: T.Tok, +block: Bool, +indentless: Bool, +anchor: Maybe<&2, String>, +props: Bool, +at: T.Mark, +ps: Ps) -> PStep:
  match r:
    case Fail{e}:
      PStop{ps, Some{e}}
    case Done{tag}:
      content(k, block, indentless, anchor, tag, props, at, ps)

def node.rest(+block: Bool, +indentless: Bool, +anchor: Maybe<&2, String>, +tag: Maybe<&2, Written>, +bare: Bool, +at: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  content.tagged(tag.resolve(tag, ps.tags(ps), at), tok.kind(t), block, indentless, anchor, Bool.not(bare), at, ps)

def h.node.kind(k: T.Tok, +block: Bool, +indentless: Bool, +anchor: Maybe<&2, String>, +tag: Maybe<&2, Written>, +bare: Bool, +at: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  match k:
    case T.AliasTok{name}:
      when(PStep, bare, u => PGo{take(emit(pop(ps), AliasEv{name}, at))}, u => node.rest(block, indentless, anchor, tag, bare, at, t, ps))
    case T.AnchorTok{name}:
      when(PStep, is_none.s(anchor), u => PGo{take(goto(ps, SNode{block, indentless, Some{name}, tag, Some{at}}))},
        u => node.rest(block, indentless, anchor, tag, bare, at, t, ps))
    case T.TagTok{h, s}:
      when(PStep, is_none.w(tag), u => PGo{take(goto(ps, SNode{block, indentless, anchor, Some{Written{h, s}}, Some{at}}))},
        u => node.rest(block, indentless, anchor, tag, bare, at, t, ps))
    case _:
      node.rest(block, indentless, anchor, tag, bare, at, t, ps)

# A node: its anchor and tag (in either order), then an alias or content.
def h.node(+block: Bool, +indentless: Bool, +anchor: Maybe<&2, String>, +tag: Maybe<&2, Written>, +start: Maybe<&2, T.Mark>, +t: T.Token, +ps: Ps) -> PStep:
  +at = mark.or(start, tok.start(t))
  +bare = Bool.and(is_none.s(anchor), is_none.w(tag))
  h.node.kind(tok.kind(t), block, indentless, anchor, tag, bare, at, t, ps)

def h.doc.content(+t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.any(t, [VERSION(), TAG_DIR(), DOC_START(), DOC_END(), STREAM_END()]), u => PGo{empty(pop(ps), tok.start(t))},
    u => h.node(True{}, False{}, None{}, None{}, None{}, t, ps))

# Block collections
# -----------------

def node.next(+block: Bool, +indentless: Bool, back: St, +t: T.Token, ps: Ps) -> PStep:
  h.node(block, indentless, None{}, None{}, None{}, t, push(ps, back))

def h.bseq.entry(+m: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.is(t, BENTRY()), u => PGo{take(goto(ps, SBSeqAfter{m, tok.end(t)}))},
    u => when(PStep, tok.is(t, BEND()), u => PGo{take(emit(pop(ps), SeqEndEv{}, tok.start(t)))},
      u => fail(ps, "did not find expected '-' indicator while parsing a block collection", m)))

def h.bseq.after(+m: T.Mark, e: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.any(t, [BENTRY(), BEND()]), u => PGo{empty(goto(ps, SBSeqEntry{m}), e)},
    u => node.next(True{}, False{}, SBSeqEntry{m}, t, ps))

def h.indentless(+m: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.is(t, BENTRY()), u => PGo{take(goto(ps, SIndentlessAfter{m, tok.end(t)}))},
    u => PGo{emit(pop(ps), SeqEndEv{}, tok.start(t))})

def h.indentless.after(+m: T.Mark, e: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.any(t, [BENTRY(), KEY(), VALUE(), BEND()]), u => PGo{empty(goto(ps, SIndentless{m}), e)},
    u => node.next(True{}, False{}, SIndentless{m}, t, ps))

def h.bmap.key(+m: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.is(t, KEY()), u => PGo{take(goto(ps, SBMapAfterKey{m, tok.end(t)}))},
    u => when(PStep, tok.is(t, BEND()), u => PGo{take(emit(pop(ps), MapEndEv{}, tok.start(t)))},
      u => when(PStep, tok.is(t, VALUE()), u => PGo{empty(goto(ps, SBMapValue{m}), tok.start(t))},
        u => fail(ps, "did not find expected key while parsing a block mapping", m))))

def h.bmap.after.key(+m: T.Mark, e: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.any(t, [KEY(), VALUE(), BEND()]), u => PGo{empty(goto(ps, SBMapValue{m}), e)},
    u => node.next(True{}, True{}, SBMapValue{m}, t, ps))

def h.bmap.value(+m: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.is(t, VALUE()), u => PGo{take(goto(ps, SBMapAfterValue{m, tok.end(t)}))},
    u => PGo{empty(goto(ps, SBMapKey{m}), tok.start(t))})

def h.bmap.after.value(+m: T.Mark, e: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.any(t, [KEY(), VALUE(), BEND()]), u => PGo{empty(goto(ps, SBMapKey{m}), e)},
    u => node.next(True{}, True{}, SBMapKey{m}, t, ps))

# Flow collections
# ----------------

def h.fseq.entry(+m: T.Mark, +first: Bool, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.is(t, FSEQ_END()), u => PGo{take(emit(pop(ps), SeqEndEv{}, tok.start(t)))},
    u => when(PStep, Bool.not(first),
      u => when(PStep, tok.is(t, FENTRY()), u => PGo{take(goto(ps, SFSeqEntry{m, True{}}))},
        u => fail(ps, "did not find expected ',' or ']' while parsing a flow sequence", m)),
      u => when(PStep, tok.is(t, KEY()), u => PGo{take(emit(goto(ps, SFSeqMapKey{m}), MapStartEv{None{}, NoTag{}, True{}}, tok.start(t)))},
        u => when(PStep, tok.is(t, VALUE()), u => PGo{emit(goto(ps, SFSeqMapKey{m}), MapStartEv{None{}, NoTag{}, True{}}, tok.start(t))},
          u => node.next(False{}, False{}, SFSeqEntry{m, False{}}, t, ps)))))

# An implicit pair's key in a flow sequence.
def h.fseq.map.key(+m: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.any(t, [VALUE(), FENTRY(), FSEQ_END()]),
    u => PGo{empty(goto(ps, SFSeqMapValue{m}), tok.start(t))},
    u => node.next(False{}, False{}, SFSeqMapValue{m}, t, ps))

def h.fseq.map.value(+m: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.is(t, VALUE()), u => PGo{take(goto(ps, SFSeqMapAfterValue{m, tok.end(t)}))},
    u => PGo{empty(goto(ps, SFSeqMapEnd{m}), tok.start(t))})

def h.fseq.map.after.value(+m: T.Mark, e: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.any(t, [FENTRY(), FSEQ_END()]), u => PGo{empty(goto(ps, SFSeqMapEnd{m}), e)},
    u => node.next(False{}, False{}, SFSeqMapEnd{m}, t, ps))

def h.fseq.map.end(m: T.Mark, +t: T.Token, ps: Ps) -> PStep:
  PGo{emit(goto(ps, SFSeqEntry{m, False{}}), MapEndEv{}, tok.start(t))}

def h.fmap.key(+m: T.Mark, +first: Bool, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.is(t, FMAP_END()), u => PGo{take(emit(pop(ps), MapEndEv{}, tok.start(t)))},
    u => when(PStep, Bool.not(first),
      u => when(PStep, tok.is(t, FENTRY()), u => PGo{take(goto(ps, SFMapKey{m, True{}}))},
        u => fail(ps, "did not find expected ',' or '}' while parsing a flow mapping", m)),
      u => when(PStep, tok.is(t, KEY()), u => PGo{take(goto(ps, SFMapAfterKey{m, tok.end(t)}))},
        u => when(PStep, tok.is(t, VALUE()), u => PGo{empty(goto(ps, SFMapValue{m}), tok.start(t))},
          u => node.next(False{}, False{}, SFMapEmpty{m}, t, ps)))))

def h.fmap.after.key(+m: T.Mark, e: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.any(t, [VALUE(), FENTRY(), FMAP_END()]), u => PGo{empty(goto(ps, SFMapValue{m}), tok.start(t))},
    u => node.next(False{}, False{}, SFMapValue{m}, t, ps))

def h.fmap.value(+m: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.is(t, VALUE()), u => PGo{take(goto(ps, SFMapAfterValue{m, tok.end(t)}))},
    u => PGo{empty(goto(ps, SFMapKey{m, False{}}), tok.start(t))})

def h.fmap.after.value(+m: T.Mark, e: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.any(t, [FENTRY(), FMAP_END()]), u => PGo{empty(goto(ps, SFMapKey{m, False{}}), e)},
    u => node.next(False{}, False{}, SFMapKey{m, False{}}, t, ps))

# After a key with no KeyTok: a ":" on a later line is still its value (a
# flow mapping's key may run over lines), else the value is empty.
def h.fmap.empty(+m: T.Mark, +t: T.Token, +ps: Ps) -> PStep:
  when(PStep, tok.is(t, VALUE()), u => PGo{take(goto(ps, SFMapAfterValue{m, tok.end(t)}))},
    u => PGo{empty(goto(ps, SFMapKey{m, False{}}), tok.start(t))})

# Steps
# -----

def h.state(s: St, +t: T.Token, +ps: Ps) -> PStep:
  match s:
    case SStreamStart{}:
      PGo{take(goto(emit(ps, StreamStartEv{}, tok.start(t)), SFirstDoc{}))}
    case SFirstDoc{}:
      h.doc.start(True{}, t, ps)
    case SDocStart{ended}:
      h.doc.start(ended, t, ps)
    case SDocContent{}:
      h.doc.content(t, ps)
    case SDocEnd{}:
      h.doc.end(t, ps)
    case SNode{block, indentless, anchor, tag, start}:
      h.node(block, indentless, anchor, tag, start, t, ps)
    case SBSeqFirst{}:
      PGo{take(goto(ps, SBSeqEntry{tok.start(t)}))}
    case SBSeqEntry{m}:
      h.bseq.entry(m, t, ps)
    case SBSeqAfter{m, e}:
      h.bseq.after(m, e, t, ps)
    case SIndentless{m}:
      h.indentless(m, t, ps)
    case SIndentlessAfter{m, e}:
      h.indentless.after(m, e, t, ps)
    case SBMapFirst{}:
      PGo{take(goto(ps, SBMapKey{tok.start(t)}))}
    case SBMapKey{m}:
      h.bmap.key(m, t, ps)
    case SBMapAfterKey{m, e}:
      h.bmap.after.key(m, e, t, ps)
    case SBMapValue{m}:
      h.bmap.value(m, t, ps)
    case SBMapAfterValue{m, e}:
      h.bmap.after.value(m, e, t, ps)
    case SFSeqFirst{}:
      PGo{take(goto(ps, SFSeqEntry{tok.start(t), True{}}))}
    case SFSeqEntry{m, first}:
      h.fseq.entry(m, first, t, ps)
    case SFSeqMapKey{m}:
      h.fseq.map.key(m, t, ps)
    case SFSeqMapValue{m}:
      h.fseq.map.value(m, t, ps)
    case SFSeqMapAfterValue{m, e}:
      h.fseq.map.after.value(m, e, t, ps)
    case SFSeqMapEnd{m}:
      h.fseq.map.end(m, t, ps)
    case SFMapFirst{}:
      PGo{take(goto(ps, SFMapKey{tok.start(t), True{}}))}
    case SFMapKey{m, first}:
      h.fmap.key(m, first, t, ps)
    case SFMapAfterKey{m, e}:
      h.fmap.after.key(m, e, t, ps)
    case SFMapValue{m}:
      h.fmap.value(m, t, ps)
    case SFMapAfterValue{m, e}:
      h.fmap.after.value(m, e, t, ps)
    case SFMapEmpty{m}:
      h.fmap.empty(m, t, ps)
    case SEnd{}:
      PStop{ps, None{}}

# A Broken token stops the parser with its error.
def h.token(k: T.Tok, +t: T.Token, +ps: Ps) -> PStep:
  match k:
    case T.Broken{e}:
      PStop{ps, Some{e}}
    case _:
      h.state(ps.state(ps), t, ps)

def h.head(ts: List<&2, T.Token>, +ps: Ps) -> PStep:
  match ts:
    case Nil{}:
      PStop{ps, None{}}
    case Con{+t, rest}:
      h.token(tok.kind(t), t, ps)

def p.step(+ps: Ps) -> PStep:
  h.head(ps.toks(ps), ps)

def p.run(fuel: Nat, s: PStep) -> Parsed:
  match fuel:
    case 0n:
      match s:
        case PGo{ps}:
          Parsed{List.reverse(&2, Evt, ps.out(ps)), Some{T.Error{"the parser ran out of steps", T.Mark{0n, 0n, 0n}, T.Syntax{}}}}
        case PStop{ps, e}:
          Parsed{List.reverse(&2, Evt, ps.out(ps)), e}
    case 1n+k:
      match s:
        case PGo{ps}:
          p.run(k, p.step(ps))
        case PStop{ps, e}:
          Parsed{List.reverse(&2, Evt, ps.out(ps)), e}

# The events of a token stream.
def parse(+toks: List<&2, T.Token>) -> Parsed:
  p.run(Nat.add(Nat.mul(List.length(&2, T.Token, toks), 8n), 16n), PGo{Ps{toks, SStreamStart{}, [], defaults(), []}})

# The events of a YAML text.
def events(text: String) -> Parsed:
  parse(S.scan(text))

def escaped.other(c: Char, rest: String) -> String:
  match c:
    case Chr{+x}:
      Bool.pick(String, U32.is_eq(x, 8), "\\b", Bool.pick(String, U32.is_eq(x, 0), "\\0", SCon{Chr{x}, SNil{}})) ++ rest

# Events as text
# --------------

# A scalar's text as the YAML test suite writes it: backslashes, breaks
# and tabs escaped.
def escaped(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, t}:
      match c:
        case '\\':
          "\\\\" ++ escaped(t)
        case '\n':
          "\\n" ++ escaped(t)
        case '\t':
          "\\t" ++ escaped(t)
        case '\r':
          "\\r" ++ escaped(t)
        case _:
          escaped.other(c, escaped(t))

def style.mark(s: T.Style) -> String:
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

def anchor.text(a: Maybe<&2, String>) -> String:
  match a:
    case None{}:
      ""
    case Some{n}:
      " &" ++ n

def tag.text(t: Tag) -> String:
  match t:
    case NoTag{}:
      ""
    case Tag{n}:
      " <" ++ n ++ ">"

def flow.text(+flow: Bool, brackets: String) -> String:
  Bool.pick(String, flow, " " ++ brackets, "")

# An event as the YAML test suite writes it: "+MAP {} &a <tag>", "=VAL :x".
def ev.text(e: Ev) -> String:
  match e:
    case StreamStartEv{}:
      "+STR"
    case StreamEndEv{}:
      "-STR"
    case DocStartEv{explicit}:
      Bool.pick(String, explicit, "+DOC ---", "+DOC")
    case DocEndEv{explicit}:
      Bool.pick(String, explicit, "-DOC ...", "-DOC")
    case AliasEv{name}:
      "=ALI *" ++ name
    case ScalarEv{anchor, tag, text, style}:
      "=VAL" ++ anchor.text(anchor) ++ tag.text(tag) ++ " " ++ style.mark(style) ++ escaped(text)
    case SeqStartEv{anchor, tag, flow}:
      "+SEQ" ++ flow.text(flow, "[]") ++ anchor.text(anchor) ++ tag.text(tag)
    case SeqEndEv{}:
      "-SEQ"
    case MapStartEv{anchor, tag, flow}:
      "+MAP" ++ flow.text(flow, "{}") ++ anchor.text(anchor) ++ tag.text(tag)
    case MapEndEv{}:
      "-MAP"

def evts.text(es: List<&2, Evt>) -> String:
  match es:
    case Nil{}:
      ""
    case Con{e, rest}:
      match e:
        case Evt{ev, at}:
          ev.text(ev) ++ "\n" ++ evts.text(rest)

def error.text(m: Maybe<&2, T.Error>) -> String:
  match m:
    case None{}:
      ""
    case Some{e}:
      "ERROR " ++ T.error.show(e) ++ "\n"

# The events of a parse, one per line, and the error after them.
def parsed.text(p: Parsed) -> String:
  match p:
    case Parsed{events, error}:
      evts.text(events) ++ error.text(error)
