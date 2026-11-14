# The Diagram block's fixture drawings (test/support/diagram_fixtures.rb):
# what the vendored Mermaid draws for each sample source of
# test/fixtures/diagrams/sources.yml, raw, drawn by the real renderer frame in
# headless Chrome. Run after every Mermaid upgrade, then read the new
# drawings' elements, attributes and classes against `Diagrams::Drawing`'s
# lists and `diagram.css`:
#   RAILS_ENV=test bin/rails diagram:fixtures
# It also writes the Diagram block's sample drawings, cleaned, to
# db/seeds/diagrams/sample-<locale>.svg, from the `sample_<locale>` sources;
# run it after changing `BlockTypes::Diagram::SAMPLE_SOURCES` too.
# Under the test environment only: it boots the test's server, signs in with
# an owner made for the run and rolls the test database back at the end.
namespace :diagram do
  desc "Write test/fixtures/diagrams/*.svg, MERMAID_VERSION and db/seeds/diagrams/*.svg with the vendored Mermaid (RAILS_ENV=test)"
  task fixtures: :environment do
    abort "diagram:fixtures runs under RAILS_ENV=test (it boots the test's server)." unless Rails.env.test?

    require Rails.root.join("test/support/diagram_fixtures").to_s
    DiagramFixtures.write!
  end
end
