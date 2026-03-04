defmodule Constrain.Guard do
  @moduledoc """
  Converts Elixir guard AST into predicate constraints.

  Takes the quoted form of an Elixir guard expression and produces a list
  of predicates encoding its semantics. Supports the standard guard-allowed
  functions and operators.

  ## Example

      iex> ast = quote do: is_integer(x) and x > 0
      iex> Constrain.Guard.from_guard(ast)
      [{:is_type, :integer, {:var, :x}}, {:gt, {:var, :x}, {:lit, 0}}]
  """

  alias Constrain.Predicate

  @type_guards %{
    is_integer: :integer,
    is_float: :float,
    is_number: :number,
    is_atom: :atom,
    is_boolean: :boolean,
    is_binary: :binary,
    is_bitstring: :bitstring,
    is_list: :list,
    is_tuple: :tuple,
    is_map: :map,
    is_pid: :pid,
    is_port: :port,
    is_reference: :reference,
    is_function: :function,
    is_nil: nil
  }

  @comparison_ops %{
    ==: :eq,
    !=: :neq,
    ===: :strict_eq,
    !==: :strict_neq,
    <: :lt,
    >: :gt,
    <=: :lte,
    >=: :gte
  }

  @arithmetic_ops %{
    +: :add,
    -: :sub,
    *: :mul,
    div: :div,
    rem: :rem
  }

  @unary_ops %{
    abs: :abs,
    ceil: :ceil,
    floor: :floor,
    round: :round,
    trunc: :trunc
  }

  @bitwise_ops %{
    band: :band,
    bor: :bor,
    bxor: :bxor,
    bnot: :bnot,
    bsl: :bsl,
    bsr: :bsr
  }

  @doc """
  Converts a guard AST to a list of conjunctive predicates.

  Conjunctions (`:and`) are flattened; disjunctions and negations are preserved
  in the predicate structure.
  """
  @spec from_guard(Macro.t()) :: [Predicate.t()]
  def from_guard(ast) do
    ast
    |> convert()
    |> Predicate.conjuncts()
  end

  @doc """
  Converts a guard AST to a single predicate (may be a conjunction/disjunction).
  """
  @spec convert(Macro.t()) :: Predicate.t()

  # Boolean connectives.
  def convert({:and, _, [left, right]}) do
    {:and, convert(left), convert(right)}
  end

  def convert({:or, _, [left, right]}) do
    {:or, convert(left), convert(right)}
  end

  def convert({:not, _, [arg]}) do
    Predicate.negate(convert(arg))
  end

  # Type guard functions.
  def convert({guard_fn, _, [arg]}) when is_map_key(@type_guards, guard_fn) do
    {:is_type, Map.fetch!(@type_guards, guard_fn), convert_expr(arg)}
  end

  # is_struct/2 — struct type check.
  def convert({:is_struct, _, [arg, module]}) when is_atom(module) do
    {:and, {:is_type, :struct, convert_expr(arg)},
     {:has_shape, convert_expr(arg), {:struct, module}}}
  end

  # is_function/2 — function with arity check.
  def convert({:is_function, _, [arg, arity]}) when is_integer(arity) do
    {:and, {:is_type, :function, convert_expr(arg)},
     {:has_shape, convert_expr(arg), {:function, arity}}}
  end

  # Comparison operators.
  def convert({op, _, [left, right]}) when is_map_key(@comparison_ops, op) do
    {Map.fetch!(@comparison_ops, op), convert_expr(left), convert_expr(right)}
  end

  # `in` operator (membership in a literal list).
  def convert({:in, _, [expr, list]}) when is_list(list) do
    {:in, convert_expr(expr), list}
  end

  # `when` — treat as conjunction (common in multi-clause guards).
  def convert({:when, _, [left, right]}) do
    {:and, convert(left), convert(right)}
  end

  # Bare variable used as boolean guard (e.g., `when flag`).
  def convert({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    {:eq, {:var, name}, {:lit, true}}
  end

  # Literal true/false.
  def convert(true), do: true
  def convert(false), do: false

  # Fall through for unrecognized forms.
  def convert(other) do
    raise ArgumentError, "unsupported guard expression: #{Macro.to_string(other)}"
  end

  @doc """
  Converts a guard expression (not a predicate) to a predicate expression.
  """
  @spec convert_expr(Macro.t()) :: Predicate.expr()

  # Variable reference.
  def convert_expr({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    {:var, name}
  end

  # Literal values.
  def convert_expr(n) when is_number(n), do: {:lit, n}
  def convert_expr(a) when is_atom(a), do: {:lit, a}
  def convert_expr(s) when is_binary(s), do: {:lit, s}

  # Arithmetic operations.
  def convert_expr({op, _, [left, right]}) when is_map_key(@arithmetic_ops, op) do
    {:op, Map.fetch!(@arithmetic_ops, op), [convert_expr(left), convert_expr(right)]}
  end

  # Unary arithmetic operations.
  def convert_expr({op, _, [arg]}) when is_map_key(@unary_ops, op) do
    {:op, Map.fetch!(@unary_ops, op), [convert_expr(arg)]}
  end

  # Unary minus.
  def convert_expr({:-, _, [arg]}) do
    {:op, :sub, [{:lit, 0}, convert_expr(arg)]}
  end

  # Bitwise operations.
  def convert_expr({op, _, args}) when is_map_key(@bitwise_ops, op) do
    {:op, Map.fetch!(@bitwise_ops, op), Enum.map(args, &convert_expr/1)}
  end

  # elem/2.
  def convert_expr({:elem, _, [tuple, index]}) do
    {:op, :elem, [convert_expr(tuple), convert_expr(index)]}
  end

  # hd/1, tl/1.
  def convert_expr({:hd, _, [list]}), do: {:op, :hd, [convert_expr(list)]}
  def convert_expr({:tl, _, [list]}), do: {:op, :tl, [convert_expr(list)]}

  # length/1.
  def convert_expr({:length, _, [list]}), do: {:op, :length, [convert_expr(list)]}

  # tuple_size/1.
  def convert_expr({:tuple_size, _, [t]}), do: {:op, :tuple_size, [convert_expr(t)]}

  # map_size/1.
  def convert_expr({:map_size, _, [m]}), do: {:op, :map_size, [convert_expr(m)]}

  # byte_size/1, bit_size/1.
  def convert_expr({:byte_size, _, [b]}), do: {:op, :byte_size, [convert_expr(b)]}
  def convert_expr({:bit_size, _, [b]}), do: {:op, :bit_size, [convert_expr(b)]}

  # node/0, self/0.
  def convert_expr({:node, _, []}), do: {:op, :node, []}
  def convert_expr({:self, _, []}), do: {:op, :self, []}

  # Map field access (dot notation).
  def convert_expr({{:., _, [Access, :get]}, _, [map_expr, key]}) when is_atom(key) do
    {:field, convert_expr(map_expr), key}
  end

  def convert_expr({{:., _, [{name, _, ctx}, field]}, _, []})
      when is_atom(name) and is_atom(ctx) and is_atom(field) do
    {:field, {:var, name}, field}
  end

  def convert_expr(other) do
    raise ArgumentError, "unsupported guard expression: #{inspect(other)}"
  end
end
