defmodule Constrain.BinarySegment do
  @moduledoc """
  Parses Elixir binary pattern AST segments into structured specifications.

  Each segment in a `<<...>>` pattern is parsed into a 6-tuple:

      {binding, type, size, unit, signedness, endianness}

  - `binding` — `nil` for literals/wildcards, atom for variables
  - `type` — `:integer | :float | :binary | :bitstring | :utf8 | :utf16 | :utf32`
  - `size` — bit count (integer), `:default` for rest-of-binary, or `{:dynamic, atom}` for `size(var)`
  - `unit` — bits per size unit (1 for integer, 8 for binary)
  - `signedness` — `:unsigned | :signed`
  - `endianness` — `:big | :little | :native`
  """

  @type segment_type :: :integer | :float | :binary | :bitstring | :utf8 | :utf16 | :utf32
  @type segment_size :: pos_integer() | {:dynamic, atom()} | :default
  @type signedness :: :unsigned | :signed
  @type endianness :: :big | :little | :native

  @type t ::
          {atom() | nil, segment_type(), segment_size(), pos_integer(), signedness(),
           endianness()}

  @doc """
  Parses a single binary segment AST node into a segment spec.
  """
  @spec parse(Macro.t()) :: t()
  def parse({:"::", _, [expr, spec]}) do
    binding = extract_binding(expr)
    modifiers = parse_modifiers(spec)
    apply_defaults(binding, modifiers)
  end

  # Bare variable with no type spec — defaults to 8-bit unsigned big integer.
  def parse({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    binding = if name == :_, do: nil, else: name
    {binding, :integer, 8, 1, :unsigned, :big}
  end

  # Literal integer with no type spec.
  def parse(n) when is_integer(n) do
    {nil, :integer, 8, 1, :unsigned, :big}
  end

  # Literal string embedded in binary.
  def parse(s) when is_binary(s) do
    {nil, :binary, byte_size(s) * 8, 8, :unsigned, :big}
  end

  # Extracts a variable binding from the left side of `::`.
  defp extract_binding({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    if name == :_, do: nil, else: name
  end

  defp extract_binding(_), do: nil

  # Parses the modifier chain on the right side of `::`.
  # Returns a keyword list of recognized modifiers.
  defp parse_modifiers(spec) do
    spec
    |> flatten_modifiers()
    |> Enum.reduce(%{}, &collect_modifier/2)
  end

  # Flattens the `{:-, _, [left, right]}` chain into a list of individual modifiers.
  defp flatten_modifiers({:-, _, [left, right]}) do
    flatten_modifiers(left) ++ flatten_modifiers(right)
  end

  # AST variable-like tuples representing modifier keywords (e.g., `{:binary, [], Elixir}`).
  @modifier_atoms ~w(integer float binary bitstring bits bytes utf8 utf16 utf32
                     signed unsigned big little native)a

  defp flatten_modifiers({name, _, ctx}) when name in @modifier_atoms and is_atom(ctx) do
    [name]
  end

  defp flatten_modifiers(other), do: [other]

  # Collects a single modifier into the accumulator map.
  defp collect_modifier(:integer, acc), do: Map.put(acc, :type, :integer)
  defp collect_modifier(:float, acc), do: Map.put(acc, :type, :float)
  defp collect_modifier(:binary, acc), do: Map.put(acc, :type, :binary)
  defp collect_modifier(:bitstring, acc), do: Map.put(acc, :type, :bitstring)
  defp collect_modifier(:bits, acc), do: Map.put(acc, :type, :bitstring)
  defp collect_modifier(:bytes, acc), do: Map.put(acc, :type, :binary)
  defp collect_modifier(:utf8, acc), do: Map.put(acc, :type, :utf8)
  defp collect_modifier(:utf16, acc), do: Map.put(acc, :type, :utf16)
  defp collect_modifier(:utf32, acc), do: Map.put(acc, :type, :utf32)
  defp collect_modifier(:signed, acc), do: Map.put(acc, :signedness, :signed)
  defp collect_modifier(:unsigned, acc), do: Map.put(acc, :signedness, :unsigned)
  defp collect_modifier(:big, acc), do: Map.put(acc, :type_endianness, :big)
  defp collect_modifier(:little, acc), do: Map.put(acc, :type_endianness, :little)
  defp collect_modifier(:native, acc), do: Map.put(acc, :type_endianness, :native)

  # size(n) where n is a literal integer.
  defp collect_modifier({:size, _, [n]}, acc) when is_integer(n) do
    Map.put(acc, :size, n)
  end

  # size(var) where var is a variable reference.
  defp collect_modifier({:size, _, [{name, _, ctx}]}, acc)
       when is_atom(name) and is_atom(ctx) do
    Map.put(acc, :size, {:dynamic, name})
  end

  # unit(n).
  defp collect_modifier({:unit, _, [n]}, acc) when is_integer(n) do
    Map.put(acc, :unit, n)
  end

  # Bare integer literal used as size shorthand (e.g., `x::16`).
  defp collect_modifier(n, acc) when is_integer(n) do
    Map.put(acc, :size, n)
  end

  # Applies Elixir's defaults based on the segment type.
  defp apply_defaults(binding, modifiers) do
    type = Map.get(modifiers, :type, :integer)
    signedness = Map.get(modifiers, :signedness, :unsigned)
    endianness = Map.get(modifiers, :type_endianness, :big)

    {default_size, default_unit} = type_defaults(type)

    size = Map.get(modifiers, :size, default_size)
    unit = Map.get(modifiers, :unit, default_unit)

    # Compute total bit size for integer literals given as shorthand.
    total_size = compute_total_size(size, unit, default_unit)

    {binding, type, total_size, unit, signedness, endianness}
  end

  # Returns {default_size, default_unit} for each segment type.
  defp type_defaults(:integer), do: {8, 1}
  defp type_defaults(:float), do: {64, 1}
  defp type_defaults(:binary), do: {:default, 8}
  defp type_defaults(:bitstring), do: {:default, 1}
  defp type_defaults(:utf8), do: {:default, 1}
  defp type_defaults(:utf16), do: {:default, 1}
  defp type_defaults(:utf32), do: {:default, 1}

  # When size is explicitly given, keep it as-is.  When :default, keep :default.
  # Dynamic sizes pass through unchanged.
  defp compute_total_size(:default, _unit, _default_unit), do: :default
  defp compute_total_size({:dynamic, _} = dyn, _unit, _default_unit), do: dyn
  defp compute_total_size(size, _unit, _default_unit) when is_integer(size), do: size
end
