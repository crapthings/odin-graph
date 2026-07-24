package graph

import "core:testing"
import rdf "odin-rdf:rdf"

@(private) Count_State :: struct { count: int }

@(private) count_quad :: proc(_: rdf.Quad, user_data: rawptr) -> bool {
	(cast(^Count_State)user_data).count += 1
	return true
}

@(private) stop_after_one :: proc(_: rdf.Quad, user_data: rawptr) -> bool {
	(cast(^Count_State)user_data).count += 1
	return false
}

@(private) expect_scan_count :: proc(t: ^testing.T, source: View, pattern: Quad_Pattern, expected: int) {
	state: Count_State
	testing.expect_value(t, scan(source, pattern, count_quad, &state), Error.None)
	testing.expect_value(t, state.count, expected)
}

@(test)
test_graph_keeps_default_and_named_source_data_isolated :: proc(t: ^testing.T) {
	value: Graph
	testing.expect_value(t, init(&value, {Max_Quads = 4, Max_Terms = 10}), Error.None)
	defer destroy(&value)
	published := rdf.iri("urn:graph:published")
	ada := rdf.iri("urn:graph:ada")
	knows := rdf.iri("urn:graph:knows")
	source_a := rdf.iri("urn:graph:source-a")
	source_b := rdf.iri("urn:graph:source-b")
	testing.expect_value(t, add(&value, rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:graph:catalog"), published, source_a})), Error.None)
	testing.expect_value(t, add(&value, rdf.named_graph_quad(rdf.Triple{ada, knows, rdf.iri("urn:graph:bea")}, source_a)), Error.None)
	testing.expect_value(t, add(&value, rdf.named_graph_quad(rdf.Triple{ada, knows, rdf.iri("urn:graph:cy")}, source_b)), Error.None)
	testing.expect_value(t, add(&value, rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:graph:catalog"), published, source_b})), Error.None)
	testing.expect_value(t, quad_count(&value), 4)
	testing.expect_value(t, freeze(&value), Error.None)
	view, view_error := view(&value)
	testing.expect_value(t, view_error, Error.None)
	exact: Count_State
	testing.expect_value(t, scan(view, {Graph_Mode = .Named, Graph = source_a, Has_Subject = true, Subject = ada}, count_quad, &exact), Error.None)
	testing.expect_value(t, exact.count, 1)
	any_named: Count_State
	testing.expect_value(t, scan(view, {Graph_Mode = .Any_Named, Has_Subject = true, Subject = ada}, count_quad, &any_named), Error.None)
	testing.expect_value(t, any_named.count, 2)
	default_only: Count_State
	testing.expect_value(t, scan(view, {Has_Subject = true, Subject = ada}, count_quad, &default_only), Error.None)
	testing.expect_value(t, default_only.count, 0)
	early_stop: Count_State
	testing.expect_value(t, scan(view, {}, stop_after_one, &early_stop), Error.None)
	testing.expect_value(t, early_stop.count, 1)
	testing.expect_value(t, add(&value, rdf.default_graph_quad(rdf.Triple{ada, knows, rdf.iri("urn:graph:after-freeze")})), Error.Sealed)
}

@(test)
test_graph_admission_is_atomic_across_duplicate_and_resource_boundaries :: proc(t: ^testing.T) {
	value: Graph
	testing.expect_value(t, init(&value, {Max_Quads = 1, Max_Terms = 3}), Error.None)
	defer destroy(&value)
	first := rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:graph:s"), rdf.iri("urn:graph:p"), rdf.iri("urn:graph:o")})
	named := rdf.named_graph_quad(rdf.Triple{rdf.iri("urn:graph:s"), rdf.iri("urn:graph:p"), rdf.iri("urn:graph:o")}, rdf.iri("urn:graph:name"))
	invalid := rdf.named_graph_quad(rdf.Triple{rdf.iri("urn:graph:x"), rdf.iri("urn:graph:p"), rdf.iri("urn:graph:y")}, rdf.literal("not-a-graph-name"))
	testing.expect_value(t, add(&value, first), Error.None)
	testing.expect_value(t, add(&value, first), Error.None)
	testing.expect_value(t, quad_count(&value), 1)
	testing.expect_value(t, term_count(&value), 3)
	testing.expect_value(t, add(&value, invalid), Error.Invalid_Quad)
	testing.expect_value(t, quad_count(&value), 1)
	testing.expect_value(t, term_count(&value), 3)
	testing.expect_value(t, add(&value, named), Error.Quad_Limit)
	testing.expect_value(t, quad_count(&value), 1)
	testing.expect_value(t, term_count(&value), 3)

	term_limited: Graph
	testing.expect_value(t, init(&term_limited, {Max_Terms = 3}), Error.None)
	defer destroy(&term_limited)
	testing.expect_value(t, add(&term_limited, first), Error.None)
	testing.expect_value(t, add(&term_limited, named), Error.Term_Limit)
	testing.expect_value(t, quad_count(&term_limited), 1)
	testing.expect_value(t, term_count(&term_limited), 3)

	lexical_limited: Graph
	testing.expect_value(t, init(&lexical_limited, {Max_Lexical_Bytes = 1}), Error.None)
	defer destroy(&lexical_limited)
	testing.expect_value(t, add(&lexical_limited, first), Error.Lexical_Limit)
	testing.expect_value(t, quad_count(&lexical_limited), 0)
	testing.expect_value(t, term_count(&lexical_limited), 0)
}

@(test)
test_graph_retains_first_quad_origin_without_affecting_set_admission :: proc(t: ^testing.T) {
	value: Graph
	testing.expect_value(t, init(&value), Error.None)
	defer destroy(&value)
	first := rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:origin:first"), rdf.iri("urn:origin:predicate"), rdf.iri("urn:origin:object")})
	second := rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:origin:second"), rdf.iri("urn:origin:predicate"), rdf.iri("urn:origin:object")})
	testing.expect_value(t, add(&value, first), Error.None)
	testing.expect_value(t, add_with_origin(&value, first, .Inferred), Error.None)
	testing.expect_value(t, add_with_origin(&value, second, .Inferred), Error.None)
	testing.expect_value(t, quad_count(&value), 2)
	first_origin, first_found := origin_at(&value, 0)
	second_origin, second_found := origin_at(&value, 1)
	testing.expect(t, first_found && second_found)
	testing.expect_value(t, first_origin, Origin.Asserted)
	testing.expect_value(t, second_origin, Origin.Inferred)
	testing.expect_value(t, freeze(&value), Error.None)
	frozen_origin, frozen_found := origin_at(&value, 1)
	testing.expect(t, frozen_found)
	testing.expect_value(t, frozen_origin, Origin.Inferred)
}

@(test)
test_graph_preserves_blank_node_scope_in_dataset_identity :: proc(t: ^testing.T) {
	value: Graph
	testing.expect_value(t, init(&value), Error.None)
	defer destroy(&value)
	first_scope := rdf.new_blank_node_scope()
	second_scope := rdf.new_blank_node_scope()
	predicate := rdf.iri("urn:graph:label")
	first := rdf.default_graph_quad(rdf.Triple{rdf.blank_node("same", first_scope), predicate, rdf.language_literal("value", "EN")})
	same_identity := rdf.default_graph_quad(rdf.Triple{rdf.blank_node("same", first_scope), predicate, rdf.language_literal("value", "en")})
	second := rdf.default_graph_quad(rdf.Triple{rdf.blank_node("same", second_scope), predicate, rdf.language_literal("value", "en")})
	testing.expect_value(t, add(&value, first), Error.None)
	testing.expect_value(t, add(&value, same_identity), Error.None)
	testing.expect_value(t, add(&value, second), Error.None)
	testing.expect_value(t, quad_count(&value), 2)
	testing.expect_value(t, freeze(&value), Error.None)
	view, view_error := view(&value)
	testing.expect_value(t, view_error, Error.None)
	first_matches: Count_State
	testing.expect_value(t, scan(view, {Has_Subject = true, Subject = rdf.blank_node("same", first_scope)}, count_quad, &first_matches), Error.None)
	testing.expect_value(t, first_matches.count, 1)
	second_matches: Count_State
	testing.expect_value(t, scan(view, {Has_Subject = true, Subject = rdf.blank_node("same", second_scope)}, count_quad, &second_matches), Error.None)
	testing.expect_value(t, second_matches.count, 1)
}

@(test)
test_graph_indexed_scans_preserve_all_constant_pattern_results :: proc(t: ^testing.T) {
	value: Graph
	testing.expect_value(t, init(&value), Error.None)
	defer destroy(&value)
	s1, s2 := rdf.iri("urn:index:s1"), rdf.iri("urn:index:s2")
	p1, p2 := rdf.iri("urn:index:p1"), rdf.iri("urn:index:p2")
	o1, o2 := rdf.iri("urn:index:o1"), rdf.iri("urn:index:o2")
	triples := [4]rdf.Triple{{s1, p1, o1}, {s1, p1, o2}, {s1, p2, o1}, {s2, p1, o1}}
	for triple in triples do testing.expect_value(t, add(&value, rdf.default_graph_quad(triple)), Error.None)
	source_a, source_b := rdf.iri("urn:index:source-a"), rdf.iri("urn:index:source-b")
	testing.expect_value(t, add(&value, rdf.named_graph_quad(rdf.Triple{s1, p1, o1}, source_a)), Error.None)
	testing.expect_value(t, add(&value, rdf.named_graph_quad(rdf.Triple{s1, p1, o2}, source_b)), Error.None)
	testing.expect_value(t, freeze(&value), Error.None)
	view, view_error := view(&value)
	testing.expect_value(t, view_error, Error.None)
	subject_predicate_ids, subject_predicate_found := find_two_index(&value.by_subject_predicate, {s1, p1})
	testing.expect(t, subject_predicate_found)
	testing.expect_value(t, len(subject_predicate_ids), 4)
	subject_ids, subject_found := find_one_index(&value.by_subject, s1)
	testing.expect(t, subject_found)
	testing.expect_value(t, len(subject_ids), 5)
	graph_ids, graph_found := find_one_index(&value.by_graph, source_a)
	testing.expect(t, graph_found)
	testing.expect_value(t, len(graph_ids), 1)

	expect_scan_count(t, view, {}, 4)
	expect_scan_count(t, view, {Has_Subject = true, Subject = s1}, 3)
	expect_scan_count(t, view, {Has_Predicate = true, Predicate = p1}, 3)
	expect_scan_count(t, view, {Has_Object = true, Object = o1}, 3)
	expect_scan_count(t, view, {Has_Subject = true, Subject = s1, Has_Predicate = true, Predicate = p1}, 2)
	expect_scan_count(t, view, {Has_Subject = true, Subject = s1, Has_Object = true, Object = o1}, 2)
	expect_scan_count(t, view, {Has_Predicate = true, Predicate = p1, Has_Object = true, Object = o1}, 2)
	expect_scan_count(t, view, {Has_Subject = true, Subject = s1, Has_Predicate = true, Predicate = p1, Has_Object = true, Object = o1}, 1)
	expect_scan_count(t, view, {Has_Subject = true, Subject = rdf.iri("urn:index:missing")}, 0)
	expect_scan_count(t, view, {Graph_Mode = .Named, Graph = source_a}, 1)
	expect_scan_count(t, view, {Graph_Mode = .Named, Graph = rdf.iri("urn:index:missing")}, 0)
	expect_scan_count(t, view, {Graph_Mode = .Any_Named, Has_Subject = true, Subject = s1}, 2)
}
