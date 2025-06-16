# AGENT Instructions

This repository contains a [Nanoc](https://nanoc.app/) site. Nanoc is a static site generator written in Ruby. Items under `content/` are combined with layouts in `layouts/` according to the rules in the `Rules` file and configuration in `nanoc.yaml` to produce the `output/` directory.

## Checks before commit

1. Install Ruby dependencies:
   ```
   bundle install
   ```
2. Run the test suite with coverage:
   ```
   bundle exec rspec
   ```
   The tests must pass and coverage must remain above 90% (enforced via SimpleCov in `spec/spec_helper.rb`).
3. Compile the site:
   ```
   bundle exec nanoc compile
   ```
   The compilation should finish without errors.
4. Verify that key output files were generated (these files are not tracked but should exist after compile), for example:
   - `output/index.html`
   - `output/about/index.html`
   - `output/games/index.html`

If any of these steps fail, fix the issue before committing changes.
