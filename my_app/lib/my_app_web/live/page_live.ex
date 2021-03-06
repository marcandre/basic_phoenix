defmodule MyAppWeb.PageLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, query: "", results: %{})}
  end

  @impl true
  def handle_event("suggest", %{"q" => query}, socket) do
    {:noreply, assign(socket, results: search(query), query: query)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    case search(query) do
      %{^query => vsn} ->
        {:noreply, redirect(socket, external: "https://hexdocs.pm/#{query}/#{vsn}")}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "No dependencies found matching \"#{query}\"")
         |> assign(results: %{}, query: query)}
    end
  end

  defp search(query) do
    if not MyAppWeb.Endpoint.config(:code_reloader) do
      raise "action disabled when not in development"
    end

    for {app, desc, vsn} <- Application.started_applications(),
        app = to_string(app),
        String.starts_with?(app, query) and not List.starts_with?(desc, ~c"ERTS"),
        into: %{},
        do: {app, vsn}
  end

  defmacro example_leex(assigns) do
    IO.inspect("This will print, at compile time, a string containing 42")
    IO.inspect(assigns)

    quote do
      ~L"""
      <p>Hello</p>
      """
    end
  end

  defmacro example_heex(assigns) do
    IO.inspect("The goal is to also print here, at compile time, a string containing 42")
    IO.inspect(assigns)

    quote do
      ~H"""
      <p>Hello</p>
      """
    end
  end
end
