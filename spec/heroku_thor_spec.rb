# frozen_string_literal: true

require "spec_helper"

load File.expand_path("../../lib/tasks/heroku.thor", __FILE__)

RSpec.describe "Heroku thor" do
  it "is instantiated ok" do
    Heroku.new
  end
end
