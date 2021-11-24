defmodule Hello162.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Hello162.Repo,
      # Start the Telemetry supervisor
      Hello162Web.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Hello162.PubSub},
      # Start the Endpoint (http/https)
      Hello162Web.Endpoint
      # Start a worker by calling: Hello162.Worker.start_link(arg)
      # {Hello162.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hello162.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Hello162Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
