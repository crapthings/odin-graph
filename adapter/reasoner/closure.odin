// Package graph_reasoner_adapter copies a completed reasoner closure into a
// frozen odin-graph Graph. It keeps inference, provenance, and Store indexes
// in odin-reasoner; this is a migration prototype, not a replacement Store.
package graph_reasoner_adapter

import graph "../../graph"
import rdf "odin-rdf:rdf"
import store "odin-reasoner:reasoner/store"

Error :: enum { None, Store_Error, Graph_Error }

// init copies every retained default-graph closure triple into target, freezes
// it, and leaves source unchanged. On any error target is reset and safe to
// destroy. Graph admission options make the copy all-or-nothing for callers.
init :: proc(target: ^graph.Graph, source: ^store.Store, options: graph.Options = {}) -> Error {
	if graph.init(target, options) != .None do return .Graph_Error
	for index in 0..<store.fact_count(source) {
		id, _, _, found := store.fact_at(source, index)
		if !found {
			graph.destroy(target)
			return .Store_Error
		}
		triple, valid := store.triple_for(source, id)
		if !valid {
			graph.destroy(target)
			return .Store_Error
		}
		if graph.add(target, rdf.default_graph_quad(triple)) != .None {
			graph.destroy(target)
			return .Graph_Error
		}
	}
	_ = graph.freeze(target)
	return .None
}
