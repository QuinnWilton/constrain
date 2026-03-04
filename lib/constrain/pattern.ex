defmodule Constrain.Pattern do
  @moduledoc """
  Converts Elixir pattern match AST into predicate constraints.

  Takes the quoted form of an Elixir pattern and produces predicates encoding
  the structural and type constraints implied by the match. The `context`
  parameter names the root value being matched against.

  ## Example

      iex> ast = quote do: {:ok, x}
      iex> Constrain.Pattern.from_pattern(ast, :result)
      [{:has_shape, {:var, :result}, {:tuple, 2}},
       {:eq, {:op, :elem, [{:var, :result}, {:lit, 0}]}, {:lit, :ok}},
       {:bound, :x}]
  """

  alias Constrain.Predicate

  @doc """
  Converts a pattern AST to a list of predicates.

  `context` is the expression representing the value being matched.
  For top-level patterns, this is typically `{:var, name}`.
  """
  @spec from_pattern(Macro.t(), atom() | Predicate.expr()) :: [Predicate.t()]
  def from_pattern(ast, context) when is_atom(context) do
    from_pattern(ast, {:var, context})
  end

  def from_pattern(ast, context) do
    convert(ast, context)
  end

  # Variable binding — the variable is bound and equal to the context.
  defp convert({name, _, ctx}, expr) when is_atom(name) and is_atom(ctx) do
    if name == :_ do
      # Underscore: no constraints.
      []
    else
      [{:bound, name}, {:eq, {:var, name}, expr}]
    end
  end

  # Pin operator — equality constraint with existing variable.
  defp convert({:^, _, [{name, _, ctx}]}, expr) when is_atom(name) and is_atom(ctx) do
    [{:eq, {:var, name}, expr}]
  end

  # Literal values.
  defp convert(n, expr) when is_number(n) do
    [{:eq, expr, {:lit, n}}]
  end

  defp convert(a, expr) when is_atom(a) do
    [{:eq, expr, {:lit, a}}]
  end

  defp convert(s, expr) when is_binary(s) do
    [{:is_type, :binary, expr}, {:eq, expr, {:lit, s}}]
  end

  # Tuple pattern — generates shape constraint and element constraints.
  defp convert({:{}, _, elements}, expr) do
    shape = {:has_shape, expr, {:tuple, length(elements)}}

    element_preds =
      elements
      |> Enum.with_index()
      |> Enum.flat_map(fn {elem_ast, i} ->
        elem_expr = {:op, :elem, [expr, {:lit, i}]}
        convert(elem_ast, elem_expr)
      end)

    [shape | element_preds]
  end

  # Two-element tuple (Elixir optimizes 2-tuples in AST).
  defp convert({a, b}, expr) do
    convert({:{}, [], [a, b]}, expr)
  end

  # List pattern.
  defp convert([], expr) do
    [{:is_type, :list, expr}, {:eq, expr, {:lit, []}}]
  end

  defp convert([{:|, _, [head, tail]}], expr) do
    head_preds = convert(head, {:op, :hd, [expr]})
    tail_preds = convert(tail, {:op, :tl, [expr]})
    [{:is_type, :list, expr} | head_preds ++ tail_preds]
  end

  defp convert(elements, expr) when is_list(elements) do
    length_pred = {:eq, {:op, :length, [expr]}, {:lit, length(elements)}}

    element_preds =
      elements
      |> Enum.with_index()
      |> Enum.flat_map(fn {elem_ast, i} ->
        # For lists, we express element access as nested hd/tl.
        elem_expr = list_element_expr(expr, i)
        convert(elem_ast, elem_expr)
      end)

    [{:is_type, :list, expr}, length_pred | element_preds]
  end

  # Map pattern — generates shape constraint and key constraints.
  defp convert({:%{}, _, pairs}, expr) do
    keys = Enum.map(pairs, fn {k, _v} -> key_to_atom(k) end)
    shape = {:has_shape, expr, {:map, Enum.sort(keys)}}

    pair_preds =
      Enum.flat_map(pairs, fn {k, v} ->
        key = key_to_atom(k)
        convert(v, {:field, expr, key})
      end)

    [shape | pair_preds]
  end

  # Struct pattern.
  defp convert({:%, _, [module, {:%{}, _, pairs}]}, expr) when is_atom(module) do
    struct_shape = {:has_shape, expr, {:struct, module}}

    pair_preds =
      Enum.flat_map(pairs, fn {k, v} ->
        key = key_to_atom(k)
        convert(v, {:field, expr, key})
      end)

    [{:is_type, :struct, expr}, struct_shape | pair_preds]
  end

  # `when` guard attached to pattern — handled by combining pattern + guard.
  defp convert({:when, _, [pattern, guard]}, expr) do
    pattern_preds = convert(pattern, expr)
    guard_preds = Constrain.Guard.from_guard(guard)
    pattern_preds ++ guard_preds
  end

  # String concatenation pattern (binary pattern `<<prefix::binary, rest::binary>>`).
  # Not fully supported — just assert it's a binary.
  defp convert({:<<>>, _, _parts}, expr) do
    [{:is_type, :binary, expr}]
  end

  # Builds an expression for the i-th element of a list using nested hd/tl.
  defp list_element_expr(list_expr, 0), do: {:op, :hd, [list_expr]}

  defp list_element_expr(list_expr, i) when i > 0 do
    {:op, :hd, [{:op, :tl, [list_element_expr_tail(list_expr, i)]}]}
  end

  defp list_element_expr_tail(list_expr, 1), do: list_expr

  defp list_element_expr_tail(list_expr, i),
    do: {:op, :tl, [list_element_expr_tail(list_expr, i - 1)]}

  defp key_to_atom(k) when is_atom(k), do: k
  defp key_to_atom({:__aliases__, _, parts}), do: Module.concat(parts)
end
