// Package graph_sparql_adapter maps a frozen odin-graph View to SPARQL's
// application-owned Dataset view boundary. The graph kernel itself remains
// independent from odin-sparql.
package graph_sparql_adapter

import graph "../../graph"
import dataset "odin-sparql:sparql/dataset"
import rdf "odin-rdf:rdf"

// View borrows a frozen graph.View. Keep its Graph owner alive for every
// SPARQL scan or query; this adapter owns no RDF values.
View :: struct { source: graph.View }

// init prepares a SPARQL adapter for an already frozen Graph.
init :: proc(adapter: ^View, source: ^graph.Graph) -> graph.Error {
	view, error := graph.view(source)
	if error != .None {
		adapter^ = {}
		return error
	}
	adapter^ = View{source = view}
	return .None
}

// dataset_view exposes the adapter through SPARQL's public custom-view API.
dataset_view :: proc(adapter: ^View) -> dataset.View {
	return dataset.custom_view(scan, adapter)
}

@(private) Bridge_State :: struct {
	sink:      dataset.Scan_Sink,
	sink_data: rawptr,
}

@(private) bridge_sink :: proc(quad: rdf.Quad, user_data: rawptr) -> bool {
	state := cast(^Bridge_State)user_data
	return state.sink(quad, state.sink_data)
}

@(private) graph_pattern :: proc(pattern: dataset.Quad_Pattern) -> graph.Quad_Pattern {
	return {
		Graph_Mode = graph.Graph_Mode(pattern.Graph_Mode),
		Graph = pattern.Graph,
		Has_Subject = pattern.Has_Subject,
		Subject = pattern.Subject,
		Has_Predicate = pattern.Has_Predicate,
		Predicate = pattern.Predicate,
		Has_Object = pattern.Has_Object,
		Object = pattern.Object,
	}
}

@(private) dataset_error :: proc(error: graph.Error) -> dataset.Error_Code {
	#partial switch error {
	case .None: return .None
	case .Invalid_Sink: return .Invalid_Sink
	case: return .Invalid_View
	}
}

@(private) scan :: proc(data: rawptr, pattern: dataset.Quad_Pattern, sink: dataset.Scan_Sink, sink_data: rawptr) -> dataset.Error_Code {
	adapter := cast(^View)data
	state := Bridge_State{sink = sink, sink_data = sink_data}
	return dataset_error(graph.scan(adapter.source, graph_pattern(pattern), bridge_sink, &state))
}
