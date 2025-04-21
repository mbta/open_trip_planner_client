defmodule OpenTripPlannerClient.ItineraryGroup do
  @moduledoc """
  Group itineraries by unique legs.

  A unique leg is defined as a leg that has a unique combination of mode, from, and to.
  But, this does not include walking legs that are less than 0.2 miles.
  """

  alias OpenTripPlannerClient.ItineraryTag
  alias OpenTripPlannerClient.Schema.{Itinerary, Leg, Route}

  @type t :: %__MODULE__{
          itineraries: [Itinerary.t()],
          representative_index: non_neg_integer(),
          time_key: :start | :end
        }

  defstruct [
    :itineraries,
    :representative_index,
    :time_key
  ]

  @max_per_group 4
  @num_groups 5
  @short_walk_threshold_minutes 5

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
    |> Enum.map(&truncate_list(&1, opts))
    |> Enum.reject(&Enum.empty?/1)
    |> Enum.map(&to_group(&1, opts))
    |> Enum.sort_by(&tag_priority/1)
    |> Enum.take(Keyword.get(opts, :num_groups, @num_groups))
  end

  defp truncate_list({_, grouped_itineraries}, opts) do
    if opts[:take_from_end] do
      grouped_itineraries
      |> ItineraryTag.sort_tagged(:end)
      |> Enum.take(-@max_per_group)
    else
      grouped_itineraries
      |> ItineraryTag.sort_tagged(:start)
      |> Enum.take(@max_per_group)
    end
  end

  defp to_group(grouped_itineraries, opts) do
    representative_index = if(opts[:take_from_end], do: -1, else: 0)
    time_key = if(opts[:take_from_end], do: :end, else: :start)

    %__MODULE__{
      itineraries: grouped_itineraries,
      representative_index: representative_index,
      time_key: time_key
    }
  end

  @spec leg_summaries(__MODULE__.t()) :: [%{walk_minutes: non_neg_integer(), routes: [Route.t()]}]
  def leg_summaries(%__MODULE__{itineraries: itineraries}) do
    itineraries
    |> Enum.map(& &1.legs)
    |> Enum.zip_with(&Function.identity/1)
    |> Enum.map(&aggregate_legs/1)
    |> remove_short_intermediate_walks()
  end

  defp aggregate_legs(legs) do
    legs
    |> Enum.uniq_by(&combined_leg_to_tuple/1)
    |> Enum.reduce(%{walk_minutes: 0, routes: []}, &summarize_legs/2)
  end

  defp combined_leg_to_tuple(%Leg{transit_leg: false} = leg) do
    Leg.group_identifier(leg)
  end

  defp combined_leg_to_tuple(%Leg{route: route} = leg) do
    {route.gtfs_id, leg.from.name, leg.to.name}
  end

  defp summarize_legs(%Leg{duration: duration, transit_leg: false}, summary) do
    minutes = Timex.Duration.to_minutes(duration, :seconds)

    summary
    |> Map.update!(:walk_minutes, &(&1 + minutes))
  end

  defp summarize_legs(%Leg{route: route}, summary) do
    summary
    |> Map.update!(:routes, fn routes ->
      [route | routes]
      |> Enum.sort_by(& &1.sort_order)
    end)
  end

  defp remove_short_intermediate_walks(summarized_legs) do
    summarized_legs
    |> Enum.with_index()
    |> Enum.reject(fn {leg, index} ->
      index > 0 && index < length(summarized_legs) - 1 &&
        (leg.routes == [] && leg.walk_minutes < @short_walk_threshold_minutes)
    end)
    |> Enum.map(fn {leg, _} -> leg end)
  end

  @spec tag_priority(__MODULE__.t()) :: non_neg_integer() | nil
  defp tag_priority(itinerary_group) do
    itinerary_group
    |> representative_itinerary()
    |> Map.get(:tag)
    |> then(fn representative_tag ->
      Enum.find_index(
        ItineraryTag.tag_priority_order(),
        &(&1 == representative_tag)
      )
    end)
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
