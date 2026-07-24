# Changelog

## Unreleased

- Build immutable subject, predicate, object, named-graph, and two-term scan
  indexes during `freeze`. Graph-scoped scans retain Dataset set semantics,
  insertion order, and early-stop behavior while selecting the same candidate
  shapes as the Reasoner Store.
- Retain asserted/inferred first-origin metadata beside owned quads. The
  Reasoner closure importer now preserves this metadata while retaining its
  copying, independent-ownership boundary.

## v0.1.0 — 2026-07-24

First experimental release of the bounded in-memory RDF Dataset kernel.

- Added owned default and named graph quad-set semantics, RDF term equality,
  blank-node scope preservation, resource limits, and atomic per-quad
  admission.
- Added freeze-in-place read-only views with graph-scoped wildcard scans and
  successful early-stop behavior.
- Added an optional `adapter/sparql` package that exposes a frozen graph as an
  `odin-sparql` Dataset view without adding an SPARQL dependency to `graph`.
- Added an optional copying `adapter/reasoner` package that imports a completed
  default-graph Reasoner closure into a frozen graph. Inference, provenance,
  Store indexes, and named-graph reasoning remain outside that adapter.

### Compatibility and limits

- Core tests pin `odin-rdf v0.31.1`; optional adapters pin
  `odin-sparql v0.1.2` and `odin-reasoner v0.3.0` in CI.
- This release has no persistence, transactions, concurrency control, query
  planning, RDF parsing, or serialization API.
- The Reasoner adapter is a copying migration prototype. It does not replace
  the Reasoner Store or broaden its public default-graph-only contract.
- Existing `Memory_Dataset` and Reasoner Store are not yet one common runtime
  representation. Garden remains the authority for the extraction decision.
