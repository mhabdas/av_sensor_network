defmodule ElixirconfAvNetwork.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :elixirconf_av_network

  @session_options [
    store: :cookie,
    key: "_elixirconf_av_network_key",
    signing_salt: "elixirconf_av"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static,
    at: "/",
    from: :elixirconf_av_network,
    gzip: false,
    only: ~w(assets)
  )

  # Serve Phoenix/LiveView JS from deps (fallback when CDN unavailable)
  plug(Plug.Static,
    at: "/vendor/phoenix",
    from: {:phoenix, "priv/static"},
    gzip: false
  )

  plug(Plug.Static,
    at: "/vendor/phoenix_live_view",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false
  )

  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(ElixirconfAvNetwork.Web.Router)
end
