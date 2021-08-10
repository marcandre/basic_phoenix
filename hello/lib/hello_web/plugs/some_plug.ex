defmodule HelloWeb.Plugs.SomePlug do
  def init(opts), do: opts

  def call(conn, _opts) do
    conn
  end
end
