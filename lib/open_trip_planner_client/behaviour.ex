defmodule OpenTripPlannerClient.Behaviour do
  @moduledoc """
  A behaviour that specifies the API for the `OpenTripPlannerClient`.

  May be useful for testing with libraries like [Mox](https://hex.pm/packages/mox).
  """

  alias OpenTripPlannerClient.PlanParams

  @type plan_result ::
          {:ok, [OpenTripPlannerClient.ItineraryGroup.t()]} | {:error, term()}
  @callback plan(params :: PlanParams.t()) :: plan_result()
  @callback plan(
              params :: PlanParams.t(),
              opts :: [{:tags, [OpenTripPlannerClient.ItineraryTag.Behaviour.t()]}]
            ) :: plan_result()
end
