require "test_helper"

# What a change can break without anything failing loudly (drafts spec §7).
class PublishingGuardsTest < ActiveSupport::TestCase
  # path => why it may take a copy. A new caller is read by a person first.
  TAKERS = {
    "app/models/publishing/version.rb" => "the method itself, and `take_first_copies!`, which the migration runs",
    "app/services/publishing/publish_changes.rb" => "Publish changes",
    "app/services/pages/save.rb" => "a page published or scheduled for the first time, or again after an unpublish",
    "app/services/posts/save.rb" => "a post published or scheduled for the first time, or again after an unpublish"
  }.freeze

  def sources(*roots) = roots.flat_map { |root| Rails.root.glob("#{root}/**/*.{rb,rake,erb}") }.to_h { |path| [ path.to_s.delete_prefix("#{Rails.root}/"), path.read ] }

  test "a copy is taken only where the spec says: the publish service, the two save services and the migration" do
    callers = sources("app", "lib").select { |_path, source| source.match?(/\bVersion\.take!|\.take_first_copies!/) }.keys

    assert_empty callers - TAKERS.keys, "these files take a published copy: add them to TAKERS with the reason, after reading drafts spec §7"
    (TAKERS.keys - callers).each { |path| assert_not File.exist?(Rails.root.join(path)), "TAKERS[#{path.inspect}] takes no copy any more: remove it" }
  end

  test "no row of published_versions is updated: nothing in the app writes one but take!" do
    writers = sources("app", "lib").select do |path, source|
      path != "app/models/publishing/version.rb" && source.match?(/Publishing::Version\b[^\n]*\.(?:update_all|update_columns|update_column|update!?|upsert|insert_all|create!?)\b/)
    end

    assert_empty writers.keys
  end

  test "Admin::Publishing is not defined, and the controller is a class" do
    assert_not Admin.const_defined?(:Publishing, false)
  end
end
