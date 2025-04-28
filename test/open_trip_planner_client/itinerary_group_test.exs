defmodule OpenTripPlannerClient.ItineraryGroupTest do
  use ExUnit.Case, async: true

  import OpenTripPlannerClient.Test.Support.Factory

  alias OpenTripPlannerClient.ItineraryGroup
  alias OpenTripPlannerClient.Schema.Itinerary

  describe "groups_from_itineraries/2" do
    test "can group itineraries separately" do
      itineraries = build_list(3, :itinerary)
      groups = ItineraryGroup.groups_from_itineraries(itineraries)

      for group <- groups do
        assert %ItineraryGroup{} = group
      end
    end

    test "can group itineraries together" do
      groupable_itineraries = groupable_otp_itineraries(1, 3)

      [%ItineraryGroup{} = group] =
        ItineraryGroup.groups_from_itineraries(groupable_itineraries)

      assert Enum.count(group.itineraries) == Enum.count(groupable_itineraries)
    end

    test "doesn't exceed 4 per group" do
      many_groupable_itineraries = groupable_otp_itineraries(1, 20)

      [%ItineraryGroup{} = group] =
        ItineraryGroup.groups_from_itineraries(many_groupable_itineraries)

      assert Enum.count(group.itineraries) == 4
    end

    test "returns desired number of groups" do
      many_groupable_itineraries = groupable_otp_itineraries(20, 1)
      num_groups = Faker.random_between(2, 20)

      groups =
        many_groupable_itineraries
        |> ItineraryGroup.groups_from_itineraries(num_groups: num_groups)

      assert Enum.count(groups) == num_groups
    end

    test "can adjust representative_index" do
      groupable_itineraries = groupable_otp_itineraries(1, 3)

      [%ItineraryGroup{} = group1] =
        ItineraryGroup.groups_from_itineraries(groupable_itineraries, take_from_end: true)

      [%ItineraryGroup{} = group2] =
        ItineraryGroup.groups_from_itineraries(groupable_itineraries, take_from_end: false)

      assert group1.representative_index == -1
      assert group2.representative_index == 0
    end

    test "can adjust time_key" do
      groupable_itineraries = groupable_otp_itineraries(1, 3)

      [%ItineraryGroup{} = group1] =
        ItineraryGroup.groups_from_itineraries(groupable_itineraries, take_from_end: true)

      [%ItineraryGroup{} = group2] =
        ItineraryGroup.groups_from_itineraries(groupable_itineraries, take_from_end: false)

      assert group1.time_key == :end
      assert group2.time_key == :start
    end
  end

  describe "leg_summaries/1" do
    setup do
      groupable_itineraries = groupable_otp_itineraries(1, 3)
      group = ItineraryGroup.groups_from_itineraries(groupable_itineraries) |> List.first()
      {:ok, %{group: group}}
    end

    test "returns list of either walking minutes or transit routes", %{group: group} do
      assert leg_summaries = ItineraryGroup.leg_summaries(group)

      for %{walk_minutes: walk_minutes, routes: grouped_routes} <- leg_summaries do
        assert walk_minutes > 0 or length(grouped_routes) > 0
      end
    end

    test "groups overlapping routes together" do
      route = build(:route, type: 2)
      related_route = build(:route, type: 2)
      from = build(:place_with_stop)
      to = build(:place_with_stop)

      itinerary =
        build(:itinerary, legs: build_list(1, :transit_leg, route: route, from: from, to: to))

      related_itinerary =
        build(:itinerary,
          legs: build_list(1, :transit_leg, route: related_route, from: from, to: to)
        )

      [group] = [itinerary, related_itinerary] |> ItineraryGroup.groups_from_itineraries()
      assert [%{routes: grouped_routes}] = ItineraryGroup.leg_summaries(group)
      assert Enum.sort(grouped_routes) == Enum.sort([route, related_route])
    end

    test "omits short intermediate walks" do
      short_leg = build(:walking_leg, duration: 60)
      long_leg = build(:walking_leg, duration: 600)

      [group] =
        build_list(2, :itinerary, legs: [long_leg, short_leg, long_leg])
        |> ItineraryGroup.groups_from_itineraries()

      assert [%{walk_minutes: 10}, %{walk_minutes: 10}] = ItineraryGroup.leg_summaries(group)
    end

    test "rounds minutes to minimum 1" do
      seconds = Faker.random_between(1, 30)
      very_short_leg = build(:walking_leg, duration: seconds)

      [group] =
        build_list(2, :itinerary, legs: [very_short_leg])
        |> ItineraryGroup.groups_from_itineraries()

      assert [%{walk_minutes: 1}] = ItineraryGroup.leg_summaries(group)
    end

    test "rounds minutes to nearest integer" do
      leg = build(:walking_leg, duration: Faker.random_uniform() * 600)

      [group] =
        build_list(2, :itinerary, legs: [leg])
        |> ItineraryGroup.groups_from_itineraries()

      assert [%{walk_minutes: minutes}] = ItineraryGroup.leg_summaries(group)
      assert is_integer(minutes)
    end
  end

  describe "representative_itinerary/1" do
    test "picks based on group representative_index" do
      group = build(:itinerary_group)
      %Itinerary{} = representative_itinerary = ItineraryGroup.representative_itinerary(group)
      assert representative_itinerary == Enum.at(group.itineraries, group.representative_index)
    end
  end

  describe "all_times/1" do
    test "picks times based on group time_key" do
      group = build(:itinerary_group)
      all_times = ItineraryGroup.all_times(group)
      assert length(all_times) == length(group.itineraries)
      assert all_times == Enum.map(group.itineraries, &Map.get(&1, group.time_key))
    end
  end

  describe "alternatives_text/1" do
    test "nil when no itinerary alternatives" do
      group = build(:itinerary_group, itineraries: build_list(1, :itinerary))
      refute ItineraryGroup.alternatives_text(group)
    end

    @tag flaky: "Sometimes multiple generated itineraries happen to have the same time!"
    test "doesn't include representative_itinerary details" do
      group = build(:itinerary_group)

      representative_time =
        group
        |> ItineraryGroup.representative_itinerary()
        |> Map.get(group.time_key)
        |> Timex.format!("%-I:%M", :strftime)

      refute ItineraryGroup.alternatives_text(group) =~ representative_time
    end

    test "changes based on group time_key" do
      depart_group = build(:itinerary_group, time_key: :start)
      arrive_group = %{depart_group | time_key: :end}
      depart_alternatives = ItineraryGroup.alternatives_text(depart_group)
      arrive_alternatives = ItineraryGroup.alternatives_text(arrive_group)
      refute depart_alternatives == arrive_alternatives
      assert depart_alternatives =~ "Similar trips depart at"
      assert arrive_alternatives =~ "Similar trips arrive at"
    end

    test "changes on number of alternate times" do
      group = build(:itinerary_group, time_key: :start, representative_index: 0)
      smaller_group = %{group | itineraries: Enum.take(group.itineraries, 2)}
      alternatives = ItineraryGroup.alternatives_text(group)
      smaller_alternatives = ItineraryGroup.alternatives_text(smaller_group)
      refute alternatives == smaller_alternatives
      assert alternatives =~ "Similar trips depart at"
      assert smaller_alternatives =~ "Similar trip departs at"
    end
  end
end
