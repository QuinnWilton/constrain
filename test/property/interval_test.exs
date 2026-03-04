defmodule Constrain.Property.IntervalTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Constrain.Domain.Interval
  alias Constrain.Generators

  describe "meet" do
    property "meet is commutative" do
      check all(
              a <- Generators.interval(),
              b <- Generators.interval()
            ) do
        result_ab = Interval.meet(a, b)
        result_ba = Interval.meet(b, a)
        assert result_ab == result_ba
      end
    end

    property "meet is associative" do
      check all(
              a <- Generators.interval(),
              b <- Generators.interval(),
              c <- Generators.interval()
            ) do
        result_1 = Interval.meet(Interval.meet(a, b), c)
        result_2 = Interval.meet(a, Interval.meet(b, c))
        assert result_1 == result_2
      end
    end

    property "meet with top is identity" do
      check all(a <- Generators.interval()) do
        assert Interval.meet(a, Interval.top()) == a
        assert Interval.meet(Interval.top(), a) == a
      end
    end

    property "meet is idempotent" do
      check all(a <- Generators.interval()) do
        assert Interval.meet(a, a) == a
      end
    end

    property "meet only narrows: if n is in meet(a,b) then n is in both a and b" do
      check all(
              a <- Generators.finite_interval(),
              b <- Generators.finite_interval(),
              n <- integer(-200..200)
            ) do
        result = Interval.meet(a, b)

        if Interval.contains?(result, n) do
          assert Interval.contains?(a, n)
          assert Interval.contains?(b, n)
        end
      end
    end
  end

  describe "join" do
    property "join is commutative" do
      check all(
              a <- Generators.interval(),
              b <- Generators.interval()
            ) do
        assert Interval.join(a, b) == Interval.join(b, a)
      end
    end

    property "join only widens: if n is in a then n is in join(a,b)" do
      check all(
              a <- Generators.finite_interval(),
              b <- Generators.finite_interval(),
              n <- integer(-200..200)
            ) do
        if Interval.contains?(a, n) do
          assert Interval.contains?(Interval.join(a, b), n)
        end
      end
    end
  end

  describe "arithmetic" do
    property "add with zero interval is identity" do
      check all(a <- Generators.finite_interval()) do
        zero = Interval.point(0)
        result = Interval.add(a, zero)
        assert result.lo == a.lo
        assert result.hi == a.hi
      end
    end

    property "negate is self-inverse" do
      check all(a <- Generators.finite_interval()) do
        assert Interval.negate(Interval.negate(a)) == a
      end
    end

    property "sub is add with negate" do
      check all(
              a <- Generators.finite_interval(),
              b <- Generators.finite_interval()
            ) do
        assert Interval.sub(a, b) == Interval.add(a, Interval.negate(b))
      end
    end
  end
end
