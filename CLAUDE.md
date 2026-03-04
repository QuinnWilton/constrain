# constrain

Horn clause constraint solver over Elixir guard and pattern matching predicates.

## What it does

Constrain encodes the semantics of Elixir's guard predicate language as Horn clauses and solves entailment/satisfiability via bottom-up fixpoint computation with semi-naive evaluation. Designed for use by `deft` (the bidirectional type checker) to support refinement types.

## Architecture

```
Constrain (facade)
  ├── Solver (fixpoint loop, semi-naive evaluation)
  │     ├── Database (fact store + indexes)
  │     │     └── Relation (indexed tables, three-layer semi-naive tracking)
  │     ├── Rules (rule structs)
  │     └── Domain (type lattice + interval arithmetic)
  ├── Pattern (Elixir pattern AST → predicates)
  ├── Guard (Elixir guard AST → predicates)
  └── Rules.Guards (built-in semantic rules)
```

Dependencies flow strictly downward. The solver is standalone — no dependency on deft or any external SMT solver.

## Key design decisions

- **Tagged tuples for predicates** — predicates are small, numerous, and heavily pattern-matched. Plain data, no structs or macros.
- **Interval arithmetic as hybrid domain** — pure Horn clauses can't express numeric reasoning without infinite rules. Interval propagation is built into the database: comparison facts update variable bounds, and empty intervals derive contradictions.
- **Three-valued logic** — `:yes` / `:no` / `:unknown`. Soundness requires never claiming entailment that doesn't hold.
- **Adapted Relation module** — structurally based on quail's three-layer semi-naive `Relation`, adapted (~200 lines) to keep constrain standalone on Hex.

## Development commands

```bash
mix test                      # run all tests
mix format                    # format code
mix format --check-formatted  # check formatting
mix dialyzer                  # static analysis
```

## Commit message style

```
[component] brief description
```

## Testing conventions

- Unit tests mirror `lib/` structure in `test/constrain/`.
- Example tests (entailment, satisfiability) in `test/examples/`.
- Property tests (soundness, monotonicity, intervals) in `test/property/`.
- Test support (generators) in `test/support/`.
