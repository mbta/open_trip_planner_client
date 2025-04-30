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

      transit_leg =
        build(:transit_leg, from: from, to: to, route: build(:route, type: 4))

      other_transit_leg =
        build(:transit_leg, from: from, to: to, route: build(:route, type: 4))

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

    test "Silver Line 1/2/3 doesn't group with buses" do
      from = build(:place_with_stop)
      to = build(:place_with_stop)
      bus_route = build(:route, gtfs_id: "mbta-ma-us:not-silver-line", type: 3)
      sl_route = build(:route, gtfs_id: "mbta-ma-us:#{Faker.Util.pick(~w(741 742 743))}", type: 3)
      bus_leg = build(:transit_leg, from: from, to: to, route: bus_route)
      sl_leg = build(:transit_leg, from: from, to: to, route: sl_route)

      assert Leg.group_identifier(bus_leg) != Leg.group_identifier(sl_leg)
    end

    test "Silver Line 1/2/3 grouped with each other" do
      from = build(:place_with_stop)
      to = build(:place_with_stop)

      [route1, route2] =
        Faker.Util.sample_uniq(2, fn -> Faker.Util.pick(~w(741 742 743)) end)
        |> Enum.map(&build(:route, gtfs_id: "mbta-ma-us:#{&1}", type: 3))

      leg1 = build(:transit_leg, from: from, to: to, route: route1)
      leg2 = build(:transit_leg, from: from, to: to, route: route2)

      assert Leg.group_identifier(leg1) == Leg.group_identifier(leg2)
    end

    test "Green Line B/C/D/E grouped with each other" do
      from = build(:place_with_stop)
      to = build(:place_with_stop)

      [route1, route2] =
        Faker.Util.sample_uniq(2, fn -> Faker.Util.pick(~w(Green-B Green-C Green-D Green-E)) end)
        |> Enum.map(&build(:route, gtfs_id: "mbta-ma-us:#{&1}", type: 0))

      leg1 = build(:transit_leg, from: from, to: to, route: route1)
      leg2 = build(:transit_leg, from: from, to: to, route: route2)

      assert Leg.group_identifier(leg1) == Leg.group_identifier(leg2)
    end

    test "subways not otherwise grouped with each other" do
      from = build(:place_with_stop)
      to = build(:place_with_stop)

      [route1, route2] =
        Faker.Util.sample_uniq(2, fn -> build(:route, type: 1) end)

      leg1 = build(:transit_leg, from: from, to: to, route: route1)
      leg2 = build(:transit_leg, from: from, to: to, route: route2)

      assert Leg.group_identifier(leg1) != Leg.group_identifier(leg2)
    end
  end
end
