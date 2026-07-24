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
	owned:              [dynamic]string,
	max_quads:          int,
	max_lexical_bytes:  int,
	max_terms:          int,
	lexical_bytes:      int,
	frozen:             bool,
}

// View is a borrowed read-only handle into a frozen Graph.
View :: struct { graph: ^Graph }

// init prepares a graph with optional retained-resource bounds.
init :: proc(graph: ^Graph, options: Options = {}) -> Error {
	graph^ = {}
	if options.Max_Quads < 0 || options.Max_Lexical_Bytes < 0 || options.Max_Terms < 0 do return .Invalid_Options
	graph^ = Graph{
		quads = make([dynamic]rdf.Quad),
		owned = make([dynamic]string),
		max_quads = options.Max_Quads,
		max_lexical_bytes = options.Max_Lexical_Bytes,
		max_terms = options.Max_Terms,
	}
	return .None
}

// destroy releases all owned values. A zero or failed-to-initialize Graph is safe to destroy.
destroy :: proc(graph: ^Graph) {
	for value in graph.owned do delete(value)
	delete(graph.owned)
	delete(graph.quads)
	graph^ = {}
}

quad_count :: proc(graph: ^Graph) -> int { return len(graph.quads) }

@(private) equal_term :: proc(left, right: rdf.Term) -> bool {
	return left.kind == right.kind && left.value == right.value && strings.equal_fold(left.language, right.language) && left.datatype == right.datatype && left.scope == right.scope
}

@(private) equal_quad :: proc(left, right: rdf.Quad) -> bool {
	return left.has_graph == right.has_graph && equal_term(left.subject, right.subject) && equal_term(left.predicate, right.predicate) && equal_term(left.object, right.object) && (!left.has_graph || equal_term(left.graph, right.graph))
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

// add copies one valid quad into the Dataset set. Duplicate quads succeed as a
// no-op even after a limit is reached. Every failure leaves retained state unchanged.
add :: proc(graph: ^Graph, value: rdf.Quad) -> Error {
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
	graph.lexical_bytes += lexical_bytes
	return .None
}

// freeze makes a graph read-only. It is idempotent and does not copy quads.
freeze :: proc(graph: ^Graph) -> Error {
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
	for quad in view.graph.quads {
		if matches(pattern, quad) && !sink(quad, sink_data) do break
	}
	return .None
}
