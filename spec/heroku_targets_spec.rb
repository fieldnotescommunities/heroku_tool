# frozen_string_literal: true

require "spec_helper"

require File.expand_path("../../lib/heroku_tool/heroku_targets", __FILE__)

RSpec.describe HerokuTool::HerokuTargets do
  valid_file = <<-VALID
  production:
    heroku_app : my-production-heroku_app
    git_remote : heroku_production
    deploy_ref : origin/main
  staging:
    heroku_app : my-staging-heroku_app
    git_remote : heroku_production
    deploy_ref : origin/main
    display_name : My Lovely Staging heroku_app
    staging : true
    db_color : NAVY
  VALID

  let(:valid_ht) { HerokuTool::HerokuTargets.from_string(valid_file) }
  describe "wrapper class (HerokuTargets)" do
    it "should be able to find display_names" do
      expect(valid_ht.targets).to be_a(Hash)
      expect(valid_ht.targets.keys).to include("my-staging-heroku_app")
      expect(valid_ht.targets.keys).to include("my-production-heroku_app")
    end
    it "should parse targets as a HerokuTarget" do
      expect(valid_ht.targets.values.collect(&:class).uniq).to contain_exactly(HerokuTool::HerokuTargets::HerokuTarget, HerokuTool::HerokuTargets::LocalProxy)
    end

    it "should be able to find staging targets" do
      expect(valid_ht.staging_targets).to be_a(Hash)
      expect(valid_ht.staging_targets.keys).to include("my-staging-heroku_app")
      expect(valid_ht.staging_targets.keys).not_to include("my-production-heroku_app")
    end

    it "should be able to find a target by heroku ref" do
      expect(valid_ht.targets["my-production-heroku_app"]).to be_a(HerokuTool::HerokuTargets::HerokuTarget)
      expect(valid_ht.staging_targets["my-staging-heroku_app"]).to be_a(HerokuTool::HerokuTargets::HerokuTarget)
    end
    it "should be able to find local pseudo target" do
      puts valid_ht.targets.keys
      expect(valid_ht.targets["local"]).to be_a(HerokuTool::HerokuTargets::LocalProxy)
      expect(valid_ht.staging_targets["local"]).to be_a(HerokuTool::HerokuTargets::LocalProxy)
    end
    it "should be able to find a target by name as well" do
      expect(valid_ht.targets[:production]).to be_a(HerokuTool::HerokuTargets::HerokuTarget)
      expect(valid_ht.staging_targets[:staging]).to be_a(HerokuTool::HerokuTargets::HerokuTarget)
      expect(valid_ht.staging_targets[:local]).to be_a(HerokuTool::HerokuTargets::LocalProxy)
    end
    it "should be able to find a target by string or symbol" do
      expect(valid_ht.targets["production"]).to be_a(HerokuTool::HerokuTargets::HerokuTarget)
      expect(valid_ht.targets["my-production-heroku_app".to_sym]).to be_a(HerokuTool::HerokuTargets::HerokuTarget)
    end
    it "should be able to return nil if no such target" do
      expect(valid_ht.targets["whatevs"]).to be_nil
      expect(valid_ht.staging_targets["whatevs"]).to be_nil
    end
    it "should be able to return db_color " do
      expect(valid_ht.targets["staging"].db_color).to eq("NAVY")
      expect(valid_ht.targets["production"].db_color).to eq("DATABASE")
    end
    it "should raise if repository accessed when unspecified" do
      [valid_ht.targets["staging"], valid_ht.targets["production"]].each do |target|
        expect { target.repository }.to raise_error(/repository/)
      end
    end
    it "should infer migrate_in_release_phase" do
      [valid_ht.targets["staging"], valid_ht.targets["production"]].each do |target|
        expect( target.migrate_in_release_phase ).to be_falsey
      end
    end
  end
  describe "with defaults" do
    valid_file_with_defaults = <<-VALID
    _defaults:
      repository : https://mygit.hub.com/some/where
      deploy_ref : origin/main
      migrate_in_release_phase : true
    production:
      heroku_app : my-production-heroku_app
      git_remote : heroku_production
    staging:
      heroku_app : my-staging-heroku_app
      git_remote : heroku_staging
      deploy_ref : HEAD
    VALID

    let(:valid_ht) { HerokuTool::HerokuTargets.from_string(valid_file_with_defaults) }

    it "can use defaults for deploy_ref" do
      expect(valid_ht.targets["production"].deploy_ref).to eq("origin/main")
    end
    it "can override defaults for deploy_ref" do
      expect(valid_ht.targets["staging"].deploy_ref).to eq("HEAD")
    end
    it "should use defaults for repository" do
      [valid_ht.targets["staging"], valid_ht.targets["production"]].each do |target|
        expect(target.repository).to eq("https://mygit.hub.com/some/where")
      end
    end
    it "should use defaults for migrate_in_release_phase" do
      [valid_ht.targets["staging"], valid_ht.targets["production"]].each do |target|
        expect(target.migrate_in_release_phase).to be_truthy
      end
    end
  end

  describe "heroku_target_ref" do
    context "out of the box" do
      it "uses refs/heads/main" do
        expect(valid_ht.targets["staging"].heroku_target_ref).to eq("refs/heads/main")
        expect(valid_ht.targets["production"].heroku_target_ref).to eq("refs/heads/main")
      end
    end
    context "can be explicitly set" do
      valid_file_with_defaults = <<-VALID
      _defaults:
        repository : https://mygit.hub.com/some/where
        deploy_ref : origin/main
        heroku_target_ref : refs/heads/master
      production:
        heroku_app : my-production-heroku_app
        git_remote : heroku_production
      staging:
        heroku_app : my-staging-heroku_app
        git_remote : heroku_staging
        deploy_ref : HEAD
        heroku_target_ref: refs/heads/main
      VALID

      let(:valid_ht) { HerokuTool::HerokuTargets.from_string(valid_file_with_defaults) }

      it "can set a new default" do
        expect(valid_ht.targets["production"].heroku_target_ref).to eq("refs/heads/master")
      end
      it "can override" do
        expect(valid_ht.targets["staging"].heroku_target_ref).to eq("refs/heads/main")
      end
    end
  end

  describe HerokuTool::HerokuTargets::HerokuTarget do
    let(:minimal_values) { {heroku_app: "my-lovely-app", git_remote: "heroku_branch", deploy_ref: "HEAD"} }

    it "should work with minimal values" do
      expect(HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values)).to be_a(HerokuTool::HerokuTargets::HerokuTarget)
    end
    it "should require heroku_app" do
      expect { HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values.except(:heroku_app)) }.to raise_error ArgumentError
    end
    it "should require deploy_ref" do
      expect { HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values.except(:deploy_ref)) }.to raise_error ArgumentError
    end
    it "should require git_remote" do
      expect { HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values.except(:git_remote)) }.to raise_error ArgumentError
    end

    it "should be not staging by default" do
      target = HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values.except(:staging))
      expect(target).not_to be_staging
    end
    it "should be staging when set" do
      target = HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values.merge(staging: true))
      expect(target).to be_staging
    end
    it "should give display_name as heroku_app if not specified" do
      target = HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values)
      expect(target.display_name).to eq(target.heroku_app)
    end
    it "should give display_name as heroku_app if not specified" do
      target = HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values.merge(display_name: "Flarrr"))
      expect(target.display_name).to eq("Flarrr")
    end
    it "should give heroku_app" do
      target = HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values)
      expect(target.heroku_app).to eq(minimal_values[:heroku_app])
    end
    it "should give git_remote" do
      target = HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values)
      expect(target.git_remote).to eq(minimal_values[:git_remote])
    end
    it "should give deploy_ref" do
      target = HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values)
      expect(target.deploy_ref).to eq(minimal_values[:deploy_ref])
    end
    it "should give trackable_release_stage" do
      target = HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values)
      expect(target.trackable_release_stage).to eq("production")
    end
    it "should give trackable_release_stage for staging" do
      target = HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values.merge(staging: true))
      expect(target.trackable_release_stage).to eq("staging")
    end
    it "should give trackable_release_stage for explicit set" do
      target = HerokuTool::HerokuTargets::HerokuTarget.new(minimal_values.merge(trackable_release_stage: "demo"))
      expect(target.trackable_release_stage).to eq("demo")
    end
  end
end
