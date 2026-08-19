defmodule OpenTripPlannerClient.Schema.FareProduct do
  @moduledoc """
  A subset of fields for fare products.

  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/FareProduct
  """

  use OpenTripPlannerClient.Schema

  alias OpenTripPlannerClient.Schema.{DependentFareProduct, FareProduct}

  defimpl Nestru.PreDecoder, for: FareProduct do
    # credo:disable-for-next-line
    def gather_fields_for_decoding(_, _, %{"product" => product}) do
      updated_map =
        product
        |> update_in(["dependencies"], &replace_nil_with_list/1)
        |> Map.put("us_cents", get_in(product, ["price", "amount"]) |> to_cents())
        |> Map.put("medium_name", get_in(product, ["medium", "name"]))

      {:ok, updated_map}
    end

    defp replace_nil_with_list(nil), do: []
    defp replace_nil_with_list(other), do: other

    defp to_cents(amount) when is_float(amount) do
      trunc(amount * 100)
    end

    defp to_cents(_), do: nil
  end

  @derive {Nestru.Decoder, hint: %{dependencies: [DependentFareProduct]}}
  schema do
    field(:id, String.t(), @nonnull_field)
    field(:dependencies, [DependentFareProduct.t()])
    field(:medium_name, String.t())
    field(:name, String.t(), @nonnull_field)
    field(:us_cents, non_neg_integer())
  end
end

defmodule OpenTripPlannerClient.Schema.DependentFareProduct do
  @moduledoc """
  A subset of fields for fare products.

  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/FareProduct
  """

  use OpenTripPlannerClient.Schema

  alias OpenTripPlannerClient.Schema.DependentFareProduct

  defimpl Nestru.PreDecoder, for: DependentFareProduct do
    # credo:disable-for-next-line
    def gather_fields_for_decoding(_, _, product) do
      updated_map =
        product
        |> Map.put("medium_name", get_in(product, ["medium", "name"]))

      {:ok, updated_map}
    end
  end

  @derive Nestru.Decoder
  schema do
    field(:id, String.t(), @nonnull_field)
    field(:medium_name, String.t())
    field(:name, String.t(), @nonnull_field)
  end
end
