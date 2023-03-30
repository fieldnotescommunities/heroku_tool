# HerokuTool

Tool for configurable one-shot deployment and db managment with heroku and rails

If you're using continuous deployment with pipelines in Heroku, you won't need this. However if that style doesn't work, then this may allow you to manage databases and deployment with more control but less hassle.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'heroku_tool'
```

(you can add it to development/test only if you want)

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install heroku_tool

## Configuration

> TODO: Some of these manual configuration steps, would be nicer to make a bit more automatic perhaps by making this a Rails engine.

1) Your database configuration (config/database.yml) needs to have a username if you want to use the db configurations

2) Append `load "heroku_tool/tasks/db_drop_all_tables.rake"` to the end of Rakefile (see lib/templates/Rakefile if you are adding this gem in development/test only)

3) Copy templates into codebase:

       cp $(bundle show heroku_tool)/templates/heroku.thor ./lib/tasks
       cp $(bundle show heroku_tool)/templates/heroku_targets.yml ./config

4) update heroku_targets.yml with your staging and production targets. 
  My set up for this is to have staging deploy the local version, but production 
  deploy the origin/main.

   NB: master vs main
   heroku-tool (as of 0.2.0) assumes the new current standard of main as the main branch, but if you're on the older standard of "master" then adjust your deploy refs to origin/master and the heroku_target_ref: in defaults to be ref/heads/master
   
      > TODO: more detail
 
5) You may want to set up a smoke test that your heroku targets are valid
 
       require "heroku_tool/heroku_targets"
       
       RSpec.describe "heroku_targets.yml" do
         it "is valid (smoke test)" do 
           HerokuTool::HerokuTargets.from_file(Rails.root.join("config/heroku_targets.yml"))
         end
       end

## Usage

### Deploy 

Deploy the latest with db migrate *(but see below) during maintenance

    thor heroku:deploy staging

or without maintenance*

    thor heroku:deploy staging --no-maintenance

or without migrating*

    thor heroku:deploy staging --no-migrate
    
or a specific tag/branch

    thor heroku:deploy staging hotfix-branch

*Note on db:migrate:

It is very possible to run migrations as part of the heroku release phase:
* https://mentalized.net/journal/2017/04/22/run-rails-migrations-on-heroku-deploy/
* https://devcenter.heroku.com/articles/release-phase#design-considerations

In this case you should set `migrate_in_release_phase: true` in your defaults (see templates/heroku_targets.yml)
and you won't run migrate as a separate step.

### Sync

Sync a database down from remote to local 

    thor heroku:sync:grab -f staging
    # when it finishes
    rake db:drop_all_tables && thor heroku:sync:from_dump -f staging

_FYI rake db:drop_all_tables is handy as it doesn't require you to disconnect any running processes from the database._

Copy production db to staging

    thor heroku:sync:to staging -f production

NB: this won't work from a staging to a production environment (failsafe)
    

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.


Ensure standards before PR:

    bundle exec standardrb --fix

(TODO: enforce this or rubocop)

## Release

To release a new version:

* update the version number in [version.rb](./lib/heroku_tool/version.rb)
* add a note in the [CHANGELOG.md](./CHANGELOG.md)
* commit

      git commit -am "preparing for release"

* and run

      bundle exec rake release

  whch creates a git tag for the version, pushes git commits and tags, and pushes the gem file to [rubygems.org](https://rubygems.org)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fieldnotescommunities/heroku_tool. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the HerokuTool project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/fieldnotescommunities/heroku_tool/blob/master/CODE_OF_CONDUCT.md).
