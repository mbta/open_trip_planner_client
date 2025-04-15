defmodule ItineraryTest do
  use ExUnit.Case, async: true

  import OpenTripPlannerClient.Test.Support.Factory

  alias OpenTripPlannerClient.Schema.Itinerary

  describe "accessible?" do
    test "true with accessibility_score of 1" do
      assert build(:itinerary, accessibility_score: 1.0) |> Itinerary.accessible?()
    end

    test "false with accessibility_score of nil" do
      refute build(:itinerary, accessibility_score: nil) |> Itinerary.accessible?()
    end

    test "otherwise true if all transit legs are MBTA buses" do
      accessibility_score = Faker.random_between(1, 99) / 100

      itinerary =
        build(:itinerary,
          accessibility_score: accessibility_score,
          legs: build_list(3, :mbta_bus_leg)
        )

      assert Itinerary.accessible?(itinerary)
    end
  end

  describe "group_identifier/1" do
    test "different value for otherwise identical itineraries with different accessibility scores" do
      accessible_itinerary = build(:itinerary, accessibility_score: 1.0)
      inaccessible_itinerary = %{accessible_itinerary | accessibility_score: nil}

      assert Itinerary.group_identifier(accessible_itinerary) !=
               Itinerary.group_identifier(inaccessible_itinerary)
    end

    test "same value for itineraries with same accessibility and same leg sequence" do
      legs = build_list(3, :transit_leg)
      itinerary = build(:itinerary, legs: legs, accessibility_score: nil)
      other_itinerary = build(:itinerary, legs: legs, accessibility_score: nil)

      assert Itinerary.group_identifier(itinerary) ==
               Itinerary.group_identifier(other_itinerary)
    end

    test "same value for itineraries with same accessibility and simliar leg sequence" do
      legs = build_list(3, :transit_leg)
      short_walking_leg = build(:walking_leg, distance: 200)

      itinerary = build(:itinerary, legs: legs, accessibility_score: nil)

      other_itinerary =
        build(:itinerary, legs: [short_walking_leg | legs], accessibility_score: nil)

      assert Itinerary.group_identifier(itinerary) ==
               Itinerary.group_identifier(other_itinerary)
    end
  end
end
