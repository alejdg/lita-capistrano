module Lita
  module Handlers
    class DeployTracker < Handler
      require 'mongo'

      config :host, type: String, required: true
      config :user, type: String, required: true
      config :password, type: String, required: true

      on :loaded, :define_routes

      on :deploy_started, :register_deploy
      on :deploy_finished, :update_deploy
      on :deploy_in_progress?, :check_deploy_in_progress

      def define_routes(payload)
        define_static_routes
      end

      def register_deploy(payload)
        db = mongo_client

        db[:deploys].insert_one ({
          app: payload[:app],
          area: payload[:area],
          env: payload[:env],
          tag: payload[:tag],
          responsible: payload[:responsible],
          start_time: payload[:start_time],
          status: 'in progress'
          })
      end

      def update_deploy(payload)
        db = mongo_client
        db[:deploys].update_one({
          app: payload[:app],
          area: payload[:area],
          env: payload[:env],
          tag: payload[:tag],
          responsible: payload[:responsible],
          start_time: payload[:start_time]
        },
        {
          app: payload[:app],
          area: payload[:area],
          env: payload[:env],
          tag: payload[:tag],
          responsible: payload[:responsible],
          start_time: payload[:start_time],
          finish_time: payload[:finish_time],
          status: payload[:status]
        })
        db[:deploys].find().each do |doc|
        end

      end

      def check_deploy_in_progress(payload)
        db = mongo_client
        # db[:deploys].drop

        result = db[:deploys].find({app: payload[:app],
                                    area: payload[:area],
                                    env: payload[:env],
                                    status: 'in progress'}).limit(1).count

        if result > 0
          payload[:msg] = 'Já existe um deploy dessa aplicação sendo '\
                          'executado nessa area. Aguarde ele ser finalizado'
          robot.trigger(:deploy_aborted, payload)
        else
          robot.trigger(:deploy_checked, payload)
        end

      end

      def get_deploys_in_progress(response)
        target = response.message.source.room_object
        db = mongo_client
        deploys = []
        result = db[:deploys].find(status: 'in progress')
        if result.count == 0
          return response.reply("No deploy in progress")
        end

        result.each do |doc|
          deploys << Adapters::Slack::Attachment.new(
            "",
            title: "Deploy #{doc[:app]} in progress",
            fields: [
              {
                title: "App",
                value: doc[:app],
                short: true
              },
              {
                title: "Área",
                value: doc[:area],
                short: true
              },
              {
                title: "Ambiente",
                value: doc[:env],
                short: true
              },
              {
                title: "tag",
                value: doc[:tag],
                short: true
              },
              {
                title: "responsible",
                value: doc[:responsible],
                short: true
              }
            ]
          )
        end
        return robot.chat_service.send_attachments(target, deploys)
      end

      def get_last_deploys(response)
        target = response.message.source.room_object
        app = response.args[3]
        area = response.args[4]
        db = mongo_client

        result = db[:deploys].find({app: app, area: area}).limit(5)
        if result.count == 0
          return response.reply("No previous deployments of the app #{app} #{area}")
        end

        deploys = []
        result.each do |doc|
          deploys << Adapters::Slack::Attachment.new(
            "",
            title: "Deploy #{doc[:app]}",
            fields: [
              {
                title: "App",
                value: doc[:app],
                short: true
              },
              {
                title: "Área",
                value: doc[:area],
                short: true
              },
              {
                title: "Ambiente",
                value: doc[:env],
                short: true
              },
              {
                title: "tag",
                value: doc[:tag],
                short: true
              },
              {
                title: "responsible",
                value: doc[:responsible],
                short: true
              }
            ]
          )
        end
        return robot.chat_service.send_attachments(target, deploys)
      end


      private

      def define_static_routes
        self.class.route(
          %r{^show\s+deploy\s+in\s+progress},
          :get_deploys_in_progress,
          command: false,
          help: { "show deploy in progress" => "Show all deploys being executed"}
        )
        self.class.route(
          %r{^show\s+last\s+deploys\s+from\s+(.+)\s+(.+)},
          :get_last_deploys,
          command: false,
          help: { "show last deploys from APP AREA" => "Show the last 5 deploys from the application area"}
        )
      end

      def mongo_client
        # client = Mongo::Client.new("mongodb://#{config.user}:#{config.password}@#{config.host}:27017/lita-deploy-tracker")
        client = Mongo::Client.new("mongodb://#{config.host}:27017/lita-deploy-tracker")
      end

      Lita.register_handler(self)
    end
  end
end
