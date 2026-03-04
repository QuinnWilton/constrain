defmodule Constrain.Rules.GuardsTest do
  use ExUnit.Case, async: true

  alias Constrain.Rules.Guards

  describe "rules/0" do
    test "returns a non-empty list of rules" do
      rules = Guards.rules()
      assert length(rules) > 0
    end

    test "all rules have names" do
      for rule <- Guards.rules() do
        assert is_atom(rule.name), "rule missing name: #{inspect(rule)}"
      end
    end

    test "all rules have at least one premise" do
      for rule <- Guards.rules() do
        assert length(rule.premises) >= 1,
               "rule #{rule.name} has no premises"
      end
    end

    test "all rule names are unique" do
      names = Enum.map(Guards.rules(), & &1.name)
      assert length(names) == length(Enum.uniq(names))
    end
  end

  describe "type_hierarchy_rules/0" do
    test "includes integer -> number rule" do
      rules = Guards.type_hierarchy_rules()
      names = Enum.map(rules, & &1.name)
      assert :integer_is_number in names
    end

    test "includes boolean -> atom rule" do
      rules = Guards.type_hierarchy_rules()
      names = Enum.map(rules, & &1.name)
      assert :boolean_is_atom in names
    end

    test "includes binary -> bitstring rule" do
      rules = Guards.type_hierarchy_rules()
      names = Enum.map(rules, & &1.name)
      assert :binary_is_bitstring in names
    end

    test "includes struct -> map rule" do
      rules = Guards.type_hierarchy_rules()
      names = Enum.map(rules, & &1.name)
      assert :struct_is_map in names
    end
  end

  describe "mutual_exclusion_rules/0" do
    test "includes integer/atom exclusion" do
      rules = Guards.mutual_exclusion_rules()
      names = Enum.map(rules, & &1.name)
      # atom < integer alphabetically.
      assert :atom_excludes_integer in names
    end

    test "excludes non-disjoint types" do
      rules = Guards.mutual_exclusion_rules()
      names = Enum.map(rules, & &1.name)
      # integer and number are not disjoint (integer <: number).
      refute :integer_excludes_number in names
    end
  end

  describe "comparison_rules/0" do
    test "includes transitivity rules" do
      rules = Guards.comparison_rules()
      names = Enum.map(rules, & &1.name)
      assert :gt_transitive in names
      assert :gte_transitive in names
      assert :lt_transitive in names
      assert :lte_transitive in names
    end

    test "includes weakening rules" do
      rules = Guards.comparison_rules()
      names = Enum.map(rules, & &1.name)
      assert :gt_weakens_to_gte in names
      assert :lt_weakens_to_lte in names
    end

    test "includes contradiction rules" do
      rules = Guards.comparison_rules()
      names = Enum.map(rules, & &1.name)
      assert :gt_lt_contradiction in names
      assert :gt_eq_contradiction in names
      assert :lt_eq_contradiction in names
    end
  end

  describe "equality_rules/0" do
    test "includes symmetry" do
      rules = Guards.equality_rules()
      names = Enum.map(rules, & &1.name)
      assert :eq_symmetric in names
      assert :neq_symmetric in names
    end

    test "includes type substitution" do
      rules = Guards.equality_rules()
      names = Enum.map(rules, & &1.name)
      assert :eq_type_subst in names
    end

    test "includes eq/neq contradiction" do
      rules = Guards.equality_rules()
      names = Enum.map(rules, & &1.name)
      assert :eq_neq_contradiction in names
    end
  end
end
