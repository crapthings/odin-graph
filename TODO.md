# odin-graph development TODO

## Guiding rule

Build the smallest common graph kernel demonstrated by real consumers. A task
is complete only when its behavior is used by an integration fixture or a
public adapter contract; do not add speculative database features.

## P0 — establish extraction evidence in Garden

- [x] Create `odin-garden/ecosystem.toml` pinning the Odin compiler and
  released `odin-rdf`, `odin-reasoner`, and `odin-sparql` revisions.
- [x] Add the first provenance-backed source RDF fixture.
- [x] Run it through public APIs: RDF input → RDFS closure → immutable
  SPARQL Dataset view → `SELECT`, `ASK`, and `CONSTRUCT` expectations.
- [x] Record the exact ownership, blank-node, resource-limit, and error
  behavior exercised by the fixture.

**Exit gate: passed.** Garden’s RDFS-to-SPARQL integration command is
reproducible from pinned revisions and no check follows a moving `main` branch.
The release-qualified CI run also covers snapshot lifetime, graph scope,
limits, and cross-ingestion blank-node identity.

## P1 — write the graph contract before implementation

- [x] Decide whether `odin-rdf` term values can be copied directly without a
  second public term-identity system.
- [x] Define RDF Dataset identity: default graph plus named graph, RDF term
  equality, and global quad set semantics.
- [x] Define blank-node identity across ingestion, snapshots, and graph scope.
- [x] Specify ownership: callers may discard input after insertion; a snapshot
  defines the lifetime of scan results.
- [x] Define bounded resource limits and stable errors before selecting an
  allocator or index layout.
- [x] Define only the graph-scoped scan pattern needed to satisfy
  `odin-sparql:dataset.custom_view`.

**Exit gate: candidate contract adopted for experimental implementation.** ADR
0002 remains in force for production extraction. The released direct path has
a Store-adopting immutable Snapshot that retains reasoner-owned terms and
indexes, but it is not a representation shared with `Memory_Dataset`. No
method is justified solely by a future persistent store.

## P2 — minimal in-memory graph kernel

- [x] Create the actual `odin-graph` Git repository after P0 and the candidate
  P1 contract pass.
- [x] Add a bounded mutable builder with per-quad all-or-nothing admission.
- [x] Implement default/named graph quad set semantics and owned value copies.
- [x] Implement freeze-in-place immutable views.
- [x] Implement synchronous graph-scoped scans with correct wildcard and
  early-stop behavior.
- [ ] Add only evidence-backed indexes; measure scan work before optimizing.
- [x] Gate with ownership, limit, duplicate, graph-scope, and freeze tests.

**Exit gate:** The kernel's own immutable snapshot is sufficient to back
SPARQL’s public read-only adapter without an adapter-specific second Dataset
copy and without changing query semantics.

## P3 — consumer adapters and integration proof

- [ ] Implement an `odin-sparql` adapter from an `odin-graph` immutable
  snapshot to `dataset.custom_view`.
- [ ] Prototype a reasoner adapter that maps its asserted/default-graph facts
  into the shared contract without moving inference rules into `odin-graph`.
- [ ] Repeat the Garden fixture against the shared snapshot implementation.
- [ ] Compare asserted/inferred result sets and query answers with the existing
  reasoner/SPARQL path.
- [ ] Decide whether one common snapshot and index contract is genuinely used
  by both production-quality paths.

**Exit gate:** Garden’s extraction conditions are met and a separate
`odin-graph` repository has a minimal, independently useful public API.

## P4 — evaluate a future odin-store (not implementation work)

- [ ] Capture a concrete request for persistence across restart, multiple
  writers, recovery, or isolation.
- [ ] State required durability, failure, and transaction semantics.
- [ ] Confirm that the requirement cannot be met by application-owned
  snapshots or a graph adapter.
- [ ] Create a separate `odin-store` proposal only then; it may depend on
  `odin-graph` but must not redefine its Dataset semantics.

## Non-negotiable exclusions for this workspace

- [ ] Do not import `odin-graph` into `odin-rdf`, `odin-reasoner`, or
  `odin-sparql` before P3.
- [ ] Do not implement disk files, WAL, MVCC, locks, replication, HTTP,
  SPARQL Update, or query planning here.
- [ ] Do not create another RDF term model or change blank-node behavior
  without a Garden ADR and cross-project tests.
