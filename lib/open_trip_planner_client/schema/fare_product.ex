defmodule OpenTripPlannerClient.Schema.FareProduct do
  @moduledoc """
  A subset of fields for fare products.

  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/FareProduct
  """

  use OpenTripPlannerClient.Schema

  defimpl Nestru.PreDecoder do
    # credo:disable-for-next-line
    def gather_fields_for_decoding(_, _, %{"product" => product}) do
      updated_map =
        product
        |> Map.put("usd_price", get_in(product, ["price", "amount"]))
        |> Map.put("medium_name", get_in(product, ["medium", "name"]))

      {:ok, updated_map}
    end
  end

  @derive Nestru.Decoder
  schema do
    field(:medium_name, String.t())
    field(:name, String.t())
    field(:usd_price, float())
  end
end
