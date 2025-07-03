defmodule OpenTripPlannerClient.Gettext do
  @moduledoc """
  Gettext backend to support translations in `OpenTripPlannerClient`.

  Usage:

  ```elixir
  use Gettext, backend: OpenTripPlannerClient.Gettext

  # in your functions, and so on
  gettext("Some text string")
  ```

  """

  use Gettext.Backend,
    default_domain: "open_trip_planner_client",
    default_locale: :en,
    locales: ["es", "fr", "ht", "pt-BR", "vi", "zh-CN", "zh-TW"],
    otp_app: :open_trip_planner_client,
    plural_forms: OpenTripPlannerClient.GettextPlural,
    priv: "priv/gettext"
end
