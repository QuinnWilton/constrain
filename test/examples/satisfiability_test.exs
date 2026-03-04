defmodule Constrain.Examples.SatisfiabilityTest do
  @moduledoc """
  End-to-end satisfiability tests.
  """
  use ExUnit.Case, async: true

  describe "type satisfiability" do
    test "single type is satisfiable" do
      assert Constrain.satisfiable?([{:is_type, :integer, {:var, :x}}]) == :yes
    end

    test "compatible types are satisfiable" do
      assert Constrain.satisfiable?([
               {:is_type, :integer, {:var, :x}},
               {:is_type, :number, {:var, :x}}
             ]) == :yes
    end

    test "disjoint types are unsatisfiable" do
      assert Constrain.satisfiable?([
               {:is_type, :integer, {:var, :x}},
               {:is_type, :atom, {:var, :x}}
             ]) == :no
    end

    test "boolean and integer are unsatisfiable" do
      assert Constrain.satisfiable?([
               {:is_type, :boolean, {:var, :x}},
               {:is_type, :integer, {:var, :x}}
             ]) == :no
    end

    test "integer and float are unsatisfiable" do
      assert Constrain.satisfiable?([
               {:is_type, :integer, {:var, :x}},
               {:is_type, :float, {:var, :x}}
             ]) == :no
    end

    test "different variables can have different types" do
      assert Constrain.satisfiable?([
               {:is_type, :integer, {:var, :x}},
               {:is_type, :atom, {:var, :y}}
             ]) == :yes
    end
  end

  describe "comparison satisfiability" do
    test "consistent range is satisfiable" do
      assert Constrain.satisfiable?([
               {:gt, {:var, :x}, {:lit, 0}},
               {:lt, {:var, :x}, {:lit, 100}}
             ]) == :yes
    end

    test "empty range is unsatisfiable" do
      assert Constrain.satisfiable?([
               {:gt, {:var, :x}, {:lit, 10}},
               {:lt, {:var, :x}, {:lit, 5}}
             ]) == :no
    end

    test "touching exclusive bounds are unsatisfiable" do
      assert Constrain.satisfiable?([
               {:gt, {:var, :x}, {:lit, 5}},
               {:lt, {:var, :x}, {:lit, 5}}
             ]) == :no
    end

    test "contradictory gt and lt on same variables" do
      assert Constrain.satisfiable?([
               {:gt, {:var, :x}, {:var, :y}},
               {:lt, {:var, :x}, {:var, :y}}
             ]) == :no
    end

    test "gt and eq contradiction" do
      assert Constrain.satisfiable?([
               {:gt, {:var, :x}, {:var, :y}},
               {:eq, {:var, :x}, {:var, :y}}
             ]) == :no
    end
  end

  describe "guard-based satisfiability" do
    test "consistent guard" do
      preds = Constrain.Guard.from_guard(quote(do: is_integer(x) and x > 0))
      assert Constrain.satisfiable?(preds) == :yes
    end

    test "contradictory numeric bounds from guard" do
      preds = Constrain.Guard.from_guard(quote(do: x > 10 and x < 5))
      assert Constrain.satisfiable?(preds) == :no
    end
  end

  describe "pattern + guard satisfiability" do
    test "pattern with consistent guard" do
      pattern_preds = Constrain.Pattern.from_pattern(quote(do: {:ok, x}), :result)
      guard_preds = Constrain.Guard.from_guard(quote(do: is_integer(x) and x > 0))
      assert Constrain.satisfiable?(pattern_preds ++ guard_preds) == :yes
    end
  end
end
