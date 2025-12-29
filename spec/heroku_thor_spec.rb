# frozen_string_literal: true

require "spec_helper"

load File.expand_path("../../lib/heroku_tool/tasks/heroku.thor", __FILE__)

RSpec.describe "Heroku thor" do
  let(:standard_targets_yml) {
    <<~VALID
      _defaults:
        repository: https://github.com/some/where
      production:
        heroku_app : my-heroku-app
        git_remote : heroku-production
        deploy_ref : origin/main
        display_name : my.heroku.com
      staging:
        heroku_app : my-heroku-staging-app
        git_remote : heroku-staging
        deploy_ref : HEAD
        display_name : my-staging.heroku.com
        staging : true
    VALID
  }
  let(:standard_targets) { HerokuTool::HerokuTargets.from_string(standard_targets_yml) }

  describe "configs" do
    let(:heroku_thor) { Heroku.new }

    around do |example|
      example.run
    rescue SystemExit
      puts "!!!system exit called"
    end

    before do
      Dir.mkdir("tmp") unless Dir.exist?("tmp")
      allow(heroku_thor).to receive(:heroku_targets).and_return(standard_targets)
    end

    it "calls once per target" do
      expect(heroku_thor).to receive(:exec_with_clean_env).with(start_with("heroku config -s -a my-heroku-app"))
      expect(heroku_thor).to receive(:exec_with_clean_env).with(start_with("heroku config -s -a my-heroku-staging-app"))
      heroku_thor.configs
    end
  end
end
