require "test_helper"

# Design pass spec §3: tokens only, red only for destruction and failure,
# and none of the components the shared parts replaced. These rules are easy to
# break one innocent edit at a time, so they are pinned here.
class AdminDesignRulesTest < ActiveSupport::TestCase
  ADMIN_SOURCES = Dir[Rails.root.join("app/{views/admin,views/layouts,views/setup,components/admin,javascript/controllers}/**/*.{erb,rb,js}")]

  test "no raw hex colours and no dark: colour variants in CS Studio" do
    offenders = ADMIN_SOURCES.select do |path|
      source = File.read(path)
      source.match?(/#[0-9a-fA-F]{6}\b/) || source.match?(/\bdark:(bg|text|border|ring|fill|stroke)-/)
    end
    assert_empty offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end

  test "translation chips and language tabs never use the danger colour" do
    %w[app/components/admin/translation_chip_component.rb app/components/admin/language_tabs_component.html.erb].each do |path|
      assert_no_match(/danger/, Rails.root.join(path).read, path)
    end
  end

  test "the replaced components are gone" do
    %w[status_badge_component.rb language_switcher_component.rb flash_component.rb translation_screen/state_badge_component.rb].each do |file|
      assert_not Rails.root.join("app/components/admin", file).exist?, file
    end
    assert_not Rails.root.join("app/views/shared/_theme_toggle.html.erb").exist?
  end
end
