defmodule FirmbootReference.MixProject do
  use Mix.Project

  def project do
    [
      app: :firmboot_reference,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      deps: []
    ]
  end

  def application, do: [extra_applications: [:crypto]]
end
