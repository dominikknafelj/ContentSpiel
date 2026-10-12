require "test_helper"

# `PublicSite::Paths.refresh` is the one entry point that derives addresses
# (Task 4b of the drafts plan): a caller says what it touched, and the
# function knows what depends on that. Before it, eleven places each worked
# out for themselves which posts their own kind of change could have moved,
# and each new situation (a copy, a scheduled copy, a tag by name) needed
# every one of them taught. A caller that reaches past `refresh` for one of
# the functions inside it is the first step back there, and nothing fails
# when it is taken: the addresses are right for the case its author thought
# of.
class PublicPathsEntryTest < ActiveSupport::TestCase
  # What may be called from outside `app/models/public_site/paths.rb`.
  WRITES = {
    "refresh" => "the entry point",
    "rebuild!" => "the repair: empties the table and refreshes everything"
  }.freeze
  READS = {
    "current_path" => "a stored address",
    "compute" => "the address a record would have, for the slug's validation",
    "canonical_page" => "the page a post's address runs through",
    "canonical_pages" => "the same for several posts",
    "post_path" => "a post's path under a given page, for the preview's link"
  }.freeze

  PATHS = "app/models/public_site/paths.rb".freeze

  # A root is a directory, searched, or a single file.
  def code(*roots)
    roots.flat_map { |root| Rails.root.join(root).file? ? [ Rails.root.join(root) ] : Rails.root.glob("#{root}/**/*.{rb,rake,erb}") }.to_h do |path|
      [ path.to_s.delete_prefix("#{Rails.root}/"), path.read.lines.reject { |line| line.strip.start_with?("#") }.join ]
    end
  end

  test "outside its own file PublicSite::Paths is asked to refresh, to rebuild, or to read: nothing calls a function inside the entry point" do
    called = code("app", "lib", "db/seeds.rb").except(PATHS).flat_map do |path, source|
      source.scan(/\bPaths\.([a-z_]+[!?]?)/).flatten.map { |name| [ name, path ] }
    end

    reaching_in = called.reject { |name, _| WRITES.key?(name) || READS.key?(name) }
    assert_empty reaching_in, "these call into PublicSite::Paths past its entry point: say what was touched with `refresh(pages:, posts:)` instead"
    assert_includes called, [ "rebuild!", "db/seeds.rb" ], "the seed file is read by this guard"
    (WRITES.keys + READS.keys - called.map(&:first)).each { |name| flunk "nothing outside #{PATHS} calls Paths.#{name} any more: remove it from this test's lists" }
  end

  test "the guard sees a bare Paths inside module PublicSite and the functions it is there to refuse" do
    assert_equal [ [ "sync_subtree" ], [ "write_all" ] ], "Paths.sync_subtree(page)\nPublicSite::Paths.write_all(desired)".scan(/\bPaths\.([a-z_]+[!?]?)/)
  end

  PUBLIC_PATH_WRITES = /\bPublicPath\b[^\n]*\.(?:update_all|update_columns|update!?|upsert_all|insert_all!?|create!?|delete_all|delete_by|destroy_all|destroy_by)\b/
  # path => why it writes a row of `public_paths` itself.
  ROW_WRITERS = {
    PATHS => "the derivation",
    "app/services/locales/disable.rb" => "a language switched off loses its rows; nothing is derived"
  }.freeze

  test "a row of public_paths is written only by PublicSite::Paths (and deleted with its record, or with its language)" do
    writers = code("app", "lib").select { |_path, source| source.match?(PUBLIC_PATH_WRITES) }.keys

    assert_equal ROW_WRITERS.keys.sort, writers.sort
  end
end
