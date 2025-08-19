defmodule OpenTripPlannerClient.Request do
  @moduledoc false

  alias OpenTripPlannerClient.PlanParams

  require Logger

  @plan_query File.read!("priv/plan.graphql")

  @docp """
  An extended `Req.Request` struct which
  - Sets `base_url` to OpenTripPlanner's default router
  - Keeps automatic response body decoding, but transforms OTP's camel-case
    keys into snake-case
  - Raises on HTTP 4XX/5XX responses instead of returning an :ok tuple
  - Configures the AbsintheClient plugin for making GraphQL requests
  """
  @spec new :: Req.Request.t()
  defp new do
    Req.new(
      base_url:
        Application.fetch_env!(:open_trip_planner_client, :otp_url) <>
          "/otp/routers/default/index/",
      decode_json: [keys: &Macro.underscore/1],
      http_errors: :raise
    )
    |> AbsintheClient.attach()
  end

  @doc """
  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/queries/planConnection
  """
  @spec plan_connection(PlanParams.t()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def plan_connection(%PlanParams{} = params) do
    new()
    |> Req.post(graphql: {@plan_query, params})
  rescue
    error ->
      handle_exception(error, params: inspect(params))
  end

  defp handle_exception(error, metadata) do
    error
    |> Exception.message()
    |> Logger.error(metadata)

    {:error, error}
  end
end
