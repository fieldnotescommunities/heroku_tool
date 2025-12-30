# frozen_string_literal: true

require "active_support/all"
require "yaml"

module HerokuTool
  class HerokuTargets
    class << self
      def from_string(heroku_targets_yml)
        new(YAML.safe_load(heroku_targets_yml))
      end

      def from_file(yaml_file)
        new(YAML.safe_load_file(yaml_file))
      end
    end

    attr_reader :targets, :staging_targets

    DEFAULTS_KEY = "_defaults"

    def initialize(targets_hash)
      defaults = if targets_hash.keys.first == DEFAULTS_KEY
        targets_hash.delete(DEFAULTS_KEY)
      else
        {}
      end
      specified = targets_hash.collect { |name, values|
        heroku_target = HerokuTarget.new(defaults.merge(values), name)
        [heroku_target.heroku_app, heroku_target]
      }
      built_in = [["local", LocalProxy.new(defaults)]]
      @targets = TargetsContainer[(specified + built_in)].freeze
      @staging_targets = TargetsContainer[@targets.select { |_name, target| target.staging? }]
    end

    class TargetsContainer < HashWithIndifferentAccess
      def [](key)
        return super if key?(key)
        values.each do |value|
          return value if value.name.to_s == key.to_s
        end
        nil
      end
    end

    class HerokuTarget
      attr_reader :name

      def initialize(values_hash, name = nil)
        @values = values_hash.symbolize_keys.freeze
        @name = name.to_sym if name
        %i[heroku_app git_remote deploy_ref].each do |required_name|
          raise required_value(required_name) unless @values[required_name] || local?
        end
      end

      def required_value(required_name)
        ArgumentError.new("please specify '#{required_name}:' ")
      end

      def staging?
        @values[:staging]
      end

      def local?
        false
      end

      def display_name
        @values[:display_name] || @values[:heroku_app]
      end

      def heroku_app
        @values[:heroku_app]
      end

      def database_url
        @values[:database_url]
      end

      def git_remote
        @values[:git_remote]
      end

      def deploy_ref
        @values[:deploy_ref]
      end

      def db_color
        @values[:db_color] || "DATABASE"
      end

      def repository
        @values[:repository] || raise(required_value(:repository))
      end

      def heroku_target_ref
        @values[:heroku_target_ref] || "refs/heads/main"
      end

      def migrate_in_release_phase
        @values[:migrate_in_release_phase]
      end

      def to_s
        display_name
      end

      def dump_filename
        File.expand_path("tmp/latest_#{heroku_app}_backup.dump")
      end

      def trackable_release_stage
        @values[:trackable_release_stage].presence || (staging? ? "staging" : "production")
      end
    end

    class LocalProxy < HerokuTarget
      def initialize(defaults)
        super(defaults.merge(staging: true, heroku_app: "local"), "local")
      end

      def local?
        true
      end
    end
  end
end
