defmodule ElixirconfAvNetwork.Web do
  @moduledoc """
  The entrypoint for defining your web interface.
  """

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {ElixirconfAvNetwork.Web.LayoutView, :live}

      unquote(view_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  defp view_helpers do
    quote do
      use Phoenix.HTML
      import Phoenix.LiveView.Helpers
      import Phoenix.View
      alias ElixirconfAvNetwork.Web.Router.Helpers, as: Routes
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
