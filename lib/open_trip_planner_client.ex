defmodule OpenTripPlannerClient do
  @moduledoc """
  Fetches data from the OpenTripPlanner API.

  ## Configuration

  ```elixir
  config :open_trip_planner_client,
    otp_url: "http://localhost:8080",
    timezone: "America/New_York"
  ```
  """
  @behaviour OpenTripPlannerClient.Behaviour

  import OpenTripPlannerClient.Request, only: [plan_connection: 1]

  alias OpenTripPlannerClient.{ItineraryGroup, ItineraryTag, Parser, QueryResult}

  @impl OpenTripPlannerClient.Behaviour
  @doc """
  Generate a trip plan with the given endpoints and options. Supports customizing which tags are applied to the results.
  """
  def plan(params, tags \\ nil) do
    tags = if tags, do: tags, else: default_tags(params.dateTime)

    with {:ok, %Req.Response{status: 200, body: body}} <- plan_connection(params),
         {:ok, %QueryResult{actual_plan: actual_plan, ideal_plan: ideal_plan}} <-
           Parser.validate_body(body) do
      actual_plan.itineraries
      |> Enum.map(&Map.put_new(&1, :tag, nil))
      |> ItineraryTag.apply_tags(tags)
      |> ItineraryGroup.groups_from_itineraries(
        ideal_itineraries: ideal_plan.itineraries |> ItineraryTag.apply_tags(tags),
        take_from_end: Map.has_key?(params.dateTime, :latestArrival)
      )
      |> then(&{:ok, &1})
    end
  end

  defp default_tags(%{latestArrival: _}), do: ItineraryTag.default_arriving()
  defp default_tags(_), do: ItineraryTag.default_departing()

  defmodule GraphQLError do
    defexception [:message]

    @impl true
    def exception(error) do
      {message, metadata} = Map.pop(error, "message", "")
      %__MODULE__{message: "#{message} Details: #{inspect(metadata)}"}
    end
  end
end
