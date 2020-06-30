defmodule Estuary do
  @moduledoc """
  Documentation for `Estuary`.
  """
  require Logger

  def main() do
    rss_map = Application.fetch_env!(:estuary, :rss_map)
    for {k, v} <- rss_map do
      Logger.info "Start request rss_url: #{v[:url]}"

      v[:url]
      |> HTTPoison.get!
      |> Map.get(:body)
      |> Feedraptor.parse
      |> parse_feed(v[:css])

    end
  end

  def parse_feed(feed, css) do
    time_interval = Application.fetch_env!(:estuary, :time_interval)
    end_time = DateTime.add(DateTime.utc_now(), -time_interval)

    # parse feed while the updated > end time
    Enum.reduce_while(feed.entries, 0, fn entry, acc ->
      {:ok, updated, 0} = DateTime.from_iso8601(to_string(entry.updated))
      if updated > end_time do
        parse_link_by_css(entry.content, css)
        |> IO.iodata_to_binary
        |> send_message(entry.title)
        {:cont, acc}
      else
        {:halt, acc}
      end
    end)
  end

  def send_message(message, title) do
    Logger.info "Start send message to slackbot: #{title}"
    json = %{text: "#{title} \n" <> message} |> Poison.encode!
  
    HTTPoison.post(
      Application.fetch_env!(:estuary, :slack_webhooks),
      json,
      [{"Content-Type", "application/json"}]
    )
  end


  def parse_link_by_css(document, css_selector) do
    import Meeseeks.CSS

    for story <- Meeseeks.all(document, css(css_selector)) do
      title = Meeseeks.one(story, css("a")) |> Meeseeks.text
      if title != nil do
        url = Meeseeks.attr(element, "href") |> generate_url_shortener

        "- #{title}: #{url}\n"
      else
        ""
      end
    end
  end

  def generate_url_shortener(url) do
    "http://tinyurl.com/api-create.php?url=#{url}"
    |> HTTPoison.get!
    |> Map.get(:body)
  end

end
