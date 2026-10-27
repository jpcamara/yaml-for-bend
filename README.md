# yaml-for-bend

A YAML library for [Bend 2](https://bend-lang.com). It reads YAML 1.2 into
a value tree, under the Core schema or the YAML 1.1 types, and writes
values back as YAML. It is written in plain Bend: every function
terminates, nothing is `@unsafe`, and it needs nothing but Base.

## Install

From BendHub:

```python
import yaml-for-bend@0.1.0.0/yaml.bend as Y
import yaml-for-bend@0.1.0.0/value.bend as V
import yaml-for-bend@0.1.0.0/token.bend as T
```

Or copy `src/` into your project and import `./src/yaml.bend` and the
others by path.

## Example

```python
import Base
import ../src/yaml.bend as Y
import ../src/value.bend as V
import ../src/token.bend as T

def shown(r: Result<&2, &2, T.Error, V.Yaml>) -> String:
  match r:
    case Done{v}:
      V.json(v)
    case Fail{e}:
      T.error.show(e)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(shown(Y.load("name: bend\ntags: [yaml, 1.2]")))  # {"name":"bend","tags":["yaml",1.2]}
    IO.print(shown(Y.load("a: b: c")))      # mapping values are not allowed in this context at line 1 column 5
    IO.print(shown(Y.load.v11("on: yes")))  # {"true":true}
```

That's `examples/hello.bend`: `bend examples/hello.bend` runs it.

## Values

```python
type Yaml is Data:          # src/value.bend
  Null{}
  Boolean{on: Bool}
  Int{text: String}         # decimal text, any size: 0x1A is "26"
  Float{text: String}       # decimal text; ".inf", "-.inf", ".nan"
  Str{text: String}
  Seq{items: List<&2, Yaml>}
  Mapping{entries: List<&2, Entry>}    # in the order written
  Tagged{tag: String, val: Yaml}       # a tag the schema doesn't resolve

type Entry is Data:
  Entry{key: Yaml, val: Yaml}
```

Bend has no 64-bit floats, so a float keeps its text: as written under
the Core schema (`1.50e3`), and as an exact decimal under YAML 1.1
(`1_000.50` is `1000.5`). Integers are exact at any size.

`value.bend` also has `get(v, key)`, `find(v, key)`, `at(v, key)`,
`items`, `entries`, `keys`, `text`, `is_null`, structural equality `eq`,
and `json(v)`, which writes a value as one line of JSON.

## API

`src/yaml.bend`:

| Def | What it does |
|---|---|
| `load(text)` | The one document, under the Core schema. No document is `Null`; more than one is an error. |
| `load.all(text)` | Every document, under the Core schema. |
| `load.v11(text)`, `load.all.v11(text)` | The same, reading the YAML 1.1 types. |
| `load.with(schema, limits, text)`, `load.all.with(...)` | With a schema (`C.Core{}` or `C.Yaml11{}`, from `compose.bend`) and limits (see [Limits](#limits)). |
| `limits()` | The default limits. |
| `dump(v)`, `dump.all(vs)` | A value, or documents, as block-style YAML. |
| `events(text)` | The parser's events, and the error that ended them, if any. |

Each `load` returns `Result<&2, &2, T.Error, ...>`:

```python
type Error is Data:         # src/token.bend
  Error{why: String, at: Mark, cause: Cause}   # Cause: Syntax{}, Content{} or Limit{}
```

`Syntax` means the text isn't YAML; `Content` means it is, but the schema
can't load it (a bad `!!int`, a repeated key, an unknown alias); `Limit`
means it went past one of the limits, which the message names.
`T.error.show(e)` is `"did not find expected key while parsing a block
mapping at line 2 column 1"`; lines and columns count from 1.

## The Core schema

`load` resolves an untagged plain scalar as YAML 1.2's Core schema does:
`null`, `Null`, `NULL`, `~` and nothing are null; `true`/`True`/`TRUE`
and `false`/`False`/`FALSE` are booleans; decimal, `0o` octal and `0x`
hex are integers; decimal floats, `.inf`, `-.inf` and `.nan` are floats;
anything else is a string. Quoted and block scalars are strings, and so is
a scalar tagged `!`. `!!str`, `!!null`, `!!bool`, `!!int` and `!!float`
read the text as that type and fail when they can't. Other tags are kept
as `Tagged`.

## The YAML 1.1 types

`load.v11` reads YAML written for YAML 1.1 parsers, as much real-world
YAML is (Rails config, Docker Compose, Ansible and so on):

- `yes`, `no`, `on`, `off`, `true` and `false` (lowercase, capitalized
  or uppercase) are booleans. `y` and `n` are strings, as in most 1.1
  parsers, though the 1.1 type list has them as booleans.
- `0b101` is binary, `010` octal, `0x1A` hex, and `190:20:30` base 60
  (685230). `_` may go anywhere among the digits.
- Floats need a point (`1.0e+5`, `.5`, `1.`), and base 60 takes a
  fraction (`1:30.5`).
- A timestamp (`2001-12-14`, `2001-12-14t21:59:43.10-05:00`) is
  `Tagged{"tag:yaml.org,2002:timestamp", Str{...}}`, with the text as
  written.
- `<<` is the merge key. Its value is a mapping, or a list of them, whose
  entries the mapping takes in. The mapping's own keys win, and among the
  listed mappings the earlier wins.

`test/v11/compare.py` checks these against PyYAML. They agree on all but
a few cases, where this library differs on purpose: `-.5` is a float (as
the 1.1 float form allows), `!` is the non-specific tag (a string),
unknown tags are kept, merged keys keep their order, and a key may appear
only once.

## Keys and aliases

A key may appear only once in a mapping, under either schema; a repeat
is an error. Keys are compared as values, so `1` and `"1"` differ, and
`0x1` and `1` don't.

An alias is a copy of its anchored node. The nodes aliases copy into a
document are counted, every copy in full, against the alias limit, so a
small text can't expand into a huge tree ("billion laughs"). An alias
inside the node it names would make a cycle, which a tree can't hold, so
it is an error; so a merge can't make a cycle either.

## Writing

`dump` writes block style, indented two spaces. A string is plain when
the Core schema reads it back as that string, and double-quoted
otherwise; a key that is a collection goes after `?`; an empty collection
is `[]` or `{}`. `load(dump(v))` is `v` for any value `load` returns.

## Conformance

The reader passes all 402 cases of the [YAML test
suite](https://github.com/yaml/yaml-test-suite) (data branch): the events
of the 308 valid cases match the suite's, and the 94 invalid cases fail.
Under the Core schema, the 279 valid cases with an `in.json` load to the
same values, and each of their 332 documents comes back the same through
`dump` and `load`.

## Limits

`load`, `load.all`, `load.v11` and `load.all.v11` read within the default
limits. `load.with` and `load.all.with` take others:

```python
C.Limits{size: Nat, depth: Nat, aliases: Nat, digits: Nat}   # src/compose.bend

Y.load.with(C.Core{}, C.Limits{65536n, 64n, 1000n, 100n}, text)
```

| Limit | Default | What it bounds |
|---|---|---|
| `size` | 1,048,576 | Characters in the text. A longer text is refused before it is read. |
| `depth` | 256 | How deep collections nest, block and flow. |
| `aliases` | 100,000 | Nodes that aliases copy into one document, counting every copy in full. |
| `digits` | 1,000 | Characters in a number written in a base other than ten (`0x`, `0o`, YAML 1.1's `0b`, `0` octal and base 60), which takes time that grows with the square of its length to convert. Decimal numbers have no such limit. |

Past a limit, the load fails with an error whose cause is `T.Limit{}` and
whose message names the limit, as in `found nesting deeper than the depth
limit of 256 at line 257 column 257`.

Reading takes time and memory in proportion to the text: on a recent
Apple silicon machine, 0.2 to 1.5 seconds per million characters, and
about 300 bytes of memory per character, so about 320 MB at the default
size limit. The size limit counts
the characters of a `String` you have already read; read a file with a
byte cap (Bend's `File.read` takes one) so that a huge file is never read
whole.

## Security

YAML libraries are known for a few kinds of attack. This is how each fares
here.

| Attack | Here |
|---|---|
| Objects built from tags (`!ruby/object`, `!!python/object/apply`, SnakeYAML's constructors), and with them code execution | Can't happen. Loading is a pure function from text to `Result<Error, Yaml>`: it does no IO, and `Yaml` holds only data. A tag the schema doesn't know is kept as `Tagged{tag, val}`; nothing looks a tag up to run it, and there is no way to register one. `LAWS.bend` proves that every tag the schema doesn't know is kept this way. |
| Alias expansion ("billion laughs"), and merges of aliases | The alias limit counts what aliases copy, merges included. A bomb is refused at once. |
| Recursive aliases and merge cycles | Errors: a tree can't hold a cycle. |
| Deep nesting | The depth limit. The reader is a loop, not recursion, so depth can't overflow a stack while reading; the limit keeps the value tree shallow for the code that walks it. |
| Huge texts, scalars and keys | The size limit. Reading is linear in the text, so a long scalar, comment, anchor, tag or quoted run costs time in proportion to its length. A simple key past 1024 characters is an error, as YAML says. |
| Long numbers | Decimal integers and floats stay text and are copied in linear time. Numbers in other bases need conversion; the digits limit bounds them. |
| Hash floods | There are no hashes. Mappings are checked for repeats with a crit-bit trie keyed by each key's text, so many keys, or keys with long shared prefixes, cost in proportion to their text. |
| Duplicate keys | A repeated key is an error under both schemas, so two readers can't take different values from one mapping. Keys compare as values: `0x1` and `1` are the same key. |
| Encoding tricks | The reader takes a Bend `String`. Control characters, NUL and lone surrogates are errors. A BOM is skipped at the start of the text and is content anywhere else, as in libyaml and PyYAML. Invalid UTF-8 never reaches the reader: Bend's `File.read` turns it into U+FFFD. |

`script/adversarial` builds inputs for each of these, at a few sizes, and
times the reader on them with its peak memory.

## Known gaps

- The whole text is read at once; there is no streaming.
- A float is decimal text, not a binary double. Comparing two floats by
  value is up to you.
- `dump` writes block style for the Core schema only. It keeps no
  comments, anchors or the original layout.
- Recursive aliases (`&a [*a]`) are errors.
- A BOM is skipped only at the very start of the text, not before a later
  document.

## Laws

`LAWS.bend` states facts the code keeps, and `PROOF.bend` proves them:
booleans and null round-trip through `dump` and `load`; an integer is
written as its text; escaping for double quotes joins over text
(`escaped(a ++ b) == escaped(a) ++ escaped(b)`, by induction); and worked
examples of both schemas, merge keys, a syntax error's message, and each
limit. For every tag a schema doesn't know, scalar or collection, the
node is the tag and its value, kept as data. `bend PROOF.bend --verdict` rechecks them with the BendTT
kernel.

## How it's built

The reader follows the design of libyaml: a scanner (`scan.bend`) turns
text into tokens, a parser (`parse.bend`) turns tokens into events, and a
composer (`compose.bend`) turns events into values through a schema
(`core.bend` or `yaml11.bend`). Each is a state machine: a step function
moves one state to the next, and one loop runs it on fuel the input's
length bounds, so nothing recurses mutually and every def terminates.

| Module | What it does |
|---|---|
| `token.bend` | Marks, tokens, errors |
| `scan.bend` | Text to tokens |
| `parse.bend` | Tokens to events |
| `compose.bend` | Events to values: anchors, aliases, keys, merges |
| `core.bend`, `yaml11.bend` | The two schemas |
| `value.bend` | The value tree, lookups, equality, JSON |
| `emit.bend` | Values to YAML |
| `num.bend` | Big integers as digits, exact decimals |
| `re.bend` | A small regex matcher for scalar forms |
| `yaml.bend` | The API |

## Development

You need Bend 2, Python 3 (for `script/order` and `script/affine`), and
Ruby (for the test suite's runner). PyYAML is optional.

```sh
script/check src/scan.bend   # type-check a module
script/prove --verdict       # the laws
script/v11                   # the YAML 1.1 cases, and PyYAML if it's installed
script/adversarial           # times hostile inputs, with peak memory
git clone -b data https://github.com/yaml/yaml-test-suite.git /path/to/yts
script/suite /path/to/yts    # the YAML test suite, in.json, and the dump round trip
```

Bend defs must come after the defs they call; the scripts run
`script/order` first, which sorts each file's defs that way.

The scripts run `bend` locally. To run it on another machine, set
`BEND_HOST` to an ssh destination: the project is copied there with
rsync, to `BEND_DIR` (default `yaml-for-bend` in the remote home), commands
run in that copy, and built binaries are copied back to `build/`.
`BEND_BIN` names the bend command, locally or remotely (default `bend`).

## License

MIT. See `LICENSE`.
