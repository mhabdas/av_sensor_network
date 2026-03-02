defmodule ElixirconfAvNetwork.Web.Router do
  use ElixirconfAvNetwork.Web, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {ElixirconfAvNetwork.Web.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", ElixirconfAvNetwork.Web do
    pipe_through(:browser)

    live("/sensor-dashboard", Live.SensorDashboardLive, :index)
  end
end
