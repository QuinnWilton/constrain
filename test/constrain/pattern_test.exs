defmodule Constrain.PatternTest do
  use ExUnit.Case, async: true

  alias Constrain.Pattern

  describe "from_pattern/2" do
    test "variable binding" do
      ast = quote do: x
      preds = Pattern.from_pattern(ast, :input)
      assert {:bound, :x} in preds
      assert {:eq, {:var, :x}, {:var, :input}} in preds
    end

    test "underscore produces no constraints" do
      ast = quote do: _
      assert Pattern.from_pattern(ast, :input) == []
    end

    test "integer literal" do
      preds = Pattern.from_pattern(42, :input)
      assert preds == [{:eq, {:var, :input}, {:lit, 42}}]
    end

    test "atom literal" do
      preds = Pattern.from_pattern(:ok, :input)
      assert preds == [{:eq, {:var, :input}, {:lit, :ok}}]
    end

    test "two-element tuple" do
      ast = quote do: {:ok, x}
      preds = Pattern.from_pattern(ast, :result)

      assert {:has_shape, {:var, :result}, {:tuple, 2}} in preds

      assert {:eq, {:op, :elem, [{:var, :result}, {:lit, 0}]}, {:lit, :ok}} in preds
      assert {:bound, :x} in preds
      assert {:eq, {:var, :x}, {:op, :elem, [{:var, :result}, {:lit, 1}]}} in preds
    end

    test "three-element tuple" do
      ast = quote do: {a, b, c}
      preds = Pattern.from_pattern(ast, :t)
      assert {:has_shape, {:var, :t}, {:tuple, 3}} in preds
      assert {:bound, :a} in preds
      assert {:bound, :b} in preds
      assert {:bound, :c} in preds
    end

    test "nested tuple" do
      ast = quote do: {:ok, {x, y}}
      preds = Pattern.from_pattern(ast, :result)
      assert {:has_shape, {:var, :result}, {:tuple, 2}} in preds

      inner_expr = {:op, :elem, [{:var, :result}, {:lit, 1}]}
      assert {:has_shape, inner_expr, {:tuple, 2}} in preds
    end

    test "pinned variable" do
      ast = quote do: ^expected
      preds = Pattern.from_pattern(ast, :input)
      assert preds == [{:eq, {:var, :expected}, {:var, :input}}]
    end

    test "empty list" do
      preds = Pattern.from_pattern([], :input)
      assert {:is_type, :list, {:var, :input}} in preds
      assert {:eq, {:var, :input}, {:lit, []}} in preds
    end

    test "list pattern" do
      ast = quote do: [a, b]
      preds = Pattern.from_pattern(ast, :input)
      assert {:is_type, :list, {:var, :input}} in preds
      assert {:eq, {:op, :length, [{:var, :input}]}, {:lit, 2}} in preds
      assert {:bound, :a} in preds
      assert {:bound, :b} in preds
    end

    test "cons pattern [head | tail]" do
      ast = quote do: [h | t]
      preds = Pattern.from_pattern(ast, :input)
      assert {:is_type, :list, {:var, :input}} in preds
      assert {:bound, :h} in preds
      assert {:bound, :t} in preds
    end

    test "map pattern" do
      ast = quote do: %{status: s}
      preds = Pattern.from_pattern(ast, :input)
      assert {:has_shape, {:var, :input}, {:map, [:status]}} in preds
      assert {:bound, :s} in preds
    end

    test "map with multiple keys" do
      ast = quote do: %{a: x, b: y}
      preds = Pattern.from_pattern(ast, :m)
      assert {:has_shape, {:var, :m}, {:map, [:a, :b]}} in preds
      assert {:bound, :x} in preds
      assert {:bound, :y} in preds
    end

    test "string literal" do
      preds = Pattern.from_pattern("hello", :input)
      assert {:is_type, :binary, {:var, :input}} in preds
      assert {:eq, {:var, :input}, {:lit, "hello"}} in preds
    end

    test "accepts atom context" do
      preds = Pattern.from_pattern(42, :x)
      assert preds == [{:eq, {:var, :x}, {:lit, 42}}]
    end

    test "accepts expression context" do
      preds = Pattern.from_pattern(42, {:op, :elem, [{:var, :t}, {:lit, 0}]})
      assert preds == [{:eq, {:op, :elem, [{:var, :t}, {:lit, 0}]}, {:lit, 42}}]
    end
  end

  describe "binary patterns" do
    test "empty binary <<>>" do
      ast = quote do: <<>>
      preds = Pattern.from_pattern(ast, :input)
      assert {:is_type, :binary, {:var, :input}} in preds
      assert {:eq, {:op, :byte_size, [{:var, :input}]}, {:lit, 0}} in preds
    end

    test "<<a::8, b::8>> — two 8-bit integers" do
      ast = quote do: <<a::8, b::8>>
      preds = Pattern.from_pattern(ast, :input)

      assert {:is_type, :binary, {:var, :input}} in preds
      assert {:eq, {:op, :byte_size, [{:var, :input}]}, {:lit, 2}} in preds
      assert {:bound, :a} in preds
      assert {:bound, :b} in preds
      assert {:is_type, :integer, {:var, :a}} in preds
      assert {:is_type, :integer, {:var, :b}} in preds
      assert {:gte, {:var, :a}, {:lit, 0}} in preds
      assert {:lte, {:var, :a}, {:lit, 255}} in preds
      assert {:gte, {:var, :b}, {:lit, 0}} in preds
      assert {:lte, {:var, :b}, {:lit, 255}} in preds
    end

    test "<<header::binary-size(4), rest::binary>> — two binary segments" do
      ast = quote do: <<header::binary-size(4), rest::binary>>
      preds = Pattern.from_pattern(ast, :input)

      assert {:is_type, :binary, {:var, :input}} in preds
      assert {:bound, :header} in preds
      assert {:bound, :rest} in preds
      assert {:is_type, :binary, {:var, :header}} in preds
      assert {:is_type, :binary, {:var, :rest}} in preds
      # 4 bytes static from header, rest is dynamic — at least 4 bytes.
      assert {:gte, {:op, :byte_size, [{:var, :input}]}, {:lit, 4}} in preds
    end

    test "<<x::signed-8>> — signed bounds" do
      ast = quote do: <<x::signed-8>>
      preds = Pattern.from_pattern(ast, :input)

      assert {:bound, :x} in preds
      assert {:is_type, :integer, {:var, :x}} in preds
      assert {:gte, {:var, :x}, {:lit, -128}} in preds
      assert {:lte, {:var, :x}, {:lit, 127}} in preds
    end

    test "<<c::utf8>> — unicode codepoint bounds" do
      ast = quote do: <<c::utf8>>
      preds = Pattern.from_pattern(ast, :input)

      assert {:bound, :c} in preds
      assert {:is_type, :integer, {:var, :c}} in preds
      assert {:gte, {:var, :c}, {:lit, 0}} in preds
      assert {:lte, {:var, :c}, {:lit, 0x10FFFF}} in preds
    end

    test "has_binary_segments structural predicate is emitted" do
      ast = quote do: <<x::8>>
      preds = Pattern.from_pattern(ast, :input)

      segments =
        Enum.find_value(preds, fn
          {:has_binary_segments, {:var, :input}, segs} -> segs
          _ -> nil
        end)

      assert segments != nil
      assert [{:x, :integer, 8, 1, :unsigned, :big}] = segments
    end
  end
end
