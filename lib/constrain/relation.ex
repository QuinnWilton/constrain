defmodule Constrain.Relation do
  @moduledoc """
  Indexed relation table with three-layer semi-naive tracking.

  Adapted from `Quail.Relation` for use in constraint solving. Stores sets of
  predicate facts with per-column indexes for fast lookup. The three-layer
  tracking (total, delta, new_rows) enables semi-naive evaluation where each
  fixpoint iteration only considers rules with at least one premise matching
  a newly derived fact.

  ## Three-layer model

    - `rows` — the total set of known facts
    - `delta` — facts promoted in the last `advance/1` call (for semi-naive queries)
    - `new_rows` — facts staged since the last `advance/1` (not yet in delta or total)

  The cycle is: insert into new_rows → `advance/1` moves new_rows to delta
  and merges into total → repeat.
  """

  @type row :: tuple()

  @typep row_set :: %{optional(row()) => []}

  @opaque t :: %__MODULE__{
            arity: pos_integer(),
            rows: row_set(),
            indexes: map(),
            delta: row_set(),
            new_rows: row_set()
          }

  @enforce_keys [:arity]
  defstruct [
    :arity,
    rows: %{},
    indexes: %{},
    delta: %{},
    new_rows: %{}
  ]

  @doc """
  Creates a new relation with the given arity.
  """
  @spec new(pos_integer()) :: t()
  def new(arity) when arity > 0 do
    indexes = Map.new(0..(arity - 1), fn i -> {i, %{}} end)
    %__MODULE__{arity: arity, indexes: indexes}
  end

  @doc """
  Inserts a row into the total set.

  Duplicate rows are ignored.
  """
  @spec insert(t(), row()) :: t()
  def insert(%__MODULE__{arity: arity} = rel, row) when tuple_size(row) == arity do
    if is_map_key(rel.rows, row) do
      rel
    else
      %{rel | rows: Map.put(rel.rows, row, []), indexes: add_to_indexes(rel.indexes, row)}
    end
  end

  @doc """
  Stages a row into `new_rows` for semi-naive tracking.

  The row is only staged if it doesn't already exist in the total set.
  """
  @spec insert_new(t(), row()) :: t()
  def insert_new(%__MODULE__{arity: arity} = rel, row) when tuple_size(row) == arity do
    if is_map_key(rel.rows, row) do
      rel
    else
      %{rel | new_rows: Map.put(rel.new_rows, row, [])}
    end
  end

  @doc """
  Looks up rows by a value in the given column.
  """
  @spec lookup(t(), non_neg_integer(), term()) :: [row()]
  def lookup(%__MODULE__{} = rel, column, value) do
    rel.indexes
    |> Map.get(column, %{})
    |> Map.get(value, %{})
    |> Map.keys()
  end

  @doc """
  Returns whether the relation contains the given row.
  """
  @spec member?(t(), row()) :: boolean()
  def member?(%__MODULE__{} = rel, row) do
    is_map_key(rel.rows, row)
  end

  @doc """
  Returns all rows in the relation.
  """
  @spec to_list(t()) :: [row()]
  def to_list(%__MODULE__{} = rel) do
    Map.keys(rel.rows)
  end

  @doc """
  Returns the number of rows.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = rel) do
    map_size(rel.rows)
  end

  @doc """
  Copies the total row set into the delta, making all existing facts appear
  as new for the first iteration of semi-naive evaluation.
  """
  @spec seed_delta(t()) :: t()
  def seed_delta(%__MODULE__{} = rel) do
    %{rel | delta: rel.rows, new_rows: %{}}
  end

  @doc """
  Rotates the three-layer tracking: merges `new_rows` into total, sets
  `delta = new_rows`, and clears `new_rows`.
  """
  @spec advance(t()) :: t()
  def advance(%__MODULE__{} = rel) do
    new_delta = rel.new_rows

    rel =
      Enum.reduce(Map.keys(new_delta), rel, fn row, rel ->
        insert(rel, row)
      end)

    %{rel | delta: new_delta, new_rows: %{}}
  end

  @doc """
  Returns the delta set (facts from the last advance).
  """
  @spec delta_rows(t()) :: [row()]
  def delta_rows(%__MODULE__{} = rel) do
    Map.keys(rel.delta)
  end

  @doc """
  Returns whether there are any new facts staged for the next advance.
  """
  @spec has_new?(t()) :: boolean()
  def has_new?(%__MODULE__{} = rel) do
    map_size(rel.new_rows) > 0
  end

  defp add_to_indexes(indexes, row) do
    Enum.reduce(0..(tuple_size(row) - 1), indexes, fn i, indexes ->
      val = elem(row, i)
      col_index = Map.get(indexes, i, %{})
      col_index = Map.update(col_index, val, %{row => []}, &Map.put(&1, row, []))
      Map.put(indexes, i, col_index)
    end)
  end
end
