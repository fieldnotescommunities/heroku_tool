# frozen_string_literal: true

namespace :db do
  desc "drop all tables without worrying about concurrent accesses"
  task drop_all_tables: :environment do
    require File.expand_path("../../heroku_tool/db_configuration.rb", __FILE__)
    abort("Don't run this on production") if Rails.env.production?

    db_config = HerokuTool::DbConfiguration.new
    generate_drop_tables_sql = db_config.generate_drop_tables_sql
    cmd_string = %(#{generate_drop_tables_sql} | psql #{db_config.user_arg} #{db_config.database})
    puts cmd_string
    system(cmd_string)
  end
end
