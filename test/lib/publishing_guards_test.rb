require "test_helper"
require_relative "version_bump_test"

# What a change can break without anything failing loudly (drafts spec §7).
class PublishingGuardsTest < ActiveSupport::TestCase
  # path => why it may take a copy. A new caller is read by a person first.
  TAKERS = {
    "app/models/publishing/version.rb" => "the method itself",
    "app/services/publishing/publish_changes.rb" => "Publish changes",
    "app/services/pages/save.rb" => "a page published or scheduled for the first time, or again after an unpublish",
    "app/services/posts/save.rb" => "a post published or scheduled for the first time, or again after an unpublish",
    "app/models/public_site/paths.rb" => "foresee: a copy taken inside a savepoint that is rolled back, to say what a publish would take away"
  }.freeze

  def sources(*roots) = roots.flat_map { |root| Rails.root.glob("#{root}/**/*.{rb,rake,erb}") }.to_h { |path| [ path.to_s.delete_prefix("#{Rails.root}/"), path.read ] }

  test "a copy is taken only where the spec says: the publish service, the two save services and the rolled-back trial" do
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

  # The model's own file is exempt above, so its writers are named here:
  # `take!`, which writes a copy and removes a pending one;
  # `withdraw_pending!`, which removes a pending one and nothing else; `repoint_tag!`,
  # which replaces a merged tag's id (a reference that is about to name
  # nothing; drafts fix round, Task 4); and `settle!`, which marks a copy
  # whose coming into force is being acted on (Task 4b). Neither of the last
  # two touches what a copy shows.
  WRITERS_IN_THE_MODEL = %w[take! repoint_tag! settle! withdraw_pending!].freeze
  # `withdraw_pending!` deletes the one copy that was never public (its time
  # has not come): "Cancel scheduled change", and a discard, which goes back
  # to what is in force (Task 7).
  WITHDRAWERS = {
    "app/services/publishing/cancel_scheduled_change.rb" => "Cancel scheduled change withdraws the pending copy",
    "app/services/publishing/discard_changes.rb" => "a discard goes back to the copy in force, so a scheduled change goes with it"
  }.freeze
  REPOINTERS = { "app/services/tags/merge.rb" => "a merge replaces the merged tag's id in the copies" }.freeze
  SETTLERS = { "app/models/public_site/paths.rb" => "refresh settles the due copies and re-derives their records in one transaction" }.freeze

  def callers_of(name)
    sources("app", "lib").select { |path, source| path != "app/models/publishing/version.rb" && source.lines.any? { |line| !line.strip.start_with?("#") && line.include?(name) } }.keys
  end

  test "inside Publishing::Version only take!, repoint_tag!, settle! and withdraw_pending! write a row; only Tags::Merge repoints, only PublicSite::Paths settles and only the cancel and the discard withdraw" do
    writing = []
    method = nil
    Rails.root.join("app/models/publishing/version.rb").read.each_line do |line|
      method = line[/def (?:self\.)?([a-z_]+[!?]?)/, 1] || method
      next if line.strip.start_with?("#")

      writing << method if line.match?(/#{WRITES}|\bcreate!?\(/)
    end
    assert_equal WRITERS_IN_THE_MODEL.sort, writing.uniq.sort

    assert_equal REPOINTERS.keys, callers_of("repoint_tag!")
    assert_equal SETTLERS.keys, callers_of("settle!")
    assert_equal WITHDRAWERS.keys.sort, callers_of("withdraw_pending!").sort
  end

  # "A live record has a copy" is not enforced by the database or by a
  # callback: a record written around the services is served, listed and
  # given its address from its ROWS (`Publishing.published_all`,
  # `Publishing::Listing.blocks`). What keeps that a case of tests and a
  # console is that the application sets a publication time in two places
  # only, each of which takes the copy in the same transaction. A third place
  # would publish records with no copy from CS Studio itself.
  PUBLISHERS = {
    "app/services/pages/save.rb" => "publishes, schedules and unpublishes a page, and takes its copy",
    "app/services/posts/save.rb" => "publishes, schedules and unpublishes a post, and takes its copy",
    "app/services/starter_contents/add.rb" => "unsaved stand-ins to ask the rights for; the records are written by the save services"
  }.freeze
  ASSIGNS_PUBLISHED_AT = /\.published_at\s*=(?![=~])|\[:published_at\]\s*=(?![=~])|\b(?:update_column|write_attribute)\(\s*:published_at\b|\b(?:update!?|update_columns?|update_all|assign_attributes|new|create!?|insert_all!?|upsert_all)\b[^\n]*\bpublished_at:/

  test "published_at is assigned only in the two save services" do
    assigning = sources("app", "lib").select { |_path, source| source.lines.any? { |line| !line.strip.start_with?("#") && line.match?(ASSIGNS_PUBLISHED_AT) } }.keys

    assert_equal PUBLISHERS.keys.sort, assigning.sort, "a new place that sets published_at must take the copy too (drafts spec §4.1): read Pages::Save before adding it here"
  end

  test "the published_at guard sees a setter, an update and a new record, and not a condition" do
    [ "page.published_at = now", "post.update!(published_at: nil)", "Page.new(parent: home, published_at: now)", "scope.update_all(published_at: now)",
      "page.update_column(:published_at, now)", "write_attribute(:published_at, now)", "self[:published_at] = now" ].each do |line|
      assert_match ASSIGNS_PUBLISHED_AT, line
    end
    [ "Post.where(published_at: ..now)", "page.published_at == nil", "Pages::Save.call(page, attributes: { published_at: at })", "Page.arel_table[:published_at].gt(since)" ].each do |line|
      assert_no_match ASSIGNS_PUBLISHED_AT, line
    end
  end

  test "a copy still refuses every write of its own: update, destroy and a changed attribute saved" do
    page = create_page(title: "Kept as taken")
    copy = Publishing.current(page)

    assert_raises(ActiveRecord::ReadOnlyRecord) { copy.update!(tag_ids: [ 1 ]) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { copy.destroy! }
    assert_raises(ActiveRecord::ReadOnlyRecord) { copy.tap { |row| row.blocks = [] }.save! }
  end

  test "the writes guard sees a bare Version inside module Publishing and a relation of a record's copies" do
    assert_match(/\bVersion\b[^\n]*#{WRITES}/, "Version.where(id: 1).delete_all")
    assert_match(/\bpublished_versions\b[^\n]*#{WRITES}/, "page.published_versions.update_all(live_at: nil)")
    assert_match(/\bVersion\b[^\n]*#{WRITES}/, "Publishing::Version.of(page).destroy_all")
  end

  # Files that write pages, posts or blocks. A write around the callbacks in
  # one of them runs neither `Publishable`'s `before_save` nor its
  # `after_touch`, so nothing marks the record as changed for it.
  CONTENT_WRITERS = %w[
    app/services/content_blocks/**/*.rb app/services/tags/**/*.rb app/services/pages/**/*.rb app/services/posts/**/*.rb
    app/services/translations/**/*.rb app/services/trash/**/*.rb app/services/locales/**/*.rb app/services/publishing/**/*.rb
    app/models/page/**/*.rb app/models/rich_text/action_text_import.rb app/models/access_control/seeds.rb
  ].freeze
  MARKS = /\.touch\b|\bPublishing\.note_change\(/
  NO_CHANGE = /changes:\s*none\s*\((?<reason>[^)]{10,})\)/

  test "a write around the callbacks in a file that writes pages, posts or blocks marks the record as changed, or says on its line why it is no change to content" do
    offences = CONTENT_WRITERS.flat_map { |pattern| Rails.root.glob(pattern) }.uniq.sort.flat_map do |file|
      path = file.to_s.delete_prefix("#{Rails.root}/")
      source = file.read
      VersionBumpTest.writes(path, source).reject { |write| source.match?(MARKS) || write.comment.match?(NO_CHANGE) }.map { |write| "#{path}:#{write.line}: #{write.code}" }
    end

    assert_empty offences, <<~MESSAGE
      These lines write around the model callbacks in a file that writes content. If the write
      changes what a copy holds of a published record (drafts spec §4.2), touch the page or post
      or call `Publishing.note_change(…)` in the file. If it does not, end the line with
      `# changes: none (why not)`. A file that marks at all is taken at its word for all its writes.
    MESSAGE
  end

  test "Admin::Publishing is not defined" do
    assert_not Admin.const_defined?(:Publishing, false)
  end
end
