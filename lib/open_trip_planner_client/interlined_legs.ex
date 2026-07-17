defmodule OpenTripPlannerClient.InterlinedLegs do
  @moduledoc """
  A little utility module for combining interlined legs together into a single leg.
  """

  alias OpenTripPlannerClient.Schema.{Geometry, IntermediateStop, Leg, Route}

  @spec merge([Leg.t()]) :: [Leg.t()]
  def merge([
        %Leg{route: %Route{gtfs_id: route_id_1}} = leg_1,
        %Leg{route: %Route{gtfs_id: route_id_2}, interline_with_previous_leg: true} = leg_2
        | remaining_legs
      ])
      when route_id_1 == route_id_2,
      do:
        [combine_legs(leg_1, leg_2) | remaining_legs]
        |> merge()

  def merge([first_leg | remaining_legs]),
    do: [first_leg | merge(remaining_legs)]

  def merge([]), do: []

  defp combine_legs(leg_1, leg_2) do
    %Leg{
      leg_1
      | to: leg_2.to,
        end: leg_2.end,
        duration: leg_1.duration + leg_2.duration,
        distance: leg_1.distance + leg_2.distance,
        intermediate_stops:
          leg_1.intermediate_stops ++
            [
              %IntermediateStop{
                gtfs_id: leg_1.to.stop && leg_1.to.stop.gtfs_id,
                name: leg_1.to.name
              }
            ] ++
            leg_2.intermediate_stops,
        leg_geometry: combine_geometries(leg_1.leg_geometry, leg_2.leg_geometry)
    }
  end

  defp combine_geometries(
         %Geometry{points: polyline_1},
         %Geometry{points: polyline_2}
       ) do
    points_1 = polyline_1 |> Polyline.decode()
    points_2 = polyline_2 |> Polyline.decode()
    points = points_1 ++ points_2

    %Geometry{points: points |> Polyline.encode()}
  end
end
