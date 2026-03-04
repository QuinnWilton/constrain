defmodule Constrain.Property.MonotonicityTest do
  @moduledoc """
  Property tests for monotonicity.

  Adding more assumptions should never cause an entailment to stop holding
  (unless the new assumptions introduce a contradiction, in which case
  everything becomes entailed).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Constrain.Generators

  describe "monotonicity" do
    property "adding assumptions preserves entailment" do
      check all(
              base <- Generators.fact_list(),
              extra <- Generators.fact_list(),
              goal <- Generators.type_pred()
            ) do
        base_answer = Constrain.entails?(base, goal)
        extended_answer = Constrain.entails?(base ++ extra, goal)

        # If base entails goal, extended should too.
        if base_answer == :yes do
          assert extended_answer == :yes,
                 "monotonicity violated: base entails #{inspect(goal)} but extended does not"
        end
      end
    end

    property "adding assumptions preserves unsatisfiability" do
      check all(
              base <- Generators.fact_list(),
              extra <- Generators.fact_list()
            ) do
        base_sat = Constrain.satisfiable?(base)
        extended_sat = Constrain.satisfiable?(base ++ extra)

        # If base is unsatisfiable, extended must also be.
        if base_sat == :no do
          assert extended_sat == :no,
                 "monotonicity violated: base is unsat but extended is not"
        end
      end
    end
  end
end
