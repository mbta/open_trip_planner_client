defmodule OpenTripPlannerClient.Schema.Trip do
  @moduledoc """
  Trip is a specific occurance of a pattern, usually identified by route,
  direction on the route and exact departure time.

  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/Trip
  """

  use OpenTripPlannerClient.Schema

  @derive Nestru.Decoder
  schema do
    field(:gtfs_id, gtfs_id(), @nonnull_field)
    field(:trip_headsign, String.t())
    field(:trip_short_name, String.t())
  end
end
