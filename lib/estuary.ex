defmodule Estuary do
  @moduledoc """
  Documentation for `Estuary`.
  """

  def main(url) do
    url
    |> fetch_rss
    |> parse_content
  end

  def fetch_rss(url) do
    HTTPoison.start
    response = HTTPoison.get!(url)
    Feedraptor.parse(response.body)
  end

  def parse_content(map_rss) do
    time_interval = Application.fetch_env!(:estuary, :time_interval)
    end_time = DateTime.add(DateTime.utc_now(), -time_interval)
    IO.puts(end_time)

    # parse rss while the updated > end time
    Enum.reduce_while(map_rss.entries, 0, fn entry, acc ->
      {:ok, updated, 0} = DateTime.from_iso8601(to_string(entry.updated))
      if updated > end_time do
        parse_link(entry.content, "span > a")
        |> join_strings
        |> send_message(entry.title)
        {:cont, acc}
      else
        {:halt, acc}
      end
    end)
  end

  def send_message(message, title) do
    json = %{text: "#{title} \n" <> message} |> Poison.encode!
    IO.puts(Application.fetch_env!(:estuary, :slack_webhooks))
    HTTPoison.post(
      Application.fetch_env!(:estuary, :slack_webhooks),
      json,
      [{"Content-Type", "application/json"}]
    )
  end

  def join_strings(list) do
    list |> IO.iodata_to_binary
  end

  def parse_link(document, css_selector) do
    import Meeseeks.CSS

    for story <- Meeseeks.all(document, css(css_selector)) do
      element = Meeseeks.one(story, css("a"))
      title = Meeseeks.text(element)
      if title != nil do
        url = Meeseeks.attr(element, "href") |> generate_url_shortener()
        "- #{title}: #{url}\n"
      else
        ""
      end
    end
  end

  def generate_url_shortener(url) do
    response = HTTPoison.get!("http://tinyurl.com/api-create.php?url=#{url}")
    response.body
  end

end
