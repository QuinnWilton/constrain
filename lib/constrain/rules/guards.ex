defmodule Constrain.Rules.Guards do
  @moduledoc """
  Built-in Horn clause rules encoding the semantics of Elixir guard predicates.

  Generates rules from the type lattice (subtyping, mutual exclusion) and
  encodes properties of comparison operators (transitivity, weakening,
  antisymmetry, contradiction detection).
  """

  alias Constrain.Domain.TypeLattice
  alias Constrain.Rule

  @doc """
  Returns all built-in guard semantic rules.
  """
  @spec rules() :: [Rule.t()]
  def rules do
    type_hierarchy_rules() ++
      mutual_exclusion_rules() ++
      comparison_rules() ++
      equality_rules() ++
      binary_rules()
  end

  @doc """
  Returns rules encoding the type hierarchy.

  For each subtype relationship (e.g., integer <: number), generates a rule:
  `is_type(:integer, x) → is_type(:number, x)`
  """
  @spec type_hierarchy_rules() :: [Rule.t()]
  def type_hierarchy_rules do
    for type <- TypeLattice.all_types(),
        parent <- TypeLattice.parents(type) do
      %Rule{
        name: :"#{type}_is_#{parent}",
        premises: [{:is_type, type, {:var, :x}}],
        conclusion: {:is_type, parent, {:var, :x}}
      }
    end
  end

  @doc """
  Returns rules encoding mutual exclusion between disjoint types.

  For each disjoint pair (e.g., integer and atom), generates:
  `is_type(:integer, x) ∧ is_type(:atom, x) → :false`
  """
  @spec mutual_exclusion_rules() :: [Rule.t()]
  def mutual_exclusion_rules do
    for {a, b} <- TypeLattice.disjoint_pairs() do
      %Rule{
        name: :"#{a}_excludes_#{b}",
        premises: [{:is_type, a, {:var, :x}}, {:is_type, b, {:var, :x}}],
        conclusion: false
      }
    end
  end

  @doc """
  Returns rules for comparison operator properties.
  """
  @spec comparison_rules() :: [Rule.t()]
  def comparison_rules do
    [
      # Transitivity of >
      %Rule{
        name: :gt_transitive,
        premises: [{:gt, {:var, :x}, {:var, :y}}, {:gt, {:var, :y}, {:var, :z}}],
        conclusion: {:gt, {:var, :x}, {:var, :z}}
      },
      # Transitivity of >=
      %Rule{
        name: :gte_transitive,
        premises: [{:gte, {:var, :x}, {:var, :y}}, {:gte, {:var, :y}, {:var, :z}}],
        conclusion: {:gte, {:var, :x}, {:var, :z}}
      },
      # Transitivity of <
      %Rule{
        name: :lt_transitive,
        premises: [{:lt, {:var, :x}, {:var, :y}}, {:lt, {:var, :y}, {:var, :z}}],
        conclusion: {:lt, {:var, :x}, {:var, :z}}
      },
      # Transitivity of <=
      %Rule{
        name: :lte_transitive,
        premises: [{:lte, {:var, :x}, {:var, :y}}, {:lte, {:var, :y}, {:var, :z}}],
        conclusion: {:lte, {:var, :x}, {:var, :z}}
      },
      # Weakening: > implies >=
      %Rule{
        name: :gt_weakens_to_gte,
        premises: [{:gt, {:var, :x}, {:var, :y}}],
        conclusion: {:gte, {:var, :x}, {:var, :y}}
      },
      # Weakening: < implies <=
      %Rule{
        name: :lt_weakens_to_lte,
        premises: [{:lt, {:var, :x}, {:var, :y}}],
        conclusion: {:lte, {:var, :x}, {:var, :y}}
      },
      # Weakening: > implies !=
      %Rule{
        name: :gt_implies_neq,
        premises: [{:gt, {:var, :x}, {:var, :y}}],
        conclusion: {:neq, {:var, :x}, {:var, :y}}
      },
      # Weakening: < implies !=
      %Rule{
        name: :lt_implies_neq,
        premises: [{:lt, {:var, :x}, {:var, :y}}],
        conclusion: {:neq, {:var, :x}, {:var, :y}}
      },
      # Antisymmetry: >= and <= implies ==
      %Rule{
        name: :gte_lte_antisymmetry,
        premises: [{:gte, {:var, :x}, {:var, :y}}, {:lte, {:var, :x}, {:var, :y}}],
        conclusion: {:eq, {:var, :x}, {:var, :y}}
      },
      # Contradiction: > and < simultaneously
      %Rule{
        name: :gt_lt_contradiction,
        premises: [{:gt, {:var, :x}, {:var, :y}}, {:lt, {:var, :x}, {:var, :y}}],
        conclusion: false
      },
      # Contradiction: > and ==
      %Rule{
        name: :gt_eq_contradiction,
        premises: [{:gt, {:var, :x}, {:var, :y}}, {:eq, {:var, :x}, {:var, :y}}],
        conclusion: false
      },
      # Contradiction: < and ==
      %Rule{
        name: :lt_eq_contradiction,
        premises: [{:lt, {:var, :x}, {:var, :y}}, {:eq, {:var, :x}, {:var, :y}}],
        conclusion: false
      },
      # Mixed transitivity: > and >= gives >
      %Rule{
        name: :gt_gte_transitive,
        premises: [{:gt, {:var, :x}, {:var, :y}}, {:gte, {:var, :y}, {:var, :z}}],
        conclusion: {:gt, {:var, :x}, {:var, :z}}
      },
      # Mixed transitivity: >= and > gives >
      %Rule{
        name: :gte_gt_transitive,
        premises: [{:gte, {:var, :x}, {:var, :y}}, {:gt, {:var, :y}, {:var, :z}}],
        conclusion: {:gt, {:var, :x}, {:var, :z}}
      },
      # Mixed transitivity: < and <= gives <
      %Rule{
        name: :lt_lte_transitive,
        premises: [{:lt, {:var, :x}, {:var, :y}}, {:lte, {:var, :y}, {:var, :z}}],
        conclusion: {:lt, {:var, :x}, {:var, :z}}
      },
      # Mixed transitivity: <= and < gives <
      %Rule{
        name: :lte_lt_transitive,
        premises: [{:lte, {:var, :x}, {:var, :y}}, {:lt, {:var, :y}, {:var, :z}}],
        conclusion: {:lt, {:var, :x}, {:var, :z}}
      },
      # Converse: x > y ↔ y < x
      %Rule{
        name: :gt_converse,
        premises: [{:gt, {:var, :x}, {:var, :y}}],
        conclusion: {:lt, {:var, :y}, {:var, :x}}
      },
      %Rule{
        name: :lt_converse,
        premises: [{:lt, {:var, :x}, {:var, :y}}],
        conclusion: {:gt, {:var, :y}, {:var, :x}}
      },
      # Converse: x >= y ↔ y <= x
      %Rule{
        name: :gte_converse,
        premises: [{:gte, {:var, :x}, {:var, :y}}],
        conclusion: {:lte, {:var, :y}, {:var, :x}}
      },
      %Rule{
        name: :lte_converse,
        premises: [{:lte, {:var, :x}, {:var, :y}}],
        conclusion: {:gte, {:var, :y}, {:var, :x}}
      }
    ]
  end

  @doc """
  Returns rules for equality properties.
  """
  @spec equality_rules() :: [Rule.t()]
  def equality_rules do
    [
      # Symmetry of ==
      %Rule{
        name: :eq_symmetric,
        premises: [{:eq, {:var, :x}, {:var, :y}}],
        conclusion: {:eq, {:var, :y}, {:var, :x}}
      },
      # Symmetry of !=
      %Rule{
        name: :neq_symmetric,
        premises: [{:neq, {:var, :x}, {:var, :y}}],
        conclusion: {:neq, {:var, :y}, {:var, :x}}
      },
      # == implies >=
      %Rule{
        name: :eq_implies_gte,
        premises: [{:eq, {:var, :x}, {:var, :y}}],
        conclusion: {:gte, {:var, :x}, {:var, :y}}
      },
      # == implies <=
      %Rule{
        name: :eq_implies_lte,
        premises: [{:eq, {:var, :x}, {:var, :y}}],
        conclusion: {:lte, {:var, :x}, {:var, :y}}
      },
      # Type substitution: x == y and is_type(T, x) implies is_type(T, y)
      %Rule{
        name: :eq_type_subst,
        premises: [{:eq, {:var, :x}, {:var, :y}}, {:is_type, {:var, :__tag}, {:var, :x}}],
        conclusion: {:is_type, {:var, :__tag}, {:var, :y}}
      },
      # == and != contradiction
      %Rule{
        name: :eq_neq_contradiction,
        premises: [{:eq, {:var, :x}, {:var, :y}}, {:neq, {:var, :x}, {:var, :y}}],
        conclusion: false
      }
    ]
  end

  @doc """
  Returns rules encoding binary/bitstring size semantics.
  """
  @spec binary_rules() :: [Rule.t()]
  def binary_rules do
    [
      # byte_size(x) >= 0 when is_binary(x).
      %Rule{
        name: :binary_byte_size_non_negative,
        premises: [{:is_type, :binary, {:var, :x}}],
        conclusion: {:gte, {:op, :byte_size, [{:var, :x}]}, {:lit, 0}}
      },
      # bit_size(x) >= 0 when is_bitstring(x).
      %Rule{
        name: :bitstring_bit_size_non_negative,
        premises: [{:is_type, :bitstring, {:var, :x}}],
        conclusion: {:gte, {:op, :bit_size, [{:var, :x}]}, {:lit, 0}}
      },
      # byte_size(x) is an integer when is_binary(x).
      %Rule{
        name: :byte_size_is_integer,
        premises: [{:is_type, :binary, {:var, :x}}],
        conclusion: {:is_type, :integer, {:op, :byte_size, [{:var, :x}]}}
      },
      # bit_size(x) is an integer when is_bitstring(x).
      %Rule{
        name: :bit_size_is_integer,
        premises: [{:is_type, :bitstring, {:var, :x}}],
        conclusion: {:is_type, :integer, {:op, :bit_size, [{:var, :x}]}}
      }
    ]
  end
end
