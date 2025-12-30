# frozen_string_literal: true

module HerokuTool
  class Commander
    # @return [HerokuTool::HerokuTargets::HerokuTarget]
    attr_reader :target
    attr_reader :configuration

    def initialize(target, configuration:, **options)
      @target = target
      @migrate_outside_of_release_phase = target&.migrate_in_release_phase ? false : options[:migrate]
      @configuration = configuration
    end

    def deploy(deploy_ref, with_maintenance:)
      deploy_ref_description = deploy_ref_describe(deploy_ref)
      puts "Deploy #{deploy_ref_description} to #{target} with migrate=#{target.migrate_in_release_phase ? "(during release phase)" : migrate_outside_of_release_phase?} with_maintenance=#{with_maintenance} "

      output_to_be_deployed(deploy_ref)
      configuration.before_deploying(self, target, deploy_ref_description)
      successful_push = puts_and_system "git push -f #{target.git_remote} #{deploy_ref || target}^{}:#{target.heroku_target_ref}"

      return false unless successful_push

      maintenance_on if with_maintenance
      if migrate_outside_of_release_phase?
        puts_and_system "heroku run rake db:migrate -a #{target.heroku_app}"
      end

      app_revision_env_var = configuration.app_revision_env_var
      if app_revision_env_var && app_revision_env_var != "HEROKU_SLUG_COMMIT"
        # HEROKU_SLUG_COMMIT is automatically set by https://devcenter.heroku.com/articles/dyno-metadata
        puts_and_system %{heroku config:set #{app_revision_env_var}=$(git describe --always #{deploy_ref}) -a #{target.heroku_app}}
      end

      maintenance_off if with_maintenance
      configuration.after_deploying(self, target, deploy_ref_description)
      true
    end

    def maintenance_on
      puts_and_system "heroku maintenance:on -a #{target.heroku_app}"
      puts_and_system "heroku config:set #{configuration.maintenance_mode_env_var}=true -a #{target.heroku_app}"
    end

    def maintenance_off
      puts_and_system "heroku maintenance:off -a #{target.heroku_app}"
      puts_and_system "heroku config:unset #{configuration.maintenance_mode_env_var} -a #{target.heroku_app}"
    end

    def migrate_outside_of_release_phase?
      @migrate_outside_of_release_phase
    end

    def deploy_ref_describe(deploy_ref = nil)
      `git describe #{deploy_ref || target.deploy_ref}`.strip
    end

    def output_to_be_deployed(since_deploy_ref = nil)
      puts "------------------------------"
      puts " Deploy to #{target}:"
      puts "------------------------------"
      system_with_clean_env "git --no-pager log $(heroku config:get #{configuration.app_revision_env_var} -a #{target.heroku_app})..#{since_deploy_ref || target.deploy_ref}"
      puts "------------------------------"
    end

    # @return [Boolean] true if the command was successful
    def puts_and_system(cmd)
      puts cmd
      puts "-------------"
      system_with_clean_env(cmd).tap do |result|
        if result
          puts "-------------"
        else
          puts "❌❌❌❌❌❌❌❌❌❌"
        end
      end
    end

    def puts_and_exec(cmd)
      puts cmd
      exec_with_clean_env(cmd)
    end

    def exec_with_clean_env(cmd)
      if defined?(Bundler) && Bundler.respond_to?(:with_unbundled_env)
        Bundler.with_unbundled_env { `#{cmd}` }
      elsif defined?(Bundler)
        Bundler.with_clean_env { `#{cmd}` }
      else
        `#{cmd}`
      end
    end

    protected

    def system_with_clean_env(cmd)
      if defined?(Bundler) && Bundler.respond_to?(:with_unbundled_env)
        Bundler.with_unbundled_env { system cmd }
      elsif defined?(Bundler)
        Bundler.with_clean_env { system cmd }
      else
        system cmd
      end
    end
  end
end
