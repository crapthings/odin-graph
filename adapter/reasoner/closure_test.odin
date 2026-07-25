package graph_reasoner_adapter

import "core:testing"
import rdf "odin-rdf:rdf"
import graph "../../graph"
import store "odin-reasoner:reasoner/store"

@(private) Count_State :: struct { count: int }

@(private) count_quad :: proc(_: rdf.Quad, user_data: rawptr) -> bool {
	(cast(^Count_State)user_data).count += 1
	return true
}

@(test)
test_graph_error_mapping_preserves_resource_categories :: proc(t: ^testing.T) {
	cases := [5]struct { input: graph.Error, expected: Error }{
		{.Invalid_Options, .Invalid_Options},
		{.Quad_Limit, .Quad_Limit},
		{.Lexical_Limit, .Lexical_Limit},
		{.Term_Limit, .Term_Limit},
		{.Out_Of_Memory, .Out_Of_Memory},
	}
	for item in cases do testing.expect_value(t, map_graph_error(item.input), item.expected)
	// Internal Graph state remains deliberately opaque at this adapter boundary.
	testing.expect_value(t, map_graph_error(.Invalid_Derivation), Error.Graph_Error)
}

@(test)
test_closure_copy_outlives_reasoner_store :: proc(t: ^testing.T) {
	source: store.Store
	testing.expect_value(t, store.init(&source), store.Error_Code.None)
	added, insert_error := store.insert_triple(&source, {rdf.iri("urn:reasoner:ada"), rdf.iri("urn:reasoner:knows"), rdf.iri("urn:reasoner:bea")})
	testing.expect(t, added)
	testing.expect_value(t, insert_error, store.Error_Code.None)
	inferred_added, inferred_error := store.insert_triple(&source, {rdf.iri("urn:reasoner:bea"), rdf.iri("urn:reasoner:knows"), rdf.iri("urn:reasoner:cy")}, .Inferred)
	testing.expect(t, inferred_added)
	testing.expect_value(t, inferred_error, store.Error_Code.None)
	snapshot: graph.Graph
	testing.expect_value(t, init(&snapshot, &source), Error.None)
	store.destroy(&source)
	defer graph.destroy(&snapshot)
	testing.expect_value(t, graph.quad_count(&snapshot), 2)
	asserted_origin, asserted_found := graph.origin_at(&snapshot, 0)
	inferred_origin, inferred_found := graph.origin_at(&snapshot, 1)
	testing.expect(t, asserted_found && inferred_found)
	testing.expect_value(t, asserted_origin, graph.Origin.Asserted)
	testing.expect_value(t, inferred_origin, graph.Origin.Inferred)
	view, view_error := graph.view(&snapshot)
	testing.expect_value(t, view_error, graph.Error.None)
	state: Count_State
	testing.expect_value(t, graph.scan(view, {Has_Subject = true, Subject = rdf.iri("urn:reasoner:ada")}, count_quad, &state), graph.Error.None)
	testing.expect_value(t, state.count, 1)
}

@(test)
test_closure_copy_limit_failure_keeps_source_and_clears_target :: proc(t: ^testing.T) {
	source: store.Store
	testing.expect_value(t, store.init(&source), store.Error_Code.None)
	defer store.destroy(&source)
	first := rdf.Triple{rdf.iri("urn:reasoner:one"), rdf.iri("urn:reasoner:knows"), rdf.iri("urn:reasoner:two")}
	second := rdf.Triple{rdf.iri("urn:reasoner:two"), rdf.iri("urn:reasoner:knows"), rdf.iri("urn:reasoner:three")}
	first_added, first_error := store.insert_triple(&source, first)
	testing.expect(t, first_added)
	testing.expect_value(t, first_error, store.Error_Code.None)
	second_added, second_error := store.insert_triple(&source, second)
	testing.expect(t, second_added)
	testing.expect_value(t, second_error, store.Error_Code.None)

	snapshot: graph.Graph
	testing.expect_value(t, init(&snapshot, &source, {Max_Quads = 1}), Error.Quad_Limit)
	defer graph.destroy(&snapshot)
	// The failed migration is all-or-nothing: no partial frozen graph escapes,
	// while the completed reasoner closure remains available to its owner.
	testing.expect_value(t, graph.quad_count(&snapshot), 0)
	testing.expect_value(t, store.fact_count(&source), 2)
	first_id, _, _, first_found := store.fact_at(&source, 0)
	testing.expect(t, first_found)
	first_round_trip, found := store.triple_for(&source, first_id)
	testing.expect(t, found)
	testing.expect_value(t, first_round_trip.object.value, "urn:reasoner:two")
}
