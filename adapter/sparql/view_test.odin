package graph_sparql_adapter

import "core:testing"
import rdf "odin-rdf:rdf"
import sparql "odin-sparql:sparql"
import dataset "odin-sparql:sparql/dataset"
import engine "odin-sparql:sparql/engine"
import graph "../../graph"

@(private) execute :: proc(t: ^testing.T, text: string, view: dataset.View) -> engine.Result {
	query, parse_error := sparql.Parse(text)
	defer sparql.Destroy(&query)
	testing.expect_value(t, sparql.Parse_Error_Code(parse_error), sparql.Error_Code.None)
	result, execute_error := engine.execute(&query, view, {Max_Solutions = 8})
	testing.expect_value(t, execute_error, engine.Error_Code.None)
	return result
}

@(test)
test_adapter_exposes_frozen_named_graphs_to_sparql :: proc(t: ^testing.T) {
	source: graph.Graph
	testing.expect_value(t, graph.init(&source), graph.Error.None)
	defer graph.destroy(&source)
	ada := rdf.iri("urn:adapter:ada")
	knows := rdf.iri("urn:adapter:knows")
	source_a := rdf.iri("urn:adapter:source-a")
	source_b := rdf.iri("urn:adapter:source-b")
	testing.expect_value(t, graph.add(&source, rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:adapter:catalog"), rdf.iri("urn:adapter:published"), source_a})), graph.Error.None)
	testing.expect_value(t, graph.add(&source, rdf.named_graph_quad(rdf.Triple{ada, knows, rdf.iri("urn:adapter:bea")}, source_a)), graph.Error.None)
	testing.expect_value(t, graph.add(&source, rdf.named_graph_quad(rdf.Triple{ada, knows, rdf.iri("urn:adapter:cy")}, source_b)), graph.Error.None)
	testing.expect_value(t, graph.freeze(&source), graph.Error.None)
	adapter: View
	testing.expect_value(t, init(&adapter, &source), graph.Error.None)
	view := dataset_view(&adapter)

	exact := execute(t, `SELECT ?friend { GRAPH <urn:adapter:source-a> { <urn:adapter:ada> <urn:adapter:knows> ?friend } }`, view)
	defer engine.destroy(&exact)
	testing.expect_value(t, engine.Row_Count(&exact), 1)
	friend, friend_bound, friend_valid := engine.Cell(&exact, 0, 0)
	testing.expect(t, friend_valid && friend_bound)
	testing.expect_value(t, friend.value, "urn:adapter:bea")

	variable := execute(t, `SELECT ?source ?friend { GRAPH ?source { <urn:adapter:ada> <urn:adapter:knows> ?friend } } ORDER BY ?source`, view)
	defer engine.destroy(&variable)
	testing.expect_value(t, engine.Row_Count(&variable), 2)
	first_source, first_source_bound, first_source_valid := engine.Cell(&variable, 0, 0)
	first_friend, first_friend_bound, first_friend_valid := engine.Cell(&variable, 0, 1)
	testing.expect(t, first_source_valid && first_source_bound && first_friend_valid && first_friend_bound)
	testing.expect_value(t, first_source.value, "urn:adapter:source-a")
	testing.expect_value(t, first_friend.value, "urn:adapter:bea")

	default_scope := execute(t, `ASK { <urn:adapter:ada> <urn:adapter:knows> <urn:adapter:bea> }`, view)
	defer engine.destroy(&default_scope)
	answer, answer_valid := engine.Ask_Value(&default_scope)
	testing.expect(t, answer_valid && !answer)
}
