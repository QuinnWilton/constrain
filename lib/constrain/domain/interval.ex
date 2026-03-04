defmodule Constrain.Domain.Interval do
  @moduledoc """
  Interval arithmetic for numeric constraint propagation.

  Intervals represent bounded ranges of numbers with inclusive/exclusive endpoints.
  The solver uses intervals to track numeric bounds as comparison predicates are
  derived, enabling contradiction detection (e.g., x > 5 and x < 3).

  Intervals only shrink (via `meet/2`), guaranteeing termination of the fixpoint.
  """

  @type bound :: :neg_inf | :pos_inf | number()

  @type t :: %__MODULE__{
          lo: bound(),
          hi: bound(),
          lo_inclusive: boolean(),
          hi_inclusive: boolean()
        }

  @enforce_keys [:lo, :hi]
  defstruct lo: :neg_inf, hi: :pos_inf, lo_inclusive: false, hi_inclusive: false

  @doc """
  Returns the universal interval (-inf, +inf).
  """
  @spec top() :: t()
  def top, do: %__MODULE__{lo: :neg_inf, hi: :pos_inf}

  @doc """
  Returns a point interval [n, n].
  """
  @spec point(number()) :: t()
  def point(n) when is_number(n) do
    %__MODULE__{lo: n, hi: n, lo_inclusive: true, hi_inclusive: true}
  end

  @doc """
  Returns the interval (lo, +inf).
  """
  @spec gt(number()) :: t()
  def gt(n) when is_number(n) do
    %__MODULE__{lo: n, hi: :pos_inf, lo_inclusive: false, hi_inclusive: false}
  end

  @doc """
  Returns the interval [lo, +inf).
  """
  @spec gte(number()) :: t()
  def gte(n) when is_number(n) do
    %__MODULE__{lo: n, hi: :pos_inf, lo_inclusive: true, hi_inclusive: false}
  end

  @doc """
  Returns the interval (-inf, hi).
  """
  @spec lt(number()) :: t()
  def lt(n) when is_number(n) do
    %__MODULE__{lo: :neg_inf, hi: n, lo_inclusive: false, hi_inclusive: false}
  end

  @doc """
  Returns the interval (-inf, hi].
  """
  @spec lte(number()) :: t()
  def lte(n) when is_number(n) do
    %__MODULE__{lo: :neg_inf, hi: n, lo_inclusive: false, hi_inclusive: true}
  end

  @doc """
  Returns whether the interval is empty (no values satisfy it).
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{lo: lo, hi: hi, lo_inclusive: lo_inc, hi_inclusive: hi_inc}) do
    cond do
      lo == :neg_inf or hi == :pos_inf -> false
      lo > hi -> true
      lo == hi -> not (lo_inc and hi_inc)
      true -> false
    end
  end

  @doc """
  Returns whether a value is contained in the interval.
  """
  @spec contains?(t(), number()) :: boolean()
  def contains?(%__MODULE__{} = interval, n) when is_number(n) do
    lo_ok =
      case interval.lo do
        :neg_inf -> true
        lo when interval.lo_inclusive -> n >= lo
        lo -> n > lo
      end

    hi_ok =
      case interval.hi do
        :pos_inf -> true
        hi when interval.hi_inclusive -> n <= hi
        hi -> n < hi
      end

    lo_ok and hi_ok
  end

  @doc """
  Computes the intersection (meet) of two intervals.

  The result is the tightest interval that is contained in both inputs.
  This is the only operation the solver uses to update intervals, guaranteeing
  that intervals only shrink and the fixpoint terminates.
  """
  @spec meet(t(), t()) :: t()
  def meet(%__MODULE__{} = a, %__MODULE__{} = b) do
    {lo, lo_inc} = max_bound(a.lo, a.lo_inclusive, b.lo, b.lo_inclusive, :lo)
    {hi, hi_inc} = min_bound(a.hi, a.hi_inclusive, b.hi, b.hi_inclusive, :hi)
    %__MODULE__{lo: lo, hi: hi, lo_inclusive: lo_inc, hi_inclusive: hi_inc}
  end

  @doc """
  Computes the union (join) of two intervals.

  Returns the smallest interval containing both inputs.
  """
  @spec join(t(), t()) :: t()
  def join(%__MODULE__{} = a, %__MODULE__{} = b) do
    {lo, lo_inc} = min_bound(a.lo, a.lo_inclusive, b.lo, b.lo_inclusive, :lo)
    {hi, hi_inc} = max_bound(a.hi, a.hi_inclusive, b.hi, b.hi_inclusive, :hi)
    %__MODULE__{lo: lo, hi: hi, lo_inclusive: lo_inc, hi_inclusive: hi_inc}
  end

  @doc """
  Adds two intervals: [a.lo + b.lo, a.hi + b.hi].
  """
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      lo: add_bounds(a.lo, b.lo),
      hi: add_bounds(a.hi, b.hi),
      lo_inclusive: a.lo_inclusive and b.lo_inclusive,
      hi_inclusive: a.hi_inclusive and b.hi_inclusive
    }
  end

  @doc """
  Negates an interval: [-hi, -lo].
  """
  @spec negate(t()) :: t()
  def negate(%__MODULE__{} = a) do
    %__MODULE__{
      lo: negate_bound(a.hi),
      hi: negate_bound(a.lo),
      lo_inclusive: a.hi_inclusive,
      hi_inclusive: a.lo_inclusive
    }
  end

  @doc """
  Subtracts two intervals: a - b = a + (-b).
  """
  @spec sub(t(), t()) :: t()
  def sub(%__MODULE__{} = a, %__MODULE__{} = b) do
    add(a, negate(b))
  end

  @doc """
  Multiplies two intervals.

  Uses the four-product method to handle sign changes.
  """
  @spec mul(t(), t()) :: t()
  def mul(%__MODULE__{} = a, %__MODULE__{} = b) do
    products = [
      {mul_bounds(a.lo, b.lo), a.lo_inclusive and b.lo_inclusive},
      {mul_bounds(a.lo, b.hi), a.lo_inclusive and b.hi_inclusive},
      {mul_bounds(a.hi, b.lo), a.hi_inclusive and b.lo_inclusive},
      {mul_bounds(a.hi, b.hi), a.hi_inclusive and b.hi_inclusive}
    ]

    {lo, lo_inc} = Enum.min_by(products, &elem(&1, 0), fn -> {:neg_inf, false} end)
    {hi, hi_inc} = Enum.max_by(products, &elem(&1, 0), fn -> {:pos_inf, false} end)

    %__MODULE__{lo: lo, hi: hi, lo_inclusive: lo_inc, hi_inclusive: hi_inc}
  end

  # max_bound: pick the larger bound.
  # For :lo (meet), equal bounds use AND on inclusiveness (tighter).
  # For :hi (join), equal bounds use OR on inclusiveness (wider).
  defp max_bound(:neg_inf, _a_inc, b, b_inc, :lo), do: {b, b_inc}
  defp max_bound(a, a_inc, :neg_inf, _b_inc, :lo), do: {a, a_inc}

  defp max_bound(a, a_inc, b, b_inc, :lo) do
    cond do
      a > b -> {a, a_inc}
      b > a -> {b, b_inc}
      true -> {a, a_inc and b_inc}
    end
  end

  defp max_bound(:pos_inf, _a_inc, _b, _b_inc, :hi), do: {:pos_inf, false}
  defp max_bound(_a, _a_inc, :pos_inf, _b_inc, :hi), do: {:pos_inf, false}

  defp max_bound(a, a_inc, b, b_inc, :hi) do
    cond do
      a > b -> {a, a_inc}
      b > a -> {b, b_inc}
      true -> {a, a_inc or b_inc}
    end
  end

  # min_bound: pick the smaller bound.
  # For :hi (meet), equal bounds use AND on inclusiveness (tighter).
  # For :lo (join), equal bounds use OR on inclusiveness (wider).
  defp min_bound(:pos_inf, _a_inc, b, b_inc, :hi), do: {b, b_inc}
  defp min_bound(a, a_inc, :pos_inf, _b_inc, :hi), do: {a, a_inc}

  defp min_bound(a, a_inc, b, b_inc, :hi) do
    cond do
      a < b -> {a, a_inc}
      b < a -> {b, b_inc}
      true -> {a, a_inc and b_inc}
    end
  end

  defp min_bound(:neg_inf, _a_inc, _b, _b_inc, :lo), do: {:neg_inf, false}
  defp min_bound(_a, _a_inc, :neg_inf, _b_inc, :lo), do: {:neg_inf, false}

  defp min_bound(a, a_inc, b, b_inc, :lo) do
    cond do
      a < b -> {a, a_inc}
      b < a -> {b, b_inc}
      true -> {a, a_inc or b_inc}
    end
  end

  defp add_bounds(:neg_inf, _), do: :neg_inf
  defp add_bounds(_, :neg_inf), do: :neg_inf
  defp add_bounds(:pos_inf, _), do: :pos_inf
  defp add_bounds(_, :pos_inf), do: :pos_inf
  defp add_bounds(a, b), do: a + b

  defp negate_bound(:neg_inf), do: :pos_inf
  defp negate_bound(:pos_inf), do: :neg_inf
  defp negate_bound(n), do: -n

  defp mul_bounds(:neg_inf, b) when is_number(b) and b > 0, do: :neg_inf
  defp mul_bounds(:neg_inf, b) when is_number(b) and b < 0, do: :pos_inf
  defp mul_bounds(:neg_inf, 0), do: 0
  defp mul_bounds(:neg_inf, :pos_inf), do: :neg_inf
  defp mul_bounds(:neg_inf, :neg_inf), do: :pos_inf
  defp mul_bounds(:pos_inf, b) when is_number(b) and b > 0, do: :pos_inf
  defp mul_bounds(:pos_inf, b) when is_number(b) and b < 0, do: :neg_inf
  defp mul_bounds(:pos_inf, 0), do: 0
  defp mul_bounds(:pos_inf, :pos_inf), do: :pos_inf
  defp mul_bounds(:pos_inf, :neg_inf), do: :neg_inf
  defp mul_bounds(a, :neg_inf) when is_number(a), do: mul_bounds(:neg_inf, a)
  defp mul_bounds(a, :pos_inf) when is_number(a), do: mul_bounds(:pos_inf, a)
  defp mul_bounds(a, b) when is_number(a) and is_number(b), do: a * b
end
