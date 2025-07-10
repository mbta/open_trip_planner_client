defmodule OpenTripPlannerClient.GettextPlural do
  @moduledoc """
  This module defines plural form equations for languages for PO files.

  Plural forms are documented in the gettext docs here:
  https://www.gnu.org/software/gettext/manual/gettext.html#Plural-forms

  There's a list of plural forms for most languages here:
  https://docs.translatehouse.org/projects/localization-guide/en/latest/l10n/pluralforms.html
  """
  @behaviour Gettext.Plural

  # Haitian Creole is not supported by default by Gettext.Plural
  @impl Gettext.Plural
  def nplurals("ht"), do: 2

  # Fall back to Gettext.Plural
  defdelegate nplurals(locale), to: Gettext.Plural

  # Haitian Creole is not supported by default by Gettext.Plural
  @impl Gettext.Plural
  def plural("ht", 1), do: 0
  def plural("ht", _), do: 1

  # Fall back to Gettext.Plural
  defdelegate plural(locale, n), to: Gettext.Plural
end
