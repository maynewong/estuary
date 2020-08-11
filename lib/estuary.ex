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
      |> parse_feed(v[:css], v[:type])

    end

    Logger.info("run before interval...")
    Process.sleep(:timer.seconds(@time_interval))
    Logger.info("run after interval...")
    run()
  end

  def parse_feed(feed, css, type) do
    end_time = DateTime.add(DateTime.utc_now(), -@time_interval)

    # parse feed while the updated > end time
    Enum.reduce_while(feed.entries, 0, fn entry, acc ->
      updated_at = entry.updated || entry.published
      {:ok, updated, 0} = if is_datetime?(updated_at) do
                            {:ok, updated_at, 0}
                          else
                            DateTime.from_iso8601(to_string(entry.updated))
                          end

      Logger.info("fetch updated: #{updated}")
      if DateTime.compare(updated, end_time) != :lt do
        Logger.info "Start parse_feed: #{updated}, #{end_time}"
        cond do 
          type == 'direct' ->
            parse_link_by_css(entry.content, css, type)
            |> IO.iodata_to_binary
            |> send_message(entry.title)
          true ->
            entry.url
            |> HTTPoison.get!([], [follow_redirect: true])
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
    Logger.info "Start send message to slackbot: #{title}"
    json = %{text: "#{title} \n" <> message} |> Poison.encode!
  
    HTTPoison.post(
      Application.fetch_env!(:estuary, :slack_webhooks),
      json,
      [{"Content-Type", "application/json"}]
    )
  end


  def parse_link_by_css(document, css_selector, type) do
    import Meeseeks.CSS

    for story <- Meeseeks.all(document, css(css_selector)) do
      element = Meeseeks.one(story, css("a"))
      title = if type == "direct" do
                Meeseeks.text(element)
              else
                ""
              end
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

  def is_datetime?(time) do
    case DateTime.from_iso8601(time) do
      {:ok, _} -> true
      _ -> false
    end
  end

end
