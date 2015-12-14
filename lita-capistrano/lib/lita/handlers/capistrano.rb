module Lita
  module Handlers
    class Capistrano < Handler
      require 'net/ssh'

      config :server, type: String, required: true
      config :server_user, type: String, required: true
      config :server_password, type: String, required: true
      config :deploy_tree, type: Hash, required: true

      route(
        /^capistrano\s+(.+)\s+list$/,
        :cap_list, command: true,
        restrict_to: [:admins],
        help: { "capistrano APP list " => "List available commands for determined application"}
      )

      route(
        /^deploy\s+(.+)\s+(.+)\s+(.+)/,
        :deploy_test, command: true,
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

      def deploy_test(response)
        area = response.matches[0][0]
        env = response.matches[0][1]
        tag = response.matches[0][2]

        unless area_exists?(area)
          return response.reply("A área informada é inválida.")
        end
        unless env_exists?(area, env)
          return response.reply("O ambiente informado é inválido.")
        end

        dir = config.deploy_tree[:commerce][area.to_sym][:dir]

        response.reply("Deploy da tag #{tag} iniciado no ambiente #{env}.")
        output = deploy(dir, env, tag)
        # The deploy:restart could be in two positions depending on the
        if (output.lines.last.include? "deploy:restart") || (output.lines.last(5)[0].include? "deploy:restart")
          return response.reply("Deploy da tag #{tag} no ambiente #{env} realizado com sucesso!")
        elsif output.lines.last.include? "status code 32768"
          return response.reply("A tag #{tag} informada não existe. Deploy não realizado.")
        else
          return response.reply("Ocorreu um erro na execução do deploy da tag #{tag} no ambiente #{env}.")
        end
      end

      def area_exists?(area)
        config.deploy_tree[:commerce].include?(area.to_sym)
      end

      def env_exists?(area, env)
        config.deploy_tree[:commerce][area.to_sym][:envs].include?(env)
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
