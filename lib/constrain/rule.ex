defmodule Constrain.Rule do
  @moduledoc """
  Horn clause rule for the constraint solver.

  A rule has a list of premises (predicates that must hold) and a conclusion
  (predicate that is derived). An optional guard function provides a side
  condition for concrete arithmetic checks that can't be expressed as
  pattern matching on predicates.

  ## Example

      # Transitivity of >
      %Rule{
        name: :gt_transitive,
        premises: [{:gt, {:var, :x}, {:var, :y}}, {:gt, {:var, :y}, {:var, :z}}],
        conclusion: {:gt, {:var, :x}, {:var, :z}}
      }

      # Type hierarchy: integer <: number
      %Rule{
        name: :integer_is_number,
        premises: [{:is_type, :integer, {:var, :x}}],
        conclusion: {:is_type, :number, {:var, :x}}
      }
  """

  alias Constrain.Predicate

  @type t :: %__MODULE__{
          name: atom(),
          premises: [Predicate.t()],
          conclusion: Predicate.t(),
          guard: (map() -> boolean()) | nil
        }

  @enforce_keys [:name, :premises, :conclusion]
  defstruct [:name, :guard, premises: [], conclusion: true]

  @doc """
  Attempts to match a single premise against a fact.

  Returns a substitution (variable bindings) if the premise matches the fact,
  or `:no_match` if it doesn't. The substitution from a prior match can be
  threaded through to accumulate bindings across multiple premises.
  """
  @spec match_premise(Predicate.t(), Predicate.t(), map()) :: {:ok, map()} | :no_match
  def match_premise(premise, fact, bindings \\ %{})

  # Type check matching with variable tag.
  def match_premise(
        {:is_type, {:var, tag_var}, premise_expr},
        {:is_type, tag, fact_expr},
        bindings
      )
      when is_atom(tag) do
    case Map.get(bindings, tag_var) do
      nil -> match_expr(premise_expr, fact_expr, Map.put(bindings, tag_var, tag))
      ^tag -> match_expr(premise_expr, fact_expr, bindings)
      _ -> :no_match
    end
  end

  # Type check matching with concrete tag.
  def match_premise({:is_type, tag, premise_expr}, {:is_type, tag, fact_expr}, bindings)
      when is_atom(tag) do
    match_expr(premise_expr, fact_expr, bindings)
  end

  # Shape matching.
  def match_premise({:has_shape, premise_expr, shape}, {:has_shape, fact_expr, shape}, bindings) do
    match_expr(premise_expr, fact_expr, bindings)
  end

  # Comparison matching.
  def match_premise({op, p_lhs, p_rhs}, {op, f_lhs, f_rhs}, bindings)
      when op in [:eq, :neq, :strict_eq, :strict_neq, :lt, :gt, :lte, :gte] do
    with {:ok, bindings} <- match_expr(p_lhs, f_lhs, bindings) do
      match_expr(p_rhs, f_rhs, bindings)
    end
  end

  # Bound matching.
  def match_premise({:bound, name}, {:bound, fact_name}, bindings) when is_atom(name) do
    case Map.get(bindings, name) do
      nil -> {:ok, Map.put(bindings, name, fact_name)}
      ^fact_name -> {:ok, bindings}
      _ -> :no_match
    end
  end

  # Membership matching.
  def match_premise({:in, premise_expr, p_values}, {:in, fact_expr, f_values}, bindings) do
    if p_values == f_values do
      match_expr(premise_expr, fact_expr, bindings)
    else
      :no_match
    end
  end

  # Truth values.
  def match_premise(true, true, bindings), do: {:ok, bindings}
  def match_premise(false, false, bindings), do: {:ok, bindings}

  # Logical connectives — only match structurally identical shapes.
  def match_premise({:not, p}, {:not, f}, bindings), do: match_premise(p, f, bindings)

  def match_premise({:and, p1, p2}, {:and, f1, f2}, bindings) do
    with {:ok, bindings} <- match_premise(p1, f1, bindings) do
      match_premise(p2, f2, bindings)
    end
  end

  def match_premise({:or, p1, p2}, {:or, f1, f2}, bindings) do
    with {:ok, bindings} <- match_premise(p1, f1, bindings) do
      match_premise(p2, f2, bindings)
    end
  end

  # No match.
  def match_premise(_premise, _fact, _bindings), do: :no_match

  @doc """
  Instantiates a predicate's variables using a substitution map.

  Variables in the predicate are replaced with their bound values from the
  substitution. Variables not in the substitution remain as variables.
  """
  @spec instantiate(Predicate.t(), map()) :: Predicate.t()
  def instantiate(true, _bindings), do: true
  def instantiate(false, _bindings), do: false

  def instantiate({:bound, name}, bindings) do
    {:bound, Map.get(bindings, name, name)}
  end

  def instantiate({:not, p}, bindings), do: {:not, instantiate(p, bindings)}

  def instantiate({:and, p, q}, bindings),
    do: {:and, instantiate(p, bindings), instantiate(q, bindings)}

  def instantiate({:or, p, q}, bindings),
    do: {:or, instantiate(p, bindings), instantiate(q, bindings)}

  def instantiate({:is_type, {:var, tag_var}, expr}, bindings) do
    tag = Map.get(bindings, tag_var, {:var, tag_var})
    {:is_type, tag, instantiate_expr(expr, bindings)}
  end

  def instantiate({:is_type, tag, expr}, bindings) when is_atom(tag) do
    {:is_type, tag, instantiate_expr(expr, bindings)}
  end

  def instantiate({:has_shape, expr, shape}, bindings) do
    {:has_shape, instantiate_expr(expr, bindings), shape}
  end

  def instantiate({:in, expr, values}, bindings) do
    {:in, instantiate_expr(expr, bindings), values}
  end

  def instantiate({op, lhs, rhs}, bindings)
      when op in [:eq, :neq, :strict_eq, :strict_neq, :lt, :gt, :lte, :gte] do
    {op, instantiate_expr(lhs, bindings), instantiate_expr(rhs, bindings)}
  end

  @doc """
  Instantiates an expression's variables using a substitution map.
  """
  @spec instantiate_expr(Predicate.expr(), map()) :: Predicate.expr()
  def instantiate_expr({:var, name}, bindings) do
    case Map.get(bindings, name) do
      nil -> {:var, name}
      value when is_atom(value) -> {:var, value}
      value -> value
    end
  end

  def instantiate_expr({:lit, _} = lit, _bindings), do: lit

  def instantiate_expr({:field, expr, name}, bindings),
    do: {:field, instantiate_expr(expr, bindings), name}

  def instantiate_expr({:op, op, args}, bindings) do
    {:op, op, Enum.map(args, &instantiate_expr(&1, bindings))}
  end

  # Expression matching: unify a premise expression against a fact expression.
  defp match_expr({:var, name}, fact_expr, bindings) do
    case Map.get(bindings, name) do
      nil -> {:ok, Map.put(bindings, name, fact_expr)}
      ^fact_expr -> {:ok, bindings}
      _ -> :no_match
    end
  end

  defp match_expr({:lit, val}, {:lit, val}, bindings), do: {:ok, bindings}
  defp match_expr({:lit, _}, _, _bindings), do: :no_match

  defp match_expr({:field, p_expr, name}, {:field, f_expr, name}, bindings) do
    match_expr(p_expr, f_expr, bindings)
  end

  defp match_expr({:op, op, p_args}, {:op, op, f_args}, bindings)
       when length(p_args) == length(f_args) do
    Enum.zip(p_args, f_args)
    |> Enum.reduce_while({:ok, bindings}, fn {p, f}, {:ok, b} ->
      case match_expr(p, f, b) do
        {:ok, b2} -> {:cont, {:ok, b2}}
        :no_match -> {:halt, :no_match}
      end
    end)
  end

  defp match_expr(_, _, _bindings), do: :no_match
end
