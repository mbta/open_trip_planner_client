defmodule OpenTripPlannerClient.PlanTest do
  use ExUnit.Case, async: true
  alias OpenTripPlannerClient.Plan

  test "creates structs from maps" do
    map = %{
      itineraries: []
    }

    assert {:ok, %Plan{}} = Nestru.decode(map, Plan)
  end

  test "updates unix timestamps to DateTime in local timezone" do
    map = %{search_date_time: Faker.DateTime.forward(1) |> DateTime.to_iso8601()}
    assert {:ok, %Plan{search_date_time: parsed_date}} = Nestru.decode(map, Plan)
    assert parsed_date.time_zone == Application.fetch_env!(:open_trip_planner_client, :timezone)
  end
end
