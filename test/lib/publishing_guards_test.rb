require "test_helper"

# What a change can break without anything failing loudly (drafts spec §7).
class PublishingGuardsTest < ActiveSupport::TestCase
  # path => why it may take a copy. A new caller is read by a person first.
  TAKERS = {
    "app/models/publishing/version.rb" => "the method itself",
    "app/services/publishing/publish_changes.rb" => "Publish changes",
    "app/services/pages/save.rb" => "a page published or scheduled for the first time, or again after an unpublish",
    "app/services/posts/save.rb" => "a post published or scheduled for the first time, or again after an unpublish"
  }.freeze

  def sources(*roots) = roots.flat_map { |root| Rails.root.glob("#{root}/**/*.{rb,rake,erb}") }.to_h { |path| [ path.to_s.delete_prefix("#{Rails.root}/"), path.read ] }

  test "a copy is taken only where the spec says: the publish service, the two save services and the migration" do
    callers = sources("app", "lib").select { |_path, source| source.match?(/\bVersion\.take!|def self\.take!/) }.keys

    assert_empty callers - TAKERS.keys, "these files take a published copy: add them to TAKERS with the reason, after reading drafts spec §7"
    (TAKERS.keys - callers).each { |path| assert_not File.exist?(Rails.root.join(path)), "TAKERS[#{path.inspect}] takes no copy any more: remove it" }
  end

  WRITES = /\.(?:update_all|update_columns|update_column|update!?|upsert|upsert_all|insert_all|insert|create!?|delete_all|delete_by|delete|destroy_all|destroy_by|destroy!?|touch_all|touch)\b/

  test "no row of published_versions is written or removed but by take! (and the destroyed record's own dependent delete)" do
    writers = sources("app", "lib").select do |path, source|
      path != "app/models/publishing/version.rb" && source.lines.any? do |line|
        next false if line.strip.start_with?("#")

        line.match?(/\bVersion\b[^\n]*#{WRITES}/) || line.match?(/\bpublished_versions\b[^\n]*#{WRITES}/)
      end
    end

    assert_empty writers.keys
  end

  test "the writes guard sees a bare Version inside module Publishing and a relation of a record's copies" do
    assert_match(/\bVersion\b[^\n]*#{WRITES}/, "Version.where(id: 1).delete_all")
    assert_match(/\bpublished_versions\b[^\n]*#{WRITES}/, "page.published_versions.update_all(live_at: nil)")
    assert_match(/\bVersion\b[^\n]*#{WRITES}/, "Publishing::Version.of(page).destroy_all")
  end

  test "Admin::Publishing is not defined" do
    assert_not Admin.const_defined?(:Publishing, false)
  end
end
