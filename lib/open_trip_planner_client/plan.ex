defmodule OpenTripPlannerClient.Plan do
  @moduledoc """
  Data type returned by the plan query.
  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/Plan
  """

  use OpenTripPlannerClient.Schema

  alias OpenTripPlannerClient.Plan.RoutingError
  alias OpenTripPlannerClient.Schema.Itinerary

  defimpl Nestru.PreDecoder do
    # credo:disable-for-next-line
    def gather_fields_for_decoding(_, _, map) do
      updated_map =
        map
        |> update_in(["routing_errors"], &replace_nil_with_list/1)
        |> update_in(["itineraries"], &replace_nil_with_list/1)
        |> update_in(["itineraries"], fn edges -> Enum.map(edges, &unwrap_node/1) end)

      {:ok, updated_map}
    end

    defp replace_nil_with_list(nil), do: []
    defp replace_nil_with_list(other), do: other

    defp unwrap_node(%{"node" => node}), do: node
    defp unwrap_node(other), do: other
  end

  @derive {Nestru.Decoder,
           hint: %{
             itineraries: [Itinerary],
             routing_errors: [RoutingError],
             search_date_time: DateTime
           }}
  schema do
    field(:itineraries, [Itinerary.t()])
    field(:routing_errors, [RoutingError.t()])
    field(:search_date_time, DateTime)
  end
end
