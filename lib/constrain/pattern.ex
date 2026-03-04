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

  alias Constrain.BinarySegment
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

  # Binary pattern — decompose segments into type, bound, and range constraints.
  defp convert({:<<>>, _, parts}, expr) do
    segments = Enum.map(parts, &BinarySegment.parse/1)
    binary_segment_predicates(expr, segments)
  end

  # Produces predicates for a binary pattern from parsed segments.
  defp binary_segment_predicates(expr, segments) do
    type_pred = binary_type_predicate(expr, segments)
    structural = {:has_binary_segments, expr, segments}
    size_preds = binary_size_predicates(expr, segments)
    var_preds = Enum.flat_map(segments, &segment_variable_predicates/1)

    [type_pred, structural | size_preds ++ var_preds]
  end

  # If all segments are byte-aligned, the value is a binary; otherwise bitstring.
  defp binary_type_predicate(expr, segments) do
    byte_aligned? =
      Enum.all?(segments, fn {_binding, type, size, unit, _sign, _end} ->
        case type do
          t when t in [:binary, :utf8, :utf16, :utf32] -> true
          :bitstring -> size == :default and unit == 1
          _ -> is_integer(size) and rem(size * unit, 8) == 0
        end
      end)

    if byte_aligned? do
      {:is_type, :binary, expr}
    else
      {:is_type, :bitstring, expr}
    end
  end

  # Compute size constraints from the segments.
  defp binary_size_predicates(expr, segments) do
    {static_bits, all_static?} =
      Enum.reduce(segments, {0, true}, fn {_binding, _type, size, unit, _sign, _end},
                                          {total, static?} ->
        case size do
          :default -> {total, false}
          {:dynamic, _} -> {total, false}
          n when is_integer(n) -> {total + n * unit, static?}
        end
      end)

    cond do
      # All segments have known sizes — exact byte_size constraint.
      all_static? and rem(static_bits, 8) == 0 ->
        [{:eq, {:op, :byte_size, [expr]}, {:lit, div(static_bits, 8)}}]

      # Some segments are dynamic but we have a static lower bound.
      static_bits > 0 and rem(static_bits, 8) == 0 ->
        [{:gte, {:op, :byte_size, [expr]}, {:lit, div(static_bits, 8)}}]

      true ->
        []
    end
  end

  # Produces predicates for a single segment's bound variable.
  defp segment_variable_predicates({nil, _type, _size, _unit, _sign, _end}), do: []

  defp segment_variable_predicates({name, type, size, unit, signedness, _endianness}) do
    bound = [{:bound, name}]
    type_preds = segment_type_predicates(name, type)
    range_preds = segment_range_predicates(name, type, size, unit, signedness)
    bound ++ type_preds ++ range_preds
  end

  # Type predicates for the variable bound by a segment.
  defp segment_type_predicates(name, type) when type in [:integer, :float] do
    [{:is_type, type, {:var, name}}]
  end

  defp segment_type_predicates(name, type) when type in [:binary, :bitstring] do
    [{:is_type, type, {:var, name}}]
  end

  defp segment_type_predicates(name, type) when type in [:utf8, :utf16, :utf32] do
    [{:is_type, :integer, {:var, name}}]
  end

  # Range predicates for integer segments based on bit width and signedness.
  defp segment_range_predicates(name, :integer, size, unit, signedness) when is_integer(size) do
    bits = size * unit
    integer_bounds(name, bits, signedness)
  end

  defp segment_range_predicates(name, type, _size, _unit, _signedness)
       when type in [:utf8, :utf16, :utf32] do
    # Unicode codepoints are non-negative integers up to U+10FFFF.
    [{:gte, {:var, name}, {:lit, 0}}, {:lte, {:var, name}, {:lit, 0x10FFFF}}]
  end

  defp segment_range_predicates(_name, _type, _size, _unit, _signedness), do: []

  # Computes the min/max bounds for an integer of a given bit width.
  defp integer_bounds(name, bits, :unsigned) do
    max = Bitwise.bsl(1, bits) - 1
    [{:gte, {:var, name}, {:lit, 0}}, {:lte, {:var, name}, {:lit, max}}]
  end

  defp integer_bounds(name, bits, :signed) do
    max = Bitwise.bsl(1, bits - 1) - 1
    min = -Bitwise.bsl(1, bits - 1)
    [{:gte, {:var, name}, {:lit, min}}, {:lte, {:var, name}, {:lit, max}}]
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
