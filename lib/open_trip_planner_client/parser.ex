defmodule OpenTripPlannerClient.Parser do
  @moduledoc """
  Basic error parsing for Open Trip Planner outputs, processing GraphQL client
  errors and trip planner errors into standard formats for logging and testing.
  """

  alias OpenTripPlannerClient.{Error, Plan}
  alias OpenTripPlannerClient.Schema.{Itinerary, Leg}

  @walking_better_than_transit "WALKING_BETTER_THAN_TRANSIT"

  @doc """
  The errors entry in the response is a non-empty list of errors raised during
  the request, where each error is a map of data described by the error result
  format below.

  If present, the errors entry in the response must contain at least one error. If
  no errors were raised during the request, the errors entry must not be present
  in the result.

  If the data entry in the response is not present, the errors entry must be
  present. It must contain at least one request error indicating why no data was
  able to be returned.

  If the data entry in the response is present (including if it is the value
  null), the errors entry must be present if and only if one or more field error
  was raised during execution.
  """
  @spec validate_body(map()) :: {:ok, Plan.t()} | {:error, term()}

  def validate_body(%{errors: [_ | _] = errors}) do
    {:error, Enum.map(errors, &Error.from_graphql_error/1)}
  end

  def validate_body(body) do
    with {:ok, plan} <- plan_from_data(body),
         {:ok, %Plan{} = decoded_plan} <- Nestru.decode(plan, Plan) do
      decoded_plan
      |> drop_nonfatal_errors()
      |> then(&%Plan{&1 | itineraries: simplify_itineraries(&1.itineraries)})
      |> validate_no_routing_errors()
    else
      error ->
        error
    end
  end

  defp plan_from_data(%{data: %{plan: nil}}), do: {:error, :no_plan}
  defp plan_from_data(%{data: %{plan: plan}}), do: {:ok, plan}
  defp plan_from_data(_), do: {:error, :no_data}

  defp validate_no_routing_errors(%Plan{routing_errors: []} = plan), do: {:ok, plan}
  defp validate_no_routing_errors(%Plan{} = plan), do: {:error, Error.from_routing_errors(plan)}

  defp drop_nonfatal_errors(plan) do
    plan.routing_errors
    |> Enum.reject(&(&1.code == @walking_better_than_transit))
    |> then(&%Plan{plan | routing_errors: &1})
  end

  @spec simplify_itineraries([Itinerary.t()]) :: [Itinerary.t()]
  @doc """
  Making the final output nicer through various means.
  """
  def simplify_itineraries(itineraries) do
    Enum.map(itineraries, fn itinerary ->
      update_in(itinerary, [:legs], &drop_spurious_stop_terminal_walking_legs/1)
    end)
  end

  # Avoid extra tiny walking legs when starting at or ending at a transit stop.
  # These legs feature a very short walk between a stop and nearby location with the same name.
  # - initial leg involves this walk from a nearby location to a transit stop
  # - terminal leg inolves this walk from a transit stop to a nearby location
  defp drop_spurious_stop_terminal_walking_legs([]), do: []
  defp drop_spurious_stop_terminal_walking_legs([leg]), do: [leg]

  defp drop_spurious_stop_terminal_walking_legs([first | other_legs] = all_legs) do
    {last, middle_legs} = List.pop_at(other_legs, -1)

    drop_first? = drop_leg?(first, false, true)
    drop_last? = drop_leg?(last, true, false)

    case {drop_first?, drop_last?} do
      {true, true} -> middle_legs
      {true, false} -> other_legs
      {false, true} -> [first | middle_legs]
      {false, false} -> all_legs
    end
  end

  defp drop_leg?(leg, has_from_stop?, has_to_stop?) do
    satisfies_from_condition? = has_from_stop? == not is_nil(leg.from.stop)
    satisfies_to_condition? = has_to_stop? == not is_nil(leg.to.stop)
    spurious_walking_leg?(leg) and satisfies_from_condition? and satisfies_to_condition?
  end

  defp spurious_walking_leg?(leg) do
    Leg.short_walking_leg?(leg) and leg.from.name == leg.to.name
  end
end
