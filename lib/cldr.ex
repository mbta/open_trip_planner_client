defmodule OpenTripPlannerClient.Cldr do
  @moduledoc """
  Define a backend module that will host our
  Cldr configuration and public API.

  Most function calls in Cldr will be calls
  to functions on this module.
  """
  use Cldr,
    default_locale: "en",
    locales: ["es", "fr", "ht", "pt-BR", "vi", "zh-CN", "zh-TW"],
    gettext: OpenTripPlannerClient.Gettext,
    otp_app: :open_trip_planner_client,
    force_locale_download: Mix.env() == :prod,
    providers: [Cldr.Calendar, Cldr.DateTime, Cldr.List, Cldr.Number]
end
