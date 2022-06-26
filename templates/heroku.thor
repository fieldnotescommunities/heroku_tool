# frozen_string_literal: true

require "thor"
spec = Gem::Specification.find_by_name "heroku_tool"
Thor::Util.load_thorfile(File.expand_path("lib/heroku_tool/tasks/heroku.thor", spec.gem_dir))

class Heroku
  module MyConfig
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

    # def notify_of_deploy_tracking(running_thor_task, release_stage:, revision:, revision_describe:, repository:, target:, target_name:, deploy_ref:)
    # end

    # def app_revision_env_var
    #  "APP_REVISION"
    # end
    #
    # def after_sync_down(instance)
    #  super
    #  instance.puts_and_system "rake dev:dev_data"
    # end
    #
    # def after_sync_to(instance, target)
    #  super
    #  instance.puts_and_system %(heroku run rake dev:staging_data -a #{target.heroku_app})
    # end
    #
    # def before_deploying(instance, target, version)
    #   # override
    # end
    #
    # def after_deploying(instance, target, version)
    #   # override
    # end
  end

  module Configuration
    class << self
      prepend MyConfig
    end
  end

  # desc "set_message TARGET (MESSAGE)", "sets a MESSAGE to display on the TARGET server. If you give no MESSAGE, it will clear the message"
  #
  # def set_message(target_name, message = nil)
  #   target = lookup_heroku(target_name)
  #   if message
  #     puts_and_system "heroku run rake data:util:set_message[\"#{message}\"] -a #{target.heroku_app}"
  #   else
  #     puts_and_system "heroku run rake data:util:set_message -a #{target.heroku_app}"
  #   end
  # end
end
