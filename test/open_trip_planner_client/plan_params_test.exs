defmodule OpenTripPlannerClient.PlanParamsTest do
  use ExUnit.Case, async: true

  alias OpenTripPlannerClient.PlanParams

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
      assert %PlanParams{origin: from_param, destination: to_param} = PlanParams.new(from, to)
      assert from_param
      assert to_param
    end

    test "provides defaults", %{from: from, to: to} do
      assert %PlanParams{
               dateTime: datetime,
               locale: "en",
               numItineraries: 5,
               wheelchair: false
             } =
               PlanParams.new(from, to)

      assert datetime
    end

    test "sets custom datetime", %{from: from, to: to} do
      assert %PlanParams{dateTime: default_datetime} = PlanParams.new(from, to)
      datetime = Faker.DateTime.forward(1)
      assert %PlanParams{dateTime: custom_datetime} = PlanParams.new(from, to, datetime: datetime)
      assert custom_datetime != default_datetime
    end

    test "sets custom numItineraries", %{from: from, to: to} do
      number = Faker.random_between(1, 1000)

      assert %PlanParams{numItineraries: ^number} =
               PlanParams.new(from, to, num_itineraries: number)
    end

    test "sets custom dateTime based on arriveBy", %{from: from, to: to} do
      assert %PlanParams{dateTime: arrive_datetime} =
               PlanParams.new(from, to, arrive_by: true)

      assert %PlanParams{dateTime: depart_datetime} =
               PlanParams.new(from, to, arrive_by: false)

      assert {:ok, _, _} = DateTime.from_iso8601(arrive_datetime.latestArrival)
      refute Map.has_key?(arrive_datetime, :earliestDeparture)
      refute Map.has_key?(depart_datetime, :latestArrival)
      assert {:ok, _, _} = DateTime.from_iso8601(depart_datetime.earliestDeparture)
    end

    test "sets custom locale", %{from: from, to: to} do
      locale = Faker.Util.pick(["es", "fr", "it"])

      assert %PlanParams{locale: ^locale} =
               PlanParams.new(from, to, locale: locale)
    end

    test "sets custom wheelchair", %{from: from, to: to} do
      wheelchair = Faker.Util.pick([true, false])

      assert %PlanParams{wheelchair: ^wheelchair} =
               PlanParams.new(from, to, wheelchair: wheelchair)
    end

    @non_subway_modes PlanParams.modes() -- [:SUBWAY, :TRAM]

    test "sets custom non-subway modes", %{from: from, to: to} do
      modes =
        Faker.random_between(1, 5)
        |> Faker.Util.sample_uniq(fn -> Faker.Util.pick(@non_subway_modes) end)

      assert %PlanParams{modes: %{transit: %{transit: modes_param}}} =
               PlanParams.new(from, to, modes: modes)

      assert Enum.map(modes_param, &Map.get(&1, :mode)) == modes
    end

    test "includes TRAM as a custom mode if SUBWAY is present", %{from: from, to: to} do
      modes = [
        :SUBWAY
        | Faker.random_between(1, 4)
          |> Faker.Util.sample_uniq(fn -> Faker.Util.pick(@non_subway_modes) end)
      ]

      assert %PlanParams{modes: %{transit: %{transit: modes_param}}} =
               PlanParams.new(from, to, modes: modes)

      assert Enum.map(modes_param, &Map.get(&1, :mode)) == [:TRAM | modes]
    end

    test "handles no transit modes", %{from: from, to: to} do
      assert %PlanParams{modes: %{transit: %{transit: _}}} = PlanParams.new(from, to)
      assert %PlanParams{modes: %{directOnly: true}} = PlanParams.new(from, to, modes: [])
    end
  end
end
