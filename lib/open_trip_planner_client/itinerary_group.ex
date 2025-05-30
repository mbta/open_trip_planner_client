defmodule OpenTripPlannerClient.ItineraryGroup do
  @moduledoc """
  Group itineraries by unique legs.

  A unique leg is defined as a leg that has a unique combination of mode, from, and to.
  But, this does not include walking legs that are less than 0.2 miles.
  """

  alias OpenTripPlannerClient.ItineraryTag
  alias OpenTripPlannerClient.Schema.{Itinerary, Leg}

  @type t :: %__MODULE__{
          itineraries: [Itinerary.t()],
          summary: [Leg.leg_summary()],
          representative_index: non_neg_integer(),
          time_key: :start | :end
        }

  defstruct [
    :itineraries,
    :summary,
    :representative_index,
    :time_key
  ]

  @max_per_group 4
  @num_groups 5

  @doc """
  From a large list of itineraries, collect them into #{@num_groups} groups of at most
  #{@max_per_group} itineraries each, sorting the groups in favor of tagged
  groups first.

  A different numbers of groups can be specified via the second argument.

  ```elixir
  _ = groups_from_itineraries(itineraries, num_groups: 8)
  ```
  """
  @spec groups_from_itineraries([Itinerary.t()], Keyword.t()) :: [%__MODULE__{}]
  def groups_from_itineraries(itineraries, opts \\ []) do
    itineraries
    |> Enum.group_by(&Itinerary.group_identifier/1)
    |> Enum.map(&to_group(&1, opts))
    |> Enum.sort_by(&tag_and_cost_sorter/1)
    |> Enum.take(Keyword.get(opts, :num_groups, @num_groups))
  end

  defp truncate_list(grouped_itineraries, opts) do
    if opts[:take_from_end] do
      grouped_itineraries
      |> Enum.sort_by(&DateTime.to_unix(&1.end))
      |> Enum.take(-@max_per_group)
    else
      grouped_itineraries
      |> Enum.sort_by(&DateTime.to_unix(&1.start))
      |> Enum.take(@max_per_group)
    end
  end

  defp to_group({_, all_itineraries}, opts) do
    limited_itineraries = truncate_list(all_itineraries, opts)
    summary = summary(all_itineraries)
    representative_index = if(opts[:take_from_end], do: length(limited_itineraries) - 1, else: 0)
    time_key = if(opts[:take_from_end], do: :end, else: :start)

    %__MODULE__{
      itineraries: limited_itineraries,
      summary: summary,
      representative_index: representative_index,
      time_key: time_key
    }
  end

  @doc """
  An aggregation of `Itinerary.summary/1` for an itinerary group. Because itineraries
  in a given group contain similar sequences of legs (as computed by
  `Leg.group_identifier/1`), we can summarize across many itineraries by aggregating
  one leg at a time.

  Corresponding walking legs in a given group have the same from/to location and are
  assumed to have the same duration, so we can just pick one, additionally rounding to
  the nearest integer.

  `[%{walk_minutes: 3.75}, %{walk_minutes: 3.75}, %{walk_minutes: 3.75}]` --> `%{walk_minutes: 4}`

  Corresponding transit legs may use different routes, so these are collected together:

  `[%{routes: [A]}, %{routes: [B]}, %{routes: [C]}]` --> `%{routes: [A, B, C]}`
  """
  @spec summary([Itinerary.t()]) :: [Leg.leg_summary()]
  def summary(itineraries) do
    itineraries
    |> Enum.map(&Itinerary.summary/1)
    |> aggregate_summaries()
  end

  defp aggregate_summaries(itinerary_summaries) do
    itinerary_summaries
    |> Enum.zip()
    |> Enum.map(fn leg_summaries ->
      leg_summaries
      |> Tuple.to_list()
      |> aggregate_leg_summaries()
    end)
  end

  defp aggregate_leg_summaries([%{routes: routes} | _] = summaries) when routes != [] do
    summaries
    |> Enum.flat_map(& &1.routes)
    |> Enum.uniq()
    |> Enum.sort_by(& &1.sort_order)
    |> then(&%{routes: &1, walk_minutes: 0})
  end

  defp aggregate_leg_summaries(walks) do
    walks
    |> Enum.map(& &1.walk_minutes)
    |> Enum.filter(&(&1 > 0))
    |> List.first(0)
    |> then(&%{routes: [], walk_minutes: &1})
  end

  # Sorting first by tag priority, then by increasing generalized cost
  @spec tag_and_cost_sorter(__MODULE__.t()) :: tuple()
  defp tag_and_cost_sorter(itinerary_group) do
    itinerary = representative_itinerary(itinerary_group)
    {ItineraryTag.tag_order(itinerary[:tag]), itinerary[:generalized_cost]}
  end

  @spec representative_itinerary(__MODULE__.t()) :: Itinerary.t()
  def representative_itinerary(%__MODULE__{
        itineraries: itineraries,
        representative_index: representative_index
      }) do
    Enum.at(itineraries, representative_index, List.first(itineraries))
  end

  @spec all_times(__MODULE__.t()) :: [DateTime.t()]
  def all_times(%__MODULE__{itineraries: itineraries, time_key: time_key}) do
    Enum.map(itineraries, &Map.get(&1, time_key))
  end

  @doc """
  Formatted list of times arriving or departing.
  """
  @spec alternatives_text(__MODULE__.t()) :: String.t() | nil
  @spec alternatives_text([DateTime.t()], :start | :end) :: String.t() | nil
  def alternatives_text(
        %__MODULE__{representative_index: representative_index, time_key: time_key} =
          itinerary_group
      ) do
    itinerary_group
    |> all_times()
    |> List.delete_at(representative_index)
    |> alternatives_text(time_key)
  end

  @doc """
  Formatted list of times arriving or departing.
  """
  @spec alternatives_text([DateTime.t()], :start | :end) :: String.t() | nil
  def alternatives_text([], _), do: nil
  def alternatives_text([time], :start), do: "Similar trip departs at #{time(time)}"
  def alternatives_text([time], :end), do: "Similar trip arrives at #{time(time)}"

  def alternatives_text(times, :start),
    do: "Similar trips depart at #{Enum.map_join(times, ", ", &time/1)}"

  def alternatives_text(times, :end),
    do: "Similar trips arrive at #{Enum.map_join(times, ", ", &time/1)}"

  defp time(time), do: Timex.format!(time, "%-I:%M", :strftime)
end
