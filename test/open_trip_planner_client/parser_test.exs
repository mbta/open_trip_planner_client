defmodule OpenTripPlannerClient.ParserTest do
  use ExUnit.Case, async: true

  import OpenTripPlannerClient.Parser
  import OpenTripPlannerClient.Test.Support.Factory

  alias OpenTripPlannerClient.{GraphQLError, Plan, QueryResult}

  describe "validate_body/1" do
    test "handles GraphQL request error" do
      error_data = build_list(3, :graphql_error)

      assert_raise GraphQLError, fn ->
        validate_body(%{"errors" => error_data})
      end
    end

    test "handles GraphQL field error" do
      error_data =
        build(:graphql_error, %{
          "path" => ["plan"],
          "extensions" => %{
            "classification" => "DataFetchingException"
          }
        })

      assert_raise GraphQLError, fn ->
        validate_body(%{
          "data" => mock_data(%{actual_plan: nil}),
          "errors" => [error_data]
        })
      end
    end

    test "handles routing errors" do
      code = :OUTSIDE_BOUNDS

      plan_with_routing_error =
        build(:plan, itineraries: [], routing_errors: build_list(1, :routing_error, code: code))

      mock_data = mock_data(%{actual_plan: plan_with_routing_error})

      assert {:error, %Plan{routing_errors: [%Plan.RoutingError{}]}} =
               validate_body(%{"data" => mock_data})
    end

    test "does not treat 'WALKING_BETTER_THAN_TRANSIT' as a fatal error" do
      mock_data =
        mock_data(%{actual_plan: %{routing_errors: [%{code: :WALKING_BETTER_THAN_TRANSIT}]}})

      assert {:ok, %QueryResult{}} = validate_body(%{"data" => mock_data})
    end

    test "handles a nil plan" do
      assert {:error, :no_plan} = validate_body(%{"data" => mock_data(%{actual_plan: nil})})
    end

    test "handles a missing plan" do
      assert {:error, :no_plan} = validate_body(%{"data" => %{}})
    end

    test "treats routing errors in ideal_plan as just an empty list of itineraries" do
      routing_error = build(:routing_error, code: :NO_TRANSIT_CONNECTION)

      mock_data =
        mock_data(%{
          actual_plan: %{routing_errors: []},
          ideal_plan: %{routing_errors: [routing_error]}
        })

      assert {:ok, %OpenTripPlannerClient.QueryResult{}} = validate_body(%{"data" => mock_data})
    end

    test "handles valid plan" do
      assert {:ok, %OpenTripPlannerClient.QueryResult{}} = validate_body(%{"data" => mock_data()})
    end
  end

  describe "simplify_itineraries/1" do
    setup do
      %{itinerary: build(:itinerary)}
    end

    test "drops first walking leg to station only if having same name and short distance", %{
      itinerary: itinerary
    } do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)
      parsed_itinerary = get_simplified_itinerary(itinerary, [leg_to_remove | itinerary.legs])
      refute leg_to_remove in parsed_itinerary.legs
      assert Enum.all?(itinerary.legs, &Enum.member?(parsed_itinerary.legs, &1))
    end

    test "keeps first walking leg if sufficiently distant", %{itinerary: itinerary} do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)

      leg_with_larger_distance =
        update_in(leg_to_remove, [:distance], fn _ -> Faker.random_between(322, 10_000_000) end)

      parsed_itinerary =
        get_simplified_itinerary(itinerary, [leg_with_larger_distance | itinerary.legs])

      assert leg_with_larger_distance in parsed_itinerary.legs
    end

    test "keeps first walking leg if from a different location", %{itinerary: itinerary} do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)

      leg_with_other_location =
        update_in(leg_to_remove, [:to, :name], fn _ -> Faker.App.name() end)

      parsed_itinerary =
        get_simplified_itinerary(itinerary, [leg_with_other_location | itinerary.legs])

      assert leg_with_other_location in parsed_itinerary.legs
    end

    test "keeps short first walking legs if not from place to station", %{
      itinerary: itinerary
    } do
      first_leg_no_station = base_little_leg_to_remove()
      first_leg_from_station = first_leg_no_station |> with_stop(:from)

      for leg <- [first_leg_no_station, first_leg_from_station] do
        parsed_itinerary = get_simplified_itinerary(itinerary, [leg | itinerary.legs])
        assert leg in parsed_itinerary.legs
      end
    end

    test "keeps walking legs having same name and short distance if not at start", %{
      itinerary: itinerary
    } do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)
      # put somewhere in middle
      legs =
        (itinerary.legs ++ itinerary.legs)
        |> List.insert_at(length(itinerary.legs), leg_to_remove)

      parsed_itinerary =
        get_simplified_itinerary(itinerary, legs)

      assert leg_to_remove in parsed_itinerary.legs
    end

    test "keeps short last walking legs if not from station to place", %{itinerary: itinerary} do
      last_leg_no_station = base_little_leg_to_remove()

      parsed_itinerary =
        get_simplified_itinerary(
          itinerary,
          List.insert_at(itinerary.legs, -1, last_leg_no_station)
        )

      assert last_leg_no_station in parsed_itinerary.legs
    end

    test "drops last walking leg from station only if having same name and short distance", %{
      itinerary: itinerary
    } do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:from)

      parsed_itinerary =
        get_simplified_itinerary(itinerary, List.insert_at(itinerary.legs, -1, leg_to_remove))

      refute leg_to_remove in parsed_itinerary.legs
      assert Enum.all?(itinerary.legs, &Enum.member?(parsed_itinerary.legs, &1))
    end

    test "keeps last walking leg if sufficiently distant", %{itinerary: itinerary} do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:from)

      leg_with_larger_distance =
        update_in(leg_to_remove, [:distance], fn _ -> Faker.random_between(322, 10_000_000) end)

      parsed_itinerary =
        get_simplified_itinerary(
          itinerary,
          List.insert_at(itinerary.legs, -1, leg_with_larger_distance)
        )

      assert leg_with_larger_distance in parsed_itinerary.legs
    end

    test "keeps last walking leg if to a different location", %{itinerary: itinerary} do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:from)

      leg_with_other_location =
        update_in(leg_to_remove, [:to, :name], fn _ -> Faker.App.name() end)

      parsed_itinerary =
        get_simplified_itinerary(
          itinerary,
          List.insert_at(itinerary.legs, -1, leg_with_other_location)
        )

      assert leg_with_other_location in parsed_itinerary.legs
    end

    test "can drop first and last walking legs", %{itinerary: itinerary} do
      first_leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)
      last_leg_to_remove = base_little_leg_to_remove() |> with_stop(:from)

      parsed_itinerary =
        get_simplified_itinerary(itinerary, [
          first_leg_to_remove | List.insert_at(itinerary.legs, -1, last_leg_to_remove)
        ])

      refute first_leg_to_remove in parsed_itinerary.legs
      refute last_leg_to_remove in parsed_itinerary.legs
    end

    test "if only leg, does not remove", %{itinerary: itinerary} do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)
      parsed_itinerary = get_simplified_itinerary(itinerary, [leg_to_remove])
      assert leg_to_remove in parsed_itinerary.legs
    end

    test "if no legs, does nothing", %{itinerary: itinerary} do
      assert parsed_itinerary = get_simplified_itinerary(itinerary, [])
      assert parsed_itinerary.legs == []
    end
  end

  defp get_simplified_itinerary(itinerary, new_legs) do
    itinerary
    |> update_in([:legs], fn _ -> new_legs end)
    |> List.wrap()
    |> simplify_itineraries()
    |> List.first()
  end

  defp base_little_leg_to_remove do
    name = Faker.Lorem.word()

    build(
      :leg,
      %{
        distance: Faker.random_between(1, 321),
        mode: :WALK,
        steps: build_list(3, :step),
        transit_leg: false,
        from: build(:place, name: name),
        to: build(:place, name: name)
      }
    )
  end

  defp with_stop(leg, from_or_to) do
    update_in(leg, [from_or_to, :stop], fn _ -> build(:stop) end)
  end

  defp mock_data(attrs \\ %{}) do
    {:ok, query_result_data} = build(:query_result, attrs) |> Nestru.encode()
    query_result_data
  end
end
