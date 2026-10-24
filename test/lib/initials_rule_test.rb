require "test_helper"

# Layout points spec, decision 10: a person's letters are written once, by
# `PersonName.initials` on the server, and handed to the scripts that draw a
# circle. A source grep for the shape the two copies had (split on white
# space, two words, a first character); a rule written another way is not seen.
class InitialsRuleTest < ActiveSupport::TestCase
  test "no script computes a person's initials: the letters come from PersonName.initials on the server" do
    offenders = Dir[Rails.root.join("app/javascript/**/*.js")].select do |path|
      File.read(path).match?(/split\(\/\\s\+\/\)\S*\.slice\(0,\s*2\)/)
    end
    assert_empty offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end
end
