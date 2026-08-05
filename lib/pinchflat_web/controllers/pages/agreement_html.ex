defmodule PinchflatWeb.Pages.AgreementHTML do
  use PinchflatWeb, :html

  alias Pinchflat.Settings.UserAgreement
  alias PinchflatWeb.Helpers.MarkdownHelpers

  embed_templates "agreement_html/*"

  # The agreement ships with the app and can't change at runtime, so it's
  # rendered once at compile time rather than on every request. Editing
  # DISCLAIMER.md recompiles `UserAgreement` (which declares the file as an
  # `@external_resource`), which recompiles this module in turn.
  @agreement_html MarkdownHelpers.to_html!(UserAgreement.markdown())

  @doc """
  The user agreement text, rendered from `DISCLAIMER.md`.
  """
  def agreement_text(assigns) do
    assigns = assign(assigns, :agreement_html, @agreement_html)

    ~H"""
    {@agreement_html}
    """
  end
end
