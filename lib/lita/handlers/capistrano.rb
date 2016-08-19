require 'net/ssh'

module Lita
  module Handlers
    class Capistrano < Handler

      config :server, type: String, required: true
      config :server_user, type: String, required: true
      config :server_password, type: String, required: true
      config :deploy_tree, type: Hash, required: true

      on :loaded, :define_routes

      on :deploy_checked, :deploy_exec
      on :deploy_aborted, :deploy_abort

      def define_routes(payload)
        define_static_routes
        define_dinamic_routes(config.deploy_tree)
      end

      def deploy_list(response)
        requested_app = response.args[1]
        if requested_app.nil?
          apps = config.deploy_tree.keys.join("\n")
          response.reply_privately("Available apps:\n#{apps}")
        else
          app_tree = get_app_tree(config.deploy_tree[requested_app.to_sym])
          response.reply_privately("Available tree for #{requested_app}: \n #{app_tree}")
        end
      end

      def deploy_auth_list(response)
        requested_app = response.args[2]
        if requested_app.nil?
          apps_auth_tree = get_apps_auth_groups(config.deploy_tree)
          response.reply_privately("Auth groups for apps:\n#{apps_auth_tree}")
        else
          app_tree = get_app_auth_group(config.deploy_tree[requested_app.to_sym])
          response.reply_privately("Auth group needed to deploy #{requested_app}: \n #{app_tree}")
        end
      end

      def deploy_request(response)
        app = response.matches[0][0]
        area = response.matches[0][1]
        env = response.matches[0][2]
        tag = response.matches[0][3]
        allowed_channel = config.deploy_tree[app.to_sym][area.to_sym][:channel]
        room_id = response.message.source.room_object.id

        # Do not deploy if not in the right channel, only if channel is
        # set in config.
        if !allowed_channel.nil? && !allowed_room?(room_id, allowed_channel)
          return response.reply("Deploy da app #{app} #{area} permitido somente no canal ##{allowed_channel}")
        end

        unless area_exists?(app, area)
          return response.reply("A área informada é inválida.")
        end
        unless env_exists?(app, area, env)
          return response.reply("O ambiente informado é inválido.")
        end

        # Pre deploy check, if no deploy in progress, deploy-tracker will
        # trigger :deploy_checked to continue the deploy.
        deploy_in_progress?(app, area, env, tag, response)
      end

      def area_exists?(app, area)
        config.deploy_tree[app.to_sym].include?(area.to_sym)
      end

      def env_exists?(app, area, env)
        config.deploy_tree[app.to_sym][area.to_sym][:envs].include?(env)
      end

      def get_app_tree(config_tree)
        app_tree = {}
        config_tree.each do |key, value|
          app_tree.store(key.to_s, value[:envs].map { |e| ">#{e}\n" }.join)
        end
        app_tree.flatten.map { |e| "#{e}\n" }.join
      end

      def get_apps_auth_groups(config_tree)
        app_tree = {}
        config_tree.each do |key, value|
          app_tree.store(key.to_s, value.map { |e| ">#{e[0]}: #{e[1][:auth_group]}\n" }.join)
        end
        app_tree.flatten.map { |e| "#{e}\n" }.join
      end

      def get_app_auth_group(config_tree)
        app_tree = []
        config_tree.each do |key, value|
          app_tree << "#{key.to_s}: #{value[:auth_group]}"
        end
        app_tree.flatten.map { |e| "#{e}\n" }.join
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
        responsible_user = response.user.mention_name
        target = response.message.source.room_object

        # Default initial message
        initial_message = "#{responsible_user}: Deploy da tag #{tag} iniciado no ambiente #{env}."

        if (tag == "rollback")
          # Change the initial message in case of rollback
          initial_message = "#{responsible_user}: Rollback iniciado no ambiente #{env}."
        end

        # Deploy/Rollback start
        response.reply(initial_message)
        start_time = Time.now
        robot.trigger(:deploy_started,
                      app: app,
                      area: area,
                      env: env,
                      tag: tag,
                      responsible: responsible_user,
                      start_time: start_time)

        # Deploy/Rollback execution
        output = ""
        if (tag == "rollback")
          output = rollback(dir, env)
        else
          output = deploy(dir, env, tag)
        end

        # After deploy stopped
        finish_time =Time.now

        msg_components = {}

        # Send back a message indicating the deploy status
        if !output[:error]
          robot.trigger(:deploy_finished,
                        app: app,
                        area: area,
                        env: env,
                        tag: tag,
                        responsible: responsible_user,
                        start_time: start_time,
                        finish_time: finish_time,
                        status: 'success')
        msg_components = {title: "Finalizado com sucesso!",
                          color: "good",
                          text: ""}
      elsif output[:data].lines.last.include? "status code 32768"
          robot.trigger(:deploy_finished,
                        app: app,
                        area: area,
                        env: env,
                        tag: tag,
                        responsible: responsible_user,
                        start_time: start_time,
                        finish_time: finish_time,
                        status: 'invalid tag')
          msg_components = {title: "A tag informada não existe.",
                            color: "warning",
                            text: ""}
        else
          robot.trigger(:deploy_finished,
                        app: app,
                        area: area,
                        env: env,
                        tag: tag,
                        responsible: responsible_user,
                        start_time: start_time,
                        finish_time: finish_time,
                        status: 'error')
          msg_components = {title: "Error!",
                            color: "danger",
                            text: output[:data]}
        end

        # generate the Attachment for slack
        attachment = gen_deploy_msg(msg_components[:title],
                            msg_components[:color],
                            msg_components[:text],
                            responsible_user,
                            app,
                            area,
                            env,
                            tag)

        # Default message for other adapters
        message = "Deploy - #{msg_components[:title]}. #{msg_components[:text]}"
        if (tag == "rollback")
          message = "Rollback - #{msg_components[:title]}. #{msg_components[:text]}"
        end

        case robot.config.robot.adapter
        when :slack
          return robot.chat_service.send_attachments(target, attachment)
        else
          robot.send_message(target, message)
        end
      end

      private

      def define_static_routes
        self.class.route(
          %r{^deploy\s+list},
          :deploy_list,
          command: false,
          help: { "deploy list [APP] " => "List available apps for deploy"}
        )
        self.class.route(
          %r{^deploy\s+auth\s+list},
          :deploy_auth_list,
          command: false,
          help: { "deploy auth list [APP] " => "List required auth groups to deploy"}
        )
      end

      def define_dinamic_routes(deploy_tree)
        deploy_tree.each do |app, areas|
          areas.each do |area, value|
            self.class.route(
              %r{^deploy\s+(#{app})\s+(#{area})\s+(.+)\s+(.+)},
              :deploy_request,
              command: true,
              restrict_to: [:admins, value[:auth_group].to_sym],
              help: { "deploy #{app} #{area} ENV TAG " => "Executa deploy da app #{app} na area #{area}"}
            )

          end
        end
      end

      def deploy(dir, env, tag)
        output = ssh_exec("cd #{dir}; cap #{env} deploy tag=#{tag}")
      end

      def rollback(dir, env)
        output = ssh_exec("cd #{dir}; cap #{env} deploy:rollback")
      end

      def ssh_exec(cmd)
        Net::SSH.start(config.server, config.server_user, password: config.server_password) do |ssh|
          exec_ssh(ssh, cmd)
        end
      end

      def exec_ssh(ssh, cmd)
        ssh.exec! cmd do |ch, stream, data|
          @output = get_deploy_output(stream, data)
        end
        @output
      end

       def get_deploy_output(stream, data)
         if stream == :stderr
           { data: "#{data}", error: true }
         else
           { data: "#{data}", error: false }
         end
       end


      def gen_deploy_msg (title, color, body, user, app, area, env, tag)
        msg = Adapters::Slack::Attachment.new(
          body,
          title: "Deploy - #{title}",
          color: "#{color}",
          pretext: "@#{user}:",
          fields: [
            {
              title: "App",
              value: app,
              short: true
            },
            {
              title: "Área",
              value: area,
              short: true
            },
            {
              title: "Ambiente",
              value: env,
              short: true
            },
            {
              title: "tag",
              value: tag,
              short: true
            },
          ]
        )
      end

      def allowed_room?(room_id, allowed_channel)
        room = Lita::Room.find_by_id(room_id)
        return false if room.nil?
        return true if room.metadata["name"] == allowed_channel
      end

      def remind()
        config
      end

    end

    Lita.register_handler(Capistrano)
  end
end
