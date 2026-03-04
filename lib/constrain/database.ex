defmodule Constrain.Database do
  @moduledoc """
  Fact store for the constraint solver.

  Wraps a `Relation` of predicate facts with an interval table for numeric
  bounds and a type table for known type assignments. Provides a unified
  interface for inserting facts, querying membership, and advancing the
  semi-naive evaluation layers.

  ## Design

  The database stores three kinds of information:

    - **Facts** — predicate tuples in a `Relation` (the primary store)
    - **Intervals** — numeric bounds per variable, updated when comparison
      facts are derived
    - **Types** — known type tags per variable, updated when type check
      facts are derived

  Intervals and types are secondary indexes derived from facts. They enable
  efficient contradiction detection without scanning all facts.
  """

  alias Constrain.Domain.Interval
  alias Constrain.Predicate
  alias Constrain.Relation

  @type t :: %__MODULE__{
          facts: Relation.t(),
          intervals: %{atom() => Interval.t()},
          types: %{atom() => MapSet.t(Predicate.type_tag())},
          contradiction: boolean()
        }

  @enforce_keys [:facts]
  defstruct [
    :facts,
    intervals: %{},
    types: %{},
    contradiction: false
  ]

  @doc """
  Creates a new empty database.
  """
  @spec new() :: t()
  def new do
    # Arity 1: each row is a single-element tuple wrapping a predicate.
    %__MODULE__{facts: Relation.new(1)}
  end

  @doc """
  Inserts a predicate fact into the database.

  Also updates the interval and type secondary indexes. If a contradiction
  is detected (empty interval or conflicting types), sets `contradiction: true`.
  """
  @spec insert(t(), Predicate.t()) :: t()
  def insert(%__MODULE__{} = db, true), do: db

  def insert(%__MODULE__{} = db, false) do
    %{db | contradiction: true}
  end

  def insert(%__MODULE__{} = db, fact) do
    db = %{db | facts: Relation.insert_new(db.facts, {fact})}

    db
    |> update_intervals(fact)
    |> update_types(fact)
  end

  @doc """
  Returns whether the database contains a fact.
  """
  @spec member?(t(), Predicate.t()) :: boolean()
  def member?(%__MODULE__{} = db, fact) do
    Relation.member?(db.facts, {fact})
  end

  @doc """
  Returns all facts in the database.
  """
  @spec facts(t()) :: [Predicate.t()]
  def facts(%__MODULE__{} = db) do
    db.facts |> Relation.to_list() |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Returns the delta facts (newly derived in the last advance).
  """
  @spec delta_facts(t()) :: [Predicate.t()]
  def delta_facts(%__MODULE__{} = db) do
    db.facts |> Relation.delta_rows() |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Seeds the delta with all existing facts for the first semi-naive iteration.
  """
  @spec seed_delta(t()) :: t()
  def seed_delta(%__MODULE__{} = db) do
    %{db | facts: Relation.seed_delta(db.facts)}
  end

  @doc """
  Advances the semi-naive layers.
  """
  @spec advance(t()) :: t()
  def advance(%__MODULE__{} = db) do
    %{db | facts: Relation.advance(db.facts)}
  end

  @doc """
  Returns whether there are new facts staged.
  """
  @spec has_new?(t()) :: boolean()
  def has_new?(%__MODULE__{} = db) do
    Relation.has_new?(db.facts)
  end

  @doc """
  Returns the number of facts.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = db) do
    Relation.size(db.facts)
  end

  @doc """
  Returns the interval for a variable, or the universal interval if unknown.
  """
  @spec interval_for(t(), atom()) :: Interval.t()
  def interval_for(%__MODULE__{} = db, var) do
    Map.get(db.intervals, var, Interval.top())
  end

  @doc """
  Returns the known types for a variable.
  """
  @spec types_for(t(), atom()) :: MapSet.t(Predicate.type_tag())
  def types_for(%__MODULE__{} = db, var) do
    Map.get(db.types, var, MapSet.new())
  end

  # Updates interval bounds when comparison facts involving literal numbers are derived.
  defp update_intervals(db, {:gt, {:var, name}, {:lit, n}}) when is_number(n) do
    narrow_interval(db, name, Interval.gt(n))
  end

  defp update_intervals(db, {:gte, {:var, name}, {:lit, n}}) when is_number(n) do
    narrow_interval(db, name, Interval.gte(n))
  end

  defp update_intervals(db, {:lt, {:var, name}, {:lit, n}}) when is_number(n) do
    narrow_interval(db, name, Interval.lt(n))
  end

  defp update_intervals(db, {:lte, {:var, name}, {:lit, n}}) when is_number(n) do
    narrow_interval(db, name, Interval.lte(n))
  end

  defp update_intervals(db, {:eq, {:var, name}, {:lit, n}}) when is_number(n) do
    narrow_interval(db, name, Interval.point(n))
  end

  # Symmetric cases: literal on the left.
  defp update_intervals(db, {:gt, {:lit, n}, {:var, name}}) when is_number(n) do
    narrow_interval(db, name, Interval.lt(n))
  end

  defp update_intervals(db, {:gte, {:lit, n}, {:var, name}}) when is_number(n) do
    narrow_interval(db, name, Interval.lte(n))
  end

  defp update_intervals(db, {:lt, {:lit, n}, {:var, name}}) when is_number(n) do
    narrow_interval(db, name, Interval.gt(n))
  end

  defp update_intervals(db, {:lte, {:lit, n}, {:var, name}}) when is_number(n) do
    narrow_interval(db, name, Interval.gte(n))
  end

  defp update_intervals(db, {:eq, {:lit, n}, {:var, name}}) when is_number(n) do
    narrow_interval(db, name, Interval.point(n))
  end

  defp update_intervals(db, _fact), do: db

  defp narrow_interval(db, name, constraint) do
    current = Map.get(db.intervals, name, Interval.top())
    narrowed = Interval.meet(current, constraint)
    db = %{db | intervals: Map.put(db.intervals, name, narrowed)}

    if Interval.empty?(narrowed) do
      %{db | contradiction: true}
    else
      db
    end
  end

  # Updates the type index when is_type facts are derived.
  defp update_types(db, {:is_type, tag, {:var, name}}) do
    types = Map.get(db.types, name, MapSet.new())
    %{db | types: Map.put(db.types, name, MapSet.put(types, tag))}
  end

  defp update_types(db, _fact), do: db
end
