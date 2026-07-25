// Package graph_reasoner_adapter copies a completed reasoner closure into a
// frozen odin-graph Graph. It retains asserted/inferred first-origin metadata
// and can copy opaque first-support derivations, while inference execution and
// Store-native IDs remain in odin-reasoner; this is a migration prototype, not
// a replacement Store.
package graph_reasoner_adapter

import graph "../../graph"
import rdf "odin-rdf:rdf"
import rule "odin-reasoner:reasoner/rule"
import store "odin-reasoner:reasoner/store"

// Error reports source-store corruption separately from resource admission
// failures in the copied Graph. Graph_Error remains the fallback for internal
// graph-state failures that the migration boundary cannot expose safely.
Error :: enum {
	None,
	Store_Error,
	Invalid_Options,
	Quad_Limit,
	Lexical_Limit,
	Term_Limit,
	Out_Of_Memory,
	Graph_Error,
}

@(private) map_graph_error :: proc(value: graph.Error) -> Error {
	#partial switch value {
	case .Invalid_Options: return .Invalid_Options
	case .Quad_Limit:      return .Quad_Limit
	case .Lexical_Limit:   return .Lexical_Limit
	case .Term_Limit:      return .Term_Limit
	case .Out_Of_Memory:   return .Out_Of_Memory
	case:                   return .Graph_Error
	}
}

@(private) graph_origin :: proc(value: store.Origin) -> graph.Origin {
	return value == .Inferred ? .Inferred : .Asserted
}

// init copies every retained default-graph closure triple into target, freezes
// it, and leaves source unchanged. On any error target is reset and safe to
// destroy. Graph admission options make the copy all-or-nothing for callers.
init :: proc(target: ^graph.Graph, source: ^store.Store, options: graph.Options = {}) -> Error {
	return copy_closure(target, source, nil, options)
}

// init_with_derivations additionally copies first-support records from the
// latest successful rule materialization. Graph stores opaque rule IDs and
// Graph-local quad indexes, never Store IDs or rule definitions.
init_with_derivations :: proc(target: ^graph.Graph, source: ^store.Store, materializer: ^rule.Materializer, options: graph.Options = {}) -> Error {
	return copy_closure(target, source, materializer, options)
}

@(private) copy_closure :: proc(target: ^graph.Graph, source: ^store.Store, materializer: ^rule.Materializer, options: graph.Options) -> Error {
	if graph_error := graph.init(target, options); graph_error != .None do return map_graph_error(graph_error)
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
		if graph_error := graph.add_with_origin(target, rdf.default_graph_quad(triple), graph_origin(origin)); graph_error != .None {
			graph.destroy(target)
			return map_graph_error(graph_error)
		}
	}
	if materializer != nil {
		for derivation_index in 0..<rule.derivation_count(materializer) {
			derivation, found := rule.derivation_at(materializer, derivation_index)
			if !found {
				graph.destroy(target)
				return .Store_Error
			}
			quad_index := int(derivation.fact_id) - 1
			supports := make([dynamic]int, 0, len(derivation.supports))
			for support in derivation.supports {
				_, append_error := append(&supports, int(support) - 1)
				if append_error != nil {
					delete(supports)
					graph.destroy(target)
					return .Out_Of_Memory
				}
			}
			record_error := graph.record_derivation(target, quad_index, u32(derivation.rule_id), supports[:])
			delete(supports)
			if record_error != .None {
				graph.destroy(target)
				return map_graph_error(record_error)
			}
		}
	}
	if graph_error := graph.freeze(target); graph_error != .None {
		graph.destroy(target)
		return map_graph_error(graph_error)
	}
	return .None
}
