defmodule Constrain.Solver do
  @moduledoc """
  Fixpoint solver with semi-naive evaluation.

  Iteratively applies Horn clause rules to a database of predicate facts until
  a fixed point is reached, a contradiction is found, or an iteration limit is
  exceeded.

  ## Algorithm

  1. Insert initial predicates as facts into the database.
  2. Seed deltas so all initial facts are visible to semi-naive queries.
  3. Loop:
     a. Advance relations (new_rows → delta, delta → total).
     b. For each rule, for each semi-naive plan (one premise from delta,
        rest from total): find all matching substitutions, apply guard,
        instantiate conclusion, insert if new.
     c. If a comparison fact is derived, update the interval table.
        If the interval becomes empty, derive `:false` (contradiction).
     d. If no new facts → `:saturated`, break.
     e. If iteration limit → `:iter_limit`, break.
  4. Return the database and stop reason.
  """

  alias Constrain.Database
  alias Constrain.Predicate
  alias Constrain.Rule

  defmodule Result do
    @moduledoc """
    Result of a solver run.
    """

    @type t :: %__MODULE__{
            database: Database.t(),
            iterations: non_neg_integer(),
            stop_reason: :saturated | :iter_limit | :contradiction
          }

    @enforce_keys [:database, :iterations, :stop_reason]
    defstruct [:database, :iterations, :stop_reason]
  end

  @default_iter_limit 100

  @doc """
  Solves a set of predicate constraints using the built-in rules.
  """
  @spec solve([Predicate.t()]) :: Result.t()
  def solve(predicates) do
    solve(predicates, [])
  end

  @doc """
  Solves with additional custom rules beyond the built-in set.
  """
  @spec solve([Predicate.t()], [Rule.t()]) :: Result.t()
  def solve(predicates, extra_rules) do
    rules = Constrain.Rules.Guards.rules() ++ extra_rules

    db =
      predicates
      |> Enum.reduce(Database.new(), fn pred, db ->
        insert_predicate(db, pred)
      end)

    if db.contradiction do
      %Result{database: db, iterations: 0, stop_reason: :contradiction}
    else
      # Initial facts are in new_rows. The first advance in the fixpoint
      # will promote them to both rows and delta, seeding semi-naive evaluation.
      fixpoint(db, rules, 0, @default_iter_limit)
    end
  end

  @doc """
  Checks entailment: do the assumptions derive the goal?
  """
  @spec entails?([Predicate.t()], Predicate.t()) :: Constrain.answer()
  def entails?(assumptions, goal) do
    result = solve(assumptions)

    cond do
      result.database.contradiction -> :yes
      Database.member?(result.database, goal) -> :yes
      Database.member?(result.database, Predicate.negate(goal)) -> :no
      true -> check_goal_via_intervals(result.database, goal)
    end
  end

  @doc """
  Checks satisfiability: can the predicates all hold simultaneously?
  """
  @spec satisfiable?([Predicate.t()]) :: Constrain.answer()
  def satisfiable?(predicates) do
    result = solve(predicates)

    cond do
      result.database.contradiction -> :no
      result.stop_reason == :saturated -> :yes
      true -> :unknown
    end
  end

  # Inserts a predicate, flattening conjunctions.
  defp insert_predicate(db, {:and, p, q}) do
    db |> insert_predicate(p) |> insert_predicate(q)
  end

  defp insert_predicate(db, pred) do
    Database.insert(db, pred)
  end

  # The core fixpoint loop.
  defp fixpoint(db, _rules, iteration, iter_limit) when iteration >= iter_limit do
    %Result{database: db, iterations: iteration, stop_reason: :iter_limit}
  end

  defp fixpoint(db, rules, iteration, iter_limit) do
    # Advance: promote new_rows to delta, merge into total.
    db = Database.advance(db)

    delta = Database.delta_facts(db)

    if delta == [] do
      %Result{database: db, iterations: iteration, stop_reason: :saturated}
    else
      all_facts = Database.facts(db)

      # Semi-naive: for each rule, try matching with at least one premise from delta.
      db = apply_rules_semi_naive(db, rules, delta, all_facts)

      if db.contradiction do
        %Result{database: db, iterations: iteration + 1, stop_reason: :contradiction}
      else
        if Database.has_new?(db) do
          fixpoint(db, rules, iteration + 1, iter_limit)
        else
          %Result{database: db, iterations: iteration + 1, stop_reason: :saturated}
        end
      end
    end
  end

  # Applies all rules using semi-naive evaluation.
  # For each rule, at least one premise must match a delta fact.
  defp apply_rules_semi_naive(db, rules, delta, all_facts) do
    Enum.reduce_while(rules, db, fn rule, db ->
      db = apply_rule_semi_naive(db, rule, delta, all_facts)

      if db.contradiction do
        {:halt, db}
      else
        {:cont, db}
      end
    end)
  end

  # For a rule with N premises, generate N semi-naive plans.
  # Plan i: premise i matches from delta, all others from total.
  defp apply_rule_semi_naive(db, rule, delta, all_facts) do
    premises = rule.premises

    premises
    |> Enum.with_index()
    |> Enum.reduce_while(db, fn {_premise, delta_idx}, db ->
      db = try_rule_with_delta_at(db, rule, delta, all_facts, delta_idx)

      if db.contradiction do
        {:halt, db}
      else
        {:cont, db}
      end
    end)
  end

  # Try matching a rule where premise at `delta_idx` must match from delta,
  # and all other premises match from total facts.
  defp try_rule_with_delta_at(db, rule, delta, all_facts, delta_idx) do
    premises = rule.premises

    # Start by matching the delta premise.
    delta_premise = Enum.at(premises, delta_idx)

    Enum.reduce_while(delta, db, fn delta_fact, db ->
      case Rule.match_premise(delta_premise, delta_fact) do
        {:ok, bindings} ->
          # Try to match remaining premises against all facts.
          other_premises =
            premises
            |> Enum.with_index()
            |> Enum.reject(fn {_p, i} -> i == delta_idx end)
            |> Enum.map(&elem(&1, 0))

          db = match_remaining(db, rule, other_premises, all_facts, bindings)

          if db.contradiction do
            {:halt, db}
          else
            {:cont, db}
          end

        :no_match ->
          {:cont, db}
      end
    end)
  end

  # Recursively match remaining premises against all facts.
  defp match_remaining(db, rule, [], _all_facts, bindings) do
    # All premises matched — check guard and derive conclusion.
    if rule.guard == nil or rule.guard.(bindings) do
      conclusion = Rule.instantiate(rule.conclusion, bindings)
      Database.insert(db, conclusion)
    else
      db
    end
  end

  defp match_remaining(db, rule, [premise | rest], all_facts, bindings) do
    Enum.reduce_while(all_facts, db, fn fact, db ->
      case Rule.match_premise(premise, fact, bindings) do
        {:ok, new_bindings} ->
          db = match_remaining(db, rule, rest, all_facts, new_bindings)

          if db.contradiction do
            {:halt, db}
          else
            {:cont, db}
          end

        :no_match ->
          {:cont, db}
      end
    end)
  end

  # Check if a comparison goal can be determined from interval bounds.
  defp check_goal_via_intervals(db, {:gt, {:var, name}, {:lit, n}}) when is_number(n) do
    interval = Database.interval_for(db, name)

    cond do
      interval.lo != :neg_inf and compare_bound_gt(interval.lo, interval.lo_inclusive, n) -> :yes
      interval.hi != :pos_inf and compare_bound_lte(interval.hi, interval.hi_inclusive, n) -> :no
      true -> :unknown
    end
  end

  defp check_goal_via_intervals(db, {:gte, {:var, name}, {:lit, n}}) when is_number(n) do
    interval = Database.interval_for(db, name)

    cond do
      interval.lo != :neg_inf and compare_bound_gte(interval.lo, interval.lo_inclusive, n) -> :yes
      interval.hi != :pos_inf and compare_bound_lt(interval.hi, interval.hi_inclusive, n) -> :no
      true -> :unknown
    end
  end

  defp check_goal_via_intervals(db, {:lt, {:var, name}, {:lit, n}}) when is_number(n) do
    interval = Database.interval_for(db, name)

    cond do
      interval.hi != :pos_inf and compare_bound_lt(interval.hi, interval.hi_inclusive, n) -> :yes
      interval.lo != :neg_inf and compare_bound_gte(interval.lo, interval.lo_inclusive, n) -> :no
      true -> :unknown
    end
  end

  defp check_goal_via_intervals(db, {:lte, {:var, name}, {:lit, n}}) when is_number(n) do
    interval = Database.interval_for(db, name)

    cond do
      interval.hi != :pos_inf and compare_bound_lte(interval.hi, interval.hi_inclusive, n) -> :yes
      interval.lo != :neg_inf and compare_bound_gt(interval.lo, interval.lo_inclusive, n) -> :no
      true -> :unknown
    end
  end

  defp check_goal_via_intervals(_db, _goal), do: :unknown

  # bound > n: the lower bound is strictly greater than n.
  defp compare_bound_gt(bound, _inclusive, n) when bound > n, do: true
  defp compare_bound_gt(bound, false, n) when bound == n, do: true
  defp compare_bound_gt(_bound, _inclusive, _n), do: false

  # bound >= n.
  defp compare_bound_gte(bound, _inclusive, n) when bound > n, do: true
  defp compare_bound_gte(bound, true, n) when bound == n, do: true
  defp compare_bound_gte(_bound, _inclusive, _n), do: false

  # bound < n.
  defp compare_bound_lt(bound, _inclusive, n) when bound < n, do: true
  defp compare_bound_lt(bound, false, n) when bound == n, do: true
  defp compare_bound_lt(_bound, _inclusive, _n), do: false

  # bound <= n.
  defp compare_bound_lte(bound, _inclusive, n) when bound <= n, do: true
  defp compare_bound_lte(_bound, _inclusive, _n), do: false
end
