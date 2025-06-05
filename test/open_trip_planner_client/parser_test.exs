defmodule OpenTripPlannerClient.ParserTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  import OpenTripPlannerClient.Parser
  import OpenTripPlannerClient.Test.Support.Factory

  describe "validate_body/1" do
    test "handles GraphQL request error" do
      assert {{:error, errors}, log} =
               with_log(fn ->
                 validate_body(%{
                   errors: [
                     %{
                       message:
                         "Validation error (UndefinedVariable@[plan]) : Undefined variable 'from'",
                       locations: [
                         %{
                           line: 3,
                           column: 16
                         }
                       ],
                       extensions: %{
                         classification: "ValidationError"
                       }
                     },
                     %{
                       message: "Validation error (UnusedVariable) : Unused variable 'fromPlace'",
                       locations: [
                         %{
                           line: 1,
                           column: 16
                         }
                       ],
                       extensions: %{
                         classification: "ValidationError"
                       }
                     }
                   ]
                 })
               end)

      assert errors == [
               %OpenTripPlannerClient.Error{
                 details: %{
                   extensions: %{classification: "ValidationError"},
                   locations: [%{line: 3, column: 16}]
                 },
                 message:
                   "Validation error (UndefinedVariable@[plan]) : Undefined variable 'from'",
                 type: :graphql_error
               },
               %OpenTripPlannerClient.Error{
                 details: %{
                   extensions: %{classification: "ValidationError"},
                   locations: [%{line: 1, column: 16}]
                 },
                 message: "Validation error (UnusedVariable) : Unused variable 'fromPlace'",
                 type: :graphql_error
               }
             ]

      assert log =~ "Validation error"
    end

    test "handles GraphQL field error" do
      {{:error, [error]}, log} =
        with_log(fn ->
          validate_body(%{
            data: %{plan: nil},
            errors: [
              %{
                message:
                  "Exception while fetching data (/plan) : The value is not in range[0.0, 1.7976931348623157E308]: -5.0",
                locations: [
                  %{
                    line: 2,
                    column: 3
                  }
                ],
                path: [
                  "plan"
                ],
                extensions: %{
                  classification: "DataFetchingException"
                }
              }
            ]
          })
        end)

      assert error == %OpenTripPlannerClient.Error{
               details: %{
                 path: ["plan"],
                 extensions: %{classification: "DataFetchingException"},
                 locations: [%{line: 2, column: 3}]
               },
               message:
                 "Exception while fetching data (/plan) : The value is not in range[0.0, 1.7976931348623157E308]: -5.0",
               type: :graphql_error
             }

      assert log =~ "Exception while fetching data"
    end

    test "handles and logs routing errors" do
      code = "PATH_NOT_FOUND"
      routing_error = build(:routing_error, code: code)

      assert {{:error, errors}, log} =
               with_log(fn ->
                 validate_body(%{
                   data: %{plan: %{routing_errors: [routing_error]}}
                 })
               end)

      assert [
               %OpenTripPlannerClient.Error{
                 details: ^routing_error,
                 message: "Something went wrong.",
                 type: :routing_error
               }
             ] = errors

      assert log =~ code
    end

    test "does not treat 'WALKING_BETTER_THAN_TRANSIT' as a fatal error" do
      assert {:ok, %OpenTripPlannerClient.Plan{}} =
               validate_body(%{
                 data: %{plan: %{routing_errors: [%{code: "WALKING_BETTER_THAN_TRANSIT"}]}}
               })
    end

    test "handles a nil plan" do
      assert {{:error, :no_plan}, _log} =
               with_log(fn ->
                 validate_body(%{
                   data: %{plan: nil}
                 })
               end)
    end

    test "handles a missing plan" do
      assert {{:error, :no_data}, _log} =
               with_log(fn ->
                 validate_body(%{
                   data: %{}
                 })
               end)
    end
  end

  describe "validate_itineraries/1" do
    setup do
      %{itinerary: build(:itinerary)}
    end

    test "drops first walking leg to station only if having same name and short distance", %{
      itinerary: itinerary
    } do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)
      parsed_itinerary = get_validated_itinerary(itinerary, [leg_to_remove | itinerary.legs])
      refute leg_to_remove in parsed_itinerary.legs
    end

    test "keeps first walking leg if sufficiently distant", %{itinerary: itinerary} do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)

      leg_with_larger_distance =
        update_in(leg_to_remove, [:distance], fn _ -> Faker.random_between(322, 10_000_000) end)

      parsed_itinerary =
        get_validated_itinerary(itinerary, [leg_with_larger_distance | itinerary.legs])

      assert leg_with_larger_distance in parsed_itinerary.legs
    end

    test "keeps first walking leg if from a different location", %{itinerary: itinerary} do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)

      leg_with_other_location =
        update_in(leg_to_remove, [:to, :name], fn _ -> Faker.App.name() end)

      parsed_itinerary =
        get_validated_itinerary(itinerary, [leg_with_other_location | itinerary.legs])

      assert leg_with_other_location in parsed_itinerary.legs
    end

    test "keeps short first walking legs if not from place to station", %{
      itinerary: itinerary
    } do
      first_leg_no_station = base_little_leg_to_remove()
      first_leg_from_station = first_leg_no_station |> with_stop(:from)

      for leg <- [first_leg_no_station, first_leg_from_station] do
        parsed_itinerary = get_validated_itinerary(itinerary, [leg | itinerary.legs])
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
        get_validated_itinerary(itinerary, legs)

      assert leg_to_remove in parsed_itinerary.legs
    end

    test "keeps short last walking legs if not from station to place", %{itinerary: itinerary} do
      last_leg_no_station = base_little_leg_to_remove()

      parsed_itinerary =
        get_validated_itinerary(
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
        get_validated_itinerary(itinerary, List.insert_at(itinerary.legs, -1, leg_to_remove))

      refute leg_to_remove in parsed_itinerary.legs
    end

    test "keeps last walking leg if sufficiently distant", %{itinerary: itinerary} do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:from)

      leg_with_larger_distance =
        update_in(leg_to_remove, [:distance], fn _ -> Faker.random_between(322, 10_000_000) end)

      parsed_itinerary =
        get_validated_itinerary(
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
        get_validated_itinerary(
          itinerary,
          List.insert_at(itinerary.legs, -1, leg_with_other_location)
        )

      assert leg_with_other_location in parsed_itinerary.legs
    end

    test "can drop first and last walking legs", %{itinerary: itinerary} do
      first_leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)
      last_leg_to_remove = base_little_leg_to_remove() |> with_stop(:from)

      parsed_itinerary =
        get_validated_itinerary(itinerary, [
          first_leg_to_remove | List.insert_at(itinerary.legs, -1, last_leg_to_remove)
        ])

      refute first_leg_to_remove in parsed_itinerary.legs
      refute last_leg_to_remove in parsed_itinerary.legs
    end

    test "if only leg, does not remove", %{itinerary: itinerary} do
      leg_to_remove = base_little_leg_to_remove() |> with_stop(:to)
      parsed_itinerary = get_validated_itinerary(itinerary, [leg_to_remove])
      assert leg_to_remove in parsed_itinerary.legs
    end

    test "if no legs, does nothing", %{itinerary: itinerary} do
      assert parsed_itinerary = get_validated_itinerary(itinerary, [])
      assert parsed_itinerary.legs == []
    end
  end

  defp get_validated_itinerary(itinerary, new_legs) do
    itinerary
    |> update_in([:legs], fn _ -> new_legs end)
    |> List.wrap()
    |> validate_itineraries()
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
end
