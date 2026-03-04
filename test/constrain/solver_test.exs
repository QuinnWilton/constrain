defmodule Constrain.SolverTest do
  use ExUnit.Case, async: true

  alias Constrain.Solver

  describe "solve/1" do
    test "returns saturated for empty input" do
      result = Solver.solve([])
      assert result.stop_reason == :saturated
    end

    test "returns contradiction when input is contradictory" do
      result = Solver.solve([{:gt, {:var, :x}, {:lit, 10}}, {:lt, {:var, :x}, {:lit, 5}}])
      assert result.stop_reason == :contradiction
    end

    test "derives type hierarchy facts" do
      result = Solver.solve([{:is_type, :integer, {:var, :x}}])
      assert result.stop_reason == :saturated

      db = result.database
      # integer <: number <: any.
      assert Constrain.Database.member?(db, {:is_type, :number, {:var, :x}})
      assert Constrain.Database.member?(db, {:is_type, :any, {:var, :x}})
    end

    test "derives comparison weakening" do
      result = Solver.solve([{:gt, {:var, :x}, {:var, :y}}])
      db = result.database
      # x > y implies x >= y and x != y.
      assert Constrain.Database.member?(db, {:gte, {:var, :x}, {:var, :y}})
      assert Constrain.Database.member?(db, {:neq, {:var, :x}, {:var, :y}})
    end

    test "derives equality symmetry" do
      result = Solver.solve([{:eq, {:var, :x}, {:var, :y}}])
      db = result.database
      assert Constrain.Database.member?(db, {:eq, {:var, :y}, {:var, :x}})
    end

    test "derives transitivity" do
      result =
        Solver.solve([
          {:gt, {:var, :x}, {:var, :y}},
          {:gt, {:var, :y}, {:var, :z}}
        ])

      db = result.database
      assert Constrain.Database.member?(db, {:gt, {:var, :x}, {:var, :z}})
    end

    test "detects gt and lt contradiction" do
      result =
        Solver.solve([
          {:gt, {:var, :x}, {:var, :y}},
          {:lt, {:var, :x}, {:var, :y}}
        ])

      assert result.stop_reason == :contradiction
    end

    test "detects gt and eq contradiction" do
      result =
        Solver.solve([
          {:gt, {:var, :x}, {:var, :y}},
          {:eq, {:var, :x}, {:var, :y}}
        ])

      assert result.stop_reason == :contradiction
    end

    test "detects type mutual exclusion" do
      result =
        Solver.solve([
          {:is_type, :integer, {:var, :x}},
          {:is_type, :atom, {:var, :x}}
        ])

      assert result.stop_reason == :contradiction
    end

    test "derives antisymmetry: >= and <= gives ==" do
      result =
        Solver.solve([
          {:gte, {:var, :x}, {:var, :y}},
          {:lte, {:var, :x}, {:var, :y}}
        ])

      db = result.database
      assert Constrain.Database.member?(db, {:eq, {:var, :x}, {:var, :y}})
    end

    test "type substitution through equality" do
      result =
        Solver.solve([
          {:eq, {:var, :x}, {:var, :y}},
          {:is_type, :integer, {:var, :x}}
        ])

      db = result.database
      assert Constrain.Database.member?(db, {:is_type, :integer, {:var, :y}})
    end
  end

  describe "entails?/2" do
    test "entails goal from type hierarchy" do
      assert Solver.entails?(
               [{:is_type, :integer, {:var, :x}}],
               {:is_type, :number, {:var, :x}}
             ) == :yes
    end

    test "does not entail unrelated goal" do
      assert Solver.entails?(
               [{:is_type, :integer, {:var, :x}}],
               {:is_type, :atom, {:var, :x}}
             ) == :unknown
    end

    test "entails from comparison transitivity" do
      assert Solver.entails?(
               [{:gt, {:var, :x}, {:var, :y}}, {:gt, {:var, :y}, {:var, :z}}],
               {:gt, {:var, :x}, {:var, :z}}
             ) == :yes
    end

    test "contradictory assumptions entail anything" do
      assert Solver.entails?(
               [{:is_type, :integer, {:var, :x}}, {:is_type, :atom, {:var, :x}}],
               {:is_type, :float, {:var, :x}}
             ) == :yes
    end

    test "entails from interval reasoning" do
      assert Solver.entails?(
               [{:gt, {:var, :x}, {:lit, 5}}],
               {:gt, {:var, :x}, {:lit, 0}}
             ) == :yes
    end

    test "does not entail from insufficient bounds" do
      assert Solver.entails?(
               [{:gt, {:var, :x}, {:lit, 5}}],
               {:gt, {:var, :x}, {:lit, 10}}
             ) == :unknown
    end

    test "negation entailment" do
      assert Solver.entails?(
               [{:gt, {:var, :x}, {:var, :y}}],
               {:neq, {:var, :x}, {:var, :y}}
             ) == :yes
    end
  end

  describe "satisfiable?/1" do
    test "empty constraints are satisfiable" do
      assert Solver.satisfiable?([]) == :yes
    end

    test "consistent type is satisfiable" do
      assert Solver.satisfiable?([{:is_type, :integer, {:var, :x}}]) == :yes
    end

    test "disjoint types are unsatisfiable" do
      assert Solver.satisfiable?([
               {:is_type, :integer, {:var, :x}},
               {:is_type, :atom, {:var, :x}}
             ]) == :no
    end

    test "contradictory comparisons are unsatisfiable" do
      assert Solver.satisfiable?([
               {:gt, {:var, :x}, {:lit, 10}},
               {:lt, {:var, :x}, {:lit, 5}}
             ]) == :no
    end

    test "consistent comparisons are satisfiable" do
      assert Solver.satisfiable?([
               {:gt, {:var, :x}, {:lit, 0}},
               {:lt, {:var, :x}, {:lit, 10}}
             ]) == :yes
    end
  end
end
