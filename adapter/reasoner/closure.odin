// Package graph_reasoner_adapter copies a completed reasoner closure into a
// frozen odin-graph Graph. It retains asserted/inferred first-origin metadata,
// while inference execution and Store-native IDs remain in odin-reasoner; this
// is a migration prototype, not a replacement Store.
package graph_reasoner_adapter

import graph "../../graph"
import rdf "odin-rdf:rdf"
import store "odin-reasoner:reasoner/store"

Error :: enum { None, Store_Error, Graph_Error }

@(private) graph_origin :: proc(value: store.Origin) -> graph.Origin {
	return value == .Inferred ? .Inferred : .Asserted
}

// init copies every retained default-graph closure triple into target, freezes
// it, and leaves source unchanged. On any error target is reset and safe to
// destroy. Graph admission options make the copy all-or-nothing for callers.
init :: proc(target: ^graph.Graph, source: ^store.Store, options: graph.Options = {}) -> Error {
	if graph.init(target, options) != .None do return .Graph_Error
	for index in 0..<store.fact_count(source) {
		id, _, origin, found := store.fact_at(source, index)
		if !found {
			graph.destroy(target)
			return .Store_Error
		}
		triple, valid := store.triple_for(source, id)
		if !valid {
			graph.destroy(target)
			return .Store_Error
		}
		if graph.add_with_origin(target, rdf.default_graph_quad(triple), graph_origin(origin)) != .None {
			graph.destroy(target)
			return .Graph_Error
		}
	}
	if graph.freeze(target) != .None {
		graph.destroy(target)
		return .Graph_Error
	}
	return .None
}
