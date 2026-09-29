"""Program-specific analytics: progress measured against what the program is for.

The engine is a generic interpreter. It knows how to compute a dozen metric
primitives (src/analytics/primitives) over what an athlete has logged; a
*package* declares which of those primitives constitute progress for its
methodology, over which sessions and against what target, in its own
`data/packages/<id>/analytics.yaml`. A package that ships no such file gets a
spec synthesised from its frameworks. Nothing in here names a philosophy.

`compute_program_analytics` is the single entry point and produces the one
document GET /api/analytics/program serves. It is assembled in
src/analytics/document.py once the pieces below exist; until then the pieces
are importable and tested on their own.
"""
