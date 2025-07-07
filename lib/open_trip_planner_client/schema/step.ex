defmodule OpenTripPlannerClient.Schema.Step do
  @moduledoc """
  Part of a walking leg.

  https://docs.opentripplanner.org/api/dev-2.x/graphql-gtfs/types/step
  """

  use Gettext, backend: OpenTripPlannerClient.Gettext
  use OpenTripPlannerClient.Schema

  @absolute_direction [
    :NORTH,
    :NORTHEAST,
    :EAST,
    :SOUTHEAST,
    :SOUTH,
    :SOUTHWEST,
    :WEST,
    :NORTHWEST
  ]

  @typedoc """
  The cardinal (compass) direction taken when engaging a walking/driving step.
  """
  @type absolute_direction ::
          unquote(
            @absolute_direction
            |> Enum.map_join(" | ", &inspect/1)
            |> Code.string_to_quoted!()
          )

  @relative_direction [
    :DEPART,
    :HARD_LEFT,
    :LEFT,
    :SLIGHTLY_LEFT,
    :CONTINUE,
    :SLIGHTLY_RIGHT,
    :RIGHT,
    :HARD_RIGHT,
    :CIRCLE_CLOCKWISE,
    :CIRCLE_COUNTERCLOCKWISE,
    :ELEVATOR,
    :UTURN_LEFT,
    :UTURN_RIGHT,
    :ENTER_STATION,
    :EXIT_STATION,
    :FOLLOW_SIGNS
  ]

  @typedoc """
  Actions to take relative to the current position when engaging a
  walking/driving step.
  """
  @type relative_direction ::
          unquote(
            @relative_direction
            |> Enum.map_join(" | ", &inspect/1)
            |> Code.string_to_quoted!()
          )

  defimpl Nestru.PreDecoder do
    # credo:disable-for-next-line
    def gather_fields_for_decoding(_, _, map) do
      updated_map =
        map
        |> update_in([:absolute_direction], &OpenTripPlannerClient.Util.to_uppercase_atom/1)
        |> update_in([:relative_direction], &OpenTripPlannerClient.Util.to_uppercase_atom/1)

      {:ok, updated_map}
    end
  end

  @derive [
    {Nestru.Decoder,
     hint: %{
       absolute_direction: &__MODULE__.to_atom/1,
       relative_direction: &__MODULE__.to_atom/1
     }}
  ]
  schema do
    field(:distance, distance_meters())
    field(:street_name, String.t())
    field(:absolute_direction, absolute_direction())
    field(:relative_direction, relative_direction())
  end

  @spec absolute_direction :: [absolute_direction()]
  def absolute_direction, do: @absolute_direction

  @spec relative_direction :: [relative_direction()]
  def relative_direction, do: @relative_direction

  @spec to_atom(any()) :: {:ok, any()}
  def to_atom(term), do: {:ok, OpenTripPlannerClient.Util.to_uppercase_atom(term)}

  @doc """
  Generate a friendly description of this walking step.
  """
  @spec walk_summary(t()) :: String.t()
  def walk_summary(%__MODULE__{relative_direction: :DEPART, street_name: "Transfer"}),
    do: gettext("Transfer")

  def walk_summary(%__MODULE__{
        relative_direction: relative_direction,
        street_name: street_name
      }) do
    "#{human_relative_direction(relative_direction)} #{human_relative_preposition(relative_direction)} #{street_name}"
  end

  defp human_relative_direction(:DEPART), do: gettext("Depart")
  defp human_relative_direction(:SLIGHTLY_LEFT), do: gettext("Slightly left")
  defp human_relative_direction(:LEFT), do: gettext("Left")
  defp human_relative_direction(:HARD_LEFT), do: gettext("Hard left")
  defp human_relative_direction(:SLIGHTLY_RIGHT), do: gettext("Slightly right")
  defp human_relative_direction(:RIGHT), do: gettext("Right")
  defp human_relative_direction(:HARD_RIGHT), do: gettext("Hard right")
  defp human_relative_direction(:CONTINUE), do: gettext("Continue")
  defp human_relative_direction(:CIRCLE_CLOCKWISE), do: gettext("Enter the traffic circle")
  defp human_relative_direction(:CIRCLE_COUNTERCLOCKWISE), do: gettext("Enter the traffic circle")
  defp human_relative_direction(:ELEVATOR), do: gettext("Take the elevator")
  defp human_relative_direction(:UTURN_LEFT), do: gettext("Make a U-turn")
  defp human_relative_direction(:UTURN_RIGHT), do: gettext("Make a U-turn")
  defp human_relative_direction(:ENTER_STATION), do: gettext("Enter the station")
  defp human_relative_direction(:EXIT_STATION), do: gettext("Exit the station")
  defp human_relative_direction(:FOLLOW_SIGNS), do: gettext("Follow signs")
  defp human_relative_direction(_), do: "Go"

  defp human_relative_preposition(:FOLLOW_SIGNS), do: gettext("for")
  defp human_relative_preposition(:ENTER_STATION), do: gettext("through")
  defp human_relative_preposition(:EXIT_STATION), do: gettext("towards")
  defp human_relative_preposition(_), do: gettext("onto")
end
