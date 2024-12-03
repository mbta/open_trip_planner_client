defmodule OpenTripPlannerClient.Error do
  @moduledoc """
  Describes errors from OpenTripPlanner, including routing errors from the /plan
  endpoint for now. For routing errors, generates custom human-friendly error
  messages based on routing error code and plan details.
  """

  alias OpenTripPlannerClient.Plan
  alias Timex.{Duration, Format.Duration.Formatter}

  require Logger

  defstruct [:details, :message, :type]

  @type t :: %__MODULE__{
          details: map(),
          message: String.t(),
          type: :graphql_error | :routing_error
        }

  @spec from_graphql_error(map()) :: t()
  def from_graphql_error(error) do
    _ = log_error(error)

    {message, details} = Map.pop(error, :message)
    %__MODULE__{details: details, message: message, type: :graphql_error}
  end

  @spec from_routing_errors(Plan.t()) :: t()
  def from_routing_errors(%Plan{routing_errors: routing_errors} = plan) do
    _ = log_error(routing_errors)

    for %{code: code, description: description} <- routing_errors do
      %__MODULE__{
        details: %{code: code, description: description},
        message: code_to_message(code, description, plan),
        type: :routing_error
      }
    end
  end

  defp code_to_message(code, description, _)
       when code in ["LOCATION_NOT_FOUND", "NO_STOPS_IN_RANGE"] do
    case description do
      "Origin" <> _ ->
        "Origin location is not close enough to any transit stops"

      "Destination" <> _ ->
        "Destination location is not close enough to any transit stops"

      _ ->
        "Location is not close enough to any transit stops"
    end
  end

  defp code_to_message("NO_TRANSIT_CONNECTION", _, _) do
    "No transit connection was found between the origin and destination on this date and time"
  end

  defp code_to_message("OUTSIDE_BOUNDS", _, _) do
    "Origin or destination location is outside of our service area"
  end

  defp code_to_message("NO_TRANSIT_CONNECTION_IN_SEARCH_WINDOW", _, %Plan{} = plan) do
    with window when is_binary(window) <- humanized_search_window(plan.search_window_used),
         {:ok, formatted_datetime} <- humanized_full_date(plan.date) do
      "No transit routes found within #{window} of #{formatted_datetime}. Routes may be available at other times."
    else
      _ ->
        fallback_error_message()
    end
  end

  defp code_to_message(_, _, _), do: fallback_error_message()

  defp humanized_search_window(number) do
    number
    |> Duration.from_seconds()
    |> Formatter.format(:humanized)
  end

  defp humanized_full_date(datetime) do
    datetime
    |> OpenTripPlannerClient.Util.to_local_time()
    |> Timex.format("{h12}:{m}{am} on {WDfull}, {Mfull} {D}")
  end

  defp fallback_error_message do
    Application.get_env(
      :open_trip_planner_client,
      :fallback_error_message
    )
  end

  defp log_error(errors) when is_list(errors), do: Enum.each(errors, &log_error/1)

  defp log_error(error), do: Logger.error(error)
end
