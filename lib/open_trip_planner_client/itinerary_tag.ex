defmodule OpenTripPlannerClient.ItineraryTag do
  @moduledoc """
  Logic for a tag which can be applied to itineraries which are the best by some criterion.
  """
  @tag_priority_order [:earliest_arrival, :shortest_trip, :least_walking]

  @callback optimal :: :max | :min
  @callback score(map()) :: number() | nil
  @callback tag :: atom()

  @type t :: module()

  @doc """
  Applies the tag defined by the given module to the itinerary with the optimal score.

  If multiple itineraries are optimal, they will each get the tag.
  If all itineraries have a score of nil, nothing gets the tag.
  """
  @spec apply_tag(t(), [map()]) :: [map()]
  def apply_tag(tag_module, itineraries) do
    scores = itineraries |> Enum.map(&tag_module.score/1)

    {min_score, max_score} =
      scores
      |> Enum.reject(&is_nil/1)
      |> Enum.min_max(fn -> {nil, nil} end)

    best_score =
      case tag_module.optimal() do
        :max -> max_score
        :min -> min_score
      end

    itineraries
    |> Enum.map(&initialize_tags/1)
    |> Enum.zip_with(scores, fn itinerary, score ->
      apply_best(itinerary, tag_module.tag(), score === best_score and not is_nil(score))
    end)
    |> final_tiebreaker(tag_module.tag())
    |> Enum.sort(&tagged_first/2)
  end

  defp initialize_tags(%{"tag" => _} = itinerary), do: itinerary
  defp initialize_tags(itinerary), do: Map.put_new(itinerary, "tag", nil)

  defp apply_best(itinerary, _, false), do: itinerary
  defp apply_best(%{"tag" => nil} = itinerary, tag, _), do: %{itinerary | "tag" => tag}

  defp apply_best(%{"tag" => current_tag} = itinerary, tag, _) do
    if tag_priority(tag) < tag_priority(current_tag) do
      %{itinerary | "tag" => tag}
    else
      itinerary
    end
  end

  defp tag_priority(tag), do: Enum.find_index(@tag_priority_order, &(&1 == tag)) || 0

  defp final_tiebreaker(itineraries, tag) do
    indexed_itineraries =
      itineraries
      |> Enum.with_index()

    tied_indexes =
      indexed_itineraries
      |> Enum.filter(fn {itinerary, _} ->
        itinerary["tag"] == tag
      end)
      |> Enum.map(&elem(&1, 1))

    if Enum.count(tied_indexes) <= 1 do
      itineraries
    else
      winning_index = Enum.random(tied_indexes)

      indexed_itineraries
      |> Enum.map(&to_itinerary(&1, winning_index, tag))
    end
  end

  defp to_itinerary({itinerary, index}, winning_index, _)
       when index == winning_index,
       do: itinerary

  defp to_itinerary({%{"tag" => itinerary_tag} = itinerary, _}, _, tag) when itinerary_tag == tag,
    do: %{itinerary | "tag" => nil}

  defp to_itinerary({itinerary, _}, _, _), do: itinerary

  # Sort itineraries such that the tagged ones are always preceding untagged
  defp tagged_first(%{"tag" => nil}, %{"tag" => nil}), do: true
  defp tagged_first(%{"tag" => _}, %{"tag" => nil}), do: true
  defp tagged_first(%{"tag" => nil}, %{"tag" => _}), do: false
  defp tagged_first(_, _), do: true
end
