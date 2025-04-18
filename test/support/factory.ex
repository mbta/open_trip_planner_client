# credo:disable-for-this-file Credo.Check.Readability.Specs
if Code.ensure_loaded?(ExMachina) and Code.ensure_loaded?(Faker) do
  defmodule OpenTripPlannerClient.Test.Support.Factory do
    @moduledoc """
    Generate OpenTripPlannerClient.Schema structs
    """

    use ExMachina

    import Faker.Random.Elixir, only: [random_uniform: 0]

    alias OpenTripPlannerClient.{Plan, PlanParams}

    alias OpenTripPlannerClient.Schema.{
      Agency,
      Geometry,
      Itinerary,
      Leg,
      LegTime,
      Place,
      Route,
      Step,
      Stop,
      Trip
    }

    def plan_factory do
      %Plan{
        date: Faker.DateTime.forward(2),
        itineraries: __MODULE__.build_list(3, :itinerary),
        routing_errors: [],
        search_window_used: 3600
      }
    end

    def plan_with_errors_factory do
      build(:plan, routing_errors: __MODULE__.build_list(2, :routing_error), itineraries: [])
    end

    def routing_error_factory do
      %{
        code:
          Faker.Util.pick([
            "NO_TRANSIT_CONNECTION",
            "NO_TRANSIT_CONNECTION_IN_SEARCH_WINDOW",
            "OUTSIDE_SERVICE_PERIOD",
            "OUTSIDE_BOUNDS",
            "LOCATION_NOT_FOUND",
            "NO_STOPS_IN_RANGE",
            "WALKING_BETTER_THAN_TRANSIT"
          ]),
        description: Faker.Lorem.sentence(3)
      }
    end

    def agency_factory do
      %Agency{
        name: Faker.Util.pick(["MBTA", "Massport", "Logan Express"])
      }
    end

    def geometry_factory do
      %Geometry{
        points: Faker.Lorem.characters(12),
        length: nil
      }
    end

    def itinerary_factory do
      legs = Faker.random_between(1, 3) |> build_leg_sequence()
      %Leg{start: %LegTime{scheduled_time: first_start}} = List.first(legs)
      %Leg{end: %LegTime{scheduled_time: last_end}} = List.last(legs)

      %Itinerary{
        accessibility_score: random_uniform(),
        duration:
          legs
          |> Enum.map(& &1.duration)
          |> Enum.sum(),
        end: last_end,
        legs: legs,
        number_of_transfers: length(legs) - 1,
        start: first_start,
        walk_distance:
          legs
          |> Enum.filter(&(&1.mode == :WALK))
          |> Enum.map(& &1.distance)
          |> Enum.sum()
      }
    end

    def leg_time_factory do
      %LegTime{
        scheduled_time: Faker.DateTime.forward(2),
        estimated: nil
      }
    end

    # Build a bunch of legs such that their start/end times follow each other
    # (e.g. creating a coherent sequence)
    defp build_leg_sequence(number) do
      base_time = Timex.now("America/New_York")

      transit_legs =
        0..number
        |> Enum.map(fn index ->
          build(:transit_leg, %{
            start:
              sequence(:leg_start, fn _ ->
                build(:leg_time, %{
                  scheduled_time: Timex.shift(base_time, minutes: (index + 1) * 10)
                })
              end)
          })
        end)

      %LegTime{scheduled_time: transit_start_time} = List.first(transit_legs).start
      %LegTime{scheduled_time: transit_end_time} = List.last(transit_legs).end

      first_walk_leg =
        build(:walking_leg, %{
          end:
            build(:leg_time, %{
              scheduled_time: transit_start_time
            }),
          start:
            build(:leg_time, %{
              scheduled_time: Timex.shift(transit_start_time, minutes: -random_seconds())
            })
        })

      last_walk_leg =
        build(:walking_leg, %{
          start:
            build(:leg_time, %{
              scheduled_time: transit_end_time
            })
        })

      transit_legs
      |> List.insert_at(0, first_walk_leg)
      |> List.insert_at(-1, last_walk_leg)
    end

    def leg_factory(attrs) do
      # coherence between timed values - end time should be after the start time,
      # by the number of seconds specified in the duration.
      duration = attrs[:duration] || random_seconds()
      start_time = attrs[:start] || build(:leg_time)

      end_time =
        build(:leg_time, %{
          scheduled_time: Timex.shift(start_time.scheduled_time, seconds: duration)
        })

      leg = %Leg{
        agency: nil,
        distance: random_distance(),
        duration: duration,
        end: end_time,
        from: build(:place),
        intermediate_stops: nil,
        leg_geometry: build(:geometry),
        mode: nil,
        real_time: false,
        realtime_state: nil,
        route: nil,
        start: start_time,
        steps: nil,
        transit_leg: nil,
        trip: nil,
        to: build(:place)
      }

      leg
      |> merge_attributes(attrs)
      |> evaluate_lazy_attributes()
    end

    def transit_leg_factory(attrs) do
      agency = attrs[:agency] || build(:agency, %{name: "MBTA"})
      trip_gtfs_id = gtfs_prefix(agency.name) <> Faker.Internet.slug()

      build(:leg, %{
        agency: agency,
        from:
          build(:place, %{
            stop: build(:stop, %{gtfs_id: gtfs_prefix(agency.name) <> Faker.Internet.slug()})
          }),
        intermediate_stops:
          build_list(3, :stop, %{
            gtfs_id: fn ->
              sequence(:intermediate_stop_id, fn _ ->
                gtfs_prefix(agency.name) <> Faker.Internet.slug()
              end)
            end
          }),
        mode: Faker.Util.pick([:TRANSIT, :RAIL, :SUBWAY, :BUS]),
        real_time: true,
        realtime_state: Faker.Util.pick(Leg.realtime_state()),
        route: build(:route),
        to:
          build(:place, %{
            stop: build(:stop, %{gtfs_id: gtfs_prefix(agency.name) <> Faker.Internet.slug()})
          }),
        trip: build(:trip, %{gtfs_id: trip_gtfs_id}),
        transit_leg: true
      })
      |> merge_attributes(attrs)
      |> evaluate_lazy_attributes()
    end

    def walking_leg_factory do
      build(:leg, %{
        mode: :WALK,
        steps: build_list(3, :step),
        transit_leg: false
      })
    end

    def place_factory do
      %Place{
        name: Faker.Address.street_name(),
        lat: Faker.Address.latitude(),
        lon: Faker.Address.longitude(),
        stop: nil
      }
    end

    def route_factory do
      %Route{
        gtfs_id: gtfs_prefix() <> Faker.Internet.slug(),
        short_name: Faker.Person.suffix(),
        long_name: Faker.Color.fancy_name(),
        type: Faker.Util.pick(Route.gtfs_route_type()),
        color: Faker.Color.rgb_hex(),
        text_color: Faker.Color.rgb_hex(),
        desc: Faker.Company.catch_phrase(),
        sort_order: Faker.random_between(100, 1000)
      }
    end

    def step_factory do
      %Step{
        absolute_direction: Faker.Util.pick(Step.absolute_direction()),
        distance: random_distance(),
        relative_direction: Faker.Util.pick(Step.relative_direction()),
        street_name: Faker.Address.street_name()
      }
    end

    def stop_factory do
      %Stop{
        gtfs_id: gtfs_prefix() <> Faker.Internet.slug(),
        name: Faker.Address.city()
      }
    end

    def trip_factory do
      %Trip{
        direction_id: Faker.Util.pick(["0", "1"]),
        gtfs_id: gtfs_prefix() <> Faker.Internet.slug(),
        trip_short_name: [Faker.Internet.slug(), nil] |> Faker.Util.pick(),
        trip_headsign: Faker.Color.fancy_name()
      }
    end

    defp gtfs_prefix(agency_name \\ "MBTA")

    defp gtfs_prefix(agency_name) when agency_name in ["Massport", "Logan Express"],
      do: "massport-ma-us:"

    defp gtfs_prefix(_), do: "mbta-ma-us:"

    defp random_distance, do: Faker.random_uniform() * 2000
    defp random_seconds, do: Faker.random_between(100, 1000)

    def plan_params_factory do
      %PlanParams{
        fromPlace: build(:place_param),
        toPlace: build(:place_param),
        date: build(:date_param),
        time: build(:time_param),
        arriveBy: Faker.Util.pick([true, false]),
        transportModes: build(:modes_param),
        wheelchair: Faker.Util.pick([true, false])
      }
    end

    def modes_param_factory(_) do
      modes =
        Faker.random_between(1, 5)
        |> Faker.Util.sample_uniq(fn ->
          Faker.Util.pick(PlanParams.modes())
        end)
        |> Enum.map(&Map.new(mode: &1))

      sequence(:modes, fn _ -> modes end)
    end

    def date_param_factory(_) do
      formatted =
        Faker.DateTime.forward(2)
        |> Timex.format!("{YYYY}-{0M}-{0D}")

      sequence(:date, fn _ -> formatted end)
    end

    def time_param_factory(_) do
      formatted =
        Faker.DateTime.forward(2)
        |> Timex.format!("{h12}:{m}{am}")

      sequence(:time, fn _ -> formatted end)
    end

    def place_param_factory(_) do
      [:lat_lon_place_param, :stop_place_param]
      |> Faker.Util.pick()
      |> build()
    end

    def lat_lon_place_param_factory(_) do
      lat = Faker.Address.latitude()
      lon = Faker.Address.longitude()

      sequence(
        :other_place,
        fn _ -> "#{Faker.Address.street_name()}::#{lat},#{lon}" end
      )
    end

    def stop_place_param_factory(_) do
      sequence(
        :stop_place,
        fn _ ->
          "#{Faker.Address.street_name()}::#{gtfs_prefix()}:#{Faker.Internet.slug()}"
        end
      )
    end
  end
end
