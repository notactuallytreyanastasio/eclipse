defmodule Eclipse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EclipseWeb.Telemetry,
      Eclipse.Repo,
      {DNSCluster, query: Application.get_env(:eclipse, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Eclipse.PubSub},
      # Start a worker by calling: Eclipse.Worker.start_link(arg)
      # {Eclipse.Worker, arg},
      # Start to serve requests, typically the last entry
      EclipseWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eclipse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EclipseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
