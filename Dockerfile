FROM elixir:1.9.4

ARG MIX_ENV
RUN apt-get update && apt-get install -y inotify-tools

# install toolchain
RUN curl https://sh.rustup.rs -sSf | \
    sh -s -- --default-toolchain stable -y

ENV PATH=/root/.cargo/bin:$PATH

WORKDIR "/opt/app"

RUN mix local.hex --force && mix local.rebar --force

COPY config/* config/
COPY mix.exs ./
RUN HEX_HTTP_TIMEOUT=240 MIX_ENV=$MIX_ENV mix do deps.get, deps.compile

COPY . ./

CMD ["sh", "bin/endpoint.sh"]