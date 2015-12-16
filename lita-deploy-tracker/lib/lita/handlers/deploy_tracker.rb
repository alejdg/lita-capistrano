module Lita
  module Handlers
    class DeployTracker < Handler
      require 'mongo'

      config :host, type: String, required: true
      config :user, type: String, required: true
      config :password, type: String, required: true

      on :deploy_started, :register_deploy

      def register_deploy(payload)
        app = payload[:app]
        area = payload[:area]
        env = payload[:env]
        tag = payload[:tag]

        db = mongo_client

        result = db[:deploys].insert_one ({
          app: payload[:app],
          area: payload[:area],
          env: payload[:env],
          tag: payload[:tag],
          start_time: payload[:start_time],
          status: 'in progress'
          })

      end

      def mongo_client
        # client = Mongo::Client.new("mongodb://#{config.user}:#{config.password}@#{config.host}:27017/lita-deploy-tracker")
        client = Mongo::Client.new("mongodb://#{config.host}:27017/lita-deploy-tracker")
      end

      Lita.register_handler(self)
    end
  end
end
