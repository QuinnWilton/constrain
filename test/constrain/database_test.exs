defmodule Constrain.DatabaseTest do
  use ExUnit.Case, async: true

  alias Constrain.Database
  alias Constrain.Domain.Interval

  describe "new/0" do
    test "creates empty database" do
      db = Database.new()
      assert Database.size(db) == 0
      assert Database.facts(db) == []
      refute db.contradiction
    end
  end

  describe "insert/2" do
    test "inserts a fact" do
      db = Database.new()
      db = Database.insert(db, {:is_type, :integer, {:var, :x}})
      assert Database.has_new?(db)
    end

    test "inserting :true is a no-op" do
      db = Database.new()
      db = Database.insert(db, true)
      assert Database.size(db) == 0
    end

    test "inserting :false sets contradiction" do
      db = Database.new()
      db = Database.insert(db, false)
      assert db.contradiction
    end

    test "updates type index on is_type" do
      db = Database.new()
      db = Database.insert(db, {:is_type, :integer, {:var, :x}})
      types = Database.types_for(db, :x)
      assert MapSet.member?(types, :integer)
    end

    test "updates interval on gt" do
      db = Database.new()
      db = Database.insert(db, {:gt, {:var, :x}, {:lit, 5}})
      interval = Database.interval_for(db, :x)
      assert interval.lo == 5
      refute interval.lo_inclusive
    end

    test "updates interval on lte" do
      db = Database.new()
      db = Database.insert(db, {:lte, {:var, :x}, {:lit, 10}})
      interval = Database.interval_for(db, :x)
      assert interval.hi == 10
      assert interval.hi_inclusive
    end

    test "detects contradiction from empty interval" do
      db = Database.new()
      db = Database.insert(db, {:gt, {:var, :x}, {:lit, 10}})
      db = Database.insert(db, {:lt, {:var, :x}, {:lit, 5}})
      assert db.contradiction
    end

    test "narrowing intervals with consistent bounds" do
      db = Database.new()
      db = Database.insert(db, {:gt, {:var, :x}, {:lit, 0}})
      db = Database.insert(db, {:lt, {:var, :x}, {:lit, 100}})
      interval = Database.interval_for(db, :x)
      assert interval.lo == 0
      assert interval.hi == 100
      refute Interval.empty?(interval)
      refute db.contradiction
    end

    test "handles symmetric comparison (literal on left)" do
      db = Database.new()
      db = Database.insert(db, {:gt, {:lit, 10}, {:var, :x}})
      # 10 > x means x < 10.
      interval = Database.interval_for(db, :x)
      assert interval.hi == 10
      refute interval.hi_inclusive
    end

    test "eq narrows to point interval" do
      db = Database.new()
      db = Database.insert(db, {:eq, {:var, :x}, {:lit, 42}})
      interval = Database.interval_for(db, :x)
      assert interval == Interval.point(42)
    end
  end

  describe "member?/2" do
    test "reports membership after advance" do
      db = Database.new()
      db = Database.insert(db, {:is_type, :integer, {:var, :x}})
      db = Database.advance(db)
      assert Database.member?(db, {:is_type, :integer, {:var, :x}})
    end

    test "new facts are not in total until advance" do
      db = Database.new()
      db = Database.insert(db, {:is_type, :integer, {:var, :x}})
      refute Database.member?(db, {:is_type, :integer, {:var, :x}})
    end
  end

  describe "semi-naive" do
    test "seed_delta and advance cycle" do
      db = Database.new()
      db = Database.insert(db, {:is_type, :integer, {:var, :x}})
      db = Database.advance(db)
      db = Database.seed_delta(db)

      deltas = Database.delta_facts(db)
      assert {:is_type, :integer, {:var, :x}} in deltas
    end
  end

  describe "interval_for/2" do
    test "returns top for unknown variable" do
      db = Database.new()
      interval = Database.interval_for(db, :unknown)
      assert interval == Interval.top()
    end
  end

  describe "types_for/2" do
    test "returns empty set for unknown variable" do
      db = Database.new()
      types = Database.types_for(db, :unknown)
      assert types == MapSet.new()
    end

    test "accumulates multiple types" do
      db = Database.new()
      db = Database.insert(db, {:is_type, :integer, {:var, :x}})
      db = Database.insert(db, {:is_type, :number, {:var, :x}})
      types = Database.types_for(db, :x)
      assert MapSet.member?(types, :integer)
      assert MapSet.member?(types, :number)
    end
  end
end
