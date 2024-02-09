defmodule OpenTripPlannerClient.ItineraryTag.LeastWalkingTest do
  use ExUnit.Case, async: true
  alias OpenTripPlannerClient.ItineraryTag

  test "works" do
    itineraries = [
      %{
        "legs" => [%{"mode" => "SUBWAY"}]
      },
      %{
        "legs" => [%{"mode" => "WALK", "distance" => 10}]
      },
      %{
        "legs" => [%{"mode" => "WALK", "distance" => 8}, %{"mode" => "WALK", "distance" => 8}]
      }
    ]

    tags =
      ItineraryTag.LeastWalking
      |> ItineraryTag.apply_tag(itineraries)
      |> Enum.map(
        &(&1
          |> Map.get("tag"))
      )

    assert tags == [:least_walking, nil, nil]
  end
end
