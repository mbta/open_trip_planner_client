defmodule OpenTripPlannerClient.ItineraryTag.ShortestTripTest do
  use ExUnit.Case, async: true
  alias OpenTripPlannerClient.{Itinerary, ItineraryTag}

  test "works" do
    itineraries = [
      %Itinerary{start: ~U[2024-01-03 04:00:00Z], stop: ~U[2024-01-03 05:15:00Z]},
      %Itinerary{start: ~U[2024-01-03 04:15:00Z], stop: ~U[2024-01-03 05:30:00Z]},
      %Itinerary{start: ~U[2024-01-03 04:22:00Z], stop: ~U[2024-01-03 05:15:00Z]}
    ]

    tags =
      ItineraryTag.apply_tag(ItineraryTag.ShortestTrip, itineraries)
      |> Enum.map(&(&1.tags |> Enum.sort()))

    assert tags == [[], [], [:shortest_trip]]
  end
end
