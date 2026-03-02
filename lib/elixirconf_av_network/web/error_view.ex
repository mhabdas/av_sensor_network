defmodule ElixirconfAvNetwork.Web.ErrorView do
  use Phoenix.View,
    root: "lib/elixirconf_av_network/web/templates",
    namespace: ElixirconfAvNetwork.Web

  def render("404.html", _assigns) do
    "Page not found"
  end

  def render("500.html", _assigns) do
    "Internal server error"
  end

  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
