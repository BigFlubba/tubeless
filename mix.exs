defmodule Pinchflat.MixProject do
  use Mix.Project

  def project do
    [
      app: :pinchflat,
      # x-release-please-start-version
      version: "0.1.0",
      # x-release-please-end-version
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: System.get_env("EX_CHECK") == "1"],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # The OTP application stays `:pinchflat` (internal), but the release — and
      # therefore the `bin/` launcher the overlay scripts exec — is named `tubeless`.
      releases: [
        tubeless: [
          applications: [pinchflat: :permanent]
        ]
      ],
      preferred_cli_env: [
        check: :test,
        credo: :test
      ],
      test_coverage: [
        ignore_modules: [
          Pinchflat.HTTP.HTTPClient,
          PinchflatWeb.Layouts,
          Pinchflat.DataCase,
          Pinchflat.Release,
          # Runtime wiring with no testable logic
          Pinchflat.Application,
          Pinchflat.PromEx,
          PinchflatWeb.Telemetry,
          # Test support (like DataCase above)
          Pinchflat.TestingHelperMethods,
          ~r/Fixtures/,
          ~r/HTML$/
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Pinchflat.Application, []},
      extra_applications: [:logger, :runtime_tools, :inets, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto, "~> 3.12.3"},
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, "~> 0.19.0"},
      {:ecto_sqlite3_extras, "~> 1.2.0"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.2"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5.0", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.3"},
      {:finch, "~> 0.18"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2"},
      {:plug_cowboy, "~> 2.5"},
      {:oban, "~> 2.17"},
      {:nimble_parsec, "~> 1.4"},
      {:timex, "~> 3.7"},
      {:prom_ex, "~> 1.11"},
      {:mox, "~> 1.0", only: :test},
      {:credo, "~> 1.7.7", only: [:dev, :test], runtime: false},
      {:credo_naming, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16.0", only: [:dev, :test], runtime: false},
      {:faker, "~> 0.19", only: :test},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      check: "check --config=tooling/.check.exs",
      credo: "credo --config-file=tooling/.credo.exs",
      setup: ["deps.get", "cmd ./tooling/fetch-sqlean.sh", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"],
      "ecto.migrate": [
        "ecto.migrate",
        ~s(cmd sh -c '[ -z "$MIX_ENV" ] && yarn run create-erd || echo "No ERD generated"')
      ],
      "ecto.rollback": [
        "ecto.rollback",
        ~s(cmd sh -c '[ -z "$MIX_ENV" ] && yarn run create-erd || echo "No ERD generated"')
      ],
      "version.bump": "cmd ./tooling/version_bump.sh"
    ]
  end
end
