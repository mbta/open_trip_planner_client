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
origin = %{name: "North Station", latitude: 42.3664, longitude: -71.0620}
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

## Auditing station walking connectivity

`scripts/station_connectivity.py` is a read-only local diagnostic for disconnected
platforms. It requires Python 3.10+, GTFS `stops.txt`, a local `.osm.pbf` extract
(ideally the one used to build OTP), and access to the OTP GTFS GraphQL API.
It does not upload GTFS or OSM files or call public mapping services. Only
stop identifiers and routing coordinates are sent to the specified OTP server.

Install the PBF reader in a virtual environment outside the repository:

```bash
python3 -m venv /tmp/otp-connectivity-venv
/tmp/otp-connectivity-venv/bin/pip install -r scripts/station_connectivity_requirements.txt
/tmp/otp-connectivity-venv/bin/python scripts/station_connectivity.py \
  --stops /path/to/stops.txt \
  --osm /path/to/massachusetts.osm.pbf \
  --otp-url http://localhost:8080 \
  --feed-id mbta-ma-us \
  --station place-WR-0120 \
  --output /tmp/reading-connectivity
```

Omit `--station` to check every parent station's child platforms, including ferry
and bus stations. Repeat it to select several stations. Standalone bus stops,
station centroids, entrances, and non-boarding nodes are not audited as platforms.
Stops are matched to OTP's inventory by GTFS ID; use `--feed-id` to disambiguate
multiple imported feeds. Missing stops are reported rather than silently skipped.
An older GTFS file can disagree with the deployed feed.

The script selects OSM street/path nodes 100-500 metres from each platform in
different directions, excluding platform geometry and restricted ways. It checks
walking routes between those targets as controls, then probes each target in
both directions using both platform coordinates and explicit OTP stop IDs.
All routes use `directOnly: true` and `direct: [WALK]`, without transit filters or
a custom walking reluctance.

Outputs are a summary `.csv` and detailed `.jsonl` containing metadata, selected
OSM way/node IDs, OTP version metadata (or an explicit retrieval warning),
routing errors, and returned directions/geometries. Completed
platform results are flushed as the audit progresses; existing outputs are never
overwritten. Default concurrency is two platforms, with sequential probes within
each platform. Use `--workers 1` for lower server load. A platform with three
targets makes 16 routing requests; a complete audit can take considerable time.
Reading a large PBF also requires memory for its node-location index.
Use `--help` for distance, target count, and timeout options.

Interpret results conservatively:

| Classification | Meaning |
| --- | --- |
| `likely_isolated_platform` | All platform probes fail with `NO_DIRECT_MODE_CONNECTION`, but surrounding target controls succeed. |
| `connected` | All coordinate and stop-ID probes and controls succeed. This does not certify every entrance or path. |
| `possible_linking_or_snapping_problem` | Coordinate-based and stop-ID-based results disagree. |
| `partial_or_directional_failure` | Some platform probes succeed and others fail. |
| `inconclusive` | Fewer than three suitable targets, or surrounding controls fail. |
| `missing_otp_stop` | The GTFS platform ID is absent from OTP's stop inventory. |
| `request_error` | Network, GraphQL, or other unexpected routing errors; not proof of disconnection. |

Target selection is heuristic, not a local pedestrian graph analysis. Nodes
may snap differently in OTP, and OSM access tags, barriers, long ways without
nearby nodes, extract boundaries, or legitimate isolated sites can confound
results. A successful response may still contain an unreasonable detour; inspect
the recorded distances and geometry. Confirm flagged stations against the
deployed graph's OSM snapshot and build reports before changing mapping or
pruning settings. The script does not read `graph.obj`, modify OSM, rebuild the
graph, or change the client library's planning behavior.

Exit codes: `0` for a completed audit (including connectivity findings or
inconclusive results), `2` if any platforms have request errors or are missing
from OTP, `1` for execution failures, and `130` for interruption. Argument errors
also use code `2`. On interruption, pending audits are cancelled; in-flight
HTTP requests can take up to the configured timeout to finish.

Run the standalone script tests with:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_station_connectivity.py'
```

## Zizmor

We use [Zizmor](https://docs.zizmor.sh/) to ensure that our Github Actions are configured securely. It runs automatically in CI, but if you'd like to run it locally, you can install it with

```bash
brew install zizmor
zizmor .
```

If you have Github CLI tools installed (`brew install gh`), and are logged in (`gh auth login`), then you can get more informative output by running in "Online Mode":
```bash
zizmor --gh-token $(gh auth token) .
```

And you can have it auto-fix what it can with
```bash
zizmor --gh-token $(gh auth token) --pedantic --fix=all .
```

## License

TBD
