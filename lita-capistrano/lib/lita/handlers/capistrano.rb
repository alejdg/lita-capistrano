module Lita
  module Handlers
    class Capistrano < Handler
      require 'net/ssh'

      config :server, type: String, required: true
      config :server_user, type: String, required: true
      config :server_password, type: String, required: true
      config :deploy_tree, type: Hash, required: true

      on :deploy_checked, :deploy_exec
      on :deploy_aborted, :deploy_abort

      route(
        /^capistrano\s+(.+)\s+list$/,
        :cap_list, command: true,
        restrict_to: [:admins],
        help: { "capistrano APP list " => "List available commands for determined application"}
      )

      route(
        /^deploy\s+(.+)\s+(.+)\s+(.+)/,
        :deploy_request, command: true,
        restrict_to: [:admins, :deploy_test],
        help: { "deploy AREA ENV TAG " => "Executa deploy nos ambientes internos"}
      )

      def cap(response)
        env = response.matches[0][0]
        method = response.matches[0][1]

        Net::SSH.start(config.server, config.server_user, :password => config.server_password) do |ssh|
          @output = ssh.exec!("cap #{env} #{method}")
        end

        response.reply(@output)
      end

      def cap_list(response)
        app = response.matches[0][0]
        output = ssh_exec("cd /home/deploy/deploy_#{app}; cap -vT")
        response.reply(output)
      end

      def deploy_request(response)
        app = 'commerce'
        area = response.matches[0][0]
        env = response.matches[0][1]
        tag = response.matches[0][2]

        unless area_exists?(area)
          return response.reply("A área informada é inválida.")
        end
        unless env_exists?(area, env)
          return response.reply("O ambiente informado é inválido.")
        end

        # Pre deploy check
        deploy_in_progress?(app, area, env, tag, response)
      end


      def area_exists?(area)
        config.deploy_tree[:commerce].include?(area.to_sym)
      end

      def env_exists?(area, env)
        config.deploy_tree[:commerce][area.to_sym][:envs].include?(env)
      end

      # If a deploy is in progress the deploy_tracker handler will return a
      # reponse to chat and will interrupt further using the interrupt_deploy
      # method
      def deploy_in_progress?(app, area, env, tag, response)
        robot.trigger(:deploy_in_progress?, app: app, area: area, env: env, tag: tag, response: response)
      end

      def deploy_abort(payload)
        return payload[:response].reply(payload[:msg])
      end

      def deploy_exec(payload)
        app = payload[:app]
        area = payload[:area]
        env = payload[:env]
        tag = payload[:tag]
        response = payload[:response]
        dir = config.deploy_tree[app.to_sym][area.to_sym][:dir]

        # Deploy start
        response.reply("Deploy da tag #{tag} iniciado no ambiente #{env}.")
        start_time = Time.now
        robot.trigger(:deploy_started,
                      app: app,
                      area: area,
                      env: env,
                      tag: tag,
                      start_time: start_time)

        # Deploy execution
        output = deploy(dir, env, tag)
        # After deploy stopped
        finish_time =Time.now

        # The deploy:restart could be in two positions depending on the
        # capistrano config
        if (output.lines.last.include? "deploy:restart") || (output.lines.last(5)[0].include? "deploy:restart")
          robot.trigger(:deploy_finished,
                        app: app,
                        area: area,
                        env: env,
                        tag: tag,
                        start_time: start_time,
                        finish_time: finish_time,
                        status: 'success')
        return response.reply("Deploy da tag #{tag} no ambiente #{env} realizado com sucesso!")
        elsif output.lines.last.include? "status code 32768"
          robot.trigger(:deploy_finished,
                        app: app,
                        area: area,
                        env: env,
                        tag: tag,
                        start_time: start_time,
                        finish_time: finish_time,
                        status: 'invalid tag')
          return response.reply("A tag #{tag} informada não existe. Deploy não realizado.")
        else
          robot.trigger(:deploy_finished,
                        app: app,
                        area: area,
                        env: env,
                        tag: tag,
                        start_time: start_time,
                        finish_time: finish_time,
                        status: 'error')
          return response.reply("Ocorreu um erro na execução do deploy da tag #{tag} no ambiente #{env}.")
        end
      end

      def deploy(dir, env, tag)
        output = ssh_exec("cd #{dir}; cap #{env} deploy tag=#{tag}")
      end

      def ssh_exec(cmd)
        #TODO tornar acesso ao servidor dinamico entro prod e test
        Net::SSH.start(config.server, config.server_user, :password => config.server_password) do |ssh|
          @output = ssh.exec!(cmd)
        end
        @output
      end

      Lita.register_handler(self)
    end
  end
end
