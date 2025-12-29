lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "heroku_tool/version"

Gem::Specification.new do |spec|
  spec.name = "heroku_tool"
  spec.version = HerokuTool::VERSION
  spec.authors = ["Tim Diggins"]
  spec.email = ["tim@fieldnotescommunities.com"]

  spec.summary = "Tool for configurable one-shot deployment and db managment with heroku and rails"
  spec.homepage = "https://github.com/fieldnotescommunities/heroku_tool"
  spec.license = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path("..", __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.0"
  spec.add_dependency "activesupport"
  spec.add_dependency "psych", ">= 4.0"

  spec.add_development_dependency "rake", ">= 12.3.3"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "standard", "~> 1.52.0"
  spec.add_development_dependency "rubocop", "~> 1.81.7"
  spec.add_development_dependency "rubocop-rspec", "~> 3.8.0"
end
