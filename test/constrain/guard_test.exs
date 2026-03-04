defmodule Constrain.GuardTest do
  use ExUnit.Case, async: true

  alias Constrain.Guard

  describe "from_guard/1" do
    test "type guard" do
      ast = quote do: is_integer(x)
      assert Guard.from_guard(ast) == [{:is_type, :integer, {:var, :x}}]
    end

    test "is_nil guard" do
      ast = quote do: is_nil(x)
      assert Guard.from_guard(ast) == [{:is_type, nil, {:var, :x}}]
    end

    test "comparison" do
      ast = quote do: x > 0
      assert Guard.from_guard(ast) == [{:gt, {:var, :x}, {:lit, 0}}]
    end

    test "equality" do
      ast = quote do: x == :ok
      assert Guard.from_guard(ast) == [{:eq, {:var, :x}, {:lit, :ok}}]
    end

    test "strict equality" do
      ast = quote do: x === 1.0
      assert Guard.from_guard(ast) == [{:strict_eq, {:var, :x}, {:lit, 1.0}}]
    end

    test "conjunction flattens" do
      ast = quote do: is_integer(x) and x > 0
      preds = Guard.from_guard(ast)
      assert {:is_type, :integer, {:var, :x}} in preds
      assert {:gt, {:var, :x}, {:lit, 0}} in preds
      assert length(preds) == 2
    end

    test "disjunction preserved" do
      ast = quote do: is_integer(x) or is_float(x)
      preds = Guard.from_guard(ast)
      assert preds == [{:or, {:is_type, :integer, {:var, :x}}, {:is_type, :float, {:var, :x}}}]
    end

    test "negation" do
      ast = quote do: not is_nil(x)
      preds = Guard.from_guard(ast)
      assert preds == [{:not, {:is_type, nil, {:var, :x}}}]
    end

    test "complex guard" do
      ast = quote do: is_integer(x) and x > 0 and x < 100
      preds = Guard.from_guard(ast)
      assert {:is_type, :integer, {:var, :x}} in preds
      assert {:gt, {:var, :x}, {:lit, 0}} in preds
      assert {:lt, {:var, :x}, {:lit, 100}} in preds
    end

    test "membership" do
      ast = quote do: x in [:a, :b, :c]
      preds = Guard.from_guard(ast)
      assert preds == [{:in, {:var, :x}, [:a, :b, :c]}]
    end

    test "arithmetic in comparison" do
      ast = quote do: x + 1 > 5
      preds = Guard.from_guard(ast)
      assert preds == [{:gt, {:op, :add, [{:var, :x}, {:lit, 1}]}, {:lit, 5}}]
    end

    test "unary function" do
      ast = quote do: abs(x) > 0
      preds = Guard.from_guard(ast)
      assert preds == [{:gt, {:op, :abs, [{:var, :x}]}, {:lit, 0}}]
    end

    test "elem in guard" do
      ast = quote do: elem(t, 0) == :ok
      preds = Guard.from_guard(ast)
      assert preds == [{:eq, {:op, :elem, [{:var, :t}, {:lit, 0}]}, {:lit, :ok}}]
    end

    test "tuple_size" do
      ast = quote do: tuple_size(t) == 2
      preds = Guard.from_guard(ast)
      assert preds == [{:eq, {:op, :tuple_size, [{:var, :t}]}, {:lit, 2}}]
    end

    test "length" do
      ast = quote do: length(l) > 0
      preds = Guard.from_guard(ast)
      assert preds == [{:gt, {:op, :length, [{:var, :l}]}, {:lit, 0}}]
    end

    test "map_size" do
      ast = quote do: map_size(m) > 0
      preds = Guard.from_guard(ast)
      assert preds == [{:gt, {:op, :map_size, [{:var, :m}]}, {:lit, 0}}]
    end

    test "true literal" do
      ast = quote do: true
      assert Guard.from_guard(ast) == []
    end

    test "false literal" do
      ast = quote do: false
      assert Guard.from_guard(ast) == [false]
    end

    test "multiple comparison operators" do
      ast = quote do: x >= 0 and x <= 100
      preds = Guard.from_guard(ast)
      assert {:gte, {:var, :x}, {:lit, 0}} in preds
      assert {:lte, {:var, :x}, {:lit, 100}} in preds
    end

    test "inequality" do
      ast = quote do: x != nil
      preds = Guard.from_guard(ast)
      assert preds == [{:neq, {:var, :x}, {:lit, nil}}]
    end
  end

  describe "convert_expr/1" do
    test "variable" do
      assert Guard.convert_expr(quote(do: x)) == {:var, :x}
    end

    test "integer literal" do
      assert Guard.convert_expr(42) == {:lit, 42}
    end

    test "float literal" do
      assert Guard.convert_expr(3.14) == {:lit, 3.14}
    end

    test "atom literal" do
      assert Guard.convert_expr(:ok) == {:lit, :ok}
    end

    test "string literal" do
      assert Guard.convert_expr("hello") == {:lit, "hello"}
    end

    test "arithmetic" do
      expr = quote do: x + y
      assert Guard.convert_expr(expr) == {:op, :add, [{:var, :x}, {:var, :y}]}
    end

    test "nested arithmetic" do
      expr = quote do: x * 2 + 1
      result = Guard.convert_expr(expr)
      assert result == {:op, :add, [{:op, :mul, [{:var, :x}, {:lit, 2}]}, {:lit, 1}]}
    end

    test "division" do
      expr = quote do: div(x, 2)
      assert Guard.convert_expr(expr) == {:op, :div, [{:var, :x}, {:lit, 2}]}
    end

    test "remainder" do
      expr = quote do: rem(x, 3)
      assert Guard.convert_expr(expr) == {:op, :rem, [{:var, :x}, {:lit, 3}]}
    end
  end
end
