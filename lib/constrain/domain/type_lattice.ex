defmodule Constrain.Domain.TypeLattice do
  @moduledoc """
  The Elixir/BEAM type hierarchy as a static lattice.

  Encodes the subtyping and mutual exclusion relationships between BEAM types,
  matching the semantics of Erlang type guards. This is a compile-time constant
  structure — no dynamic module discovery.

  The hierarchy:

      any
      ├── number
      │   ├── integer
      │   └── float
      ├── atom
      │   ├── boolean
      │   └── nil
      ├── binary
      │   └── bitstring (binary <: bitstring)
      ├── list
      ├── tuple
      ├── map
      │   └── struct
      ├── pid
      ├── port
      ├── reference
      └── function
  """

  @type type_tag :: Constrain.Predicate.type_tag()

  # Direct parent relationships. Each type maps to its immediate supertype(s).
  @parents %{
    integer: [:number],
    float: [:number],
    boolean: [:atom],
    nil: [:atom],
    binary: [:bitstring],
    struct: [:map]
  }

  # Top-level types (direct children of :any).
  @top_level [:number, :atom, :bitstring, :list, :tuple, :map, :pid, :port, :reference, :function]

  @doc """
  Returns true if `sub` is a subtype of `super`.

  Every type is a subtype of itself.
  """
  @spec subtype?(type_tag(), type_tag()) :: boolean()
  def subtype?(tag, tag), do: true
  def subtype?(_sub, :any), do: true
  def subtype?(:any, _super), do: false

  def subtype?(sub, super) do
    super in supertypes(sub)
  end

  @doc """
  Returns all supertypes of a type (transitive closure, not including itself).
  """
  @spec supertypes(type_tag()) :: [type_tag()]
  def supertypes(:any), do: []

  def supertypes(tag) do
    case Map.get(@parents, tag) do
      nil ->
        if tag in @top_level, do: [:any], else: [:any]

      parents ->
        (parents ++ Enum.flat_map(parents, &supertypes/1)) |> Enum.uniq()
    end
  end

  @doc """
  Returns the immediate subtypes of a type.
  """
  @spec subtypes(type_tag()) :: [type_tag()]
  def subtypes(:any), do: @top_level
  def subtypes(:number), do: [:integer, :float]
  def subtypes(:atom), do: [:boolean, nil]
  def subtypes(:bitstring), do: [:binary]
  def subtypes(:map), do: [:struct]
  def subtypes(_), do: []

  @doc """
  Returns true if two types are known to be disjoint (no value inhabits both).

  Two types are disjoint when neither is a subtype of the other and they
  share no common subtypes. Only applies to leaf and sibling types.
  """
  @spec disjoint?(type_tag(), type_tag()) :: boolean()
  def disjoint?(a, b) when a == b, do: false

  def disjoint?(a, b) do
    not subtype?(a, b) and not subtype?(b, a) and not share_subtypes?(a, b)
  end

  @doc """
  Returns all pairs of disjoint leaf/sibling types.

  Used by `Rules.Guards` to generate mutual exclusion rules.
  """
  @spec disjoint_pairs() :: [{type_tag(), type_tag()}]
  def disjoint_pairs do
    all = all_types()

    for a <- all,
        b <- all,
        a < b,
        disjoint?(a, b) do
      {a, b}
    end
  end

  @doc """
  Returns all type tags in the lattice.
  """
  @spec all_types() :: [type_tag()]
  def all_types do
    [:any | @top_level] ++ [:integer, :float, :boolean, nil, :binary, :struct]
  end

  @doc """
  Returns the immediate parent types.
  """
  @spec parents(type_tag()) :: [type_tag()]
  def parents(:any), do: []

  def parents(tag) do
    case Map.get(@parents, tag) do
      nil -> if tag in @top_level, do: [:any], else: []
      parents -> parents
    end
  end

  # Returns true if two types share any common subtypes (directly or transitively).
  defp share_subtypes?(a, b) do
    a_descendants = all_descendants(a)
    b_descendants = all_descendants(b)
    not MapSet.disjoint?(a_descendants, b_descendants)
  end

  defp all_descendants(tag) do
    children = subtypes(tag)

    children
    |> Enum.reduce(MapSet.new(children), fn child, acc ->
      MapSet.union(acc, all_descendants(child))
    end)
  end
end
