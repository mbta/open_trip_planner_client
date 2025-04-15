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

  @derive {Nestru.Decoder, hint: %{end: DateTime, legs: [Leg], start: DateTime}}
  schema do
    field(:accessibility_score, accessibility_score())
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
    all_mbta_legs?(legs)
  end

  defp all_mbta_legs?(legs) do
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
  @spec group_identifier(__MODULE__.t()) :: Tuple.t()
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
end
