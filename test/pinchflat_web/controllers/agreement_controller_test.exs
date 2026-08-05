defmodule PinchflatWeb.AgreementControllerTest do
  use PinchflatWeb.ConnCase

  alias Pinchflat.Settings
  alias Pinchflat.Settings.UserAgreement

  @moduletag :skip_user_agreement

  describe "GET /agreement" do
    test "renders the agreement when it hasn't been accepted", %{conn: conn} do
      conn = get(conn, ~p"/agreement")

      assert html_response(conn, 200) =~ "User Agreement"
    end

    test "renders the text of DISCLAIMER.md as HTML", %{conn: conn} do
      conn = get(conn, ~p"/agreement")

      response = html_response(conn, 200)

      assert response =~ "Disclaimer of warranties"
      # The Markdown is rendered, not dumped verbatim
      refute response =~ "## 6."
    end

    test "shows the version and effective date the document declares", %{conn: conn} do
      conn = get(conn, ~p"/agreement")

      response = html_response(conn, 200)

      assert response =~ "Version #{UserAgreement.version()}"
      assert response =~ "Effective #{UserAgreement.effective_date()}"
    end

    test "tells a first-run user to accept it", %{conn: conn} do
      conn = get(conn, ~p"/agreement")

      assert html_response(conn, 200) =~ "start using Tubeless"
    end

    test "tells a returning user the agreement has been updated", %{conn: conn} do
      Settings.set(agreement_accepted_version: "some-old-version")

      conn = get(conn, ~p"/agreement")

      assert html_response(conn, 200) =~ "has been updated"
    end

    test "redirects home when the agreement has already been accepted", %{conn: conn} do
      UserAgreement.accept()

      conn = get(conn, ~p"/agreement")

      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /agreement" do
    test "records acceptance and redirects home", %{conn: conn} do
      conn = post(conn, ~p"/agreement", %{"agreement" => %{"accepted" => "true"}})

      assert redirected_to(conn) == ~p"/"
      assert UserAgreement.accepted?()
    end

    test "re-renders with an error when the box isn't checked", %{conn: conn} do
      conn = post(conn, ~p"/agreement", %{})

      assert html_response(conn, 200) =~ "User Agreement"
      refute UserAgreement.accepted?()
    end
  end

  describe "the user agreement gate" do
    test "redirects browser pages to the agreement", %{conn: conn} do
      conn = get(conn, ~p"/sources")

      assert redirected_to(conn) == ~p"/agreement"
    end

    test "refuses non-GET requests to browser routes", %{conn: conn} do
      conn = post(conn, ~p"/diagnostics/reset_retryable_jobs")

      assert response(conn, 403)
    end

    test "lets browser pages through once accepted", %{conn: conn} do
      UserAgreement.accept()

      conn = get(conn, ~p"/sources")

      assert html_response(conn, 200)
    end

    test "doesn't gate the healthcheck", %{conn: conn} do
      conn = get(conn, ~p"/healthcheck")

      assert response(conn, 200)
    end
  end
end
