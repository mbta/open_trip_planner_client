# OpenTripPlannerClient

[![Documentation](https://img.shields.io/badge/-Documentation-blueviolet)](http://mbta.github.io/open_trip_planner_client/)
![Test, Docs,
Release](https://github.com/mbta/open_trip_planner_client/workflows/Test,%20Docs,%20Release/badge.svg)
[![Last
Updated](https://img.shields.io/github/last-commit/mbta/open_trip_planner_client.svg)](https://github.com/mbta/open_trip_planner_client/commits/main)

Shared functionality for working with
[OpenTripPlanner](https://docs.opentripplanner.org/en/v2.5.0/), curated to the
MBTA's needs.

> #### Use with caution {: .warning}
>
> This is in early stages and we expect things can change! Contribution welcomed.

## Installation

Github-hosted Elixir libraries such as this one can be added to a project's dependencies in `mix.exs` in this way:

```elixir
def deps do
  [
    %{:open_trip_planner_client,
      [
        github: "mbta/open_trip_planner_client",
        ref: "v0.11.1"
      ]}
  ]
end
```

Then run `mix deps.get`.

## Configuration

The library expects a URL to a running instance of OpenTripPlanner, and a
timezone name that's used to parse and format input `DateTime`s into the correct
strings for input into OpenTripPlanner. Valid timezone names are from the Olson
database; valid values can be found using
[`Timex.timezones/0`](https://hexdocs.pm/timex/Timex.html#timezones/0). Ideally
the timezone matches that configured in the OpenTripPlanner instance.

### OpenTripPlanner requirements

The OpenTripPlanner instance needs to be version 2, with the GraphQL API
enabled. 

If using the
[`transitModelTimeZone`](https://docs.opentripplanner.org/en/v2.4.0/BuildConfiguration/?h=timezone#transitModelTimeZone)
build parameter, it should be consistent with the timezone name indicated in
this configuration.

```elixir
config :open_trip_planner_client,
  otp_url: "http://localhost:8080",
  timezone: "America/New_York"
```

### Optional requirements

We include a factory (`OpenTripPlannerClient.Test.Support.Factory`) to help with testing your usage of OpenTripPlanner.
In order to use it, you'll also need to include the deps [ex_machina](https://hexdocs.pm/ex_machina/readme.html) and [faker](https://hexdocs.pm/faker/readme.html).

```
{:ex_machina, "2.8.0", only: [:dev, :test]},
{:faker, "0.18.0", only: [:dev, :test]},
```

If you don't want or need the test helper and don't want or need ExMachina or Faker, no need to do anything.
The library simply won't export the helper.

## Usage

Documentation is automatically generated with every
[release](https://github.com/mbta/open_trip_planner_client/releases), and
the latest docs are published on [Github
Pages](http://mbta.github.io/open_trip_planner_client/).

### Trip planning

At minimum, origin and destination must specify any `:name` and either a valid `:stop_id` or `:latitude` and `:longitude`.

```elixir
origin = %{name: "North Station", stop_id: "place-north"}
destination = %{name: "Park Plaza", latitude: 42.348777, longitude: -71.066481}
plan_params = OpenTripPlannerClient.PlanParams.new(origin, destination)
{:ok, plan} = OpenTripPlannerClient.plan(plan_params)
```

The `t:OpenTripPlannerClient.PlanParams.opts/0` type describes additional parameters, which include specifying custom departure or arrival times, filtering for wheelchair accessibility, or customizing which transit modes are used in the plan.

```elixir
OpenTripPlannerClient.PlanParams.new(origin, destination, datetime: ~N[2025-05-15T09:00:00] |> DateTime.from_naive!("America/New_York"), arrive_by: true)
OpenTripPlannerClient.PlanParams.new(origin, destination, wheelchair: false, arrive_by: false)
OpenTripPlannerClient.PlanParams.new(origin, destination, mode: [:RAIL, :SUBWAY], num_itineraries: 20)
```

The list of itineraries returned are directly from
OpenTripPlanner, and consumers are expected to handle further parsing. Refer to the [test fixture](/test/fixture/alewife_to_franklin_park_zoo.json) for expected fields.

### Trip planning with tagging

This optional feature will score the list of itineraries against a specified
criteria. This client provides several tag implementations, and it's also
possible to create custom tags, by implementing the
`OpenTripPlannerClient.ItineraryTag` behaviour.


```elixir
alias OpenTripPlannerClient.ItineraryTag

tags = [
  ItineraryTag.EarliestArrival,
  ItineraryTag.LeastWalking,
  ItineraryTag.ShortestTrip
]

{:ok, itineraries} = plan(params, tags)
```

The returned itineraries include an extra field, `"tag"`, which will contain the relevant tag.

```elixir
[:shortest_trip, :least_walking, nil] = Enum.map(itineraries, &Map.get(&1, "tag"))
```

## License

TBD
