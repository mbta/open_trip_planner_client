defmodule OpenTripPlannerClient.Parser do
  @moduledoc """
  Basic error parsing for Open Trip Planner outputs, processing GraphQL client
  errors and trip planner errors into standard formats for logging and testing.
  """

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
    with {:ok, plan} <- valid_plan(body),
         {:ok, %Plan{} = decoded_plan} <- Nestru.decode(plan, Plan) do
      decoded_plan
      |> with_errors()
      |> valid_plan()
    else
      error ->
        error
    end
  end

  defp valid_plan(%Plan{routing_errors: []} = plan), do: {:ok, plan}

  defp valid_plan(%Plan{} = plan),
    do: {:error, Error.from_routing_errors(plan)}

  defp valid_plan(%{data: %{plan: nil}}), do: {:error, :no_plan}
  defp valid_plan(%{data: %{plan: plan}}), do: {:ok, plan}

  defp valid_plan(_) do
    {:error, :no_data}
  end

  defp with_errors(plan) do
    plan.routing_errors
    |> Enum.reject(&(&1.code == @walking_better_than_transit))
    |> then(&%Plan{plan | routing_errors: &1})
  end
end
