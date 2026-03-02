import Config

# secret_key_base jest wymagany dla sesji Phoenix, CSRF i LiveView.
# W produkcji (Nerves): ustaw zmienną środowiskową SECRET_KEY_BASE przed startem.
# Generuj: mix phx.gen.secret
# Na Nerves: np. w config :nerves, :erlinit, env: ["SECRET_KEY_BASE=..."]
# lub przez Nerves.Runtime.KV / rootfs_overlay.
secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    case Config.config_env() do
      :prod ->
        raise """
        Brak zmiennej środowiskowej SECRET_KEY_BASE w produkcji.
        Uruchom: mix phx.gen.secret
        Następnie ustaw SECRET_KEY_BASE w środowisku uruchomieniowym (np. erlinit).
        """

      _ ->
        # Development/test - fallback (min. 64 znaki)
        "dev_secret_key_base_64_chars_minimum_for_phoenix_token_signing_abc123"
    end

config :elixirconf_av_network, ElixirconfAvNetwork.Web.Endpoint, secret_key_base: secret_key_base
