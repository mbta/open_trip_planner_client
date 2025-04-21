defmodule OpenTripPlannerClient.PlanParams do
  @moduledoc """
  Data type describing params for the plan query.
  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/queries/plan
  """

  @doc "Data type describing params for the plan query.
  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/queries/plan"
  @derive Jason.Encoder
  defstruct [
    :fromPlace,
    :toPlace,
    :date,
    :time,
    arriveBy: false,
    numItineraries: 5,
    transportModes: [%{mode: :WALK}, %{mode: :TRANSIT}],
    wheelchair: false
  ]

  @typedoc """
  Whether the itinerary should depart at the specified time (false), or arrive
  to the destination at the specified time (true). Default value: false.
  """
  @type arrive_by :: boolean()

  @typedoc """
  Date of departure or arrival in format YYYY-MM-DD. Default value: current date
  """
  @type date :: String.t()

  @typedoc """
  The place where the itinerary begins or ends in format name::place, where
  place is either a lat,lng pair (e.g. Pasila::60.199041,24.932928) or a stop id
  (e.g. Pasila::HSL:1000202)

  "New England Title Insurance Company, 151 Tremont St, Boston, MA, 02111,
  USA::42.354452,-71.06338" "Newton Highlands::mbta-ma-us:place-nwtn"
  """
  @type place :: String.t()

  @typedoc """
  Time of departure or arrival in format hh:mm:ss. Default value: current time
  """
  @type time :: String.t()

  @typedoc """
  List of transportation modes that the user is willing to use. Default:
  ["WALK","TRANSIT"]
  """
  @type transport_modes :: nonempty_list(transport_mode())
  @typep transport_mode :: %{mode: mode_t()}

  @modes [
    :AIRPLANE,
    :BICYCLE,
    :BUS,
    :CABLE_CAR,
    :CAR,
    # Private car trips shared with others
    :CARPOOL,
    :COACH,
    :FERRY,
    # Enables flexible transit for access and egress legs
    :FLEX,
    :FUNICULAR,
    :GONDOLA,
    # Railway in which the track consists of a single rail or a beam.
    :MONORAIL,
    :RAIL,
    :SCOOTER,
    :SUBWAY,
    # A taxi, possibly operated by a public transport agency.
    :TAXI,
    :TRAM,
    # A special transport mode, which includes all public transport.
    :TRANSIT,
    # Electric buses that draw power from overhead wires using poles.
    :TROLLEYBUS,
    :WALK
  ]

  @typedoc """
  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/Mode
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
  @type place_map ::
          %{name: String.t(), stop_id: String.t()}
          | %{name: String.t(), latitude: float(), longitude: float()}

  @typedoc """
  Customization options for trip planning.

  * `:arrive_by` - Whether to plan to arrive at a certain time, or, if set to
    `false`, depart at a certain time. Defalts to false.
  * `:datetime` - The DateTime to depart from the origin or arrive at the
    destination. Defaults to now.
  * `:modes` - The transit modes to be used in the plan. Defaults to
    [:WALK, :TRANSIT]
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
          arriveBy: arrive_by(),
          fromPlace: place(),
          date: date(),
          numItineraries: integer(),
          time: time(),
          toPlace: place(),
          transportModes: transport_modes(),
          wheelchair: wheelchair()
        }

  @spec modes :: [mode_t()]
  def modes, do: @modes

  @doc """
  Arguments to send to OpenTripPlanner's `plan` query. 

  Defaults to 5 itineraries departing at the current time via walking or any mode of transit.
  """
  @spec new(place_map(), place_map(), opts()) :: t()
  def new(from, to, opts \\ []) do
    datetime = Keyword.get(opts, :datetime, OpenTripPlannerClient.Util.local_now())
    modes = Keyword.get(opts, :modes, [:WALK, :TRANSIT])

    %__MODULE__{
      fromPlace: to_place_param(from),
      toPlace: to_place_param(to),
      arriveBy: Keyword.get(opts, :arrive_by, false),
      date: to_date_param(datetime),
      numItineraries: Keyword.get(opts, :num_itineraries, 5),
      time: to_time_param(datetime),
      transportModes: to_modes_param(modes),
      wheelchair: Keyword.get(opts, :wheelchair, false)
    }
  end

  @spec to_place_param(place_map()) :: place()
  defp to_place_param(%{name: name, stop_id: stop_id}) when is_binary(stop_id) do
    "#{name}::mbta-ma-us:#{stop_id}"
  end

  defp to_place_param(%{name: name, latitude: latitude, longitude: longitude})
       when is_float(latitude) and is_float(longitude) do
    "#{name}::#{latitude},#{longitude}"
  end

  @spec to_modes_param([mode_t()]) :: transport_modes()
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
  end

  @spec to_date_param(DateTime.t()) :: date()
  defp to_date_param(datetime) do
    format_datetime(datetime, "{YYYY}-{0M}-{0D}")
  end

  @spec to_time_param(DateTime.t()) :: time()
  defp to_time_param(datetime) do
    format_datetime(datetime, "{h12}:{m}{am}")
  end

  defp format_datetime(datetime, formatter) do
    Timex.format!(datetime, formatter)
  end
end
