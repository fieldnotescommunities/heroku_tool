# Changelog

## v0.9.0

BREAKING CHANGES:

- drop set_message for simplicity - you can do that as part of Configuration.before_deploying and Configuration.after_deploying

## v0.8.0

- allow for multiple databases in configuration

## v0.7.1

- update for changes to heroku cli in heroku 9.0 (#12)
  `heroku pg:backups:public-url` -> `heroku pg:backups:url`

## v0.7.0

Skip requiring users to set Heroku::Configuration.app_revision_env_var (typically COMMIT_HASH or a APP_REVISION).
Skip setting this if you don't specify it.
Skip setting this if you specify it as HEROKU_SLUG_COMMIT (see https://devcenter.heroku.com/articles/dyno-metadata)

## v0.6.0

Don't do unecessary restart after changing environment variables.

## v0.5.0

Dropped psych < 4.0 and now working with psych >= 4.0

## v0.4.0

Dropped thor < 1.0

## v0.3.0

Works with thor <= 1.0

## v0.2.0

Now assumes a default of main as the main branch.
Works after heroku git has had its repo reset (e.g. after switching from master to main, see https://help.heroku.com/O0EXQZTA/how-do-i-switch-branches-from-master-to-main).
