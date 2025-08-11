defmodule OpenTripPlannerClient.Schema.Stop do
  @moduledoc """
  Stop can represent either a single public transport stop, where passengers can board and/or disembark vehicles, or a station, which contains multiple stops.

  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/Stop
  """

  use OpenTripPlannerClient.Schema

  alias OpenTripPlannerClient.PlanParams
  alias OpenTripPlannerClient.Schema.ParentStop

  @typedoc "Transport mode (e.g. BUS) used by routes which pass through this stop"
  @type vehicle_mode :: PlanParams.mode_t()

  @wheelchair_boarding [:NOT_POSSIBLE, :NO_INFORMATION, :POSSIBLE]

  @typedoc """
  Whether wheelchair boarding is possible for at least some of vehicles on this stop
  """
  @type wheelchair_boarding ::
          unquote(
            @wheelchair_boarding
            |> Enum.map_join(" | ", &inspect/1)
            |> Code.string_to_quoted!()
          )

  @typedoc "ID of the zone where this stop is located"
  @type zone_id :: String.t()

  defimpl Nestru.PreDecoder do
    # credo:disable-for-next-line
    def gather_fields_for_decoding(_, _, map) do
      updated_map =
        map
        |> update_in(["wheelchair_boarding"], &OpenTripPlannerClient.Util.to_uppercase_atom/1)

      {:ok, updated_map}
    end
  end

  @derive {Nestru.Decoder,
           hint: %{
             parent_station: ParentStop,
             wheelchair_boarding: &__MODULE__.to_atom/1
           }}
  schema do
    field(:gtfs_id, gtfs_id(), @nonnull_field)
    field(:name, String.t())
    field(:url, String.t())
    field(:vehicle_mode, PlanParams.mode_t())
    field(:wheelchair_boarding, wheelchair_boarding())
    field(:zone_id, zone_id())
    field(:parent_station, ParentStop.t())
  end

  @spec wheelchair_boarding :: [wheelchair_boarding()]
  def wheelchair_boarding, do: @wheelchair_boarding

  @spec to_atom(any()) :: {:ok, any()}
  def to_atom(term), do: {:ok, OpenTripPlannerClient.Util.to_uppercase_atom(term)}
end

defmodule OpenTripPlannerClient.Schema.ParentStop do
  @moduledoc """
  A subset of fields for `OpenTripPlannerClient.Schema.Stop`
  """

  use OpenTripPlannerClient.Schema

  @derive Nestru.Decoder
  schema do
    field(:gtfs_id, gtfs_id(), @nonnull_field)
  end
end

defmodule OpenTripPlannerClient.Schema.IntermediateStop do
  @moduledoc """
  A subset of fields for `OpenTripPlannerClient.Schema.Stop`
  """

  use OpenTripPlannerClient.Schema

  @derive Nestru.Decoder
  schema do
    field(:name, String.t())
  end
end
