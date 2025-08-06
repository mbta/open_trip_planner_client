defmodule OpenTripPlannerClient.PlanParams do
  @moduledoc """
  Data type describing params for the planConnection query.
  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/queries/planConnection
  """
  @doc "Data type describing params for the planConnection query.
  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/queries/planConnection"
  @derive Jason.Encoder
  defstruct [
    :origin,
    :destination,
    :dateTime,
    numItineraries: 5,
    transportModes: [
      %{mode: :RAIL},
      %{mode: :SUBWAY},
      %{mode: :TRAM},
      %{mode: :BUS},
      %{mode: :FERRY}
    ],
    wheelchair: false
  ]

  @typedoc """
  Datetime of departure or arrival in ISO8601Extended format. Default value: current datetime
  """
  @type datetime :: String.t()
  @type datetime_map :: %{earliestDeparture: datetime()} | %{latestArrival: datetime()}

  @typedoc """
  List of transportation modes that the user is willing to use.
  """
  @type transport_modes :: nonempty_list(transport_mode())
  @typep transport_mode :: %{mode: mode_t()}

  @modes [
    :AIRPLANE,
    :BUS,
    :CABLE_CAR,
    # Private car trips shared with others
    :CARPOOL,
    :COACH,
    :FERRY,
    :FUNICULAR,
    :GONDOLA,
    # Railway in which the track consists of a single rail or a beam.
    :MONORAIL,
    # This includes long or short distance trains.
    :RAIL,
    # Subway or metro, depending on the local terminology.
    :SUBWAY,
    # A taxi, possibly operated by a public transport agency.
    :TAXI,
    :TRAM,
    # Electric buses that draw power from overhead wires using poles.
    :TROLLEYBUS
  ]

  @typedoc """
  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/TransitMode
  """
  @type mode_t ::
          unquote(
            @modes
            |> Enum.map_join(" | ", &inspect/1)
            |> Code.string_to_quoted!()
          )

  @typedoc """
  Whether the itinerary must be wheelchair accessible. Default value: false
  """
  @type wheelchair :: boolean()

  @typedoc """
  Specifying an origin or destination for trip planning.
  """
  @type place_map :: %{name: String.t(), latitude: float(), longitude: float()}
  @type place_location_input :: %{
          label: String.t(),
          location: %{
            coordinate: %{
              latitude: float(),
              longitude: float()
            }
          }
        }

  @typedoc """
  Customization options for trip planning.

  * `:arrive_by` - Whether to plan to arrive at a certain time, or, if set to
    `false`, depart at a certain time. Defalts to false.
  * `:datetime` - The DateTime to depart from the origin or arrive at the
    destination. Defaults to now.
  * `:modes` - The transit modes to be used in the plan. Defaults to all modes.
  * `:num_itineraries` - The maximum number of itineraries to return. Defaults
    to 5.
  * `:wheelchair` - Whether to limit itineraries to those that are wheelchair 
    accessible. Defaults to false.

  """
  @type opts :: [
          arrive_by: boolean(),
          datetime: DateTime.t(),
          modes: [mode_t()],
          num_itineraries: non_neg_integer(),
          wheelchair: boolean()
        ]

  @typedoc """
  Arguments for the OTP plan query.
  """
  @type t :: %__MODULE__{
          origin: place_location_input(),
          dateTime: datetime_map(),
          numItineraries: integer(),
          destination: place_location_input(),
          transportModes: map(),
          wheelchair: wheelchair()
        }

  @spec modes :: [mode_t()]
  def modes, do: @modes

  @doc """
  Arguments to send to OpenTripPlanner's `plan` query. 

  Defaults to 5 itineraries departing at the current time via walking or any mode of transit.
  """
  @spec new(place_map(), place_map(), opts()) :: t()
  def new(origin, destination, opts \\ []) do
    datetime = Keyword.get(opts, :datetime, OpenTripPlannerClient.Util.local_now())
    modes = Keyword.get(opts, :modes, [])

    %__MODULE__{
      origin: to_location_param(origin),
      destination: to_location_param(destination),
      dateTime: Keyword.get(opts, :arrive_by, false) |> to_datetime_param(datetime),
      numItineraries: Keyword.get(opts, :num_itineraries, 5),
      transportModes: to_modes_param(modes),
      wheelchair: Keyword.get(opts, :wheelchair, false)
    }
  end

  @spec to_modes_param([mode_t()]) :: map()
  # Will default to all modes being usable
  defp to_modes_param([]), do: %{}

  defp to_modes_param(modes) do
    modes
    |> then(fn modes ->
      if :SUBWAY in modes do
        [:TRAM | modes]
      else
        modes
      end
    end)
    |> Enum.map(&Map.new(mode: &1))
    |> then(
      &%{
        transit: %{
          transit: &1
        }
      }
    )
  end

  @spec to_datetime_param(boolean(), DateTime.t()) :: map()
  defp to_datetime_param(true, datetime) do
    %{latestArrival: DateTime.to_iso8601(datetime)}
  end

  defp to_datetime_param(false, datetime) do
    %{earliestDeparture: DateTime.to_iso8601(datetime)}
  end

  @spec to_location_param(place_map()) :: place_location_input()
  defp to_location_param(%{name: name} = map) do
    %{label: name, location: %{coordinate: Map.take(map, [:latitude, :longitude])}}
  end
end
