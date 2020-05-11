# frozen_string_literal: true

require "thor"
require_relative "../heroku_tool/db_configuration"
require_relative "../heroku_tool/heroku_targets"
require_relative "../heroku_tool/thor_utils"

class Heroku < Thor
  module Configuration
    class << self
      def base_asset_url
        asset_host = get_config_env(target, "ASSET_HOST")
        "https://#{asset_host}"
      end

      def maintenance_mode_env_var
        "X_HEROKU_TOOL_MAINTENANCE_MODE"
      end

      def app_revision_env_var
        raise "choose between APP_REVISION and COMMIT_HASH"
      end

      def before_deploying(instance, target, version, description: nil)
        puts "about to deploy to #{target.name}"
      end

      def after_deploying(instance, target, version, description: nil)
        puts "deployed to #{target.name}"
      end

      def notify_of_deploy_tracking(running_thor_task, release_stage:, revision:, revision_describe:, repository:, target:, target_name:, deploy_ref:)
        if ENV["BUGSNAG_API_KEY"].present?
          running_thor_task.notify_bugsnag_of_deploy_tracking(deploy_ref, release_stage, repository, revision, revision_describe, target_name)
        else
          puts "can't notify of deploy tracking: env var not present: BUGSNAG_API_KEY"
        end
      end

      def after_sync_down(instance)
        instance.puts_and_system "rake db:migrate"
        instance.puts_and_system "rake db:test:prepare"
      end

      def after_sync_to(instance, target)
        instance.puts_and_system %(heroku run rake db:migrate -a #{target.heroku_app})
      end
    end
  end

  module Shared
    def self.exit_on_failure?
      true
    end

    def lookup_heroku_staging(staging_target_name)
      heroku_targets.staging_targets[staging_target_name] || raise_missing_target(staging_target_name, true)
    end

    def lookup_heroku(target_name)
      heroku_targets.targets[target_name] || raise_missing_target(target_name, false)
    end

    def check_deploy_ref(deploy_ref, target)
      raise Thor::Error, "Invalid deploy ref '#{deploy_ref}'" if deploy_ref && deploy_ref[0] == "-"
      deploy_ref || target.deploy_ref
    end

    def raise_missing_target(target_name, staging)
      if staging
        description = "Staging target_name '#{target_name}'"
        targets = heroku_targets.staging_targets.keys
      else
        description = "Target '#{target_name}'"
        targets = heroku_targets.targets.keys
      end
      msg = "#{description} was not found. Valid targets are #{targets.collect { |t| "'#{t}'" }.join(",")}"
      raise Thor::Error, msg
    end

    def heroku_targets
      @heroku_targets ||= HerokuTool::HerokuTargets.from_file(File.expand_path("config/heroku_targets.yml"))
    end

    def puts_and_system(cmd)
      puts cmd
      puts "-------------"
      system_with_clean_env cmd
      puts "-------------"
    end

    def puts_and_exec(cmd)
      puts cmd
      exec_with_clean_env(cmd)
    end

    protected

    def deploy_message(target, deploy_ref_describe)
      downtime = options[:migrate] ? "👷 There will be a very short maintenance downtime" : ""
      message = <<-DEPLOY_MESSAGE
     Deploying #{target.display_name} #{deploy_ref_describe}.
     #{downtime} (in less than a minute from now).
      DEPLOY_MESSAGE
      message.gsub(/(\s|\n)+/, " ")
    end

    def system_with_clean_env(cmd)
      if defined?(Bundler)
        Bundler.with_clean_env { system cmd }
      else
        system cmd
      end
    end

    def exec_with_clean_env(cmd)
      if defined?(Bundler)
        Bundler.with_clean_env { `#{cmd}` }
      else
        `#{cmd}`
      end
    end

    def maintenance_on(target)
      puts_and_system "heroku maintenance:on -a #{target.heroku_app}"
      puts_and_system "heroku config:set #{Heroku::Configuration.maintenance_mode_env_var}=true -a #{target.heroku_app}"
    end

    def maintenance_off(target)
      puts_and_system "heroku maintenance:off -a #{target.heroku_app}"
      puts_and_system "heroku config:unset #{Heroku::Configuration.maintenance_mode_env_var} -a #{target.heroku_app}"
    end
  end

  include Shared

  class_option :verbose, type: :boolean, aliases: "v", default: true
  default_command :help

  desc "details", "collects and prints some information local and each target"

  def details
    puts
    details = heroku_targets.targets.map { |name, target|
      next if target.local?
      print "."
      [
        "Heroku #{name}",
        "(versions suppressed -- takes too long)" || exec_with_clean_env("heroku run 'rails -v && ruby -v' -a #{target.heroku_app}"),
        exec_with_clean_env("heroku releases -n 1 -a #{target.heroku_app}").split("\n").last
      ]
    }
    puts
    details << [
      "Local",
      exec_with_clean_env("rails -v && ruby -v"),
      exec_with_clean_env("git describe --always")
    ]
    details.each do |n, v, d|
      puts "-" * 80
      puts n
      puts "-" * 80
      puts v
      puts d
    end
  end

  desc "deploy TARGET (REF)", "deploy the latest to TARGET (optionally give a REF like a tag to deploy)"
  method_option :migrate, default: true, desc: "Run with migrations", type: :boolean
  method_option :maintenance, default: nil, desc: "Run with migrations", type: :boolean

  def deploy(target_name, deploy_ref = nil)
    target = lookup_heroku(target_name)
    deploy_ref = check_deploy_ref(deploy_ref, target)
    deploy_ref_description = deploy_ref_describe(deploy_ref)
    maintenance = options[:maintenance].nil? && options[:migrate] || options[:maintenance]
    puts "Deploy #{deploy_ref_description} to #{target} with migrate=#{options[:migrate]} maintenance=#{maintenance} "

    invoke :list_deployed, [target_name, deploy_ref], {}
    message = deploy_message(target, deploy_ref_description)
    Configuration.before_deploying(self, target, deploy_ref_description)
    set_message(target_name, message)
    puts_and_system "git push -f #{target.git_remote} #{deploy_ref}^{}:master"

    maintenance_on(target) if maintenance
    puts_and_system "heroku run rake db:migrate -a #{target.heroku_app}" if options[:migrate]

    puts_and_system %{heroku config:set #{Heroku::Configuration.app_revision_env_var}=$(git describe --always #{deploy_ref}) -a #{target.heroku_app}}
    if maintenance
      maintenance_off(target)
    else
      puts_and_system "heroku restart -a #{target.heroku_app}"
    end
    set_message(target_name, nil)
    Configuration.after_deploying(self, target, deploy_ref_description)
    deploy_tracking(target_name, deploy_ref)
  end

  desc "maintenance ON|OFF", "turn maintenance mode on or off"
  method_option :target_name, aliases: "a", desc: "Target (app or remote)"

  def maintenance(on_or_off)
    target = lookup_heroku(options[:target_name])
    case on_or_off.upcase
    when "ON"
      maintenance_on(target)
    when "OFF"
      maintenance_off(target)
    else
      raise Thor::Error, "maintenance must be ON or OFF not #{on_or_off}"
    end
  end

  desc "set_urls TARGET", "set and cache the error and maintenance page urls for TARGET"

  def set_urls(target_name)
    target = lookup_heroku(target_name)
    time = Time.now.strftime("%Y%m%d-%H%M-%S")
    url_hash = {
      ERROR_PAGE_URL: "#{Heroku::Configuration.base_asset_url}/platform_error/#{time}",
      MAINTENANCE_PAGE_URL: "#{Heroku::Configuration.base_asset_url}/platform_maintenance/#{time}"
    }
    url_hash.each do |_env, url|
      puts_and_system "open #{url}"
    end
    puts_and_system(
      "heroku config:set #{url_hash.map { |e, u| "#{e}=#{u}" }.join(" ")} -a #{target.heroku_app}"
    )
  end

  no_commands do
    def get_config_env(target, env_var)
      puts_and_exec("heroku config:get #{env_var} -a #{target.heroku_app}").strip.presence
    end

    def deploy_ref_describe(deploy_ref)
      `git describe #{deploy_ref}`.strip
    end

    def notify_bugsnag_of_deploy_tracking(deploy_ref, release_stage, repository, revision, revision_describe, target_name)
      api_key = ENV["BUGSNAG_API_KEY"]
      data = %W[
        apiKey=#{api_key}
        releaseStage=#{release_stage}
        repository=#{repository}
        revision=#{revision}
        appVersion=#{revision_describe}
      ].join("&")
      if api_key.blank?
        puts "\n" + ("*" * 80) + "\n"
        command = "curl -d #{data} http://notify.bugsnag.com/deploy"
        puts command
        puts "\n" + ("*" * 80) + "\n"
        puts "NB: can't notify unless you specify BUGSNAG_API_KEY and rerun"
        puts "  thor heroku:deploy_tracking #{target_name} #{deploy_ref}"
      else
        puts_and_system "curl -d \"#{data}\" http://notify.bugsnag.com/deploy"
      end
    end
  end

  desc "deploy_tracking TARGET (REF)", "set deploy tracking for TARGET and REF (used by deploy)"

  def deploy_tracking(target_name, deploy_ref = nil)
    target = lookup_heroku(target_name)
    deploy_ref = check_deploy_ref(deploy_ref, target)
    release_stage = target.staging? ? "staging" : "production"
    revision = `git log -1 #{deploy_ref} --pretty=format:%H`
    Heroku::Configuration.notify_of_deploy_tracking(
      self,
      deploy_ref: deploy_ref,
      release_stage: target.trackable_release_stage,
      revision: revision,
      target: target,
      target_name: target_name,
      revision_describe: deploy_ref_describe(deploy_ref),
      repository: target.repository
    )
  end

  include HerokuTool::ThorUtils
  desc "set_message TARGET (MESSAGE)", "set message (no-op by default)"

  def set_message(target_name, message = nil)
    # no-op -- define as override
  end

  desc "list_deployed TARGET (DEPLOY_REF)", "list what would be deployed to TARGET (optionally specify deploy_ref)"

  def list_deployed(target_name, deploy_ref = nil)
    target = lookup_heroku(target_name)
    deploy_ref = check_deploy_ref(deploy_ref, target)
    puts "------------------------------"
    puts " Deploy to #{target}:"
    puts "------------------------------"
    system_with_clean_env "git --no-pager log $(heroku config:get #{Heroku::Configuration.app_revision_env_var} -a #{target.heroku_app})..#{deploy_ref}"
    puts "------------------------------"
  end

  desc "about (TARGET)", "Describe available targets or one specific target"

  def about(target_name = nil)
    if target_name.nil?
      puts "Targets: "
      heroku_targets.targets.each_pair do |key, target|
        puts " * #{key} (#{target})"
      end
    else
      target = lookup_heroku(target_name)
      puts "Target #{target_name}:"
      puts " * display_name: #{target.display_name}"
      puts " * heroku_app:   #{target.heroku_app}"
      puts " * git_remote:   #{target.git_remote}"
      puts " * deploy_ref:   #{target.deploy_ref}"
    end
    puts
    puts "(defined in config/heroku_targets.yml)"
  end

  class Sync < Thor
    include Shared
    class_option :from, type: :string, desc: "source target (production, staging...)", required: true, aliases: "f"

    desc "down --from SOURCE_TARGET", "syncs db down from SOURCE_TARGET | thor heroku:sync -f production"

    def down
      invoke "grab", [], from: options[:from]
      invoke "from_dump", [], from: options[:from]
    end

    desc "warn", "warn", hide: true

    def warn
      puts "should maybe 'rake db:drop_all_tables' first"
      puts "if you have done some table-creating migrations that need tobe undone???"
    end

    desc "grab --from SOURCE_TARGET", "capture and download dump from SOURCE_TARGET", hide: true

    def grab
      source = lookup_heroku(options[:from])
      capture_cmd = "heroku pg:backups:capture -a #{source.heroku_app}"
      puts_and_system capture_cmd
      invoke "download", [], from: options[:from]
    end

    desc "download --from SOURCE_TARGET", "download latest db snapshot on source_target"

    def download
      source = lookup_heroku(options[:from])
      download_cmd = "curl -o #{source.dump_filename} `heroku pg:backups:public-url -a #{source.heroku_app}`"
      puts_and_system download_cmd
    end

    desc "from_dump --from SOURCE_TARGET", "make the db the same as the last target dump from SOURCE_TARGET"

    method_option :just_restore, default: false, desc: "Just do restore without post-actions", type: :boolean

    def from_dump
      invoke "warn", [], from: options[:from]
      source = lookup_heroku(options[:from])
      rails_env = ENV["RAILS_ENV"] || "development"
      db_config = HerokuTool::DbConfiguration.new.config[rails_env]
      db_username = db_config["username"]
      db = db_config["database"]
      db_username_params = db_username.blank? && "" || "-U #{db_username}"
      puts_and_system "pg_restore --verbose --clean --no-acl --no-owner -h localhost #{db_username_params} -d #{db} #{source.dump_filename}"
      Configuration.after_sync_down(self) unless options[:just_restore]
    end

    desc "dump_to_tmp", "dump to tmp directory"
    method_option(:from, type: :string, default: "local", desc: "heroku target (defaults to local)", required: false, aliases: "f")
    def dump_to_tmp
      source = lookup_heroku(options[:from])
      dump_local(source.dump_filename)
    end

    desc "to STAGING_TARGET --from=SOURCE_TARGET", "push db onto STAGING_TARGET from SOURCE_TARGET"

    def to(to_target_name)
      target = lookup_heroku_staging(to_target_name)
      source = lookup_heroku(options[:from])

      maintenance_on(target)

      puts_and_system %(
        heroku pg:copy #{source.heroku_app}::#{source.db_color} #{target.db_color} -a #{target.heroku_app} --confirm #{target.heroku_app}
      )
      Configuration.after_sync_to(self, target) unless options[:just_copy]
      puts_and_system %(heroku restart -a #{target.heroku_app})
      maintenance_off(target)
    end

    private

    def dump_local(dumpfilepath)
      puts "dumping postgres to #{dumpfilepath}"
      rails_env = ENV["RAILS_ENV"] || "development"
      db_config = HerokuTool::DbConfiguration.new.config[rails_env]
      db_username = db_config["username"]
      db = db_config["database"]
      system_with_clean_env "pg_dump --verbose --clean --no-acl --no-owner -h localhost -U #{db_username} --format=c #{db} > #{dumpfilepath}"
    end
  end

  class Db < Thor
    include Shared

    desc "drop_all_tables on STAGING_TARGET", "drop all tables on STAGING_TARGET"

    def drop_all_tables(staging_target_name)
      target = lookup_heroku_staging(staging_target_name)
      generate_drop_tables_sql = `#{HerokuTool::DbConfiguration.new.generate_drop_tables_sql}`
      cmd_string = %(heroku pg:psql -a #{target.heroku_app} -c "#{generate_drop_tables_sql}")
      puts_and_system(cmd_string)
    end

    desc "anonymize STAGING_TARGET", "run anonymization scripts on STAGING_TARGET"

    def anonymize(staging_target_name)
      target = lookup_heroku_staging(staging_target_name)
      puts_and_system %(
        heroku run rake data:anonymize -a #{target.heroku_app}
      )
    end
  end
end
