# frozen_string_literal: true

require "spec_helper"

load File.expand_path("../../lib/heroku_tool/tasks/heroku.thor", __FILE__)

RSpec.describe "Heroku thor" do
  let(:targets_yml) {
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
  let(:targets) { HerokuTool::HerokuTargets.from_string(targets_yml) }

  describe "configs" do
    let(:heroku_thor) { Heroku.new }

    around do |example|
      example.run
    rescue SystemExit
      puts "!!!system exit called"
    end

    before do
      Dir.mkdir("tmp") unless Dir.exist?("tmp")
      allow(heroku_thor).to receive(:heroku_targets).and_return(targets)
    end

    it "calls once per target" do
      expect(heroku_thor).to receive(:exec_with_clean_env).with(start_with("heroku config -s -a my-heroku-app"))
      expect(heroku_thor).to receive(:exec_with_clean_env).with(start_with("heroku config -s -a my-heroku-staging-app"))
      heroku_thor.configs
    end
  end

  describe "deploy" do
    let(:system_calls) { [] }
    around do |example|
      example.run
    rescue SystemExit
      puts "!!!system exit called"
    end

    before do
      expect(HerokuTool::HerokuTargets).to receive(:from_file).and_return(targets)
      allow_any_instance_of(Object).to receive(:system) do |_instance, *whatever|
        system_calls << whatever.join(" ")
        true
      end
      allow_any_instance_of(Object).to receive(:exec) do |_instance, *whatever|
        system_calls << whatever.join(" ")
        true
      end
    end

    context "migrate outside of release phase" do
      subject { Heroku.start(["deploy", "my-heroku-app"]) }
      it "should work" do
        expect{subject}.to output.to_stdout
        expect(system_calls).not_to be_empty
        expect(system_calls.length).to eq(6)
        expect(system_calls[0]).to eq "git push -f heroku-production origin/main^{}:refs/heads/main"
        expect(system_calls[1]).to eq "heroku maintenance:on -a my-heroku-app"
        expect(system_calls[2]).to eq "heroku config:set X_HEROKU_TOOL_MAINTENANCE_MODE=true -a my-heroku-app"
        expect(system_calls[3]).to eq "heroku run rake db:migrate -a my-heroku-app"
        expect(system_calls[4]).to eq "heroku maintenance:off -a my-heroku-app"
        expect(system_calls[5]).to eq "heroku config:unset X_HEROKU_TOOL_MAINTENANCE_MODE -a my-heroku-app"
      end
      it "should call before and after hooks" do
        expect(Heroku::Configuration).to receive(:before_deploying)
        expect(Heroku::Configuration).to receive(:after_deploying)
        expect{subject}.to output.to_stdout
      end
    end

    context "migrate in release phase" do
      let(:targets_yml) {
        <<~VALID
          _defaults:
            repository: https://github.com/some/where
            migrate_in_release_phase: true
          production:
            heroku_app : my-heroku-app
            git_remote : heroku-production
            deploy_ref : origin/main
            display_name : my.heroku.com
        VALID
      }

      subject { Heroku.start(["deploy", "my-heroku-app"]) }
      it "should work" do
        expect{subject}.to output.to_stdout
        expect(system_calls).not_to be_empty
        expect(system_calls.length).to eq(1)
        expect(system_calls[0]).to eq "git push -f heroku-production origin/main^{}:refs/heads/main"
      end
      it "should call before and after hooks" do
        expect(Heroku::Configuration).to receive(:before_deploying)
        expect(Heroku::Configuration).to receive(:after_deploying)
        expect{subject}.to output.to_stdout
      end
    end

    context "with wrong target" do
      subject { Heroku.start(["deploy", "wrong-target"]) }

      it "should fail" do
        expect { subject }.to output(/Target 'wrong-target' was not found/).to_stderr
        expect(system_calls).to be_empty
      end
    end
  end
end
