defmodule OpenTripPlannerClient.Schema.Itinerary do
  @moduledoc """
  Details regarding a single planned journey.

  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/Itinerary
  """
  use OpenTripPlannerClient.Schema

  alias OpenTripPlannerClient.Schema.Leg

  @typedoc """
  Computes a numeric accessibility score between 0 and 1.

  The closer the value is to 1 the better the wheelchair-accessibility of this
  itinerary is. A value of null means that no score has been computed, not that
  the leg is inaccessible.
  """
  @type accessibility_score :: float() | nil

  @short_walk_threshold_minutes 5

  @derive {Nestru.Decoder, hint: %{end: DateTime, legs: [Leg], start: DateTime}}
  schema do
    field(:accessibility_score, accessibility_score())
    field(:generalized_cost, non_neg_integer())
    field(:duration, duration_seconds())
    field(:end, offset_datetime())
    field(:legs, [Leg.t()], @nonnull_field)
    field(:number_of_transfers, non_neg_integer(), @nonnull_field)
    field(:start, offset_datetime())
    field(:walk_distance, distance_meters())
  end

  @doc """
   Is the itinerary accessible? It's mostly a straightforward matter
   of whether its accessibility score is equal to 1, but the MBTA also
   considers any trips on its bus fleet accessible, regardless of
   accessibility-impacting particularities of individual bus stops.
  """
  @spec accessible?(__MODULE__.t()) :: boolean() | nil
  def accessible?(%__MODULE__{accessibility_score: nil}), do: nil
  def accessible?(%__MODULE__{accessibility_score: 1.0}), do: true

  def accessible?(%__MODULE__{legs: legs}) do
    all_mbta_bus_legs?(legs)
  end

  defp all_mbta_bus_legs?(legs) do
    legs
    |> Enum.filter(& &1.transit_leg)
    |> Enum.all?(&(&1.route.type == 3 && &1.agency.name == "MBTA"))
  end

  @doc """
  To be grouped together, itineraries must share these characteristics:
  - Same accessible? value
  - Same grouped legs*
    - Disregarding very short walking legs up to 0.2 mi
  """
  @spec group_identifier(__MODULE__.t()) :: tuple()
  def group_identifier(itinerary) do
    leg_groups =
      itinerary.legs
      |> Enum.reject(&short_walking_leg?/1)
      |> Enum.map(&Leg.group_identifier/1)

    {accessible?(itinerary), leg_groups}
  end

  defp short_walking_leg?(%Leg{transit_leg: false, distance: meters}) do
    miles = Float.ceil(meters / 1609.34, 1)
    miles <= 0.2
  end

  defp short_walking_leg?(_), do: false

  @doc """
  A series of `Leg.summary/1` for an itinerary, simplified further to 
  omit very short intermediate walking legs.
  """
  @spec summary(__MODULE__.t()) :: [Leg.leg_summary()]
  def summary(%__MODULE__{legs: legs}) do
    legs
    |> Enum.map(&Leg.summary/1)
    |> drop_short_intermediate_walking_legs()
  end

  # Drops intermediate entries in `legs` that have walking times of # under
  # five minutes. Intermediate in this context means that it # will keep the
  # first and last entries, even if those are short # walking legs, but will
  # drop ones in the middle.
  defp drop_short_intermediate_walking_legs([first_leg | rest_of_legs]) do
    [first_leg | drop_short_walking_legs(rest_of_legs)]
  end

  # Drops short walking legs from the given list, except for the last # item,
  # which it keeps regardless.
  defp drop_short_walking_legs([leg]), do: [leg]
  defp drop_short_walking_legs([]), do: []

  defp drop_short_walking_legs([%{routes: [], walk_minutes: minutes} | rest_of_legs])
       when minutes < @short_walk_threshold_minutes,
       do: drop_short_walking_legs(rest_of_legs)

  defp drop_short_walking_legs([first_leg | rest_of_legs]),
    do: [first_leg | drop_short_walking_legs(rest_of_legs)]
end
