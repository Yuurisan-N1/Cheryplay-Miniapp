Code.require_file("utils/json.ex", __DIR__)
Code.require_file("utils/banner.ex", __DIR__)

defmodule CherryPlay do
  @moduledoc false

  @my_project "Cherry Play"
  @base_url "https://api.cherryearn.site/api"

  @reset "\e[0m"
  @bold "\e[1m"
  @red "\e[91m"
  @green "\e[92m"
  @yellow "\e[93m"

  def run do
    :logger.set_primary_config(:level, :error)
    install_signal_handler()

    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    Banner.set_title(@my_project)
    Banner.show_banner(@my_project)

    accounts = load_lines("data.txt")

    if accounts == [] do
      red("File data.txt is empty, please add your initData entries")
      System.halt(1)
    end

    proxies = load_lines("proxy.txt")
    settings = load_settings()

    loop(accounts, proxies, settings, 1)
  end

  defp loop(accounts, proxies, settings, cycle) do
    yellow("Starting automation cycle number #{cycle}")

    accounts
    |> Enum.with_index()
    |> Enum.each(fn {line, index} ->
      if index > 0, do: IO.puts("")

      proxy = proxy_for(proxies, index)

      if proxy != nil do
        yellow("Using proxy #{mask_proxy(proxy)}")
      end

      try do
        process_account(line, index + 1, proxy)
      rescue
        error ->
          red("Account #{index + 1} was skipped after an unexpected error")
      end
    end)

    sleep = settings["sleep_seconds"] || 3600
    yellow("All accounts were processed for cycle number #{cycle}")
    countdown(sleep, "Next cycle starts in")
    loop(accounts, proxies, settings, cycle + 1)
  end

  defp process_account(init, index, proxy) do
    case request(:get, "/bootstrap", %{}, init, proxy) do
      {:ok, state} ->
        user = state["user"] || %{}
        green("Account #{index} logged in with #{user["balance"]} cherries")
        claim_streak(user, init, proxy)
        claim_friends(user, init, proxy)
        spin_count(user, init, proxy, 1)
        claim_pending(state, init, proxy)
        run_tasks(state, init, proxy)
        run_games(state, init, proxy)
        run_ads(state, init, proxy)
        report_final(init, proxy)

      {:error, _reason} ->
        red("Account #{index} could not be signed in on this run")
    end
  end

  defp claim_streak(user, init, proxy) do
    streak = user["streak"] || %{}

    cond do
      streak["claimed"] ->
        yellow("Daily streak was already collected today")

      true ->
        case request(:post, "/streak/claim", %{}, init, proxy) do
          {:ok, result} ->
            day = get_in(result, ["streak", "count"]) || streak["count"] + 1
            green("Daily streak was claimed for day #{day}")

          {:error, reason} ->
            if to_string(reason) =~ ~r/bio/i do
              yellow("Set your invite link inside your Telegram bio to unlock the daily streak")
            else
              red("Daily streak claim was refused with #{fit(reason)}")
            end
        end
    end
  end

  defp claim_friends(user, init, proxy) do
    if is_integer(user["ref_pending"]) and user["ref_pending"] > 0 do
      case request(:post, "/friends/claim", %{}, init, proxy) do
        {:ok, result} -> green("Friend rewards of #{result["reward"]} cherries were claimed")
        {:error, reason} -> red("Friend rewards claim was refused with #{fit(reason)}")
      end
    else
      yellow("No friend rewards were ready to claim")
    end
  end

  defp spin_count(user, init, proxy, tries) do
    spins = user["spins_left"] || 0

    cond do
      spins > 0 ->
        run_spins(spins, init, proxy)

      tries > 0 ->
        case watch_ad("spin", nil, init, proxy) do
          {:ok, _result} ->
            green("Extra lucky spin was earned from an advertisement")
            spin_count(%{"spins_left" => 1}, init, proxy, tries - 1)

          {:error, reason} ->
            red("Extra spin advertisement was refused with #{fit(reason)}")
        end

      true ->
        yellow("No lucky spins were left for this account")
    end
  end

  defp run_spins(0, _init, _proxy), do: :ok

  defp run_spins(left, init, proxy) do
    case request(:post, "/spin", %{}, init, proxy) do
      {:ok, result} ->
        prize = result["prize"] || "a pending prize"
        green("Lucky spin number #{left} landed on #{prize}")

      {:error, reason} ->
        red("Lucky spin was refused with #{fit(reason)}")
    end

    run_spins(left - 1, init, proxy)
  end

  defp claim_pending(state, init, proxy) do
    pending = state["pending"] || []

    if pending == [] do
      yellow("No pending rewards were ready to claim")
    else
      Enum.each(pending, fn p -> settle_pending(p, init, proxy) end)
    end
  end

  defp settle_pending(p, init, proxy), do: settle_round(p, 0, init, proxy)

  defp settle_round(p, guard, _init, _proxy) when guard >= 10, do: :ok

  defp settle_round(p, guard, init, proxy) do
    case request(:post, "/pending/#{p["id"]}/claim", %{}, init, proxy) do
      {:ok, result} ->
        reward = result["reward"] || p["amount"]
        green("Pending #{p["kind"]} reward was claimed with #{reward} cherries")

      {:error, reason} ->
        text = to_string(reason)

        cond do
          text =~ ~r/already claimed/i ->
            yellow("The pending #{p["kind"]} reward was already settled on this account")

          (more = more_ads(text)) != nil ->
            watch_claim_ads(p, more, init, proxy)
            settle_round(p, guard + 1, init, proxy)

          true ->
            red("Pending #{p["kind"]} claim was refused with #{fit(reason)}")
        end
    end
  end

  defp watch_claim_ads(p, left, init, proxy) do
    case watch_ad("claim", p["id"], init, proxy) do
      {:ok, _result} ->
        green("Claim advertisement for #{p["kind"]} was watched on this account")

        case request(:post, "/pending/#{p["id"]}/claim", %{}, init, proxy) do
          {:ok, result} ->
            reward = result["reward"] || p["amount"]
            green("Pending #{p["kind"]} reward was claimed with #{reward} cherries")

          {:error, reason} ->
            text = to_string(reason)

            cond do
              text =~ ~r/already claimed/i ->
                yellow("The pending #{p["kind"]} reward was already settled on this account")

              (more = more_ads(text)) != nil ->
                watch_claim_ads(p, more, init, proxy)

              (seconds = wait_seconds(text)) != nil ->
                countdown(seconds + 1, "Waiting for the next claim ad in")
                watch_claim_ads(p, left, init, proxy)

              true ->
                red("Pending #{p["kind"]} claim was refused with #{fit(reason)}")
                watch_claim_ads(p, left - 1, init, proxy)
            end
        end

      {:error, reason} ->
        text = to_string(reason)

        case wait_seconds(text) do
          nil ->
            red("Claim advertisement was refused with #{fit(reason)}")
            watch_claim_ads(p, left - 1, init, proxy)

          seconds ->
            countdown(seconds + 1, "Waiting for the next claim ad in")
            watch_claim_ads(p, left, init, proxy)
        end
    end
  end

  defp more_ads(text) do
    case Regex.run(~r/watch (\d+) more ad/i, text) do
      [_, count] -> String.to_integer(count)
      _other -> nil
    end
  end

  defp wait_seconds(reason) do
    case Regex.run(~r/next ad in (\d+)/i, to_string(reason)) do
      [_, seconds] -> String.to_integer(seconds)
      _other -> nil
    end
  end

  defp run_tasks(state, init, proxy) do
    tasks = state["tasks"] || []
    regular = Enum.filter(tasks, fn t -> t["check"] != "ad" and t["state"] != "done" end)
    ad_tasks = Enum.filter(tasks, fn t -> t["check"] == "ad" and t["state"] != "done" end)

    if regular == [] and ad_tasks == [] do
      yellow("Every available task was already completed on this account")
    else
      unless regular == [] do
        yellow("Found #{length(regular)} tasks to process for this account")
      end

      unless ad_tasks == [] do
        yellow("Found #{length(ad_tasks)} rewarded ad tasks to process for this account")
      end
    end

    Enum.each(regular, fn task ->
      case request(:post, "/tasks/#{task["id"]}/start", %{}, init, proxy) do
        {:ok, %{"verified" => true}} ->
          finish_task(task, init, proxy)

        {:ok, %{"wait" => wait}} ->
          countdown(wait, "Verifying #{task["title"] |> shorten(24)} in")

          case request(:post, "/tasks/#{task["id"]}/verify", %{}, init, proxy) do
            {:ok, _result} -> finish_task(task, init, proxy)
            {:error, reason} -> red("Task #{task["title"] |> shorten(30)} was refused with #{fit(reason)}")
          end

        {:ok, _result} ->
          finish_task(task, init, proxy)

        {:error, reason} ->
          unless String.downcase(reason) =~ "already done" do
            red("Task #{task["title"] |> shorten(30)} was refused with #{fit(reason)}")
          end
      end
    end)

    Enum.each(ad_tasks, fn task ->
      case watch_ad("task", task["id"], init, proxy) do
        {:ok, _result} ->
          green("Rewarded advertisement for #{task["title"] |> shorten(30)} was watched")

          case request(:post, "/tasks/#{task["id"]}/claim", %{}, init, proxy) do
            {:ok, result} ->
              reward = result["reward"] || task["reward"]
              green("Task #{task["title"] |> shorten(30)} was claimed with #{reward} cherries")

            {:error, reason} ->
              red("Task #{task["title"] |> shorten(30)} was refused with #{fit(reason)}")
          end

        {:error, reason} ->
          red("Rewarded advertisement was refused with #{fit(reason)}")
      end
    end)
  end

  defp finish_task(task, init, proxy) do
    case request(:post, "/tasks/#{task["id"]}/claim", %{}, init, proxy) do
      {:ok, result} ->
        reward = result["reward"] || task["reward"]
        green("Task #{task["title"] |> shorten(30)} was claimed with #{reward} cherries")

      {:error, reason} ->
        red("Task #{task["title"] |> shorten(30)} was refused with #{fit(reason)}")
    end
  end

  defp run_games(state, init, proxy) do
    games = Enum.filter(state["games"] || [], fn g -> (g["plays_left"] || 0) > 0 end)

    if games == [] do
      yellow("Every arcade game was already played for this period")
    else
      Enum.each(games, fn game ->
        plays_left = game["plays_left"]
        play_game(game, plays_left, init, proxy)
      end)
    end
  end

  defp play_game(_game, 0, _init, _proxy), do: :ok

  defp play_game(game, left, init, proxy) do
    case request(:post, "/games/#{game["code"]}/start", %{"difficulty" => "hard"}, init, proxy) do
      {:ok, session} ->
        min = session["min_seconds"] || 3
        Process.sleep((min + 2) * 1000)
        score = 4000 + :rand.uniform(2001) - 1

        case request(:post, "/games/finish", %{"session" => session["session"], "score" => score}, init, proxy) do
          {:ok, result} ->
            reward = result["reward"] || 0
            green("Game #{game["code"]} was played with score #{score} and paid #{reward} cherries")

          {:error, reason} ->
            red("Game #{game["code"]} round was refused with #{fit(reason)}")
        end

      {:error, reason} ->
        if String.downcase(reason) =~ "claim your last reward" do
          settle_game_pending(game["code"], init, proxy)
          play_game(game, 1, init, proxy)
        else
          red("Game #{game["code"]} start was refused with #{fit(reason)}")
        end
    end

    play_game(game, left - 1, init, proxy)
  end

  defp settle_game_pending(code, init, proxy) do
    case request(:get, "/bootstrap", %{}, init, proxy) do
      {:ok, state} ->
        (state["pending"] || [])
        |> Enum.filter(fn p -> p["kind"] == "game" end)
        |> Enum.each(fn p -> settle_pending(p, init, proxy) end)

      {:error, reason} ->
        red("Game #{code} pending was refused with #{fit(reason)}")
    end
  end

  defp run_ads(state, init, proxy) do
    ads = state["ads"] || %{}
    block = ads["task_block"] || %{}
    left = block["left"] || 0

    if left <= 0 do
      yellow("The sponsored ad tasks were already exhausted for this period")
    else
      watch_ads(left, init, proxy)
    end
  end

  defp watch_ads(0, _init, _proxy), do: :ok

  defp watch_ads(left, init, proxy) do
    case watch_ad("ad_task", nil, init, proxy) do
      {:ok, result} ->
        reward = result["reward"] || 0
        green("Sponsored ad task was watched and paid #{reward} cherries")
        watch_ads(left - 1, init, proxy)

      {:error, reason} ->
        text = to_string(reason)

        cond do
          text =~ ~r/not available/i ->
            yellow("The sponsored ad tasks are not available on this account for now")

          (seconds = wait_seconds(text)) != nil ->
            countdown(seconds + 1, "Waiting for the next ad task in")
            watch_ads(left, init, proxy)

          true ->
            red("Sponsored ad task was refused with #{fit(reason)}")
            watch_ads(left - 1, init, proxy)
        end
    end
  end

  defp watch_ad(placement, ref, init, proxy), do: watch_ad(placement, ref, init, proxy, 6)

  defp watch_ad(_placement, _ref, _init, _proxy, 0), do: {:error, "the advertisement was refused too many times"}

  defp watch_ad(placement, ref, init, proxy, tries) do
    case do_watch(placement, ref, init, proxy) do
      {:error, reason} = result ->
        case wait_seconds(reason) do
          nil ->
            result

          seconds ->
            countdown(seconds + 1, "Waiting for the next advertisement in")
            watch_ad(placement, ref, init, proxy, tries - 1)
        end

      result ->
        result
    end
  end

  defp do_watch(placement, ref, init, proxy) do
    payload = if ref, do: %{"placement" => placement, "ref" => ref}, else: %{"placement" => placement}

    case request(:post, "/ads/start", payload, init, proxy) do
      {:ok, start} ->
        min = start["min_watch"] || 5
        Process.sleep((min + 2) * 1000)
        request(:post, "/ads/complete", %{"token" => start["token"], "shown" => 1, "clicks" => 0}, init, proxy)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp report_final(init, proxy) do
    case request(:get, "/bootstrap", %{}, init, proxy) do
      {:ok, state} ->
        user = state["user"] || %{}
        green("Cycle closed with a balance of #{user["balance"]} cherries")

      {:error, _reason} ->
        yellow("The final balance could not be read on this run")
    end
  end

  defp shorten(value, max) do
    value = to_string(value)
    if String.length(value) <= max, do: value, else: String.slice(value, 0, max) <> "…"
  end

  defp load_lines(name) do
    case File.read(Path.join(__DIR__, name)) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:error, _reason} ->
        []
    end
  end

  defp load_settings do
    path = Path.join(__DIR__, "config.json")

    case File.read(path) do
      {:ok, content} ->
        case YuurisanJSON.decode(content) do
          {:ok, %{"settings" => settings}} -> settings
          {:ok, settings} when is_map(settings) -> settings
          _other -> %{}
        end

      {:error, _reason} ->
        %{}
    end
  end

  defp request(method, path, payload, init, proxy) do
    url = String.to_charlist(@base_url <> path)
    {profile, auth} = proxy_setup(proxy)

    headers =
      [
        {~c"content-type", ~c"application/json"},
        {~c"accept", ~c"*/*"},
        {~c"accept-language", ~c"en-US,en;q=0.9"},
        {~c"origin", ~c"https://cherryearn.site"},
        {~c"referer", ~c"https://cherryearn.site/"},
        {~c"authorization", String.to_charlist("tma " <> init)},
        {~c"user-agent",
         ~c"Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Mobile Safari/537.36"}
      ]

    body = payload |> YuurisanJSON.encode()

    options = [ssl: [verify: :verify_none], timeout: 30_000, connect_timeout: 15_000] ++ auth

    dispatch(method, url, headers, body, options, profile)
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp dispatch(:get, url, headers, _body, options, profile) do
    handle(:httpc.request(:get, {url, headers}, options, [body_format: :binary], profile))
  end

  defp dispatch(:post, url, headers, body, options, profile) do
    handle(
      :httpc.request(
        :post,
        {url, headers, ~c"application/json", body},
        options,
        [body_format: :binary],
        profile
      )
    )
  end

  defp handle({:ok, {{_version, status, _reason}, _headers, response}})
       when status >= 200 and status < 300 do
    case YuurisanJSON.decode(response) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, "unreadable response"}
    end
  end

  defp handle({:ok, {{_version, status, _reason}, _headers, response}}) do
    case YuurisanJSON.decode(response) do
      {:ok, %{"error" => error}} -> {:error, error}
      {:ok, %{"message" => message}} -> {:error, message}
      {:ok, _value} -> {:error, "HTTP #{status}"}
      {:error, _reason} -> {:error, "HTTP #{status}"}
    end
  end

  defp handle({:error, reason}), do: {:error, reason}

  defp proxy_setup(nil), do: {:default, []}

  defp proxy_setup(line) do
    case parse_proxy(line) do
      {host, port, user, pass} -> proxy_profile(host, port, user, pass)
      {host, port} -> proxy_profile(host, port, "", "")
      nil -> {:default, []}
    end
  end

  defp proxy_profile(host, port, user, pass) do
    name = String.to_atom("proxy_#{host}_#{port}")
    address = {String.to_charlist(host), port}

    case :inets.start(:httpc, profile: name) do
      {:ok, _pid} -> :httpc.set_options([proxy: {address, []}, https_proxy: {address, []}], name)
      {:error, {:already_started, _pid}} -> :ok
      _other -> :ok
    end

    case user do
      "" -> {name, []}
      _ -> {name, [proxy_auth: {String.to_charlist(user), String.to_charlist(pass)}]}
    end
  end

  defp parse_proxy(line) do
    value =
      line
      |> String.trim()
      |> String.replace_prefix("http://", "")
      |> String.replace_prefix("https://", "")
      |> String.replace_prefix("socks5://", "")

    case String.split(value, "@") do
      [credentials, host_part] ->
        case String.split(credentials, ":") do
          [user, pass] -> with_host_port(host_part, user, pass)
          _other -> with_host_port(host_part, "", "")
        end

      [host_part] ->
        case String.split(host_part, ":") do
          [host, port] -> with_port(host, port)
          [host, port, user, pass] -> with_port_creds(host, port, user, pass)
          _other -> nil
        end
    end
  end

  defp with_host_port(host_part, user, pass) do
    case String.split(host_part, ":") do
      [host, port] -> with_port_creds(host, port, user, pass)
      _other -> nil
    end
  end

  defp with_port(host, port) do
    case Integer.parse(port) do
      {number, ""} -> {host, number}
      _other -> nil
    end
  end

  defp with_port_creds(host, port, user, pass) do
    case Integer.parse(port) do
      {number, ""} -> {host, number, user, pass}
      _other -> nil
    end
  end

  defp mask_proxy(line) do
    case parse_proxy(line) do
      {host, port, _user, _pass} -> "http://user:pass@#{mask_host(host)}:#{port}"
      {host, port} -> "http://user:pass@#{mask_host(host)}:#{port}"
      nil -> "http://user:pass@***:***"
    end
  end

  defp mask_host(host) do
    parts = String.split(host, ".")

    case parts do
      [a, _b, _c, d] ->
        "#{a}*****#{d}"

      _other ->
        if String.length(host) > 4 do
          String.slice(host, 0, 2) <> "*****" <> String.slice(host, -2, 2)
        else
          "***"
        end
    end
  end

  defp proxy_for([], _index), do: nil
  defp proxy_for(proxies, index), do: Enum.at(proxies, rem(index, length(proxies)))

  defp install_signal_handler do
    System.trap_signal(:sigint, :cherryplay_stop, fn _signal ->
      IO.write("\n" <> @red <> @bold <> "Script stopped by user" <> @reset <> "\n")
      System.stop(0)
    end)
  rescue
    _error -> :ok
  end

  defp fit(text), do: to_string(text)

  defp countdown(seconds, label) do
    left = max(trunc(seconds), 0)

    if left >= 1 do
      width = frame(label, left, 0)
      tick(left, label, width)
    end
  end

  defp tick(0, _label, width) do
    IO.write("\r" <> String.duplicate(" ", width) <> "\r")
  end

  defp tick(left, label, width) do
    width = frame(label, left, width)
    :timer.sleep(1000)
    tick(left - 1, label, width)
  end

  defp frame(label, left, width) do
    text = label <> " " <> format_duration(left)
    IO.write("\r" <> @yellow <> @bold <> text <> @reset)
    max(width, String.length(text))
  end

  defp format_duration(total) do
    days = div(total, 86_400)
    hours = div(rem(total, 86_400), 3600)
    minutes = div(rem(total, 3600), 60)
    seconds = rem(total, 60)

    if days > 0 do
      pad(days) <> ":" <> pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    else
      pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    end
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")

  defp green(message), do: IO.puts(@green <> @bold <> fit(message) <> @reset)
  defp yellow(message), do: IO.puts(@yellow <> @bold <> fit(message) <> @reset)
  defp red(message), do: IO.puts(@red <> @bold <> fit(message) <> @reset)
end

CherryPlay.run()
