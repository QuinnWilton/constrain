defmodule Constrain.Property.SoundnessTest do
  @moduledoc """
  Property tests for solver soundness.

  The solver should never claim entailment that doesn't hold.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Constrain.Generators

  describe "solver soundness" do
    property "derived facts are closed under the built-in rules" do
      check all(preds <- Generators.fact_list()) do
        result = Constrain.solve(preds)

        # If not contradictory, all initial facts should be in the database.
        if not result.database.contradiction do
          for pred <- preds do
            assert Constrain.Database.member?(result.database, pred),
                   "initial fact #{inspect(pred)} missing from saturated database"
          end
        end
      end
    end

    property "entails? never returns :yes for goal not in the database (non-interval)" do
      check all(
              assumptions <- Generators.fact_list(),
              goal <- Generators.type_pred()
            ) do
        answer = Constrain.entails?(assumptions, goal)

        if answer == :yes do
          result = Constrain.solve(assumptions)
          # Either the database has the goal, or there's a contradiction,
          # or the goal follows from intervals.
          assert result.database.contradiction or
                   Constrain.Database.member?(result.database, goal)
        end
      end
    end

    property "satisfiable? :no only when contradiction detected" do
      check all(preds <- Generators.fact_list()) do
        answer = Constrain.satisfiable?(preds)

        if answer == :no do
          result = Constrain.solve(preds)
          assert result.database.contradiction
        end
      end
    end
  end
end
