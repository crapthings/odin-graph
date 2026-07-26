# odin-graph

> Experimental Git repository for the in-memory RDF graph kernel.
> Its `v0.1.0` tag is a Garden-pinned experimental baseline, not a promise of
> an independently supported public API release. `odin-sparql v0.7.0` keeps
> its public `Memory_Dataset` self-contained over `odin-rdf`; Graph is an
> optional adapter, not a core SPARQL release dependency.

`odin-graph` is an experimental in-memory RDF graph kernel for the Odin
semantic ecosystem. The scope of any supported external release is extracted
only from behavior that concrete consumers have proven in integration tests.
Its SPARQL adapter remains useful migration evidence, but it does not determine
the dependency contract of the released SPARQL core.

```mermaid
flowchart LR
    Evidence["Garden integration evidence"] --> Gate{"stable shared<br/>requirements?"}
    Gate -->|not yet| Workspace["local odin-graph<br/>core-development workspace"]
    Gate -->|yes| Extract["published, independently<br/>versioned odin-graph"]
```

The governing ecosystem boundary and extraction gate live in
[`../odin-garden/docs/architecture.md`](../odin-garden/docs/architecture.md).
The decision to defer a published extraction is recorded in
[`../odin-garden/docs/adr/0001-defer-odin-graph.md`](../odin-garden/docs/adr/0001-defer-odin-graph.md).

## Intended scope

The first implementation milestone provides:

- RDF Dataset set semantics across default and named graphs;
- copied/owned RDF values with explicit blank-node identity rules;
- bounded graph-scoped scans with immutable freeze-time exact, two-term, and
  one-term candidate indexes;
- freeze-in-place immutable views suitable for a later public `odin-sparql`
  Dataset adapter;
- documented resource limits, ownership, and error behavior.

## Explicit non-goals

- RDF parsing, writing, or canonicalization;
- SPARQL syntax, algebra, query planning, or result encoding;
- RDFS/OWL rules, inference provenance, or materialization policy;
- persistence, recovery, backup, replication, or network services;
- multi-writer isolation, MVCC, WAL, or a speculative general transaction API.

Durability and operational transaction semantics belong to a future,
independent `odin-store` only when a concrete requirement exists.

## Development plan

The staged work and acceptance conditions are in [TODO.md](TODO.md). Do not
promote it to a supported component dependency until the Garden extraction gate
has produced the required multi-consumer evidence.

## Local verification

With `odin-rdf` checked out beside this repository at the release pinned by
Garden, run:

```sh
odin test graph -collection:odin-rdf=../odin-rdf
```

The optional SPARQL adapter is separate from the kernel and can be verified
against the adjacent SPARQL development checkout with:

```sh
odin test adapter/sparql -collection:odin-rdf=../odin-rdf -collection:odin-sparql=../odin-sparql
```

The separate Reasoner closure importer is a copying migration prototype. It
retains each fact's asserted/inferred first origin, but not the Store's native
term/fact IDs or its inference engine. Its optional derivation-aware entry
also retains opaque rule IDs and first-support Graph indexes. Test it against
the pinned Reasoner revision with:

```sh
odin test adapter/reasoner -collection:odin-rdf=../odin-rdf -collection:odin-reasoner=../odin-reasoner
```

For development across the adjacent working trees, run:

```sh
sh scripts/verify-current-convergence.sh
```

It prints the exact checked-out revisions and runs the Graph kernel, both
adapters, the bounded OWL RL W3C-evidence suite, and Garden's current-source
integration packages. This is migration evidence only: it intentionally does
not replace Garden's release-qualified, fixed-revision verification command.

To additionally run the optional Graph-adapter compatibility checks alongside
SPARQL's full pinned W3C suites and its 50,000-case fuzz gate, use:

```sh
ODIN_GRAPH_FULL_CONFORMANCE=1 sh scripts/verify-current-convergence.sh
```

This is deliberately opt-in: it is a broader conformance run, not the fast
development loop. SPARQL's W3C runners cache their compiled executables in
`$ODIN_SPARQL_COLLECTION/.cache`, so that directory must be writable for the
full mode; normal convergence writes only `odin-graph/.tmp`.
