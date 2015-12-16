module Lita
  module Handlers
    class DeployTracker < Handler
      require 'mongo'

      config :host, type: String, required: true
      config :user, type: String, required: true
      config :password, type: String, required: true

      on :deploy_started, :register_deploy
      on :deploy_finished, :update_deploy
      on :deploy_in_progress?, :check_deploy_in_progress

      def register_deploy(payload)
        db = mongo_client

        db[:deploys].insert_one ({
          app: payload[:app],
          area: payload[:area],
          env: payload[:env],
          tag: payload[:tag],
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
          start_time: payload[:start_time],
          status: 'in progress'
        },
        {
          app: payload[:app],
          area: payload[:area],
          env: payload[:env],
          tag: payload[:tag],
          start_time: payload[:start_time],
          finish_time: payload[:finish_time],
          status: payload[:status]
        })
        db[:deploys].find().each do |doc|
          p doc
        end

      end

      def check_deploy_in_progress(payload)
        db = mongo_client

        result = db[:deploys].find({app: payload[:app],
                                    area: payload[:area],
                                    env: payload[:env],
                                    status: 'in progress'}).limit(1).count
        p "Result é igual a ======> #{result}"

        if result > 0
          robot.trigger(:stop_deploy,
                        msg: 'Já existe um deploy dessa aplicação sendo'\
                        'executado nessa area. Aguarde ele ser finalizado',
                        response: payload[:response])
        #   robot.trigger(:deploy_in_progress_response, result: true)
        # else
        #   robot.trigger(:deploy_in_progress_response, result: false)
        end

      end

      def mongo_client
        # client = Mongo::Client.new("mongodb://#{config.user}:#{config.password}@#{config.host}:27017/lita-deploy-tracker")
        client = Mongo::Client.new("mongodb://#{config.host}:27017/lita-deploy-tracker")
      end

      Lita.register_handler(self)
    end
  end
end
