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
