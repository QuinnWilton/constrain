defmodule Constrain.Generators do
  @moduledoc """
  StreamData generators for predicates, expressions, and intervals.
  """

  use ExUnitProperties

  alias Constrain.Domain.Interval

  @type_tags [
    :integer,
    :float,
    :number,
    :atom,
    :boolean,
    nil,
    :binary,
    :bitstring,
    :list,
    :tuple,
    :map,
    :struct,
    :pid,
    :port,
    :reference,
    :function
  ]

  @comparison_ops [:eq, :neq, :strict_eq, :strict_neq, :lt, :gt, :lte, :gte]

  @doc """
  Generates variable names.
  """
  def var_name do
    member_of([:x, :y, :z, :a, :b, :c, :n, :m])
  end

  @doc """
  Generates variable expressions.
  """
  def var_expr do
    map(var_name(), fn name -> {:var, name} end)
  end

  @doc """
  Generates literal expressions (small integers and atoms).
  """
  def lit_expr do
    one_of([
      map(integer(-100..100), fn n -> {:lit, n} end),
      map(member_of([:ok, :error, true, false, nil]), fn a -> {:lit, a} end)
    ])
  end

  @doc """
  Generates simple expressions (variables or literals).
  """
  def simple_expr do
    one_of([var_expr(), lit_expr()])
  end

  @doc """
  Generates type tags.
  """
  def type_tag do
    member_of(@type_tags)
  end

  @doc """
  Generates comparison predicates.
  """
  def comparison_pred do
    gen all(
          op <- member_of(@comparison_ops),
          lhs <- simple_expr(),
          rhs <- simple_expr()
        ) do
      {op, lhs, rhs}
    end
  end

  @doc """
  Generates type check predicates.
  """
  def type_pred do
    gen all(
          tag <- type_tag(),
          expr <- var_expr()
        ) do
      {:is_type, tag, expr}
    end
  end

  @doc """
  Generates simple predicates (no logical connectives).
  """
  def simple_pred do
    one_of([comparison_pred(), type_pred()])
  end

  @doc """
  Generates predicates, potentially with conjunctions.
  """
  def predicate do
    one_of([
      simple_pred(),
      map({simple_pred(), simple_pred()}, fn {p, q} -> {:and, p, q} end),
      map({simple_pred(), simple_pred()}, fn {p, q} -> {:or, p, q} end)
    ])
  end

  @doc """
  Generates a list of simple predicates (facts for the solver).
  """
  def fact_list do
    list_of(simple_pred(), min_length: 1, max_length: 5)
  end

  @doc """
  Generates finite intervals.
  """
  def finite_interval do
    gen all(
          a <- integer(-100..100),
          b <- integer(0..100),
          lo_inc <- boolean(),
          hi_inc <- boolean()
        ) do
      # Construct a valid interval by using a + b as hi, guaranteeing lo <= hi.
      %Interval{lo: a, hi: a + b, lo_inclusive: lo_inc, hi_inclusive: hi_inc}
    end
  end

  @doc """
  Generates intervals (possibly unbounded).
  """
  def interval do
    one_of([
      finite_interval(),
      map(integer(-100..100), &Interval.gt/1),
      map(integer(-100..100), &Interval.gte/1),
      map(integer(-100..100), &Interval.lt/1),
      map(integer(-100..100), &Interval.lte/1),
      constant(Interval.top()),
      map(integer(-100..100), &Interval.point/1)
    ])
  end
end
