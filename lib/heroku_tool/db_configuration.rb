# NB need to specify a username in the database.yml if you want to use any of these commands
module HerokuTool
  class DbConfiguration
    def config
      db_config_from_file = ERB.new(File.read("config/database.yml")).result
      @config ||= YAML.safe_load(db_config_from_file, [], [], true)
    end

    def generate_drop_tables_sql
      sql = %(select 'DROP TABLE IF EXISTS \\"' || tablename || '\\" CASCADE;' from pg_tables where schemaname = 'public')
      %(psql #{user_arg} #{database} -t -c "#{sql}")
    end

    def user_arg
      username = db_config["username"]
      username.present? && "-U #{username}" || ""
    end

    def database
      db_config["database"]
    end

    private

    def db_config
      config[env]
    end

    def env
      ENV["RAILS_ENV"] || "development"
    end
  end
end
