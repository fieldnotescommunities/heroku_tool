# frozen_string_literal: true

require "spec_helper"
require File.expand_path("../../lib/heroku_tool/db_configuration", __FILE__)


RSpec.describe "HerokuTool::DbConfiguration" do
  def fixture_filepath(name)
    File.expand_path("../fixtures/db_configuration/#{name}", __FILE__)
  end

  context "with single db configuration" do
    subject { HerokuTool::DbConfiguration.new(filepath: fixture_filepath("single_db.yml"),  rails_env: "development") }
    it "can read" do
      expect(subject.config_all).to be_a(Hash)
      expect(subject.config_env).to be_a(Hash)
    end

    it "can find database" do
      expect(subject.database).to eq("someapp_development")
    end

    it "can generate user_arg" do
      expect(subject.user_arg).to eq("-U the-dev-user")
    end
  end

  context "with multi db configuration" do
    subject { HerokuTool::DbConfiguration.new(filepath: fixture_filepath("multi_db.yml"),  rails_env: "development") }
    it "can read" do
      expect(subject.config_all).to be_a(Hash)
      expect(subject.config_env).to be_a(Hash)
    end

    it "can find database" do
      expect(subject.database).to eq("someapp_development")
    end

    it "can generate user_arg" do
      expect(subject.user_arg).to eq("-U the-dev-user")
    end
  end
end
