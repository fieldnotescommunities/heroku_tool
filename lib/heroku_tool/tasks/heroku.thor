# frozen_string_literal: true

require "thor"
require_relative "../db_configuration"
require_relative "../heroku_targets"
require_relative "../commander"
require_relative "../configuration"

class Heroku < Thor
  namespace "heroku"
  module Shared
    attr_accessor :implied_source
    # @return [HerokuTool::HerokuTarget]
    attr_reader :target

    # @return [HerokuTool::Commander] commander for target
    def commander
      @commander ||= ::HerokuTool::Commander.new(target, configuration: configuration, **options.symbolize_keys)
    end

    def configuration
      ::HerokuTool::Configuration.new
    end

    def self.included(base)
      #:nodoc:
      super
      base.extend ClassMethods
    end

    module ClassMethods
      def exit_on_failure?
        true
      end
    end

    def lookup_heroku_staging(staging_target_name)
      heroku_targets.staging_targets[staging_target_name] || raise_missing_target(staging_target_name, true)
    end

    def lookup_heroku(target_name)
      heroku_targets.targets[target_name] || raise_missing_target(target_name, false)
    end

    def check_deploy_ref(deploy_ref)
      if deploy_ref && deploy_ref[0] == "-"
        raise Thor::Error, "Invalid deploy ref '#{deploy_ref}'"
      end

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
      @heroku_targets ||= ::HerokuTool::HerokuTargets.from_file(File.expand_path("config/heroku_targets.yml"))
    end

    protected

    delegate :deploy_ref_describe, :exec_with_clean_env, :maintenance_off, :maintenance_on, :output_to_be_deployed, :migrate_outside_of_release_phase?, :puts_and_exec, :puts_and_system,
      to: :commander
  end

  include Shared

  class_option :verbose, type: :boolean, aliases: "v", default: true
  default_command :help

  DEFAULT_CONFIGS_TO_DIR = "tmp"
  desc "configs", "collects configs as text files"
  method_option :to_dir, default: DEFAULT_CONFIGS_TO_DIR, desc: "Directory to collect them in", type: :string

  def configs
    to_dir = File.expand_path(options[:to_dir] || DEFAULT_CONFIGS_TO_DIR)
    unless Dir.exist?(to_dir)
      puts "Doesn't exist (or isn't directory): #{to_dir}"
      exit(-1)
    end
    remote_targets = heroku_targets.targets.reject { |_name, target| target.local? }
    remote_targets.each_with_index do |(_name, target), index|
      print_output_progress(remote_targets, index)
      cmd = "heroku config -s -a #{target.heroku_app} > #{to_dir}/config.#{target.heroku_app}.txt"
      exec_with_clean_env(cmd)
    end
    print_output_progress(remote_targets)
    puts ""
  end

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
  method_option :migrate, default: true, desc: "Run with migrations (unless part of release phase)", type: :boolean
  method_option :maintenance, default: nil, desc: "Maintenance step", type: :boolean

  def deploy(target_name, deploy_ref = nil)
    @target = lookup_heroku(target_name)
    check_deploy_ref(deploy_ref)
    with_maintenance = options[:maintenance].nil? && migrate_outside_of_release_phase? || options[:maintenance] || false
    deploy_ref ||= target.deploy_ref
    success = commander.deploy(deploy_ref, with_maintenance: with_maintenance)
    if success
      deploy_tracking(target_name, deploy_ref)
    else
      exit(-1)
    end
  end

  desc "maintenance ON|OFF", "turn maintenance mode on or off"
  method_option :target_name, aliases: "a", desc: "Target (app or remote)"

  def maintenance(on_or_off)
    @target = lookup_heroku(options[:target_name])
    case on_or_off.upcase
    when "ON"
      maintenance_on
    when "OFF"
      maintenance_off
    else
      raise Thor::Error, "maintenance must be ON or OFF not #{on_or_off}"
    end
  end

  desc "set_urls TARGET", "set and cache the error and maintenance page urls for TARGET"

  def set_urls(target_name)
    @target = lookup_heroku(target_name)
    unless asset_host.presence
      puts "asset host (ASSET_HOST) not found on #{target.heroku_app}"
      return
    end
    url_hash = configuration.platform_maintenance_urls(asset_host)
    url_hash.each do |_env, url|
      puts_and_system "open #{url}"
    end
    puts_and_system(
      "heroku config:set #{url_hash.map { |e, u| "#{e}=#{u}" }.join(" ")} -a #{target.heroku_app}"
    )
  end

  no_commands do
    def asset_host
      @asset_host ||= fetch_asset_host
    end

    def get_config_env(target, env_var)
      puts_and_exec("heroku config:get #{env_var} -a #{target.heroku_app}").strip.presence
    end

    def notify_of_deploy_tracking(deploy_ref)
      revision = `git log -1 #{deploy_ref || target.deploy_ref} --pretty=format:%H`
      configuration.notify_of_deploy_tracking(
        self,
        deploy_ref: deploy_ref,
        revision: revision
      )
    end

    def notify_bugsnag_of_deploy_tracking(deploy_ref:, revision:)
      api_key = ENV["BUGSNAG_API_KEY"]
      data = %W[
        apiKey=#{api_key}
        releaseStage=#{target.trackable_release_stage}
        repository=#{target.repository}
        revision=#{revision}
        appVersion=#{deploy_ref_describe(deploy_ref)}
      ].join("&")
      if api_key.blank?
        puts "\n" + ("*" * 80) + "\n"
        command = "curl -d #{data} http://notify.bugsnag.com/deploy"
        puts command
        puts "\n" + ("*" * 80) + "\n"
        puts "NB: can't notify unless you specify BUGSNAG_API_KEY and rerun"
        puts "  thor heroku:deploy_tracking #{target.name} #{deploy_ref}"
      else
        puts_and_system "curl -d \"#{data}\" http://notify.bugsnag.com/deploy"
      end
    end
  end

  desc "deploy_tracking TARGET (REF)", "set deploy tracking for TARGET and REF (used by deploy)"

  def deploy_tracking(target_name, deploy_ref = nil)
    @target = lookup_heroku(target_name)
    check_deploy_ref(deploy_ref)
    notify_of_deploy_tracking(deploy_ref)
  end

  desc "set_message TARGET (MESSAGE)", "set message (no-op by default)"

  def set_message(target_name, message = nil)
    # no-op -- define as override
  end

  desc "to_be_deployed TARGET (SINCE_DEPLOY_REF)", "list what would be deployed to TARGET (optionally specify SINCE_DEPLOY_REF)"

  def to_be_deployed(target_name, since_deploy_ref = nil)
    if configuration.app_revision_env_var.nil?
      puts "Can't list deployed as Configuration.app_revision_env_var is not set"
      return
    end
    @target = lookup_heroku(target_name)
    check_deploy_ref(since_deploy_ref)
    output_to_be_deployed(since_deploy_ref)
  end

  desc "about (TARGET)", "Describe available targets or one specific target"

  def about(target_name = nil)
    if target_name.nil?
      puts "Targets: "
      heroku_targets.targets.each_pair do |key, target|
        puts " * #{key} (#{target})"
      end
    else
      @target = lookup_heroku(target_name)
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
    namespace "heroku:db"
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

    desc "capture --from SOURCE_TARGET", "capture a backup (remotely) from SOURCE_TARGET", hide: true

    def capture
      source = lookup_heroku(options[:from])
      capture_cmd = "heroku pg:backups:capture -a #{source.heroku_app}"
      puts_and_system capture_cmd
    end

    desc "grab --from SOURCE_TARGET", "capture and download dump from SOURCE_TARGET", hide: true

    def grab
      invoke "capture", [], from: options[:from]
      invoke "download", [], from: options[:from]
    end

    desc "download --from SOURCE_TARGET", "download latest db snapshot on source_target"

    def download
      source = lookup_heroku(options[:from])
      download_cmd = "curl -o #{source.dump_filename} `heroku pg:backups:url -a #{source.heroku_app}`"
      puts_and_system download_cmd
    end

    desc "from_dump --from SOURCE_TARGET", "make the db the same as the last target dump from SOURCE_TARGET"

    method_option :just_restore, default: false, desc: "Just do restore without post-actions", type: :boolean

    def from_dump
      invoke "warn", [], from: options[:from]
      source = lookup_heroku(options[:from])
      db_config = ::HerokuTool::DbConfiguration.new
      puts_and_system "pg_restore --verbose --clean --no-acl --no-owner -h localhost #{db_config.user_arg} -d #{db_config.database} #{source.dump_filename}"
      configuration.after_sync_down(self) unless options[:just_restore]
    end

    desc "dump_to_tmp", "dump to tmp directory"
    method_option(:from, type: :string, default: "local", desc: "heroku target (defaults to local)", required: false, aliases: "f")

    def dump_to_tmp
      source = lookup_heroku(options[:from])
      dump_local(source.dump_filename)
    end

    desc "to STAGING_TARGET --from=SOURCE_TARGET", "push db onto STAGING_TARGET from SOURCE_TARGET"

    def to(to_target_name)
      @target = lookup_heroku_staging(to_target_name)
      self.implied_source = lookup_heroku(options[:from])

      maintenance_on

      puts_and_system %(
        heroku pg:copy #{implied_source.heroku_app}::#{implied_source.db_color} #{target.db_color} -a #{target.heroku_app} --confirm #{target.heroku_app}
      )
      configuration.after_sync_to(self, target) unless options[:just_copy]
      maintenance_off
    end

    private

    def dump_local(dumpfilepath)
      puts "dumping postgres to #{dumpfilepath}"
      rails_env = ENV["RAILS_ENV"] || "development"
      db_config = ::HerokuTool::DbConfiguration.new.config[rails_env]
      db_username = db_config["username"]
      db = db_config["database"]
      system_with_clean_env "pg_dump --verbose --clean --no-acl --no-owner -h localhost -U #{db_username} --format=c #{db} > #{dumpfilepath}"
    end
  end

  class Db < Thor
    namespace "heroku:db"
    include Shared

    desc "drop_all_tables on STAGING_TARGET", "drop all tables on STAGING_TARGET"

    def drop_all_tables(staging_target_name)
      @target = lookup_heroku_staging(staging_target_name)
      generate_drop_tables_sql = `#{::HerokuTool::DbConfiguration.new.generate_drop_tables_sql}`
      cmd_string = %(heroku pg:psql -a #{target.heroku_app} -c "#{generate_drop_tables_sql}")
      puts_and_system(cmd_string)
    end

    desc "anonymize STAGING_TARGET", "run anonymization scripts on STAGING_TARGET"

    def anonymize(staging_target_name)
      @target = lookup_heroku_staging(staging_target_name)
      puts_and_system %(
        heroku run rake data:anonymize -a #{target.heroku_app}
      )
    end
  end

  private

  def fetch_asset_host
    get_config_env(target, "ASSET_HOST")
  end

  def print_output_progress(remote_targets, index = nil)
    index ||= remote_targets.length
    remainder = remote_targets.length - index
    print "\routputting configs to tmp/config.*.txt: #{index}/#{remote_targets.count} ▕#{"██" * index}#{"  " * remainder}▏\r"
  end
end
