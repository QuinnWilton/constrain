defmodule Constrain.Domain.IntervalTest do
  use ExUnit.Case, async: true

  alias Constrain.Domain.Interval

  describe "constructors" do
    test "top is universal" do
      i = Interval.top()
      assert i.lo == :neg_inf
      assert i.hi == :pos_inf
    end

    test "point interval" do
      i = Interval.point(5)
      assert i.lo == 5
      assert i.hi == 5
      assert i.lo_inclusive
      assert i.hi_inclusive
    end

    test "gt creates open lower bound" do
      i = Interval.gt(3)
      assert i.lo == 3
      assert i.hi == :pos_inf
      refute i.lo_inclusive
    end

    test "gte creates closed lower bound" do
      i = Interval.gte(3)
      assert i.lo == 3
      assert i.hi == :pos_inf
      assert i.lo_inclusive
    end

    test "lt creates open upper bound" do
      i = Interval.lt(7)
      assert i.lo == :neg_inf
      assert i.hi == 7
      refute i.hi_inclusive
    end

    test "lte creates closed upper bound" do
      i = Interval.lte(7)
      assert i.lo == :neg_inf
      assert i.hi == 7
      assert i.hi_inclusive
    end
  end

  describe "empty?/1" do
    test "top is not empty" do
      refute Interval.empty?(Interval.top())
    end

    test "point is not empty" do
      refute Interval.empty?(Interval.point(5))
    end

    test "inverted bounds are empty" do
      i = %Interval{lo: 10, hi: 5, lo_inclusive: true, hi_inclusive: true}
      assert Interval.empty?(i)
    end

    test "exclusive point is empty" do
      i = %Interval{lo: 5, hi: 5, lo_inclusive: false, hi_inclusive: true}
      assert Interval.empty?(i)
    end

    test "half-open equal bounds are empty" do
      i = %Interval{lo: 5, hi: 5, lo_inclusive: true, hi_inclusive: false}
      assert Interval.empty?(i)
    end

    test "open interval at same point is empty" do
      i = %Interval{lo: 5, hi: 5, lo_inclusive: false, hi_inclusive: false}
      assert Interval.empty?(i)
    end
  end

  describe "contains?/2" do
    test "top contains everything" do
      assert Interval.contains?(Interval.top(), 42)
      assert Interval.contains?(Interval.top(), -100)
      assert Interval.contains?(Interval.top(), 0.5)
    end

    test "point contains only its value" do
      assert Interval.contains?(Interval.point(5), 5)
      refute Interval.contains?(Interval.point(5), 4)
      refute Interval.contains?(Interval.point(5), 6)
    end

    test "gt excludes boundary" do
      i = Interval.gt(3)
      refute Interval.contains?(i, 3)
      assert Interval.contains?(i, 4)
      assert Interval.contains?(i, 3.1)
    end

    test "gte includes boundary" do
      i = Interval.gte(3)
      assert Interval.contains?(i, 3)
      assert Interval.contains?(i, 4)
      refute Interval.contains?(i, 2)
    end

    test "lt excludes boundary" do
      i = Interval.lt(7)
      refute Interval.contains?(i, 7)
      assert Interval.contains?(i, 6)
    end

    test "lte includes boundary" do
      i = Interval.lte(7)
      assert Interval.contains?(i, 7)
      refute Interval.contains?(i, 8)
    end
  end

  describe "meet/2" do
    test "meet with top is identity" do
      i = Interval.gt(3)
      assert Interval.meet(i, Interval.top()) == i
      assert Interval.meet(Interval.top(), i) == i
    end

    test "meet narrows bounds" do
      a = Interval.gt(3)
      b = Interval.lt(10)
      result = Interval.meet(a, b)
      assert result.lo == 3
      assert result.hi == 10
      refute result.lo_inclusive
      refute result.hi_inclusive
    end

    test "meet of disjoint intervals is empty" do
      a = Interval.gt(10)
      b = Interval.lt(5)
      result = Interval.meet(a, b)
      assert Interval.empty?(result)
    end

    test "meet with equal exclusive bounds is empty" do
      a = Interval.gt(5)
      b = Interval.lt(5)
      result = Interval.meet(a, b)
      assert Interval.empty?(result)
    end

    test "meet preserves inclusiveness correctly" do
      a = Interval.gte(5)
      b = Interval.lte(5)
      result = Interval.meet(a, b)
      assert result == Interval.point(5)
    end
  end

  describe "join/2" do
    test "join with top is top" do
      i = Interval.gt(3)
      result = Interval.join(i, Interval.top())
      assert result.lo == :neg_inf
      assert result.hi == :pos_inf
    end

    test "join widens bounds" do
      a = Interval.gt(3)
      b = Interval.gt(7)
      result = Interval.join(a, b)
      assert result.lo == 3
      refute result.lo_inclusive
    end

    test "join of overlapping intervals" do
      a = %Interval{lo: 1, hi: 5, lo_inclusive: true, hi_inclusive: true}
      b = %Interval{lo: 3, hi: 8, lo_inclusive: true, hi_inclusive: true}
      result = Interval.join(a, b)
      assert result.lo == 1
      assert result.hi == 8
      assert result.lo_inclusive
      assert result.hi_inclusive
    end
  end

  describe "arithmetic" do
    test "add intervals" do
      a = %Interval{lo: 1, hi: 3, lo_inclusive: true, hi_inclusive: true}
      b = %Interval{lo: 2, hi: 4, lo_inclusive: true, hi_inclusive: true}
      result = Interval.add(a, b)
      assert result.lo == 3
      assert result.hi == 7
    end

    test "negate interval" do
      a = %Interval{lo: 1, hi: 3, lo_inclusive: true, hi_inclusive: false}
      result = Interval.negate(a)
      assert result.lo == -3
      assert result.hi == -1
      assert result.lo_inclusive == false
      assert result.hi_inclusive == true
    end

    test "sub intervals" do
      a = %Interval{lo: 5, hi: 10, lo_inclusive: true, hi_inclusive: true}
      b = %Interval{lo: 1, hi: 3, lo_inclusive: true, hi_inclusive: true}
      result = Interval.sub(a, b)
      assert result.lo == 2
      assert result.hi == 9
    end

    test "mul positive intervals" do
      a = %Interval{lo: 2, hi: 3, lo_inclusive: true, hi_inclusive: true}
      b = %Interval{lo: 4, hi: 5, lo_inclusive: true, hi_inclusive: true}
      result = Interval.mul(a, b)
      assert result.lo == 8
      assert result.hi == 15
    end

    test "mul with negative interval" do
      a = %Interval{lo: -2, hi: 3, lo_inclusive: true, hi_inclusive: true}
      b = %Interval{lo: 1, hi: 4, lo_inclusive: true, hi_inclusive: true}
      result = Interval.mul(a, b)
      assert result.lo == -8
      assert result.hi == 12
    end
  end
end
