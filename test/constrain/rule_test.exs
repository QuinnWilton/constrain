defmodule Constrain.RuleTest do
  use ExUnit.Case, async: true

  alias Constrain.Rule

  describe "match_premise/3" do
    test "matches type check with same tag" do
      premise = {:is_type, :integer, {:var, :x}}
      fact = {:is_type, :integer, {:var, :y}}
      assert {:ok, %{x: {:var, :y}}} = Rule.match_premise(premise, fact)
    end

    test "does not match type check with different tag" do
      premise = {:is_type, :integer, {:var, :x}}
      fact = {:is_type, :float, {:var, :y}}
      assert :no_match = Rule.match_premise(premise, fact)
    end

    test "matches type check with variable tag" do
      premise = {:is_type, {:var, :t}, {:var, :x}}
      fact = {:is_type, :integer, {:var, :y}}
      assert {:ok, bindings} = Rule.match_premise(premise, fact)
      assert bindings[:t] == :integer
      assert bindings[:x] == {:var, :y}
    end

    test "variable tag must be consistent" do
      premise = {:is_type, {:var, :t}, {:var, :x}}
      fact = {:is_type, :integer, {:var, :y}}
      # Pre-bind t to :float — should not match.
      assert :no_match = Rule.match_premise(premise, fact, %{t: :float})
    end

    test "matches comparison operators" do
      premise = {:gt, {:var, :x}, {:var, :y}}
      fact = {:gt, {:var, :a}, {:lit, 5}}
      assert {:ok, %{x: {:var, :a}, y: {:lit, 5}}} = Rule.match_premise(premise, fact)
    end

    test "does not match different comparison operators" do
      premise = {:gt, {:var, :x}, {:var, :y}}
      fact = {:lt, {:var, :a}, {:lit, 5}}
      assert :no_match = Rule.match_premise(premise, fact)
    end

    test "consistent variable binding across premises" do
      p1 = {:gt, {:var, :x}, {:var, :y}}
      f1 = {:gt, {:var, :a}, {:var, :b}}
      {:ok, bindings} = Rule.match_premise(p1, f1)

      p2 = {:gt, {:var, :y}, {:var, :z}}
      f2 = {:gt, {:var, :b}, {:var, :c}}
      assert {:ok, bindings} = Rule.match_premise(p2, f2, bindings)
      assert bindings[:x] == {:var, :a}
      assert bindings[:y] == {:var, :b}
      assert bindings[:z] == {:var, :c}
    end

    test "inconsistent variable binding fails" do
      p1 = {:gt, {:var, :x}, {:var, :y}}
      f1 = {:gt, {:var, :a}, {:var, :b}}
      {:ok, bindings} = Rule.match_premise(p1, f1)

      # Try to bind x to something different.
      p2 = {:gt, {:var, :x}, {:var, :z}}
      f2 = {:gt, {:var, :c}, {:var, :d}}
      assert :no_match = Rule.match_premise(p2, f2, bindings)
    end

    test "matches literal expressions" do
      premise = {:eq, {:var, :x}, {:lit, 42}}
      fact = {:eq, {:var, :y}, {:lit, 42}}
      assert {:ok, %{x: {:var, :y}}} = Rule.match_premise(premise, fact)
    end

    test "literal mismatch fails" do
      premise = {:eq, {:var, :x}, {:lit, 42}}
      fact = {:eq, {:var, :y}, {:lit, 43}}
      assert :no_match = Rule.match_premise(premise, fact)
    end

    test "matches bound predicate" do
      premise = {:bound, :x}
      fact = {:bound, :my_var}
      assert {:ok, %{x: :my_var}} = Rule.match_premise(premise, fact)
    end

    test "matches truth values" do
      assert {:ok, %{}} = Rule.match_premise(true, true)
      assert {:ok, %{}} = Rule.match_premise(false, false)
      assert :no_match = Rule.match_premise(true, false)
    end

    test "matches operations" do
      premise = {:gt, {:op, :abs, [{:var, :x}]}, {:lit, 0}}
      fact = {:gt, {:op, :abs, [{:var, :y}]}, {:lit, 0}}
      assert {:ok, %{x: {:var, :y}}} = Rule.match_premise(premise, fact)
    end

    test "matches shape predicates" do
      premise = {:has_shape, {:var, :x}, {:tuple, 2}}
      fact = {:has_shape, {:var, :result}, {:tuple, 2}}
      assert {:ok, %{x: {:var, :result}}} = Rule.match_premise(premise, fact)
    end

    test "shape mismatch fails" do
      premise = {:has_shape, {:var, :x}, {:tuple, 2}}
      fact = {:has_shape, {:var, :result}, {:tuple, 3}}
      assert :no_match = Rule.match_premise(premise, fact)
    end
  end

  describe "instantiate/2" do
    test "instantiates variables in comparison" do
      pred = {:gt, {:var, :x}, {:var, :y}}
      bindings = %{x: :a, y: :b}
      assert Rule.instantiate(pred, bindings) == {:gt, {:var, :a}, {:var, :b}}
    end

    test "instantiates variables in type check" do
      pred = {:is_type, :integer, {:var, :x}}
      bindings = %{x: :my_var}
      assert Rule.instantiate(pred, bindings) == {:is_type, :integer, {:var, :my_var}}
    end

    test "instantiates variable type tag" do
      pred = {:is_type, {:var, :t}, {:var, :x}}
      bindings = %{t: :integer, x: :my_var}
      assert Rule.instantiate(pred, bindings) == {:is_type, :integer, {:var, :my_var}}
    end

    test "leaves unbound variables" do
      pred = {:gt, {:var, :x}, {:var, :y}}
      bindings = %{x: :a}
      assert Rule.instantiate(pred, bindings) == {:gt, {:var, :a}, {:var, :y}}
    end

    test "instantiates truth values" do
      assert Rule.instantiate(true, %{}) == true
      assert Rule.instantiate(false, %{}) == false
    end

    test "instantiates with expression values" do
      pred = {:gt, {:var, :x}, {:var, :y}}
      bindings = %{x: {:lit, 10}, y: {:lit, 5}}
      assert Rule.instantiate(pred, bindings) == {:gt, {:lit, 10}, {:lit, 5}}
    end

    test "instantiates bound predicate" do
      pred = {:bound, :x}
      bindings = %{x: :my_var}
      assert Rule.instantiate(pred, bindings) == {:bound, :my_var}
    end

    test "instantiates conjunctions and disjunctions" do
      pred = {:and, {:gt, {:var, :x}, {:lit, 0}}, {:lt, {:var, :x}, {:lit, 10}}}
      bindings = %{x: :y}

      assert Rule.instantiate(pred, bindings) ==
               {:and, {:gt, {:var, :y}, {:lit, 0}}, {:lt, {:var, :y}, {:lit, 10}}}
    end

    test "instantiates negation" do
      pred = {:not, {:is_type, :integer, {:var, :x}}}
      bindings = %{x: :y}
      assert Rule.instantiate(pred, bindings) == {:not, {:is_type, :integer, {:var, :y}}}
    end
  end
end
