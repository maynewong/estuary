defmodule Estuary do
  @moduledoc """
  Documentation for `Estuary`.
  """
  require Logger
  use Task
  use Timex
  import Meeseeks.CSS

  @time_interval Application.fetch_env!(:estuary, :time_interval)
  @slack_webhooks Application.fetch_env!(:estuary, :slack_webhooks)

  def start_link() do
    Task.start_link(Estuary, :run, [])
  end

  def run() do
    rss_map = Application.fetch_env!(:estuary, :rss_map)
    for {rss_name, v} <- rss_map do
      Logger.info "Start request #{rss_name}, rss_url: #{v[:url]}"
      try do
        v[:url]
        |> HTTPoison.get!([], [follow_redirect: true, timeout: 30_000, recv_timeout: 30_000])
        |> Map.get(:body)
        |> Feedraptor.parse()
        |> parse_feed(v[:css], v[:type])
      rescue
        e in HTTPoison.Error -> Logger.info "Request Error: #{e.reason}, #{rss_name}"
        e in Protocol.UndefinedError -> Logger.info "#{Exception.message(e)}, #{rss_name}"
        e in RuntimeError -> Logger.info "#{Exception.message(e)}, #{rss_name}"
      end
    end

    Logger.info("run before interval...")
    Process.sleep(:timer.seconds(@time_interval))
    Logger.info("run after interval...")
    run()
  end

  def parse_feed(feed, css, type) do
    end_time = Timex.shift(Timex.now, seconds: -@time_interval)

    # parse feed while the updated > end time
    Enum.reduce_while(feed.entries, 0, fn entry, acc ->
      updated = entry.updated || entry.published

      Logger.info("fetch updated: #{updated}")
      if Timex.Comparable.compare(updated, end_time) != -1 do
        Logger.info "Start parse_feed: #{updated}, #{end_time}"
        cond do
          type == 'direct' ->
            parse_link_by_css(entry.content, css, type)
            |> IO.iodata_to_binary
            |> send_message(entry.title)
          true ->
            entry.url
            |> HTTPoison.get!([], [follow_redirect: true, timeout: 30_000, recv_timeout: 30_000])
            |> Map.get(:body)
            |> parse_link_by_css(css, type)
            |> IO.iodata_to_binary
            |> send_message(entry.title)
        end
        {:cont, acc}
      else
        {:halt, acc}
      end
    end)
  end

  def send_message(message, title) do
    Logger.info "Start send message to slackbot: #{title}, #{message}"
    json = %{text: "#{title} \n" <> message} |> Poison.encode!

    Logger.info "End send message,  #{json}"
    HTTPoison.post(
      @slack_webhooks,
      json,
      [{"Content-Type", "application/json"}]
    )
  end


  def parse_link_by_css(document, css_selector, type) do
    for story <- Meeseeks.all(document, css(css_selector)) do
      element = Meeseeks.one(story, css("a"))
      element_title = Meeseeks.text(element) || ""
      element_url = Meeseeks.attr(element, "href") || ""
      title = cond do
                element_title != "" and type == 'dirct' ->
                  element_title
                element_title != "" ->
                  parse_url_title(element_url)
                true ->
                  ""
              end
      if title != "" do
        url = element_url |> generate_url_shortener
        "- #{title}: #{url}\n"
      else
        ""
      end
    end
  end

  def generate_url_shortener(url) do
    "http://tinyurl.com/api-create.php?url=#{url}"
    |> HTTPoison.get!([], [follow_redirect: true, timeout: 30_000, recv_timeout: 30_000])
    |> Map.get(:body)
  end

  def parse_url_title(url) do
    url
    |> HTTPoison.get!([], [follow_redirect: true, timeout: 30_000, recv_timeout: 30_000])
    |> Map.get(:body)
    |> Meeseeks.one(css("head > title"))
    |> Meeseeks.text
  end

end
