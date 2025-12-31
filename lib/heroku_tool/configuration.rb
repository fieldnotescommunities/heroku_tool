# frozen_string_literal: true

module HerokuTool
  class Configuration
    def platform_maintenance_urls(asset_host)
      time = Time.now.strftime("%Y%m%d-%H%M-%S")
      {
        ERROR_PAGE_URL: "https://#{asset_host}/platform_error/#{time}",
        MAINTENANCE_PAGE_URL: "https://#{asset_host}/platform_maintenance/#{time}"
      }
    end

    def maintenance_mode_env_var
      "X_HEROKU_TOOL_MAINTENANCE_MODE"
    end

    def app_revision_env_var
      # alternatively if you want you can set this as APP_REVISION (for app-signal) or HEROKU_SLUG_COMMIT (see https://devcenter.heroku.com/articles/dyno-metadata)
    end

    def before_deploying(_instance, target, version, description: nil)
      puts "about to deploy #{version} to #{target.name}"
      puts "         #{description}" if description
    end

    def after_deploying(_instance, target, version, description: nil)
      puts "deployed #{version} to #{target.name}"
      puts "         #{description}" if description
    end

    def notify_of_deploy_tracking(instance, deploy_ref:, revision:)
      if ENV["BUGSNAG_API_KEY"].present?
        instance.notify_bugsnag_of_deploy_tracking(deploy_ref:, revision:)
      else
        puts "can't notify of deploy tracking: env var not present: BUGSNAG_API_KEY"
      end
    end

    def after_sync_down(instance)
      # could add source ?
      instance.puts_and_system "rails db:migrate"
      instance.puts_and_system "rails db:test:prepare"
    end

    def after_sync_to(instance, target)
      # could add source ?
      instance.puts_and_system %(heroku run rails db:migrate -a #{target.heroku_app})
    end
  end
end
