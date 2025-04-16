defmodule OpenTripPlannerClient.PlanParamsTest do
  use ExUnit.Case, async: true

  alias OpenTripPlannerClient.PlanParams

  @date_regex ~r/^\d{4}-\d{2}-\d{2}$/
  @time_regex ~r/^\d?\d:\d{2}(am|pm)$/

  setup do
    from = %{
      name: Faker.Address.street_name(),
      latitude: Faker.Address.latitude(),
      longitude: Faker.Address.longitude(),
      stop_id: [Faker.Internet.slug(), nil] |> Faker.Util.pick()
    }

    to = %{
      name: Faker.Address.street_name(),
      latitude: Faker.Address.latitude(),
      longitude: Faker.Address.longitude(),
      stop_id: [Faker.Internet.slug(), nil] |> Faker.Util.pick()
    }

    {:ok, %{from: from, to: to}}
  end

  describe "new/2" do
    test "specifies from and to", %{from: from, to: to} do
      assert %PlanParams{fromPlace: from_param, toPlace: to_param} = PlanParams.new(from, to)
      assert from_param
      assert to_param
    end

    test "provides defaults", %{from: from, to: to} do
      assert %PlanParams{
               date: date,
               time: time,
               arriveBy: false,
               numItineraries: 5,
               wheelchair: false
             } =
               PlanParams.new(from, to)

      assert date
      assert time
    end

    test "sets custom datetime, formats them", %{from: from, to: to} do
      assert %PlanParams{date: default_date, time: default_time} = PlanParams.new(from, to)
      datetime = Faker.DateTime.forward(1)
      assert %PlanParams{date: date, time: time} = PlanParams.new(from, to, datetime: datetime)
      assert date != default_date
      assert time != default_time
      assert date |> String.match?(@date_regex)
      assert time |> String.match?(@time_regex)
    end

    test "sets custom numItineraries", %{from: from, to: to} do
      number = Faker.random_between(1, 1000)

      assert %PlanParams{numItineraries: ^number} =
               PlanParams.new(from, to, num_itineraries: number)
    end

    test "sets custom arriveBy", %{from: from, to: to} do
      arrive_by = Faker.Util.pick([true, false])

      assert %PlanParams{arriveBy: ^arrive_by} =
               PlanParams.new(from, to, arrive_by: arrive_by)
    end

    test "sets custom wheelchair", %{from: from, to: to} do
      wheelchair = Faker.Util.pick([true, false])

      assert %PlanParams{wheelchair: ^wheelchair} =
               PlanParams.new(from, to, wheelchair: wheelchair)
    end

    test "sets custom modes", %{from: from, to: to} do
      modes =
        Faker.random_between(1, 5)
        |> Faker.Util.sample_uniq(fn ->
          Faker.Util.pick(PlanParams.modes())
        end)

      assert %PlanParams{transportModes: modes_param} =
               PlanParams.new(from, to, modes: modes)

      assert Enum.map(modes_param, &Map.get(&1, :mode)) == modes
    end
  end
end
