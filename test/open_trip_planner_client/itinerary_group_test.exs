defmodule OpenTripPlannerClient.ItineraryGroupTest do
  use ExUnit.Case, async: true

  import OpenTripPlannerClient.Test.Support.Factory

  alias OpenTripPlannerClient.{ItineraryGroup, ItineraryTag}
  alias OpenTripPlannerClient.Schema.{Itinerary, Route}

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

      assert group1.representative_index == length(group1.itineraries) - 1
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

    test "includes unavailable trips" do
      [ideal_cost, actual_cost] =
        Faker.Util.sample_uniq(2, fn -> Faker.random_between(1000, 9999) end)
        |> Enum.sort()

      actual_itineraries = groupable_otp_itineraries(1, 3, generalized_cost: actual_cost)
      ideal_itineraries = groupable_otp_itineraries(1, 3, generalized_cost: ideal_cost)

      groups =
        ItineraryGroup.groups_from_itineraries(actual_itineraries,
          ideal_itineraries: ideal_itineraries
        )

      [%ItineraryGroup{} = unavailable_group, %ItineraryGroup{} = available_group] = groups

      assert available_group.available?
      refute unavailable_group.available?
    end

    test "does not count trips as unavailable if they are also part of the available itineraries" do
      itineraries = groupable_otp_itineraries(1, 3)

      groups =
        ItineraryGroup.groups_from_itineraries(itineraries,
          ideal_itineraries: itineraries
        )

      [%ItineraryGroup{} = group] = groups

      assert group.available?
    end

    test "does not include unavailable trips with costs that are higher than the best collection of available trips" do
      [actual_cost1, actual_cost2, ideal_cost] =
        Faker.Util.sample_uniq(3, fn -> Faker.random_between(1000, 9999) end)
        |> Enum.sort()

      actual_itineraries1 = groupable_otp_itineraries(1, 3, generalized_cost: actual_cost1)
      actual_itineraries2 = groupable_otp_itineraries(1, 3, generalized_cost: actual_cost2)
      ideal_itineraries = groupable_otp_itineraries(1, 3, generalized_cost: ideal_cost)

      groups =
        (actual_itineraries1 ++ actual_itineraries2)
        |> Enum.shuffle()
        |> ItineraryGroup.groups_from_itineraries(ideal_itineraries: ideal_itineraries)

      # Only two groups, because actual_itineraries 1 and 2 are returned, but not ideal_itineraries.
      assert groups |> Enum.count() == 2

      groups |> Enum.each(&assert &1.available?)
    end

    test "generates a summary based on all input itineraries" do
      [a, b] = build_list(2, :place_with_stop)
      c = build(:place)

      similar_routes =
        build_list(20, :route, agency: build(:agency, name: "MBTA"), desc: nil, type: 2)

      itineraries =
        build_list(20, :itinerary,
          accessibility_score: nil,
          legs: fn ->
            [
              build(:transit_leg, route: Faker.Util.pick(similar_routes), from: a, to: b),
              build(:walking_leg, distance: 400, from: b, to: c)
            ]
          end
        )

      [%ItineraryGroup{summary: summary, itineraries: truncated_itineraries}] =
        ItineraryGroup.groups_from_itineraries(itineraries)

      assert length(truncated_itineraries) < length(itineraries)

      assert [
               %{walk_minutes: 0, routes: summarized_routes},
               %{walk_minutes: summarized_walk_minutes, routes: []}
             ] = summary

      assert length(summarized_routes) > length(truncated_itineraries)
      assert summarized_walk_minutes > 0
    end

    test "generated summary does not include short intermediate walking legs" do
      [a, b, c, d] = build_list(4, :place_with_stop)

      similar_routes =
        build_list(20, :route, agency: build(:agency, name: "MBTA"), desc: nil, type: 2)

      itineraries =
        build_list(20, :itinerary,
          accessibility_score: nil,
          legs: fn ->
            [
              build(:transit_leg, route: Faker.Util.pick(similar_routes), from: a, to: b),
              build(:walking_leg,
                distance: 400,
                duration: 60 * Faker.random_between(1, 4),
                from: b,
                to: c
              ),
              build(:transit_leg, route: Faker.Util.pick(similar_routes), from: c, to: d)
            ]
          end
        )

      [%ItineraryGroup{summary: summary}] = ItineraryGroup.groups_from_itineraries(itineraries)

      assert [
               %{walk_minutes: 0},
               %{walk_minutes: 0}
             ] = summary
    end

    test "generated summary does include intermediate walking legs over five minutes" do
      walk_minutes = Faker.random_between(6, 20)

      [a, b, c, d] = build_list(4, :place_with_stop)

      similar_routes =
        build_list(20, :route, agency: build(:agency, name: "MBTA"), desc: nil, type: 2)

      itineraries =
        build_list(20, :itinerary,
          accessibility_score: nil,
          legs: fn ->
            [
              build(:transit_leg, route: Faker.Util.pick(similar_routes), from: a, to: b),
              build(:walking_leg, distance: 400, duration: 60 * walk_minutes, from: b, to: c),
              build(:transit_leg, route: Faker.Util.pick(similar_routes), from: c, to: d)
            ]
          end
        )

      [%ItineraryGroup{summary: summary}] = ItineraryGroup.groups_from_itineraries(itineraries)

      assert [
               %{walk_minutes: 0},
               %{walk_minutes: ^walk_minutes},
               %{walk_minutes: 0}
             ] = summary
    end

    test "generated summary includes short intermediate walking legs at the beginning and end" do
      walk_minutes_start = Faker.random_between(1, 20)
      walk_minutes_end = Faker.random_between(1, 20)
      [a, b, c, d] = build_list(4, :place_with_stop)

      similar_routes =
        build_list(20, :route, agency: build(:agency, name: "MBTA"), desc: nil, type: 2)

      itineraries =
        build_list(20, :itinerary,
          accessibility_score: nil,
          legs: fn ->
            [
              build(:walking_leg,
                distance: 400,
                duration: 60 * walk_minutes_start,
                from: a,
                to: b
              ),
              build(:transit_leg, route: Faker.Util.pick(similar_routes), from: b, to: c),
              build(:walking_leg, distance: 400, duration: 60 * walk_minutes_end, from: c, to: d)
            ]
          end
        )

      [%ItineraryGroup{summary: summary}] = ItineraryGroup.groups_from_itineraries(itineraries)

      assert [
               %{walk_minutes: ^walk_minutes_start},
               %{walk_minutes: 0},
               %{walk_minutes: ^walk_minutes_end}
             ] = summary
    end

    test "generates a summary for one input itinerary" do
      [a, b] = build_list(2, :place_with_stop)
      c = build(:place)

      itineraries =
        build_list(1, :itinerary,
          accessibility_score: nil,
          legs: fn ->
            [
              build(:transit_leg, from: a, to: b),
              build(:walking_leg, distance: 400, from: b, to: c)
            ]
          end
        )

      [%ItineraryGroup{summary: summary}] =
        ItineraryGroup.groups_from_itineraries(itineraries)

      assert [
               %{walk_minutes: 0, routes: [%Route{}]},
               %{walk_minutes: _, routes: []}
             ] = summary
    end

    test "sort groups by tag and cost" do
      many_groupable_itineraries =
        groupable_otp_itineraries(20, 1)
        |> Enum.map_every(
          3,
          &Map.put(&1, :tag, Faker.Util.pick(ItineraryTag.tag_priority_order()))
        )

      num_groups = Faker.random_between(2, 20)

      groups =
        many_groupable_itineraries
        |> ItineraryGroup.groups_from_itineraries(num_groups: num_groups)

      # verify the sorting by comparing each group to the next
      # should start with tagged itineraries and end with untagged itineraries
      # within each tag, sort from lower to higher generalized cost
      groups
      |> Enum.map(&ItineraryGroup.representative_itinerary/1)
      |> Enum.scan(fn next, current ->
        if next[:tag] == current[:tag] do
          assert next[:generalized_cost] >= current[:generalized_cost]
        else
          assert ItineraryTag.tag_order(next[:tag]) > ItineraryTag.tag_order(current[:tag])
        end

        # just keep iterating
        next
      end)
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
