defmodule Constrain.Examples.EntailmentTest do
  @moduledoc """
  End-to-end entailment tests demonstrating the solver's capabilities.
  """
  use ExUnit.Case, async: true

  describe "type hierarchy entailment" do
    test "integer implies number" do
      assert Constrain.entails?(
               [{:is_type, :integer, {:var, :x}}],
               {:is_type, :number, {:var, :x}}
             ) == :yes
    end

    test "boolean implies atom" do
      assert Constrain.entails?(
               [{:is_type, :boolean, {:var, :x}}],
               {:is_type, :atom, {:var, :x}}
             ) == :yes
    end

    test "binary implies bitstring" do
      assert Constrain.entails?(
               [{:is_type, :binary, {:var, :x}}],
               {:is_type, :bitstring, {:var, :x}}
             ) == :yes
    end

    test "struct implies map" do
      assert Constrain.entails?(
               [{:is_type, :struct, {:var, :x}}],
               {:is_type, :map, {:var, :x}}
             ) == :yes
    end

    test "integer implies any" do
      assert Constrain.entails?(
               [{:is_type, :integer, {:var, :x}}],
               {:is_type, :any, {:var, :x}}
             ) == :yes
    end

    test "integer does not imply float" do
      assert Constrain.entails?(
               [{:is_type, :integer, {:var, :x}}],
               {:is_type, :float, {:var, :x}}
             ) == :unknown
    end
  end

  describe "comparison entailment" do
    test "x > 5 implies x > 0 (via intervals)" do
      assert Constrain.entails?(
               [{:gt, {:var, :x}, {:lit, 5}}],
               {:gt, {:var, :x}, {:lit, 0}}
             ) == :yes
    end

    test "x > 5 does not imply x > 10" do
      assert Constrain.entails?(
               [{:gt, {:var, :x}, {:lit, 5}}],
               {:gt, {:var, :x}, {:lit, 10}}
             ) == :unknown
    end

    test "transitivity chain" do
      assert Constrain.entails?(
               [
                 {:gt, {:var, :x}, {:var, :y}},
                 {:gt, {:var, :y}, {:var, :z}}
               ],
               {:gt, {:var, :x}, {:var, :z}}
             ) == :yes
    end

    test "antisymmetry derives equality" do
      assert Constrain.entails?(
               [
                 {:gte, {:var, :x}, {:var, :y}},
                 {:lte, {:var, :x}, {:var, :y}}
               ],
               {:eq, {:var, :x}, {:var, :y}}
             ) == :yes
    end

    test "x > y implies x != y" do
      assert Constrain.entails?(
               [{:gt, {:var, :x}, {:var, :y}}],
               {:neq, {:var, :x}, {:var, :y}}
             ) == :yes
    end
  end

  describe "equality entailment" do
    test "type propagation through equality" do
      assert Constrain.entails?(
               [
                 {:eq, {:var, :x}, {:var, :y}},
                 {:is_type, :integer, {:var, :x}}
               ],
               {:is_type, :integer, {:var, :y}}
             ) == :yes
    end

    test "type hierarchy propagation through equality" do
      assert Constrain.entails?(
               [
                 {:eq, {:var, :x}, {:var, :y}},
                 {:is_type, :integer, {:var, :x}}
               ],
               {:is_type, :number, {:var, :y}}
             ) == :yes
    end
  end

  describe "guard + pattern entailment" do
    test "pattern {:ok, x} with is_integer(x) implies number(x)" do
      pattern_preds = Constrain.Pattern.from_pattern(quote(do: {:ok, x}), :result)
      guard_preds = Constrain.Guard.from_guard(quote(do: is_integer(x)))

      assert Constrain.entails?(
               pattern_preds ++ guard_preds,
               {:is_type, :number, {:var, :x}}
             ) == :yes
    end

    test "pattern {:ok, x} with x > 0 implies x > -1" do
      pattern_preds = Constrain.Pattern.from_pattern(quote(do: {:ok, x}), :result)
      guard_preds = Constrain.Guard.from_guard(quote(do: x > 0))

      assert Constrain.entails?(
               pattern_preds ++ guard_preds,
               {:gt, {:var, :x}, {:lit, -1}}
             ) == :yes
    end
  end

  describe "contradictory assumptions" do
    test "contradictory assumptions entail anything" do
      assert Constrain.entails?(
               [
                 {:is_type, :integer, {:var, :x}},
                 {:is_type, :atom, {:var, :x}}
               ],
               {:is_type, :float, {:var, :x}}
             ) == :yes
    end
  end
end
