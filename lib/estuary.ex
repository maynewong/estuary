defmodule Estuary do
  @moduledoc """
  Documentation for `Estuary`.
  """
  require Logger
  use Task

  @time_interval Application.fetch_env!(:estuary, :time_interval)

  def start_link() do
    Task.start_link(Estuary, :run, [])
  end

  def run() do
    rss_map = Application.fetch_env!(:estuary, :rss_map)
    for {_, v} <- rss_map do
      Logger.info "Start request rss_url: #{v[:url]}"

      v[:url]
      |> HTTPoison.get!([], [follow_redirect: true])
      |> Map.get(:body)
      |> Feedraptor.parse()
      |> parse_feed(v[:css])

    end

    Logger.info("run before interval...")
    Process.sleep(:timer.seconds(@time_interval))
    Logger.info("run after interval...")
    run()
  end

  def parse_feed(feed, css) do
    end_time = DateTime.add(DateTime.utc_now(), -@time_interval)

    # parse feed while the updated > end time
    Enum.reduce_while(feed.entries, 0, fn entry, acc ->
      {:ok, updated, 0} = DateTime.from_iso8601(to_string(entry.updated))
      Logger.info("fetch updated: #{updated}")
      if DateTime.compare(updated, end_time) != :lt do
        Logger.info "Start parse_feed: #{updated}, #{end_time}"
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
      element = Meeseeks.one(story, css("a"))
      title = Meeseeks.text(element)
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
