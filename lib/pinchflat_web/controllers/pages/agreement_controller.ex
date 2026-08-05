defmodule PinchflatWeb.Pages.AgreementController do
  use PinchflatWeb, :controller

  alias Pinchflat.Settings.UserAgreement

  @doc """
  Renders the user agreement. Every other HTML page redirects here until it's
  accepted (see `PinchflatWeb.Plugs.require_user_agreement/2`), so this is
  rendered in the chrome-free onboarding layout - there's deliberately nothing
  to navigate to.
  """
  def show(conn, _params) do
    if UserAgreement.accepted?() do
      redirect(conn, to: ~p"/")
    else
      render_agreement(conn)
    end
  end

  @doc """
  Records acceptance of the agreement. The checkbox is enforced here and not
  just in the browser, since the form is the only thing standing between a fresh
  install and the rest of the UI.
  """
  def accept(conn, %{"agreement" => %{"accepted" => "true"}}) do
    case UserAgreement.accept() do
      {:ok, _setting} ->
        redirect(conn, to: ~p"/")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Couldn't save your acceptance. Please try again.")
        |> render_agreement()
    end
  end

  def accept(conn, _params) do
    conn
    |> put_flash(:error, "You must check the box to accept the agreement before continuing.")
    |> render_agreement()
  end

  defp render_agreement(conn) do
    render(conn, :show,
      agreement_version: UserAgreement.version(),
      agreement_effective_date: UserAgreement.effective_date(),
      previously_accepted: UserAgreement.accepted_before?(),
      layout: {Layouts, :onboarding}
    )
  end
end
