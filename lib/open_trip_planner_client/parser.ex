defmodule OpenTripPlannerClient.Parser do
  @moduledoc """
  Basic error parsing for Open Trip Planner outputs, processing GraphQL client
  errors and trip planner errors into standard formats for logging and testing.
  """

  alias OpenTripPlannerClient.QueryResult
  alias OpenTripPlannerClient.{Error, Plan}

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
    # {:ok, query_result} = body.data |> Nestru.decode(QueryResult)

    with %{data: data} <- body,
         {:ok, %QueryResult{actual_plan: %Plan{} = actual_plan, ideal_plan: ideal_plan}} <-
           Nestru.decode(data, QueryResult),
         {:ok, validated_actual_plan} <-
           actual_plan
           |> drop_nonfatal_errors()
           |> validate_no_routing_errors() do
      # dbg(validated_actual_plan)

      {:ok,
       %QueryResult{
         actual_plan: validated_actual_plan,
         ideal_plan: ideal_plan
       }}
    else
      error ->
        error
    end
  end

  # defp plan_from_query_result(%QueryResult{actual_plan: nil}), do: {:error, :no_plan}
  # defp plan_from_query_result(%QueryResult{actual_plan: %Plan{} = plan}), do: {:ok, plan}
  # defp plan_from_query_result(_), do: {:error, :no_data}

  defp validate_no_routing_errors(%Plan{routing_errors: []} = plan) do
    {:ok, plan}
  end

  defp validate_no_routing_errors(%Plan{} = plan) do
    {:error, Error.from_routing_errors(plan)}
  end

  defp drop_nonfatal_errors(plan) do
    plan.routing_errors
    |> Enum.reject(&(&1.code == @walking_better_than_transit))
    |> then(&%Plan{plan | routing_errors: &1})
  end
end
