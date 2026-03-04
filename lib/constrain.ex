defmodule Constrain do
  @moduledoc """
  Horn clause constraint solver over Elixir guard and pattern matching predicates.

  Encodes the semantics of Elixir's guard predicate language as Horn clauses
  and solves entailment/satisfiability via bottom-up fixpoint computation.

  ## Usage

      # Check if assumptions entail a goal.
      :yes = Constrain.entails?([{:gt, {:var, :x}, {:lit, 5}}], {:gt, {:var, :x}, {:lit, 0}})

      # Check satisfiability of constraints.
      :no = Constrain.satisfiable?([{:gt, {:var, :x}, {:lit, 5}}, {:lt, {:var, :x}, {:lit, 3}}])

      # Run the solver and inspect the resulting database.
      result = Constrain.solve([{:is_type, :integer, {:var, :x}}])
  """

  alias Constrain.Database
  alias Constrain.Solver

  @type answer :: :yes | :no | :unknown

  @doc """
  Solves a set of predicate constraints using the built-in rules.

  Returns the solver result containing the saturated database and metadata.
  """
  @spec solve([Constrain.Predicate.t()]) :: Solver.Result.t()
  def solve(predicates) do
    Solver.solve(predicates)
  end

  @doc """
  Solves with additional custom rules beyond the built-in set.
  """
  @spec solve([Constrain.Predicate.t()], [Constrain.Rule.t()]) :: Solver.Result.t()
  def solve(predicates, extra_rules) do
    Solver.solve(predicates, extra_rules)
  end

  @doc """
  Checks whether a set of assumptions entails a goal predicate.

  Returns `:yes` if the goal is derivable from the assumptions using the
  built-in rules, `:no` if the negation of the goal is derivable, or
  `:unknown` if neither can be determined.
  """
  @spec entails?([Constrain.Predicate.t()], Constrain.Predicate.t()) :: answer()
  def entails?(assumptions, goal) do
    Solver.entails?(assumptions, goal)
  end

  @doc """
  Checks whether a set of predicates is satisfiable.

  Returns `:yes` if no contradiction is derivable, `:no` if a contradiction
  is found, or `:unknown` if the solver cannot determine satisfiability
  within its limits.
  """
  @spec satisfiable?([Constrain.Predicate.t()]) :: answer()
  def satisfiable?(predicates) do
    Solver.satisfiable?(predicates)
  end

  @doc """
  Returns all facts derivable from the given predicates.

  Convenience function that solves and returns the fact list.
  """
  @spec derive([Constrain.Predicate.t()]) :: [Constrain.Predicate.t()]
  def derive(predicates) do
    result = solve(predicates)
    Database.facts(result.database)
  end
end
