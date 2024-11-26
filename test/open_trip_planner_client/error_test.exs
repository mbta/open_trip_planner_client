defmodule OpenTripPlannerClient.ErrorTest do
  use ExUnit.Case, async: true

  import OpenTripPlannerClient.Error
  import OpenTripPlannerClient.Test.Support.Factory

  alias OpenTripPlannerClient.Error

  describe "from_graphql_error/2" do
    test "handles one error" do
      message = Faker.Lorem.sentence(3, ".")
      error = %{message: message}

      assert %Error{details: %{}, type: :graphql_error, message: ^message} =
               from_graphql_error(error)
    end
  end

  describe "from_routing_errors/1" do
    test "shows a configured fallback message" do
      assert [%Error{message: custom_fallback}] =
               from_routing_errors(
                 build(:plan, routing_errors: [build(:routing_error, %{code: "Fake"})])
               )

      assert custom_fallback ==
               Application.get_env(:open_trip_planner_client, :fallback_error_message)
    end

    test "displays differing message based on error described for origin vs destination" do
      plan =
        build(:plan,
          routing_errors: [
            %{code: "LOCATION_NOT_FOUND", description: "Origin location not found"},
            %{code: "LOCATION_NOT_FOUND", description: "Destination location not found"},
            %{code: "LOCATION_NOT_FOUND", description: "Some other message"}
          ]
        )

      [origin_message, destination_message, message] =
        from_routing_errors(plan) |> Enum.map(& &1.message)

      assert origin_message != destination_message
      assert origin_message =~ "is not close enough to any transit stops"
      assert origin_message =~ "is not close enough to any transit stops"
      assert message =~ "Location is not close enough to any transit stops"
    end

    test "message for NO_TRANSIT_CONNECTION" do
      assert [%Error{message: message}] =
               from_routing_errors(plan_with_error_code("NO_TRANSIT_CONNECTION"))

      assert message =~ "No transit connection was found"
    end

    test "message for OUTSIDE_BOUNDS" do
      assert [%Error{message: message}] =
               from_routing_errors(plan_with_error_code("OUTSIDE_BOUNDS"))

      assert message =~ "is outside of our service area"
    end

    test "detailed message for NO_TRANSIT_CONNECTION_IN_SEARCH_WINDOW" do
      search_window_used = Faker.random_between(600, 7200)
      date = Faker.DateTime.forward(2)

      plan =
        build(:plan, %{
          date: Timex.to_unix(date) * 1000,
          itineraries: [],
          routing_errors: [
            build(:routing_error, %{code: "NO_TRANSIT_CONNECTION_IN_SEARCH_WINDOW"})
          ],
          search_window_used: search_window_used
        })

      assert [%Error{message: message}] = from_routing_errors(plan)

      assert message =~ "Routes may be available at other times"
    end
  end

  defp plan_with_error_code(code) do
    build(:plan, %{
      routing_errors: [build(:routing_error, %{code: code})]
    })
  end
end
