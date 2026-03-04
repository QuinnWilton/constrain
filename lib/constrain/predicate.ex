defmodule Constrain.Predicate do
  @moduledoc """
  Predicate AST for Horn clause constraints.

  Predicates are represented as tagged tuples for efficient pattern matching
  in rule bodies. This follows the same plain-data philosophy as quail's ADR-001.

  ## Expression forms

      {:var, atom()}                  - variable reference
      {:op, op(), [expr()]}           - operation (abs, elem, etc.)
      {:field, expr(), atom()}        - map field access
      {:lit, literal()}               - literal value

  ## Comparison predicates

      {:eq, expr(), expr()}           - structural equality (==)
      {:neq, expr(), expr()}          - structural inequality (!=)
      {:strict_eq, expr(), expr()}    - strict equality (===)
      {:strict_neq, expr(), expr()}   - strict inequality (!==)
      {:lt, expr(), expr()}           - less than
      {:gt, expr(), expr()}           - greater than
      {:lte, expr(), expr()}          - less than or equal
      {:gte, expr(), expr()}          - greater than or equal

  ## Type predicates

      {:is_type, type_tag(), expr()}  - type check (is_integer, etc.)

  ## Logical connectives

      {:and, pred(), pred()}          - conjunction
      {:or, pred(), pred()}           - disjunction
      {:not, pred()}                  - negation

  ## Structural predicates

      {:bound, atom()}                - variable is bound
      {:has_shape, expr(), shape()}   - structural shape constraint
      {:in, expr(), [literal()]}      - membership in literal set

  ## Truth values

      :true | :false                  - literal truth/falsehood
  """

  @type literal :: number() | atom() | binary()

  @type op ::
          :abs
          | :ceil
          | :floor
          | :round
          | :trunc
          | :elem
          | :hd
          | :tl
          | :length
          | :map_size
          | :tuple_size
          | :byte_size
          | :bit_size
          | :node
          | :self
          | :add
          | :sub
          | :mul
          | :div
          | :rem
          | :band
          | :bor
          | :bxor
          | :bnot
          | :bsl
          | :bsr

  @type expr ::
          {:var, atom()}
          | {:op, op(), [expr()]}
          | {:field, expr(), atom()}
          | {:lit, literal()}

  @type type_tag ::
          :integer
          | :float
          | :number
          | :atom
          | :boolean
          | nil
          | :binary
          | :bitstring
          | :list
          | :tuple
          | :map
          | :struct
          | :pid
          | :port
          | :reference
          | :function

  @type segment_type :: :integer | :float | :binary | :bitstring | :utf8 | :utf16 | :utf32
  @type segment_size :: pos_integer() | {:dynamic, atom()} | :default

  @type segment_spec ::
          {atom() | nil, segment_type(), segment_size(), pos_integer(), :unsigned | :signed,
           :big | :little | :native}

  @type shape ::
          {:tuple, non_neg_integer()}
          | {:map, [atom()]}

  @type t ::
          {:eq, expr(), expr()}
          | {:neq, expr(), expr()}
          | {:strict_eq, expr(), expr()}
          | {:strict_neq, expr(), expr()}
          | {:lt, expr(), expr()}
          | {:gt, expr(), expr()}
          | {:lte, expr(), expr()}
          | {:gte, expr(), expr()}
          | {:is_type, type_tag(), expr()}
          | {:and, t(), t()}
          | {:or, t(), t()}
          | {:not, t()}
          | {:bound, atom()}
          | {:has_shape, expr(), shape()}
          | {:in, expr(), [literal()]}
          | {:has_binary_segments, expr(), [segment_spec()]}
          | true
          | false

  @comparison_ops [:eq, :neq, :strict_eq, :strict_neq, :lt, :gt, :lte, :gte]

  @doc """
  Returns the set of free variables in a predicate.
  """
  @spec free_vars(t()) :: MapSet.t(atom())
  def free_vars(true), do: MapSet.new()
  def free_vars(false), do: MapSet.new()
  def free_vars({:bound, name}), do: MapSet.new([name])
  def free_vars({:not, p}), do: free_vars(p)
  def free_vars({:and, p, q}), do: MapSet.union(free_vars(p), free_vars(q))
  def free_vars({:or, p, q}), do: MapSet.union(free_vars(p), free_vars(q))
  def free_vars({:is_type, _tag, expr}), do: expr_vars(expr)
  def free_vars({:has_shape, expr, _shape}), do: expr_vars(expr)
  def free_vars({:in, expr, _values}), do: expr_vars(expr)

  def free_vars({:has_binary_segments, expr, segments}) do
    segment_vars =
      Enum.reduce(segments, MapSet.new(), fn {binding, _type, size, _unit, _sign, _end}, acc ->
        acc = if is_atom(binding) and binding != nil, do: MapSet.put(acc, binding), else: acc

        case size do
          {:dynamic, var} -> MapSet.put(acc, var)
          _ -> acc
        end
      end)

    MapSet.union(expr_vars(expr), segment_vars)
  end

  def free_vars({op, lhs, rhs}) when op in @comparison_ops do
    MapSet.union(expr_vars(lhs), expr_vars(rhs))
  end

  @doc """
  Returns the set of free variables in an expression.
  """
  @spec expr_vars(expr()) :: MapSet.t(atom())
  def expr_vars({:var, name}), do: MapSet.new([name])
  def expr_vars({:lit, _}), do: MapSet.new()
  def expr_vars({:field, expr, _name}), do: expr_vars(expr)

  def expr_vars({:op, _op, args}) do
    Enum.reduce(args, MapSet.new(), fn arg, acc -> MapSet.union(acc, expr_vars(arg)) end)
  end

  @doc """
  Negates a predicate, pushing negation inward where possible.
  """
  @spec negate(t()) :: t()
  def negate(true), do: false
  def negate(false), do: true
  def negate({:not, p}), do: p
  def negate({:and, p, q}), do: {:or, negate(p), negate(q)}
  def negate({:or, p, q}), do: {:and, negate(p), negate(q)}
  def negate({:eq, a, b}), do: {:neq, a, b}
  def negate({:neq, a, b}), do: {:eq, a, b}
  def negate({:strict_eq, a, b}), do: {:strict_neq, a, b}
  def negate({:strict_neq, a, b}), do: {:strict_eq, a, b}
  def negate({:lt, a, b}), do: {:gte, a, b}
  def negate({:gte, a, b}), do: {:lt, a, b}
  def negate({:gt, a, b}), do: {:lte, a, b}
  def negate({:lte, a, b}), do: {:gt, a, b}
  def negate(pred), do: {:not, pred}

  @doc """
  Applies a variable substitution to a predicate.

  The substitution maps variable names to expressions.
  """
  @spec subst(t(), %{atom() => expr()}) :: t()
  def subst(true, _env), do: true
  def subst(false, _env), do: false
  def subst({:bound, name}, env), do: {:bound, subst_var_name(name, env)}
  def subst({:not, p}, env), do: {:not, subst(p, env)}
  def subst({:and, p, q}, env), do: {:and, subst(p, env), subst(q, env)}
  def subst({:or, p, q}, env), do: {:or, subst(p, env), subst(q, env)}
  def subst({:is_type, tag, expr}, env), do: {:is_type, tag, subst_expr(expr, env)}
  def subst({:has_shape, expr, shape}, env), do: {:has_shape, subst_expr(expr, env), shape}
  def subst({:in, expr, values}, env), do: {:in, subst_expr(expr, env), values}

  def subst({:has_binary_segments, expr, segs}, env) do
    {:has_binary_segments, subst_expr(expr, env), segs}
  end

  def subst({op, lhs, rhs}, env) when op in @comparison_ops do
    {op, subst_expr(lhs, env), subst_expr(rhs, env)}
  end

  @doc """
  Applies a variable substitution to an expression.
  """
  @spec subst_expr(expr(), %{atom() => expr()}) :: expr()
  def subst_expr({:var, name}, env), do: Map.get(env, name, {:var, name})
  def subst_expr({:lit, _} = lit, _env), do: lit
  def subst_expr({:field, expr, name}, env), do: {:field, subst_expr(expr, env), name}

  def subst_expr({:op, op, args}, env) do
    {:op, op, Enum.map(args, &subst_expr(&1, env))}
  end

  @doc """
  Flattens a predicate into a list of conjuncts.

  Nested `:and` nodes are flattened; `:true` is dropped.
  """
  @spec conjuncts(t()) :: [t()]
  def conjuncts(true), do: []
  def conjuncts({:and, p, q}), do: conjuncts(p) ++ conjuncts(q)
  def conjuncts(pred), do: [pred]

  @doc """
  Builds a conjunction from a list of predicates.
  """
  @spec conjunction([t()]) :: t()
  def conjunction([]), do: true
  def conjunction([p]), do: p
  def conjunction([p | rest]), do: {:and, p, conjunction(rest)}

  # Extracts the variable name from a substitution, handling the case where
  # the substitution maps to another variable.
  defp subst_var_name(name, env) do
    case Map.get(env, name) do
      {:var, new_name} -> new_name
      nil -> name
      _other -> name
    end
  end
end
