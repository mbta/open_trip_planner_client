defmodule LegTest do
  use ExUnit.Case, async: true

  import OpenTripPlannerClient.Test.Support.Factory

  alias OpenTripPlannerClient.Schema.{Leg, Route}

  describe "group_identifier/1" do
    test "different value for legs between the same places using transit vs walking" do
      from = build(:place)
      to = build(:place)
      walking_leg = build(:walking_leg, from: from, to: to)
      transit_leg = build(:transit_leg, from: from, to: to)

      assert Leg.group_identifier(walking_leg) !=
               Leg.group_identifier(transit_leg)
    end

    test "different value for legs between the same places using different route type" do
      from = build(:place_with_stop)
      to = build(:place_with_stop)
      route = build(:route)
      transit_leg = build(:transit_leg, from: from, to: to, route: %{route | type: 0})
      other_transit_leg = build(:transit_leg, from: from, to: to, route: %{route | type: 2})

      assert Leg.group_identifier(transit_leg) !=
               Leg.group_identifier(other_transit_leg)
    end

    test "same value for legs between the same places using same route type" do
      from = build(:place_with_stop)
      to = build(:place_with_stop)
      route_type = Faker.Util.pick(Route.gtfs_route_type())

      transit_leg =
        build(:transit_leg, from: from, to: to, route: build(:route, type: route_type))

      other_transit_leg =
        build(:transit_leg, from: from, to: to, route: build(:route, type: route_type))

      assert Leg.group_identifier(transit_leg) ==
               Leg.group_identifier(other_transit_leg)
    end

    test "different value for bus legs between the same places where one is a rail replacement bus" do
      from = build(:place_with_stop)
      to = build(:place_with_stop)
      bus_route = build(:route, type: 3, desc: "Local Bus")
      rail_replacement_route = build(:route, type: 3, desc: "Rail Replacement Bus")
      transit_leg = build(:transit_leg, from: from, to: to, route: bus_route)
      other_transit_leg = build(:transit_leg, from: from, to: to, route: rail_replacement_route)

      assert Leg.group_identifier(transit_leg) !=
               Leg.group_identifier(other_transit_leg)
    end

    test "different value for similar legs from different agencies" do
      from = build(:place_with_stop)
      to = build(:place_with_stop)
      route = build(:route)

      transit_leg =
        build(:transit_leg,
          agency: build(:agency, name: "Logan Express"),
          from: from,
          to: to,
          route: route
        )

      other_transit_leg =
        build(:transit_leg,
          agency: build(:agency, name: "Massport"),
          from: from,
          to: to,
          route: route
        )

      assert Leg.group_identifier(transit_leg) !=
               Leg.group_identifier(other_transit_leg)
    end
  end
end
