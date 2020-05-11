# frozen_string_literal: true

require "thor"
Thor::Util.load_thorfile(File.expand_path("../../vendor/heroku_tool/lib/tasks/heroku.thor", __dir__))

class Heroku
  module MyConfig
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
