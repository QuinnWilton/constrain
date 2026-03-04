defmodule Constrain.RelationTest do
  use ExUnit.Case, async: true

  alias Constrain.Relation

  describe "new/1" do
    test "creates empty relation with given arity" do
      rel = Relation.new(3)
      assert Relation.size(rel) == 0
      assert Relation.to_list(rel) == []
    end
  end

  describe "insert/2" do
    test "inserts a row" do
      rel = Relation.new(2)
      rel = Relation.insert(rel, {:a, 1})
      assert Relation.size(rel) == 1
      assert Relation.member?(rel, {:a, 1})
    end

    test "ignores duplicate rows" do
      rel = Relation.new(2)
      rel = Relation.insert(rel, {:a, 1})
      rel = Relation.insert(rel, {:a, 1})
      assert Relation.size(rel) == 1
    end

    test "accepts multiple distinct rows" do
      rel = Relation.new(2)
      rel = Relation.insert(rel, {:a, 1})
      rel = Relation.insert(rel, {:b, 2})
      assert Relation.size(rel) == 2
    end
  end

  describe "lookup/3" do
    test "finds rows by column value" do
      rel = Relation.new(2)
      rel = Relation.insert(rel, {:a, 1})
      rel = Relation.insert(rel, {:a, 2})
      rel = Relation.insert(rel, {:b, 1})

      results = Relation.lookup(rel, 0, :a)
      assert length(results) == 2
      assert {:a, 1} in results
      assert {:a, 2} in results
    end

    test "returns empty for missing value" do
      rel = Relation.new(2)
      rel = Relation.insert(rel, {:a, 1})
      assert Relation.lookup(rel, 0, :b) == []
    end

    test "looks up by second column" do
      rel = Relation.new(2)
      rel = Relation.insert(rel, {:a, 1})
      rel = Relation.insert(rel, {:b, 1})
      rel = Relation.insert(rel, {:c, 2})

      results = Relation.lookup(rel, 1, 1)
      assert length(results) == 2
      assert {:a, 1} in results
      assert {:b, 1} in results
    end
  end

  describe "semi-naive tracking" do
    test "insert_new stages in new_rows" do
      rel = Relation.new(1)
      rel = Relation.insert_new(rel, {:fact_1})
      assert Relation.has_new?(rel)
      refute Relation.member?(rel, {:fact_1})
    end

    test "insert_new skips existing rows" do
      rel = Relation.new(1)
      rel = Relation.insert(rel, {:fact_1})
      rel = Relation.insert_new(rel, {:fact_1})
      refute Relation.has_new?(rel)
    end

    test "advance promotes new_rows to delta and total" do
      rel = Relation.new(1)
      rel = Relation.insert_new(rel, {:fact_1})
      rel = Relation.advance(rel)

      assert Relation.member?(rel, {:fact_1})
      assert {:fact_1} in Relation.delta_rows(rel)
      refute Relation.has_new?(rel)
    end

    test "seed_delta copies total to delta" do
      rel = Relation.new(1)
      rel = Relation.insert(rel, {:fact_1})
      rel = Relation.insert(rel, {:fact_2})
      rel = Relation.seed_delta(rel)

      deltas = Relation.delta_rows(rel)
      assert length(deltas) == 2
      assert {:fact_1} in deltas
      assert {:fact_2} in deltas
    end

    test "advance clears previous delta" do
      rel = Relation.new(1)
      rel = Relation.insert_new(rel, {:fact_1})
      rel = Relation.advance(rel)
      # fact_1 is now in delta.

      rel = Relation.insert_new(rel, {:fact_2})
      rel = Relation.advance(rel)
      # Now delta should only have fact_2.

      deltas = Relation.delta_rows(rel)
      assert deltas == [{:fact_2}]
    end

    test "multiple advance cycles" do
      rel = Relation.new(1)

      # Cycle 1: seed with initial facts.
      rel = Relation.insert(rel, {:a})
      rel = Relation.seed_delta(rel)
      assert length(Relation.delta_rows(rel)) == 1

      # Cycle 2: add new fact.
      rel = Relation.insert_new(rel, {:b})
      rel = Relation.advance(rel)
      assert Relation.delta_rows(rel) == [{:b}]
      assert Relation.size(rel) == 2

      # Cycle 3: no new facts.
      rel = Relation.advance(rel)
      assert Relation.delta_rows(rel) == []
    end
  end
end
