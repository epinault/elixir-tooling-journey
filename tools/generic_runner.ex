Code.require_file("gitlab_client.ex")
Code.require_file("slack_client.ex")
Code.require_file("cortex_client.ex")

defmodule GenericRunner do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @options_args [
        gitlab_token: :string,
        claude_token: :string,
        tmp_dir: :string,
        no_clean: :boolean,
        slack_token: :string,
        slack_channel: :string,
        no_slack: :boolean,
        help: :boolean,
        version: :boolean,
        debug: :boolean,
        dry_run: :boolean
      ]

      @options_args_aliases [
        t: :gitlab_token,
        l: :claude_token,
        p: :tmp_dir,
        d: :debug,
        v: :version,
        r: :dry_run,
        c: :slack_channel,
        h: :help
      ]
      def help_message(details) do
        """
        #{details[:cmd_description]}

        ## usage:

            #{details[:cmd_name]} [OPTIONS]

        ## Options

            -t, --gitlab-token      specify your personal Gitlab Token. [Default token is read from #{default_token_file_path()}]
        -l, --claude-token      specify your personal Gitlab Token. [Default token is read from #{default_claude_token_file_path()}]
            -p, --tmp-dir           path to temporary data storage to perform the upgrade locally. [Default: #{default_tmp_path()}]
            -d, --debug             Show debugging logs
            -v, --version           Print version of this script
                --slack-token       Specify the auth token to use for slack notifications. [Default: #{default_slack_token_file_path()}]
            -c, --slack-channel     Specify the Slack channel to use for slack notifications. [Default: #{default_slack_channel()}]
            -r, --dry-run           Dry run. It will do everything up to the MR push/creation. No MR created. Slack is unaffected by Dry run so use with care.
            --no-slack              Disable slack notifications.
            -h, --help              This help
        """
      end

      def run(details) do
        {parsed_args, rest} =
          OptionParser.parse!(System.argv(),
            aliases: @options_args_aliases,
            strict: @options_args
          )

        if parsed_args[:help] do
          Owl.IO.puts(help_message(details))
          exit({:shutdown, 0})
        end

        if parsed_args[:version] do
          Owl.IO.puts("version: #{details[:version]}")
          exit({:shutdown, 0})
        end

        case run(parsed_args, details) do
          :error ->
            exit({:shutdown, 1})

          {:error, _error} ->
            exit({:shutdown, 1})

          _ ->
            Owl.IO.puts("")
        end
      end

      def run(parsed_args, details) do
        with {:ok, token} <- parse_and_validate_token(parsed_args),
             {:ok, tmp_dir} <- parse_and_validate_tmp_dir(parsed_args),
             {:ok, slack_token} <- parse_and_validate_slack_token(parsed_args),
             {:ok, slack_client} <- maybe_create_slack_client(slack_token),
             {:ok, client} <- create_gitlab_client(token) do
          # make a temp dir
          File.mkdir_p!(tmp_dir)

          for repo_path <- repos_to_upgrade(client) do
            with {:ok, project} <- project_details(client, repo_path),
                 Owl.IO.puts("Preparing merge request for #{repo_path} …"),
                 {:ok, resp} <-
                   upgrade_repo(%{
                     project: project,
                     repo: repo_path,
                     repo_path: Path.join([tmp_dir, project["path"]]),
                     branch_name: details[:branch_name],
                     mr_title: details[:mr_title],
                     commit_message: details[:commit_message],
                     commit_files: details[:commit_files],
                     commit_limit: details[:commit_limit],
                     no_slack: details[:no_slack] || parsed_args[:no_slack],
                     slack_client: slack_client,
                     slack_channel: parsed_args[:slack_channel] || default_slack_channel(),
                     slack_message: details[:slack_message],
                     label: details[:label],
                     tmp_dir_path: tmp_dir,
                     client: client,
                     extra_details: details,
                     show_debug: parsed_args[:debug],
                     dry_run: parsed_args[:dry_run]
                   }) do
              Owl.IO.puts(
                "Successfully run create an Merge Request for #{repo_path}. See #{resp}"
              )

              clean_tmp_path(parsed_args[:no_clean], Path.join([tmp_dir, project["path"]]))

              {:ok, resp}
            else
              {:error, error} ->
                Owl.IO.puts(
                  Owl.Data.tag(
                    "ERROR: #{inspect(error)}",
                    :red
                  )
                )

                {:error, error}
            end
          end
        end
      end

      # Override in your runner with whatever filter you need
      # :ok will process it, {:error, "error mess"} will skip it with the reason
      # that will get displayed
      def should_process_repo(upgrade) do
        :ok
      end

      defp upgrade_repo(upgrade) do
        with :ok <- should_process_repo(upgrade),
             :ok <- clone_repo(upgrade),
             :ok <- create_branch(upgrade),
             :ok <- run_upgrade(upgrade),
             :ok <- commit_files(upgrade),
             :ok <- push_branch(upgrade),
             {:ok, mr_details} <- create_mr(upgrade) do
          if upgrade.slack_client do
            notify_slack(upgrade, mr_details)
          end

          {:ok, mr_details}
        else
          {:error, :already_exists} ->
            {:ok, %{}}

          error ->
            error
        end
      end

      defp project_details_by_id(client, id) do
        Owl.IO.puts("Retrieving project details for #{id} …")

        case GitlabClient.project_detail_by_id(client, id) do
          {:ok, %{status: code} = resp} when code == 200 ->
            Owl.IO.puts("Project #{resp.body["name"]} details retrieved! 😎")
            {:ok, resp.body}

          {:ok, resp} ->
            {:error, "Failed to get details for #{id}. #{inspect(resp.body)} (#{resp.status})"}

          error ->
            {:error, "Failed to get details for #{id}. REASON: #{inspect(error)}"}
        end
      end

      defp project_details(client, project_path) do
        Owl.IO.puts("Retrieving project details for #{project_path} …")

        case GitlabClient.project_details(client, project_path) do
          {:ok, %{status: code} = resp} when code == 200 ->
            Owl.IO.puts("Project #{project_path} details retrieved! 😎")
            {:ok, resp.body}

          {:ok, resp} ->
            {:error,
             "Failed to get details for #{project_path}. #{inspect(resp.body)} (#{resp.status})"}

          error ->
            {:error, "Failed to get details for #{project_path}. REASON: #{inspect(error)}"}
        end
      end

      defp get_merge_request(client, project_path) do
        Owl.IO.puts("Retrieving project details for #{project_path} …")

        case GitlabClient.project_details(client, project_path) do
          {:ok, %{status: code} = resp} when code == 200 ->
            Owl.IO.puts("Project #{project_path} details retrieved! 😎")
            {:ok, resp.body}

          {:ok, resp} ->
            {:error,
             "Failed to get details for #{project_path}. #{inspect(resp.body)} (#{resp.status})"}

          error ->
            {:error, "Failed to get details for #{project_path}. REASON: #{inspect(error)}"}
        end
      end

      defp create_gitlab_client(token) do
        {:ok, GitlabClient.client(token)}
      end

      defp create_cortex_client(token) do
        {:ok, CortexClient.client(token)}
      end

      defp maybe_create_slack_client(nil) do
        {:ok, nil}
      end

      defp maybe_create_slack_client(token) do
        {:ok, SlackClient.client(token)}
      end

      defp parse_and_validate_token(parsed_args) do
        case parsed_args[:token] do
          nil ->
            default_path = default_token_file_path()

            with {:ok, _} <- File.stat(default_path),
                 {:ok, data} <-
                   File.read(default_path) do
              {:ok, String.trim(data)}
            else
              error ->
                Owl.IO.puts(
                  Owl.Data.tag(
                    "No Gitlab token specified and could not find #{default_path}.. Please specify a token with -t #{inspect(error)}",
                    :red
                  )
                )

                :error
            end

          _ ->
            {:ok, parsed_args[:token]}
        end
      end

      defp parse_and_validate_slack_token(parsed_args) do
        case parsed_args[:slack_token] do
          nil ->
            default_path = default_slack_token_file_path()

            with {:ok, _} <- File.stat(default_path),
                 {:ok, data} <-
                   File.read(default_path) do
              {:ok, String.trim(data)}
            else
              error ->
                Owl.IO.puts(
                  Owl.Data.tag(
                    "No Slack token specified and could not find #{default_path}.. Will continue without being able to send message to slack. You can specify a token with -s. REASON: #{inspect(error)}",
                    :red
                  )
                )

                {:ok, nil}
            end

          _ ->
            {:ok, parsed_args[:token]}
        end
      end

      defp parse_and_validate_cortex_token(parsed_args) do
        case parsed_args[:cortex_token] do
          nil ->
            default_path = default_cortex_token_file_path()

            with {:ok, _} <- File.stat(default_path),
                 {:ok, data} <-
                   File.read(default_path) do
              {:ok, String.trim(data)}
            else
              error ->
                Owl.IO.puts(
                  Owl.Data.tag(
                    "No Cortex token specified and could not find #{default_path}.. Please specify a token with -c. REASON: #{inspect(error)}",
                    :red
                  )
                )

                :error
            end

          _ ->
            {:ok, parsed_args[:token]}
        end
      end

      defp parse_and_validate_tmp_dir(parsed_args) do
        case parsed_args[:tmp_dir] do
          nil ->
            Owl.IO.puts(
              Owl.Data.tag(
                "No tmp dir specified, using #{default_tmp_path()}.. ",
                :yellow
              )
            )

            {:ok, default_tmp_path()}

          _ ->
            {:ok, parsed_args[:tmp_dir]}
        end
      end

      def notify_slack(upgrade, mr_details) do
        unless upgrade.no_slack || upgrade.dry_run do
          SlackClient.send_message(
            upgrade.slack_client,
            upgrade.slack_channel,
            "#{mr_details} <- #{upgrade.slack_message}"
          )
        else
          debug("Dry run. Skipping Slack notifications...", upgrade[:show_debug])
        end
      end

      def elixir_repo?(upgrade, remote \\ false) do
        res =
          if remote do
            remote_check_elixir_repo(upgrade)
          else
            local_check_elixir_repo(upgrade)
          end

        res == :ok
      end

      def elixir_service?(upgrade, remote \\ false) do
        res =
          if remote do
            remote_check_elixir_service(upgrade)
          else
            local_check_service(upgrade)
          end

        res == :ok
      end

      def python_repo?(upgrade, remote \\ false) do
        res =
          if remote do
            remote_check_python_repo(upgrade)
          else
            local_check_python_repo(upgrade)
          end

        res == :ok
      end

      def python_service?(upgrade, remote \\ false) do
        res =
          if remote do
            remote_check_python_service(upgrade)
          else
            local_check_service(upgrade)
          end

        res == :ok
      end

      def javascript_repo?(upgrade, remote \\ false) do
        res =
          if remote do
            remote_check_js_repo(upgrade)
          else
            local_check_js_repo(upgrade)
          end

        res == :ok
      end

      def local_check_elixir_repo(upgrade) do
        debug(
          "checking if an elixir repo #{upgrade[:repo_path]} locally...",
          upgrade[:show_debug]
        )

        case File.exists?(Path.join([upgrade[:repo_path], "mix.exs"])) do
          true ->
            debug("Repo contains mix.exs, is an elixir repo locally", upgrade[:show_debug])
            :ok

          false ->
            {:error, "Not an elixir repo locally, skipping..."}
        end
      end

      def local_check_python_repo(upgrade) do
        debug(
          "checking if a python repo #{upgrade[:repo_path]} locally...",
          upgrade[:show_debug]
        )

        case File.exists?(Path.join([upgrade[:repo_path], "pyproject.toml"])) do
          true ->
            debug("Repo contains pyproject.toml, is a python repo locally", upgrade[:show_debug])
            :ok

          false ->
            {:error, "Not a python repo locally, skipping..."}
        end
      end

      def local_check_service(upgrade) do
        debug(
          "check if a service for repo #{upgrade[:repo_path]} locally...",
          upgrade[:show_debug]
        )

        with false <-
               File.exists?(Path.join([upgrade[:repo_path], "values-prod-usw2-kubernetes.yaml"])),
             false <-
               File.exists?(Path.join([upgrade[:repo_path], "values-prod-usw2-payments.yaml"])) do
          {:error, "Not a service repo, skipping..."}
        else
          true ->
            debug("Repo is an elixir service locally", upgrade[:show_debug])

            :ok
        end
      end

      def local_check_js_repo(upgrade) do
        debug("checking if a js repo #{upgrade[:repo_path]} locally...", upgrade[:show_debug])

        case File.exists?(Path.join([upgrade[:repo_path], "package.json"])) do
          true ->
            debug("Repo contains package.json, is a js repo locally", upgrade[:show_debug])
            :ok

          false ->
            {:error, "Not a js repo locally, skipping..."}
        end
      end

      def remote_check_python_repo(upgrade) do
        debug("checking if a python repo #{upgrade[:repo]}...", upgrade[:show_debug])

        case GitlabClient.check_file_exists(
               upgrade[:client],
               upgrade[:project]["id"],
               "pyproject.toml"
             ) do
          {:ok, %{status: 200}} ->
            debug("Repo contains pyproject.toml, is a python repo", upgrade[:show_debug])
            :ok

          {:ok, _} ->
            {:error, "Not a python repo, skipping..."}

          error ->
            {:error, "Failed to detect repository #{upgrade[:repo]} #{inspect(error)}"}
        end
      end

      def remote_check_elixir_repo(upgrade) do
        debug("checking if an elixir repo #{upgrade[:repo]}...", upgrade[:show_debug])

        case GitlabClient.check_file_exists(upgrade[:client], upgrade[:project]["id"], "mix.exs") do
          {:ok, %{status: 200}} ->
            debug("Repo contains mix.exs, is an elixir repo", upgrade[:show_debug])
            :ok

          {:ok, _} ->
            {:error, "Not an elixir repo, skipping..."}

          error ->
            {:error, "Failed to detect repository #{upgrade[:repo]} #{inspect(error)}"}
        end
      end

      def remote_check_elixir_service(upgrade) do
        debug("check if a service for repo #{upgrade[:repo]}...", upgrade[:show_debug])

        with {:ok, %{status: 404}} <-
               GitlabClient.check_file_exists(
                 upgrade[:client],
                 upgrade[:project]["id"],
                 "values-prod-usw2-kubernetes.yaml"
               ),
             {:ok, %{status: 404}} <-
               GitlabClient.check_file_exists(
                 upgrade[:client],
                 upgrade[:project]["id"],
                 "values-prod-usw2-k8s-mgmt.yaml"
               ),
             {:ok, %{status: 404}} <-
               GitlabClient.check_file_exists(
                 upgrade[:client],
                 upgrade[:project]["id"],
                 "values-prod-usw2-payments.yaml"
               ) do
          {:error, "Not a service repo, skipping..."}
        else
          {:ok, %{status: 200}} ->
            debug("Repo is an elixir service", upgrade[:show_debug])
            :ok

          {:ok, %{status: status}} ->
            {:error, "Something went wrong. Got status #{status}, skipping..."}

          error ->
            {:error, "Failed to detect repository #{upgrade[:repo]} #{inspect(error)}"}
        end
      end

      def remote_check_python_service(upgrade) do
        debug("check if a service for repo #{upgrade[:repo]}...", upgrade[:show_debug])

        with {:ok, %{status: 404}} <-
               GitlabClient.check_file_exists(
                 upgrade[:client],
                 upgrade[:project]["id"],
                 "values-prod-usw2-kubernetes.yaml"
               ),
             {:ok, %{status: 404}} <-
               GitlabClient.check_file_exists(
                 upgrade[:client],
                 upgrade[:project]["id"],
                 "values-prod-usw2-k8s-mgmt.yaml"
               ),
             {:ok, %{status: 404}} <-
               GitlabClient.check_file_exists(
                 upgrade[:client],
                 upgrade[:project]["id"],
                 "values-prod-usw2-payments.yaml"
               ) do
          {:error, "Not a service repo, skipping..."}
        else
          {:ok, %{status: 200}} ->
            debug("Repo is a python service", upgrade[:show_debug])
            :ok

          {:ok, %{status: status}} ->
            {:error, "Something went wrong. Got status #{status}, skipping..."}

          error ->
            {:error, "Failed to detect repository #{upgrade[:repo]} #{inspect(error)}"}
        end
      end

      def remote_check_js_repo(upgrade) do
        debug("checking if an Javascript repo #{upgrade[:repo]}...", upgrade[:show_debug])

        case GitlabClient.check_file_exists(
               upgrade[:client],
               upgrade[:project]["id"],
               "package.json"
             ) do
          {:ok, %{status: 200}} ->
            debug("Repo contains package.json, is a js repo", upgrade[:show_debug])
            :ok

          {:ok, _} ->
            {:error, "Not an Javascript repo, skipping..."}

          error ->
            {:error, "Failed to detect repository #{upgrade[:repo]} #{inspect(error)}"}
        end
      end

      def clone_repo(upgrade) do
        debug("cloning repo #{upgrade[:repo]}...", upgrade[:show_debug])

        case System.shell(
               "git clone git@gitlab-ssh.podium.com:engineering/#{upgrade[:repo]} #{hide_shell_error(upgrade[:show_debug])}",
               cd: upgrade[:tmp_dir_path]
             ) do
          {_, 0} ->
            :ok

          error ->
            {:error, "Failed to clone repository #{upgrade[:repo]} #{inspect(error)}"}
        end
      end

      def create_branch(upgrade) do
        branch_name = upgrade[:branch_name]

        case System.shell(
               "git checkout -b #{branch_name} #{hide_shell_error(upgrade[:show_debug])}",
               cd: upgrade[:repo_path]
             ) do
          {_, 0} ->
            :ok

          error ->
            {:error, "Failed to create branch #{branch_name}. REASON: #{inspect(error)}"}
        end
      end

      # Override with the code you want to run for this repo upgrade
      def run_upgrade(upgrade) do
        :ok
      end

      def run_deps_and_format(upgrade) do
        with :ok <- run_mix_deps(upgrade) do
          run_mix_format(upgrade)
        end
      end

      def run_mix_deps(upgrade) do
        debug("Running mix deps.get", upgrade[:show_debug])

        with {asdf_install, _} <-
               System.shell(
                 "asdf install",
                 cd: upgrade[:repo_path]
               ),
             debug("asdf install: #{asdf_install}", upgrade[:show_debug]),
             {deps_get, 0} <-
               System.shell(
                 "mix deps.get",
                 cd: upgrade[:repo_path]
               ) do
          debug("mix deps.get: #{deps_get}", upgrade[:show_debug])

          :ok
        else
          error ->
            {:error, "Failed to run mix deps.get #{inspect(error)}"}
        end
      end

      def run_mix_deps_update(upgrade, package) do
        debug("Running mix deps.update #{package}", upgrade[:show_debug])

        with {asdf_install, _} <-
               System.shell(
                 "asdf install",
                 cd: upgrade[:repo_path]
               ),
             debug("asdf install: #{asdf_install}", upgrade[:show_debug]),
             {deps_get, 0} <-
               System.shell(
                 "mix deps.update #{package}",
                 cd: upgrade[:repo_path]
               ) do
          debug("mix deps.update #{package}: #{deps_get}", upgrade[:show_debug])

          :ok
        else
          error ->
            {:error, "Failed to run mix deps.update #{package} #{inspect(error)}"}
        end
      end

      def run_mix_compile(upgrade) do
        debug("Running mix compile", upgrade[:show_debug])

        with {compile, 0} <-
               System.shell(
                 "mix compile",
                 cd: upgrade[:repo_path]
               ) do
          debug("mix compile: #{compile}", upgrade[:show_debug])

          :ok
        else
          error ->
            {:error, "Failed to run mix compile #{inspect(error)}"}
        end
      end

      def run_mix_format(upgrade) do
        debug("Running mix format", upgrade[:show_debug])

        with {format, 0} <-
               System.shell(
                 "mix format",
                 cd: upgrade[:repo_path]
               ) do
          debug("mix format: #{format}", upgrade[:show_debug])

          :ok
        else
          error ->
            {:error, "Failed to run mix format #{inspect(error)}"}
        end
      end

      def load_existing_formatter_config(filename) do
        with {:ok, original_data} <- File.read(filename) do
          {config, _binding} = Code.eval_string(original_data)
          {:ok, config}
        end
      end

      def commit_files(upgrade) do
        commit_message =
          if elixir_service?(upgrade) do
            upgrade[:commit_message]
          else
            upgrade[:commit_message] <> "[skip_publish]"
          end

        commit_files = commit_filelist(upgrade)

        with {_, 0} <-
               System.shell("git add #{Enum.join(commit_files, " ")}", cd: upgrade[:repo_path]),
             {_, 0} <-
               System.shell("git commit -m \"#{commit_message}\"", cd: upgrade[:repo_path]) do
          :ok
        else
          error ->
            {:error, "Failed to commit changes #{inspect(error)}"}
        end
      end

      def commit_filelist(upgrade) do
        if upgrade[:commit_files] do
          upgrade[:commit_files]
        else
          cmd =
            if upgrade[:commit_limit] do
              "git status -s | head -n #{upgrade[:commit_limit]}"
            else
              "git status -s"
            end

          {lines, 0} = System.shell(cmd, cd: upgrade[:repo_path])

          lines
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            [_, _, file] = String.split(line, " ")
            file
          end)
        end
      end

      def push_branch(%{dry_run: true} = upgrade) do
        debug("Dry run. Skipping pushing branch.", upgrade[:show_debug])
        :ok
      end

      def push_branch(upgrade) do
        case System.shell("git push -f #{hide_shell_error(upgrade[:show_debug])}",
               cd: upgrade[:repo_path]
             ) do
          {_, 0} ->
            :ok

          error ->
            {:error, "Failed to push branch #{inspect(error)}"}
        end
      end

      def create_mr(%{dry_run: true} = upgrade) do
        debug("Dry run. Skipping creating MR.", upgrade[:show_debug])
        {:ok, "dry run, no URL"}
      end

      def create_mr(upgrade) do
        title =
          if elixir_service?(upgrade) do
            upgrade[:mr_title]
          else
            upgrade[:mr_title] <> "[skip_publish]"
          end

        labels = upgrade[:label]

        case GitlabClient.create_mr(upgrade[:client], upgrade[:project]["id"], %{
               squash: true,
               allow_collaboration: true,
               remove_source_branch: true,
               skip_ci: true,
               title: title,
               source_branch: upgrade[:branch_name],
               target_branch: "master",
               labels: labels
             }) do
          {:ok, %{status: code} = resp} when code == 201 ->
            {:ok, resp.body["web_url"]}

          {:ok, %{status: code} = resp} when code == 409 ->
            {:ok, resp.body["message"]}

          {:ok, resp} ->
            {:error,
             "Failed to create Merge Request in Gitlab. REASON (#{resp.status}): #{inspect(resp.body)}"}

          error ->
            {:error, "Failed to create Merge Request in Gitlab. REASON: #{inspect(error)}"}
        end
      end

      defp clean_tmp_path(true, _), do: :ok

      defp clean_tmp_path(_, tmp_dir_path) do
        Owl.Spinner.run(
          fn ->
            File.rm_rf(tmp_dir_path)
          end,
          labels: [
            processing: "Cleaning up …",
            ok: "Cleaned up #{tmp_dir_path} 🎉!",
            error: fn error ->
              error
            end
          ]
        )
      end

      def hide_shell_error(debug) do
        case debug do
          true ->
            ""

          _ ->
            "1>/dev/null 2>&1"
        end
      end

      def debug(text, verbose \\ false) do
        if verbose do
          Owl.IO.puts(text)
        end
      end

      def default_token_file_path do
        Path.join([System.get_env("HOME"), ".podium", "gitlab.token"])
      end

      def default_claude_token_file_path do
        Path.join([System.get_env("HOME"), ".podium", "claude.token"])
      end

      def default_cortex_token_file_path do
        Path.join([System.get_env("HOME"), ".podium", "cortex.token"])
      end

      def default_slack_token_file_path do
        Path.join([System.get_env("HOME"), ".podium", "slack_bot.token"])
      end

      def default_tmp_path do
        Path.join([System.get_env("HOME"), "tmp"])
      end

      def default_slack_channel do
        "test__slackr"
      end

      # return a mapset of repos to upgrade of all the projects.
      # you can copy the code into your upgrader if you need
      # to filter out some repo
      def repos_to_upgrade(client) do
        {:ok, map} = GitlabClient.list_projects(client)

        already_done = MapSet.new([])

        MapSet.difference(MapSet.new(map), already_done)
      end

      defoverridable(
        default_slack_channel: 0,
        should_process_repo: 1,
        repos_to_upgrade: 1,
        commit_filelist: 1,
        run_upgrade: 1,
        upgrade_repo: 1,
        help_message: 1,
        run: 2
      )
    end
  end
end
