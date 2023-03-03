FROM elixir:latest

RUN mkdir /app
WORKDIR /app 

RUN mix do local.hex --force, local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

COPY main.ex .
COPY lib lib

RUN mix compile

EXPOSE 8080

CMD ["mix", "run", "main.ex"]


