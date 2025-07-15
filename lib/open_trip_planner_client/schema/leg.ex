# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule OpenTripPlannerClient.Schema.Leg do
  @moduledoc """
  Part of an itinerary. Can represent a transit trip or a sequence of walking
  steps.

  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/Leg
  """

  use OpenTripPlannerClient.Schema

  alias OpenTripPlannerClient.PlanParams

  alias OpenTripPlannerClient.Schema.{
    Agency,
    Geometry,
    IntermediateStop,
    LegTime,
    Place,
    Route,
    Step,
    Trip
  }

  @realtime_state [
    :SCHEDULED,
    :UPDATED,
    :CANCELED,
    :ADDED,
    :MODIFIED
  ]

  @typedoc """
  A concise description of one or more `OpenTripPlannerClient.Schema.Leg`.
  """
  @type leg_summary :: %{walk_minutes: non_neg_integer(), routes: [Route.t()]}

  @typedoc """
  State of real-time data, if present.

  SCHEDULED The trip information comes from the GTFS feed, i.e. no real-time
  update has been applied.

  UPDATED The trip information has been updated, but the trip pattern stayed the
  same as the trip pattern of the scheduled trip.

  CANCELED The trip has been canceled by a real-time update.

  ADDED The trip has been added using a real-time update, i.e. the trip was not
  present in the GTFS feed.

  MODIFIED The trip information has been updated and resulted in a different
  trip pattern compared to the trip pattern of the scheduled trip.
  """
  @type realtime_state ::
          unquote(
            @realtime_state
            |> Enum.map_join(" | ", &inspect/1)
            |> Code.string_to_quoted!()
          )

  defimpl Nestru.PreDecoder do
    # credo:disable-for-next-line
    def gather_fields_for_decoding(_, _, map) do
      updated_map =
        map
        |> update_in([:intermediate_stops], &replace_nil_with_list/1)
        |> update_in([:steps], &replace_nil_with_list/1)

      {:ok, updated_map}
    end

    defp replace_nil_with_list(nil), do: []
    defp replace_nil_with_list(other), do: other
  end

  @derive {Nestru.Decoder,
           hint: %{
             agency: Agency,
             end: LegTime,
             from: Place,
             intermediate_stops: [IntermediateStop],
             leg_geometry: Geometry,
             mode: &__MODULE__.to_atom/1,
             realtime_state: &__MODULE__.to_atom/1,
             route: Route,
             start: LegTime,
             steps: [Step],
             trip: Trip,
             to: Place
           }}
  schema do
    field(:agency, Agency.t())
    field(:distance, distance_meters())
    field(:duration, duration_seconds())
    field(:end, LegTime.t(), @nonnull_field)
    field(:from, Place.t(), @nonnull_field)
    field(:headsign, String.t())
    field(:intermediate_stops, [IntermediateStop.t()])
    field(:leg_geometry, Geometry.t())
    field(:mode, PlanParams.mode_t())
    field(:real_time, boolean())
    field(:realtime_state, realtime_state())
    field(:route, Route.t())
    field(:start, LegTime.t(), @nonnull_field)
    field(:steps, [Step.t()])
    field(:transit_leg, boolean())
    field(:trip, Trip.t())
    field(:to, Place.t(), @nonnull_field)
  end

  @spec realtime_state :: [realtime_state()]
  def realtime_state, do: @realtime_state

  @spec to_atom(any()) :: {:ok, any()}
  def to_atom(string) when is_binary(string),
    do: {:ok, OpenTripPlannerClient.Util.to_existing_atom(string)}

  def to_atom(other), do: {:ok, other}

  @doc """
  To be grouped together, legs must share these characteristics:
  - Same transit agency
  - Same origin and destination
  - Same :transit_leg value (e.g. walking legs don't get grouped with transit legs)
  - Similar transit mode, where
      - rail replacement buses are treated independently
      - each subway line is treated independently
      - branches in a line can be grouped together (GL B/C/D/E, SL 1/2/3)
      - SL4/5 are grouped with buses
  """
  @spec group_identifier(__MODULE__.t()) :: tuple()
  def group_identifier(%__MODULE__{transit_leg: false} = leg) do
    {:WALK, leg.from.name, leg.to.name}
  end

  def group_identifier(%__MODULE__{agency: %Agency{name: agency_name}} = leg)
      when agency_name != "MBTA" do
    {agency_name, leg.from.name, leg.to.name}
  end

  def group_identifier(%__MODULE__{route: %Route{desc: "Rail Replacement Bus"}} = leg) do
    {:shuttle, leg.from.name, leg.to.name}
  end

  def group_identifier(%__MODULE__{route: %Route{type: type} = route} = leg)
      when type in [0, 1] do
    route_id = mbta_id(route)

    if String.starts_with?(route_id, "Green") do
      {:green_line, leg.from.name, leg.to.name}
    else
      {route_id, leg.from.name, leg.to.name}
    end
  end

  def group_identifier(%__MODULE__{route: %Route{type: 3} = route} = leg) do
    route_id = mbta_id(route)
    silver_line_rapid_transit_ids = ~w(741 742 743 746)

    if route_id in silver_line_rapid_transit_ids do
      {:silver_line, leg.from.name, leg.to.name}
    else
      {leg.route.type, leg.from.name, leg.to.name}
    end
  end

  def group_identifier(leg) do
    {leg.route.type, leg.from.name, leg.to.name}
  end

  defp mbta_id(%{gtfs_id: "mbta-ma-us:" <> id}), do: id
  defp mbta_id(%{gtfs_id: "mbta-ma-us-initial:" <> id}), do: id
  defp mbta_id(_), do: nil

  @doc """
  A concise desciption of a leg. Transit legs are described in terms of 
  routes, and walking legs in terms of duration in minutes.
  """
  @spec summary(__MODULE__.t()) :: leg_summary()
  def summary(%__MODULE__{duration: duration, transit_leg: false}) do
    minutes =
      duration
      |> Timex.Duration.to_minutes(:seconds)
      |> Kernel.round()
      |> Kernel.max(1)

    %{walk_minutes: minutes, routes: []}
  end

  def summary(%__MODULE__{route: route}) do
    %{walk_minutes: 0, routes: [route]}
  end

  @doc """
  Whether we consider this leg exceptionally short, in terms of distance.
  This is used to simplify display.
  """
  @spec short_walking_leg?(__MODULE__.t()) :: boolean()
  def short_walking_leg?(%__MODULE__{transit_leg: false, distance: meters}) do
    miles = Float.ceil(meters / 1609.34, 1)
    miles <= 0.2
  end

  def short_walking_leg?(_), do: false
end
