defmodule Constrain.PredicateTest do
  use ExUnit.Case, async: true

  alias Constrain.Predicate

  describe "free_vars/1" do
    test "returns empty set for truth values" do
      assert Predicate.free_vars(true) == MapSet.new()
      assert Predicate.free_vars(false) == MapSet.new()
    end

    test "extracts variables from comparisons" do
      pred = {:gt, {:var, :x}, {:lit, 5}}
      assert Predicate.free_vars(pred) == MapSet.new([:x])
    end

    test "extracts variables from both sides of comparison" do
      pred = {:eq, {:var, :x}, {:var, :y}}
      assert Predicate.free_vars(pred) == MapSet.new([:x, :y])
    end

    test "extracts variables from type checks" do
      pred = {:is_type, :integer, {:var, :x}}
      assert Predicate.free_vars(pred) == MapSet.new([:x])
    end

    test "extracts variables from bound predicates" do
      assert Predicate.free_vars({:bound, :x}) == MapSet.new([:x])
    end

    test "extracts variables from conjunctions" do
      pred = {:and, {:gt, {:var, :x}, {:lit, 0}}, {:is_type, :integer, {:var, :y}}}
      assert Predicate.free_vars(pred) == MapSet.new([:x, :y])
    end

    test "extracts variables from disjunctions" do
      pred = {:or, {:gt, {:var, :x}, {:lit, 0}}, {:lt, {:var, :y}, {:lit, 10}}}
      assert Predicate.free_vars(pred) == MapSet.new([:x, :y])
    end

    test "extracts variables from negations" do
      pred = {:not, {:is_type, :integer, {:var, :z}}}
      assert Predicate.free_vars(pred) == MapSet.new([:z])
    end

    test "extracts variables from operations" do
      pred = {:gt, {:op, :abs, [{:var, :x}]}, {:lit, 0}}
      assert Predicate.free_vars(pred) == MapSet.new([:x])
    end

    test "extracts variables from has_shape" do
      pred = {:has_shape, {:var, :x}, {:tuple, 2}}
      assert Predicate.free_vars(pred) == MapSet.new([:x])
    end

    test "extracts variables from membership" do
      pred = {:in, {:var, :x}, [:a, :b, :c]}
      assert Predicate.free_vars(pred) == MapSet.new([:x])
    end

    test "literals have no free variables" do
      pred = {:eq, {:lit, 1}, {:lit, 2}}
      assert Predicate.free_vars(pred) == MapSet.new()
    end
  end

  describe "negate/1" do
    test "negates truth values" do
      assert Predicate.negate(true) == false
      assert Predicate.negate(false) == true
    end

    test "double negation eliminates" do
      pred = {:is_type, :integer, {:var, :x}}
      assert Predicate.negate({:not, pred}) == pred
    end

    test "de Morgan's law for conjunction" do
      p = {:gt, {:var, :x}, {:lit, 0}}
      q = {:lt, {:var, :x}, {:lit, 10}}
      assert Predicate.negate({:and, p, q}) == {:or, Predicate.negate(p), Predicate.negate(q)}
    end

    test "de Morgan's law for disjunction" do
      p = {:gt, {:var, :x}, {:lit, 0}}
      q = {:lt, {:var, :x}, {:lit, 10}}
      assert Predicate.negate({:or, p, q}) == {:and, Predicate.negate(p), Predicate.negate(q)}
    end

    test "negates comparisons" do
      assert Predicate.negate({:eq, {:var, :x}, {:lit, 1}}) == {:neq, {:var, :x}, {:lit, 1}}
      assert Predicate.negate({:neq, {:var, :x}, {:lit, 1}}) == {:eq, {:var, :x}, {:lit, 1}}
      assert Predicate.negate({:lt, {:var, :x}, {:lit, 1}}) == {:gte, {:var, :x}, {:lit, 1}}
      assert Predicate.negate({:gte, {:var, :x}, {:lit, 1}}) == {:lt, {:var, :x}, {:lit, 1}}
      assert Predicate.negate({:gt, {:var, :x}, {:lit, 1}}) == {:lte, {:var, :x}, {:lit, 1}}
      assert Predicate.negate({:lte, {:var, :x}, {:lit, 1}}) == {:gt, {:var, :x}, {:lit, 1}}
    end

    test "negates strict equality" do
      assert Predicate.negate({:strict_eq, {:var, :x}, {:lit, 1}}) ==
               {:strict_neq, {:var, :x}, {:lit, 1}}

      assert Predicate.negate({:strict_neq, {:var, :x}, {:lit, 1}}) ==
               {:strict_eq, {:var, :x}, {:lit, 1}}
    end

    test "wraps non-negatable predicates" do
      pred = {:is_type, :integer, {:var, :x}}
      assert Predicate.negate(pred) == {:not, pred}
    end
  end

  describe "subst/2" do
    test "substitutes variables in comparisons" do
      pred = {:gt, {:var, :x}, {:lit, 5}}
      result = Predicate.subst(pred, %{x: {:var, :y}})
      assert result == {:gt, {:var, :y}, {:lit, 5}}
    end

    test "substitutes variables in type checks" do
      pred = {:is_type, :integer, {:var, :x}}
      result = Predicate.subst(pred, %{x: {:var, :y}})
      assert result == {:is_type, :integer, {:var, :y}}
    end

    test "leaves unbound variables unchanged" do
      pred = {:gt, {:var, :x}, {:var, :z}}
      result = Predicate.subst(pred, %{x: {:var, :y}})
      assert result == {:gt, {:var, :y}, {:var, :z}}
    end

    test "substitutes in conjunctions" do
      pred = {:and, {:gt, {:var, :x}, {:lit, 0}}, {:is_type, :integer, {:var, :x}}}
      result = Predicate.subst(pred, %{x: {:var, :y}})

      assert result == {:and, {:gt, {:var, :y}, {:lit, 0}}, {:is_type, :integer, {:var, :y}}}
    end

    test "truth values pass through" do
      assert Predicate.subst(true, %{x: {:var, :y}}) == true
      assert Predicate.subst(false, %{x: {:var, :y}}) == false
    end

    test "substitutes with literal expressions" do
      pred = {:gt, {:var, :x}, {:lit, 5}}
      result = Predicate.subst(pred, %{x: {:lit, 10}})
      assert result == {:gt, {:lit, 10}, {:lit, 5}}
    end
  end

  describe "conjuncts/1" do
    test "flattens nested conjunctions" do
      pred = {:and, {:gt, {:var, :x}, {:lit, 0}}, {:and, {:lt, {:var, :x}, {:lit, 10}}, true}}
      result = Predicate.conjuncts(pred)
      assert result == [{:gt, {:var, :x}, {:lit, 0}}, {:lt, {:var, :x}, {:lit, 10}}]
    end

    test "drops true from conjuncts" do
      assert Predicate.conjuncts(true) == []
    end

    test "non-conjunction returns singleton list" do
      pred = {:gt, {:var, :x}, {:lit, 0}}
      assert Predicate.conjuncts(pred) == [pred]
    end
  end

  describe "conjunction/1" do
    test "empty list gives true" do
      assert Predicate.conjunction([]) == true
    end

    test "singleton list gives the predicate" do
      pred = {:gt, {:var, :x}, {:lit, 0}}
      assert Predicate.conjunction([pred]) == pred
    end

    test "multiple predicates build nested and" do
      p1 = {:gt, {:var, :x}, {:lit, 0}}
      p2 = {:lt, {:var, :x}, {:lit, 10}}
      p3 = {:is_type, :integer, {:var, :x}}
      result = Predicate.conjunction([p1, p2, p3])
      assert result == {:and, p1, {:and, p2, p3}}
    end
  end
end
