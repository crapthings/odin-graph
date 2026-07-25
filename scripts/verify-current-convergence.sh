#!/bin/sh
set -eu

# This gate deliberately follows the adjacent working trees. It is development
# evidence for Graph migration work, not a replacement for Garden's pinned
# release-qualified verification.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
odin_rdf=${ODIN_RDF_COLLECTION:-"$root/../odin-rdf"}
odin_reasoner=${ODIN_REASONER_COLLECTION:-"$root/../odin-reasoner"}
odin_sparql=${ODIN_SPARQL_COLLECTION:-"$root/../odin-sparql"}
garden=${ODIN_GARDEN_ROOT:-"$root/../odin-garden"}
temporary="$root/.tmp"
full_conformance=${ODIN_GRAPH_FULL_CONFORMANCE:-0}

require_directory() {
	if [ ! -d "$1" ]; then
		printf '%s\n' "$2" >&2
		exit 2
	fi
}

require_directory "$odin_rdf" 'ODIN_RDF_COLLECTION must name an odin-rdf checkout'
require_directory "$odin_reasoner" 'ODIN_REASONER_COLLECTION must name an odin-reasoner checkout'
require_directory "$odin_sparql" 'ODIN_SPARQL_COLLECTION must name an odin-sparql checkout'
require_directory "$garden/integration/rdfs_sparql" 'ODIN_GARDEN_ROOT must name an odin-garden checkout with integration fixtures'
case "$full_conformance" in
	0|1) ;;
	*) printf '%s\n' 'ODIN_GRAPH_FULL_CONFORMANCE must be 0 or 1' >&2; exit 2 ;;
esac
mkdir -p "$temporary"

printf '%s\n' "Odin: $(odin version)"
for checkout in "$root" "$odin_rdf" "$odin_reasoner" "$odin_sparql" "$garden"; do
	state=clean
	if [ -n "$(git -C "$checkout" status --porcelain)" ]; then state=dirty; fi
	printf '%s %s %s\n' "$checkout" "$(git -C "$checkout" rev-parse --short HEAD)" "$state"
done

odin test "$root/graph" -collection:odin-rdf="$odin_rdf"
odin test "$root/adapter/reasoner" -collection:odin-rdf="$odin_rdf" -collection:odin-reasoner="$odin_reasoner"
odin test "$root/adapter/sparql" -collection:odin-rdf="$odin_rdf" -collection:odin-sparql="$odin_sparql" -collection:odin-graph="$root"
# This package contains the bounded W3C Profile-RL evidence. Run it from the
# Reasoner root because its checked-in fixtures deliberately use root-relative
# paths; -out keeps the executable out of that adjacent working tree.
(
	cd "$odin_reasoner"
	odin test reasoner/owlrl \
		-out:"$temporary/owlrl" \
		-collection:odin-rdf="$odin_rdf"
)
if [ "$full_conformance" = 1 ]; then
	# The SPARQL verifier includes its pinned W3C suites and 50k-case fuzz gate.
	# It is opt-in to keep the normal source-convergence loop lightweight.
	ODIN_RDF_COLLECTION="$odin_rdf" ODIN_GRAPH_COLLECTION="$root" \
		sh "$odin_sparql/scripts/verify-release.sh"
fi
# Garden fixtures intentionally use paths relative to its repository root.
cd "$garden"
odin test integration/rdfs_sparql \
	-out:"$temporary/rdfs_sparql" \
	-collection:odin-rdf="$odin_rdf" \
	-collection:odin-reasoner="$odin_reasoner" \
	-collection:odin-sparql="$odin_sparql" \
	-collection:odin-graph="$root"
odin test integration/graph_convergence \
	-out:"$temporary/graph_convergence" \
	-collection:odin-rdf="$odin_rdf" \
	-collection:odin-reasoner="$odin_reasoner" \
	-collection:odin-graph="$root"

printf '%s\n' 'current-source Graph convergence verification completed'
