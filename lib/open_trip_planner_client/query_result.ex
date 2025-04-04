defmodule OpenTripPlannerClient.QueryResult do
  @moduledoc """
  Data type returned by the plan query.
  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/Plan
  """

  use OpenTripPlannerClient.Schema

  alias OpenTripPlannerClient.Plan

  @derive {Nestru.Decoder, hint: %{actual_plan: Plan, ideal_plan: Plan}}
  schema do
    field(:actual_plan, Plan)
    field(:ideal_plan, Plan)
  end
end
