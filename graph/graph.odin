// Package graph provides a bounded, owned in-memory RDF Dataset set.
package graph

import "core:strings"
import rdf "odin-rdf:rdf"

// Error identifies setup, admission, freeze, and scan failures.
Error :: enum {
	None,
	Invalid_Options,
	Invalid_Quad,
	Sealed,
	Quad_Limit,
	Lexical_Limit,
	Term_Limit,
	Invalid_View,
	Invalid_Sink,
	Out_Of_Memory,
}

// Options bounds retained graph state. A zero field disables that bound.
Options :: struct {
	Max_Quads:         int,
	Max_Lexical_Bytes: int,
	Max_Terms:         int,
}

// Graph_Mode selects one RDF Dataset graph scope.
Graph_Mode :: enum { Default, Named, Any_Named }

// Origin records the first successful admission source for a quad. It is
// optional metadata for graph consumers such as rule materializers; ordinary
// RDF and SPARQL scans intentionally expose only the RDF quad value.
Origin :: enum { Asserted, Inferred }

// Quad_Pattern selects quads in one graph scope. False Has_* fields are wildcards.
Quad_Pattern :: struct {
	Graph_Mode:    Graph_Mode,
	Graph:         rdf.Term,
	Has_Subject:   bool,
	Subject:       rdf.Term,
	Has_Predicate: bool,
	Predicate:     rdf.Term,
	Has_Object:    bool,
	Object:        rdf.Term,
}

// Scan_Sink receives quads borrowed from a frozen Graph. Returning false stops
// the scan successfully; callers must not retain terms beyond destroy.
Scan_Sink :: #type proc(quad: rdf.Quad, user_data: rawptr) -> bool

// Graph owns copied quads and their lexical values until destroy. It is mutable
// until freeze, after which it may expose borrowed read-only Views.
Graph :: struct {
	quads:             [dynamic]rdf.Quad,
	origins:           [dynamic]Origin,
	owned:              [dynamic]string,
	max_quads:          int,
	max_lexical_bytes:  int,
	max_terms:          int,
	lexical_bytes:      int,
	frozen:             bool,
	by_subject:          One_Index,
	by_predicate:        One_Index,
	by_object:           One_Index,
	by_graph:            One_Index,
	by_subject_predicate: Two_Index,
	by_subject_object:    Two_Index,
	by_predicate_object:  Two_Index,
}

// View is a borrowed read-only handle into a frozen Graph.
View :: struct { graph: ^Graph }

// Index_Bucket borrows one retained term and lists matching quads in insertion
// order. Indexes are built only during freeze, after all mutation is complete.
@(private) Index_Bucket :: struct {
	key: rdf.Term,
	ids: [dynamic]int,
}

@(private) One_Index :: struct { buckets: [dynamic]Index_Bucket }

@(private) Term_Pair :: struct { left, right: rdf.Term }

@(private) Pair_Index_Bucket :: struct {
	key: Term_Pair,
	ids: [dynamic]int,
}

@(private) Two_Index :: struct { buckets: [dynamic]Pair_Index_Bucket }

// init prepares a graph with optional retained-resource bounds.
init :: proc(graph: ^Graph, options: Options = {}) -> Error {
	graph^ = {}
	if options.Max_Quads < 0 || options.Max_Lexical_Bytes < 0 || options.Max_Terms < 0 do return .Invalid_Options
	graph^ = Graph{
		quads = make([dynamic]rdf.Quad),
		origins = make([dynamic]Origin),
		owned = make([dynamic]string),
		max_quads = options.Max_Quads,
		max_lexical_bytes = options.Max_Lexical_Bytes,
		max_terms = options.Max_Terms,
	}
	return .None
}

// destroy releases all owned values. A zero or failed-to-initialize Graph is safe to destroy.
destroy :: proc(graph: ^Graph) {
	destroy_indexes(graph)
	for value in graph.owned do delete(value)
	delete(graph.owned)
	delete(graph.origins)
	delete(graph.quads)
	graph^ = {}
}

quad_count :: proc(graph: ^Graph) -> int { return len(graph.quads) }

// origin_at returns immutable first-admission metadata for a retained quad.
// Values are stable until destroy and remain available after freeze.
origin_at :: proc(graph: ^Graph, index: int) -> (Origin, bool) {
	if index < 0 || index >= len(graph.origins) do return .Asserted, false
	return graph.origins[index], true
}

@(private) equal_term :: proc(left, right: rdf.Term) -> bool {
	return left.kind == right.kind && left.value == right.value && strings.equal_fold(left.language, right.language) && left.datatype == right.datatype && left.scope == right.scope
}

@(private) equal_quad :: proc(left, right: rdf.Quad) -> bool {
	return left.has_graph == right.has_graph && equal_term(left.subject, right.subject) && equal_term(left.predicate, right.predicate) && equal_term(left.object, right.object) && (!left.has_graph || equal_term(left.graph, right.graph))
}

@(private) equal_term_pair :: proc(left, right: Term_Pair) -> bool {
	return equal_term(left.left, right.left) && equal_term(left.right, right.right)
}

@(private) destroy_one_index :: proc(index: ^One_Index) {
	for bucket in index.buckets do delete(bucket.ids)
	delete(index.buckets)
	index^ = {}
}

@(private) destroy_two_index :: proc(index: ^Two_Index) {
	for bucket in index.buckets do delete(bucket.ids)
	delete(index.buckets)
	index^ = {}
}

@(private) destroy_indexes :: proc(graph: ^Graph) {
	destroy_one_index(&graph.by_subject)
	destroy_one_index(&graph.by_predicate)
	destroy_one_index(&graph.by_object)
	destroy_one_index(&graph.by_graph)
	destroy_two_index(&graph.by_subject_predicate)
	destroy_two_index(&graph.by_subject_object)
	destroy_two_index(&graph.by_predicate_object)
}

@(private) add_one_index :: proc(index: ^One_Index, key: rdf.Term, id: int) -> Error {
	for bucket_index in 0..<len(index.buckets) {
		if !equal_term(index.buckets[bucket_index].key, key) do continue
		_, append_error := append(&index.buckets[bucket_index].ids, id)
		if append_error != nil do return .Out_Of_Memory
		return .None
	}
	bucket := Index_Bucket{key = key, ids = make([dynamic]int)}
	_, append_error := append(&bucket.ids, id)
	if append_error != nil {
		delete(bucket.ids)
		return .Out_Of_Memory
	}
	_, append_error = append(&index.buckets, bucket)
	if append_error != nil {
		delete(bucket.ids)
		return .Out_Of_Memory
	}
	return .None
}

@(private) add_two_index :: proc(index: ^Two_Index, key: Term_Pair, id: int) -> Error {
	for bucket_index in 0..<len(index.buckets) {
		if !equal_term_pair(index.buckets[bucket_index].key, key) do continue
		_, append_error := append(&index.buckets[bucket_index].ids, id)
		if append_error != nil do return .Out_Of_Memory
		return .None
	}
	bucket := Pair_Index_Bucket{key = key, ids = make([dynamic]int)}
	_, append_error := append(&bucket.ids, id)
	if append_error != nil {
		delete(bucket.ids)
		return .Out_Of_Memory
	}
	_, append_error = append(&index.buckets, bucket)
	if append_error != nil {
		delete(bucket.ids)
		return .Out_Of_Memory
	}
	return .None
}

@(private) find_one_index :: proc(index: ^One_Index, key: rdf.Term) -> ([]int, bool) {
	for bucket in index.buckets do if equal_term(bucket.key, key) do return bucket.ids[:], true
	return nil, false
}

@(private) find_two_index :: proc(index: ^Two_Index, key: Term_Pair) -> ([]int, bool) {
	for bucket in index.buckets do if equal_term_pair(bucket.key, key) do return bucket.ids[:], true
	return nil, false
}

// build_indexes adds the same exact, two-term, and one-term candidate paths
// used by the Reasoner Store. The Graph stays mutable until every allocation
// succeeds, preserving its admission atomicity on an allocation failure.
@(private) build_indexes :: proc(graph: ^Graph) -> Error {
	destroy_indexes(graph)
	graph.by_subject.buckets = make([dynamic]Index_Bucket)
	graph.by_predicate.buckets = make([dynamic]Index_Bucket)
	graph.by_object.buckets = make([dynamic]Index_Bucket)
	graph.by_graph.buckets = make([dynamic]Index_Bucket)
	graph.by_subject_predicate.buckets = make([dynamic]Pair_Index_Bucket)
	graph.by_subject_object.buckets = make([dynamic]Pair_Index_Bucket)
	graph.by_predicate_object.buckets = make([dynamic]Pair_Index_Bucket)
	for quad, id in graph.quads {
		if error := add_one_index(&graph.by_subject, quad.subject, id); error != .None {
			destroy_indexes(graph)
			return error
		}
		if error := add_one_index(&graph.by_predicate, quad.predicate, id); error != .None {
			destroy_indexes(graph)
			return error
		}
		if error := add_one_index(&graph.by_object, quad.object, id); error != .None {
			destroy_indexes(graph)
			return error
		}
		if quad.has_graph {
			if error := add_one_index(&graph.by_graph, quad.graph, id); error != .None {
				destroy_indexes(graph)
				return error
			}
		}
		if error := add_two_index(&graph.by_subject_predicate, {quad.subject, quad.predicate}, id); error != .None {
			destroy_indexes(graph)
			return error
		}
		if error := add_two_index(&graph.by_subject_object, {quad.subject, quad.object}, id); error != .None {
			destroy_indexes(graph)
			return error
		}
		if error := add_two_index(&graph.by_predicate_object, {quad.predicate, quad.object}, id); error != .None {
			destroy_indexes(graph)
			return error
		}
	}
	return .None
}

@(private) contains_term :: proc(graph: ^Graph, value: rdf.Term) -> bool {
	for quad in graph.quads {
		if equal_term(quad.subject, value) || equal_term(quad.predicate, value) || equal_term(quad.object, value) do return true
		if quad.has_graph && equal_term(quad.graph, value) do return true
	}
	return false
}

@(private) new_term_count :: proc(graph: ^Graph, value: rdf.Quad) -> int {
	terms := [4]rdf.Term{value.subject, value.predicate, value.object, value.graph}
	count := value.has_graph ? 4 : 3
	additional := 0
	for index in 0..<count {
		if contains_term(graph, terms[index]) do continue
		already_counted := false
		for prior in 0..<index {
			if equal_term(terms[prior], terms[index]) {
				already_counted = true
				break
			}
		}
		if !already_counted do additional += 1
	}
	return additional
}

// term_count returns the number of distinct RDF terms retained by the Dataset.
term_count :: proc(graph: ^Graph) -> int {
	count := 0
	for quad, index in graph.quads {
		terms := [4]rdf.Term{quad.subject, quad.predicate, quad.object, quad.graph}
		term_total := quad.has_graph ? 4 : 3
		for term_index in 0..<term_total {
			seen := false
			for prior_quad_index in 0..<index {
				prior := graph.quads[prior_quad_index]
				if equal_term(prior.subject, terms[term_index]) || equal_term(prior.predicate, terms[term_index]) || equal_term(prior.object, terms[term_index]) || (prior.has_graph && equal_term(prior.graph, terms[term_index])) {
					seen = true
					break
				}
			}
			if !seen {
				for prior_term_index in 0..<term_index {
					if equal_term(terms[prior_term_index], terms[term_index]) {
						seen = true
						break
					}
				}
			}
			if !seen do count += 1
		}
	}
	return count
}

@(private) lexical_bytes_needed :: proc(graph: ^Graph, value: rdf.Quad) -> (int, bool) {
	if graph.max_lexical_bytes == 0 do return 0, true
	remaining := graph.max_lexical_bytes - graph.lexical_bytes
	if remaining < 0 do return 0, false
	terms := [4]rdf.Term{value.subject, value.predicate, value.object, value.graph}
	count := value.has_graph ? 4 : 3
	needed := 0
	for term in terms[:count] {
		values := [3]string{term.value, term.language, term.datatype}
		for lexical in values {
			if len(lexical) > remaining - needed do return 0, false
			needed += len(lexical)
		}
	}
	return needed, true
}

@(private) discard_owned_from :: proc(graph: ^Graph, start: int) {
	for index in start..<len(graph.owned) do delete(graph.owned[index])
	resize(&graph.owned, start)
}

@(private) own_string :: proc(graph: ^Graph, value: string) -> (string, Error) {
	if len(value) == 0 do return "", .None
	cloned, clone_error := strings.clone(value)
	if clone_error != nil do return "", .Out_Of_Memory
	_, append_error := append(&graph.owned, cloned)
	if append_error != nil {
		delete(cloned)
		return "", .Out_Of_Memory
	}
	return cloned, .None
}

@(private) own_term :: proc(graph: ^Graph, value: rdf.Term) -> (rdf.Term, Error) {
	result := value
	error: Error
	result.value, error = own_string(graph, value.value)
	if error != .None do return {}, error
	result.language, error = own_string(graph, value.language)
	if error != .None do return {}, error
	result.datatype, error = own_string(graph, value.datatype)
	if error != .None do return {}, error
	return result, .None
}

@(private) own_quad :: proc(graph: ^Graph, value: rdf.Quad) -> (rdf.Quad, Error) {
	result: rdf.Quad
	error: Error
	result.subject, error = own_term(graph, value.subject)
	if error != .None do return {}, error
	result.predicate, error = own_term(graph, value.predicate)
	if error != .None do return {}, error
	result.object, error = own_term(graph, value.object)
	if error != .None do return {}, error
	result.has_graph = value.has_graph
	if value.has_graph {
		result.graph, error = own_term(graph, value.graph)
		if error != .None do return {}, error
	}
	return result, .None
}

// add copies one asserted quad into the Dataset set. Duplicate quads succeed
// as a no-op even after a limit is reached. Every failure leaves retained state
// unchanged.
add :: proc(graph: ^Graph, value: rdf.Quad) -> Error {
	return add_with_origin(graph, value, .Asserted)
}

// add_with_origin copies one quad and retains its first admission origin.
// A duplicate never overwrites its existing provenance, matching set semantics.
add_with_origin :: proc(graph: ^Graph, value: rdf.Quad, origin: Origin) -> Error {
	if graph.frozen do return .Sealed
	if rdf.validate_quad_structure(value) != .None do return .Invalid_Quad
	for known in graph.quads do if equal_quad(known, value) do return .None
	if graph.max_quads > 0 && len(graph.quads) >= graph.max_quads do return .Quad_Limit
	lexical_bytes, lexical_ok := lexical_bytes_needed(graph, value)
	if !lexical_ok do return .Lexical_Limit
	if graph.max_terms > 0 && term_count(graph) + new_term_count(graph, value) > graph.max_terms do return .Term_Limit
	owned_start := len(graph.owned)
	stored, own_error := own_quad(graph, value)
	if own_error != .None {
		discard_owned_from(graph, owned_start)
		return own_error
	}
	_, append_error := append(&graph.quads, stored)
	if append_error != nil {
		discard_owned_from(graph, owned_start)
		return .Out_Of_Memory
	}
	_, append_error = append(&graph.origins, origin)
	if append_error != nil {
		resize(&graph.quads, len(graph.quads) - 1)
		discard_owned_from(graph, owned_start)
		return .Out_Of_Memory
	}
	graph.lexical_bytes += lexical_bytes
	return .None
}

// freeze makes a graph read-only and builds immutable scan indexes. It is
// idempotent and does not copy quads or term strings.
freeze :: proc(graph: ^Graph) -> Error {
	if graph.frozen do return .None
	if error := build_indexes(graph); error != .None do return error
	graph.frozen = true
	return .None
}

@(private) matches :: proc(pattern: Quad_Pattern, quad: rdf.Quad) -> bool {
	switch pattern.Graph_Mode {
	case .Default:
		if quad.has_graph do return false
	case .Named:
		if !quad.has_graph || !equal_term(pattern.Graph, quad.graph) do return false
	case .Any_Named:
		if !quad.has_graph do return false
	}
	return (!pattern.Has_Subject || equal_term(pattern.Subject, quad.subject)) &&
		(!pattern.Has_Predicate || equal_term(pattern.Predicate, quad.predicate)) &&
		(!pattern.Has_Object || equal_term(pattern.Object, quad.object))
}

// view returns a borrowed read-only view after freeze.
view :: proc(graph: ^Graph) -> (View, Error) {
	if !graph.frozen do return {}, .Sealed
	return View{graph = graph}, .None
}

// scan visits matching quads synchronously. A sink false result is a successful early stop.
scan :: proc(view: View, pattern: Quad_Pattern, sink: Scan_Sink, sink_data: rawptr = nil) -> Error {
	if view.graph == nil || !view.graph.frozen do return .Invalid_View
	if sink == nil do return .Invalid_Sink
	graph := view.graph
	if pattern.Has_Subject && pattern.Has_Predicate {
		if ids, found := find_two_index(&graph.by_subject_predicate, {pattern.Subject, pattern.Predicate}); found do scan_candidates(graph, ids, pattern, sink, sink_data)
		return .None
	}
	if pattern.Has_Subject && pattern.Has_Object {
		if ids, found := find_two_index(&graph.by_subject_object, {pattern.Subject, pattern.Object}); found do scan_candidates(graph, ids, pattern, sink, sink_data)
		return .None
	}
	if pattern.Has_Predicate && pattern.Has_Object {
		if ids, found := find_two_index(&graph.by_predicate_object, {pattern.Predicate, pattern.Object}); found do scan_candidates(graph, ids, pattern, sink, sink_data)
		return .None
	}
	if pattern.Graph_Mode == .Named && !pattern.Has_Subject && !pattern.Has_Predicate && !pattern.Has_Object {
		if ids, found := find_one_index(&graph.by_graph, pattern.Graph); found do scan_candidates(graph, ids, pattern, sink, sink_data)
		return .None
	}
	if pattern.Has_Subject {
		if ids, found := find_one_index(&graph.by_subject, pattern.Subject); found do scan_candidates(graph, ids, pattern, sink, sink_data)
		return .None
	}
	if pattern.Has_Predicate {
		if ids, found := find_one_index(&graph.by_predicate, pattern.Predicate); found do scan_candidates(graph, ids, pattern, sink, sink_data)
		return .None
	}
	if pattern.Has_Object {
		if ids, found := find_one_index(&graph.by_object, pattern.Object); found do scan_candidates(graph, ids, pattern, sink, sink_data)
		return .None
	}
	for quad in graph.quads {
		if matches(pattern, quad) && !sink(quad, sink_data) do break
	}
	return .None
}

@(private) scan_candidates :: proc(graph: ^Graph, ids: []int, pattern: Quad_Pattern, sink: Scan_Sink, sink_data: rawptr) {
	for id in ids {
		if id < 0 || id >= len(graph.quads) do continue
		quad := graph.quads[id]
		if matches(pattern, quad) && !sink(quad, sink_data) do break
	}
}
