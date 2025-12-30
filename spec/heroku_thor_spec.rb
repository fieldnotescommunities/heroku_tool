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

  shared_context "with collected system calls" do
    let(:system_calls) { [] }

    around do |example|
      example.run
    rescue SystemExit
      puts "!!!system exit called"
    end

    before do
      allow(HerokuTool::HerokuTargets).to receive(:from_file).and_return(targets)
      allow_any_instance_of(Object).to receive(:system) do |_instance, *whatever| # rubocop:disable RSpec/AnyInstance
        system_calls << whatever.join(" ")
        true
      end
      allow_any_instance_of(Object).to receive(:`) do |_instance, *whatever| # rubocop:disable RSpec/AnyInstance
        system_calls << whatever.join(" ")
        "something"
      end
    end
  end

  describe "configs" do
    include_context "with collected system calls"

    subject{ Heroku.start(["configs"]) }
    around do |example|
      example.run
    rescue SystemExit
      puts "!!!system exit called"
    end

    before do
      Dir.mkdir("tmp") unless Dir.exist?("tmp")
    end

    it "calls once per target" do
      subject
      expect(system_calls.length).to eq(2)
      expect(system_calls.shift).to start_with("heroku config -s -a my-heroku-app")
      expect(system_calls.shift).to start_with("heroku config -s -a my-heroku-staging-app")
    end
  end

  describe "deploy" do
    include_context "with collected system calls"
    context "migrate outside of release phase" do
      subject { Heroku.start(["deploy", "my-heroku-app"]) }

      it "should work" do
        expect { subject }.to output.to_stdout
        expect(system_calls).not_to be_empty
        expect(system_calls.length).to eq(9)
        expect(system_calls.shift).to eq "git describe origin/main"
        expect(system_calls.shift).to eq "git --no-pager log $(heroku config:get  -a my-heroku-app)..origin/main"
        expect(system_calls.shift).to eq "git push -f heroku-production origin/main^{}:refs/heads/main"
        expect(system_calls.shift).to eq "heroku maintenance:on -a my-heroku-app"
        expect(system_calls.shift).to eq "heroku config:set X_HEROKU_TOOL_MAINTENANCE_MODE=true -a my-heroku-app"
        expect(system_calls.shift).to eq "heroku run rake db:migrate -a my-heroku-app"
        expect(system_calls.shift).to eq "heroku maintenance:off -a my-heroku-app"
        expect(system_calls.shift).to eq "heroku config:unset X_HEROKU_TOOL_MAINTENANCE_MODE -a my-heroku-app"
        expect(system_calls.shift).to eq "git log -1 origin/main --pretty=format:%H"
      end

      it "should call before and after hooks" do
        expect(Heroku::Configuration).to receive(:before_deploying)
        expect(Heroku::Configuration).to receive(:after_deploying)
        expect { subject }.to output.to_stdout
      end
    end

    context "migrate in release phase" do
      subject { Heroku.start(["deploy", "my-heroku-app"]) }

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

      it "should work" do
        expect { subject }.to output.to_stdout
        expect(system_calls).not_to be_empty
        expect(system_calls.length).to eq(4)
        expect(system_calls.shift).to eq "git describe origin/main"
        expect(system_calls.shift).to eq "git --no-pager log $(heroku config:get  -a my-heroku-app)..origin/main"
        expect(system_calls.shift).to eq "git push -f heroku-production origin/main^{}:refs/heads/main"
        expect(system_calls.shift).to eq "git log -1 origin/main --pretty=format:%H"
      end

      it "should call before and after hooks" do
        expect(Heroku::Configuration).to receive(:before_deploying)
        expect(Heroku::Configuration).to receive(:after_deploying)
        expect { subject }.to output.to_stdout
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

  describe "sync:" do
    describe "grab" do
      subject { Heroku::Sync.start(["grab", "--from", "my-heroku-app"]) }

      include_context "with collected system calls"

      it "should work" do
        expect { subject }.to output.to_stdout
        expect(system_calls).not_to be_empty
        expect(system_calls.length).to eq(2)
        expect(system_calls.shift).to eq "heroku pg:backups:capture -a my-heroku-app"
        expect(system_calls.shift).to match(/curl -o .*latest_my-heroku-app_backup.dump `heroku pg:backups:url -a my-heroku-app`/)
      end
    end

    describe "from_dump" do
      subject { Heroku::Sync.start(["from_dump", "--from", "my-heroku-app"]) }

      let(:db_configuration) { instance_double(HerokuTool::DbConfiguration, user_arg: "-u someone", database: "my_database") }

      include_context "with collected system calls"

      before do
        allow(HerokuTool::DbConfiguration).to receive(:new).and_return(db_configuration)
      end

      it "should work" do
        expect { subject }.to output.to_stdout
        expect(system_calls).not_to be_empty
        expect(system_calls.length).to eq(3)
        expect(system_calls.shift).to match(/pg_restore --verbose --clean --no-acl --no-owner -h localhost -u someone -d my_database .*latest_my-heroku-app_backup.dump/)
        expect(system_calls.shift).to eq("rails db:migrate")
        expect(system_calls.shift).to eq("rails db:test:prepare")
      end
    end
  end
end
