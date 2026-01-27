defmodule OpenTripPlannerClient.Schema.Geometry do
  @moduledoc """
  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/Geometry
  """

  use OpenTripPlannerClient.Schema

  @typedoc """
  List of coordinates of in a Google encoded polyline format (see
  https://developers.google.com/maps/documentation/utilities/polylinealgorithm)
  """
  @type polyline :: String.t()

  @derive Nestru.Decoder
  schema do
    @typedoc """
    * points - List of coordinates of in a Google encoded polyline format (see
      https://developers.google.com/maps/documentation/utilities/polylinealgorithm)
    """
    field(:points, polyline())
  end
end
