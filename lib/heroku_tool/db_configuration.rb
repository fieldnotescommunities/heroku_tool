# NB need to specify a username in the database.yml if you want to use any of these commands
module HerokuTool
  class DbConfiguration
    attr_reader :config_all, :config_env

    def initialize(filepath: "config/database.yml", rails_env: ENV["RAILS_ENV"] || "development")
      db_config_from_file = ERB.new(File.read(filepath)).result
      @config_all = YAML.safe_load(db_config_from_file, permitted_classes: [], permitted_symbols: [], aliases: true)
      config_env = @config_all[rails_env]
      @config_env = if config_env["database"].is_a?(String)
                      config_env
                    elsif config_env.key?("primary")
                      config_env["primary"]
                    else
                      config_env.values.first
                    end
    end

    def generate_drop_tables_sql
      sql = %(select 'DROP TABLE IF EXISTS \\"' || tablename || '\\" CASCADE;' from pg_tables where schemaname = 'public')
      %(psql #{user_arg} #{database} -t -c "#{sql}")
    end

    def user_arg
      username = config_env["username"]
      username.present? && "-U #{username}" || ""
    end

    def database
      config_env["database"]
    end

  end
end
