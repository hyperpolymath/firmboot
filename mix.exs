defmodule FirmbootReference.MixProject do
  @moduledoc "Build configuration for the Firmboot reference project."
  use Mix.Project

  @doc "The Mix project configuration: app name, version, Elixir constraint and deps."
  def project do
    [
      app: :firmboot_reference,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      deps: []
    ]
  end

  @doc "Declares `:crypto` as a runtime application, needed by the journal's SHA-256 chain."
  def application, do: [extra_applications: [:crypto]]
end
