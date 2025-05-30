defmodule OpenTripPlannerClient.Schema.Route do
  @moduledoc """
  Route represents a public transportation service, usually from point A to
  point B and back, shown to customers under a single name, e.g. bus 550. Routes
  contain patterns, which describe different variants of the route, e.g.
  outbound pattern from point A to point B and inbound pattern from point B to
  point A.

  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/Route
  """

  use OpenTripPlannerClient.Schema

  alias OpenTripPlannerClient.PlanParams
  alias OpenTripPlannerClient.Schema.Agency

  @typedoc """
  Short name of the route, e.g. SL4
  """
  @type short_name :: String.t()

  @typedoc """
  Long name of the route, e.g. Nubian Station - South Station
  """
  @type long_name :: String.t()

  @typedoc """
  Description of the route, e.g. "Rail Replacement Bus"
  """
  @type desc :: String.t()

  @gtfs_route_type [0, 1, 2, 3, 4, 5, 6, 7, 11, 12]

  @typedoc """
  The raw GTFS route type as a integer.

  https://gtfs.org/schedule/reference/#routestxt
  """
  @type gtfs_route_type ::
          unquote(
            @gtfs_route_type
            |> Enum.map_join(" | ", &inspect/1)
            |> Code.string_to_quoted!()
          )

  @typedoc """
  A color encoded as a six-digit hexadecimal number.
  """
  @type hex_color :: String.t()

  @derive {Nestru.Decoder, hint: %{agency: Agency, mode: &__MODULE__.to_atom/1}}
  schema do
    field(:gtfs_id, gtfs_id(), @nonnull_field)
    field(:short_name, short_name())
    field(:long_name, long_name())
    field(:type, gtfs_route_type())
    field(:color, hex_color())
    field(:text_color, hex_color())
    field(:desc, desc())
    field(:sort_order, non_neg_integer())
    field(:mode, PlanParams.mode_t())
    field(:agency, Agency.t())
  end

  @spec gtfs_route_type :: [gtfs_route_type()]
  def gtfs_route_type, do: @gtfs_route_type

  @spec to_atom(any()) :: {:ok, any()}
  def to_atom(string) when is_binary(string),
    do: {:ok, OpenTripPlannerClient.Util.to_existing_atom(string)}

  def to_atom(other), do: {:ok, other}
end
