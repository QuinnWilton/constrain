defmodule Constrain.Domain.TypeLatticeTest do
  use ExUnit.Case, async: true

  alias Constrain.Domain.TypeLattice

  describe "subtype?/2" do
    test "every type is subtype of itself" do
      for type <- TypeLattice.all_types() do
        assert TypeLattice.subtype?(type, type), "#{type} should be subtype of itself"
      end
    end

    test "every type is subtype of :any" do
      for type <- TypeLattice.all_types(), type != :any do
        assert TypeLattice.subtype?(type, :any), "#{type} should be subtype of :any"
      end
    end

    test ":any is not subtype of anything else" do
      for type <- TypeLattice.all_types(), type != :any do
        refute TypeLattice.subtype?(:any, type), ":any should not be subtype of #{type}"
      end
    end

    test "integer is subtype of number" do
      assert TypeLattice.subtype?(:integer, :number)
    end

    test "float is subtype of number" do
      assert TypeLattice.subtype?(:float, :number)
    end

    test "boolean is subtype of atom" do
      assert TypeLattice.subtype?(:boolean, :atom)
    end

    test "nil is subtype of atom" do
      assert TypeLattice.subtype?(nil, :atom)
    end

    test "binary is subtype of bitstring" do
      assert TypeLattice.subtype?(:binary, :bitstring)
    end

    test "struct is subtype of map" do
      assert TypeLattice.subtype?(:struct, :map)
    end

    test "number is not subtype of integer" do
      refute TypeLattice.subtype?(:number, :integer)
    end

    test "transitive: boolean is subtype of :any" do
      assert TypeLattice.subtype?(:boolean, :any)
    end
  end

  describe "disjoint?/2" do
    test "same type is not disjoint" do
      refute TypeLattice.disjoint?(:integer, :integer)
    end

    test "subtype/supertype are not disjoint" do
      refute TypeLattice.disjoint?(:integer, :number)
      refute TypeLattice.disjoint?(:number, :integer)
    end

    test "integer and float are disjoint" do
      assert TypeLattice.disjoint?(:integer, :float)
    end

    test "atom and number are disjoint" do
      assert TypeLattice.disjoint?(:atom, :number)
    end

    test "integer and atom are disjoint" do
      assert TypeLattice.disjoint?(:integer, :atom)
    end

    test "list and tuple are disjoint" do
      assert TypeLattice.disjoint?(:list, :tuple)
    end

    test "boolean and nil are disjoint" do
      assert TypeLattice.disjoint?(:boolean, nil)
    end

    test "boolean and number are disjoint" do
      assert TypeLattice.disjoint?(:boolean, :number)
    end
  end

  describe "disjoint_pairs/0" do
    test "returns ordered pairs" do
      pairs = TypeLattice.disjoint_pairs()

      for {a, b} <- pairs do
        assert a < b, "expected #{a} < #{b} in disjoint pair"
      end
    end

    test "all returned pairs are actually disjoint" do
      for {a, b} <- TypeLattice.disjoint_pairs() do
        assert TypeLattice.disjoint?(a, b), "#{a} and #{b} should be disjoint"
      end
    end

    test "contains expected pairs" do
      pairs = TypeLattice.disjoint_pairs()
      assert {:float, :integer} in pairs
      assert {:atom, :number} in pairs
    end
  end

  describe "supertypes/1" do
    test ":any has no supertypes" do
      assert TypeLattice.supertypes(:any) == []
    end

    test "integer supertypes include number and any" do
      supers = TypeLattice.supertypes(:integer)
      assert :number in supers
      assert :any in supers
    end

    test "boolean supertypes include atom and any" do
      supers = TypeLattice.supertypes(:boolean)
      assert :atom in supers
      assert :any in supers
    end
  end

  describe "subtypes/1" do
    test ":any subtypes are top-level types" do
      subs = TypeLattice.subtypes(:any)
      assert :number in subs
      assert :atom in subs
      assert :list in subs
    end

    test "number subtypes" do
      assert TypeLattice.subtypes(:number) == [:integer, :float]
    end

    test "atom subtypes" do
      assert TypeLattice.subtypes(:atom) == [:boolean, nil]
    end

    test "leaf types have no subtypes" do
      assert TypeLattice.subtypes(:integer) == []
      assert TypeLattice.subtypes(:float) == []
      assert TypeLattice.subtypes(:pid) == []
    end
  end
end
