require "test_helper"

# The content side does not know notes (notes spec §3.7, plan Global
# Constraints). A page, a post, a block and a library image are written and
# read without a thought for the threads on them: no `touch`, no count column,
# no association. Notes point at content, never the other way, so the feature
# can be changed or pushed live without re-reading the content services.
#
# The one exception is removal: what deletes a record for good calls
# `Notes::Remove`, because the reference is polymorphic and no foreign key
# could. Those call sites are listed in ALLOWED with their reason, may name
# nothing of `Notes::` but `Remove`, and an entry that matches nothing fails.
class NotesBoundaryTest < ActiveSupport::TestCase
  CONTENT_SOURCES = %w[
    app/models/page.rb app/models/page/**/*.rb app/models/post.rb app/models/post/**/*.rb app/models/content_block.rb
    app/models/media.rb app/models/media/**/*.rb app/models/concerns/**/*.rb
    app/models/block_types.rb app/models/block_types/**/*.rb app/models/content_types.rb app/models/content_types/**/*.rb
    app/services/pages/**/*.rb app/services/posts/**/*.rb app/services/content_blocks/**/*.rb app/services/media/**/*.rb
    app/services/trash/**/*.rb app/services/tags/**/*.rb app/services/translations/**/*.rb app/services/starter_contents/**/*.rb
  ].freeze

  # path => why it may name `Notes::Remove`.
  ALLOWED = {
    "app/services/trash/purge.rb" => "a purge deletes a page, a post or an image for good, and their threads have no foreign key to go by",
    "app/services/content_blocks/destroy.rb" => "a block's delete is permanent, and its threads have no foreign key to go by"
  }.freeze

  # A constant under it (`Notes::Thread`) or a method of the module itself
  # (`Notes.key(page)`, reported as ".key"): either is content code knowing
  # notes. The look-behind keeps out a name that only ends in "Notes"
  # (`ReleaseNotes`) and a `Notes` of another namespace (`Admin::Notes`).
  REFERENCE = /(?<![A-Za-z0-9_:])(?:::)?Notes(?:::(?<constant>[A-Z]\w*)|\.(?<method>[a-z_]\w*))/

  def self.references(source)
    source.lines.each_with_index.flat_map do |line, index|
      next [] if line.lstrip.start_with?("#")

      line.sub(/\s#\s.*$/, "").to_enum(:scan, REFERENCE).map do
        match = Regexp.last_match
        [ index + 1, match[:constant] || ".#{match[:method]}" ]
      end
    end
  end

  def sources = CONTENT_SOURCES.flat_map { |pattern| Dir[Rails.root.join(pattern)] }.uniq.sort

  def relative(path) = Pathname(path).relative_path_from(Rails.root).to_s

  test "the guard is looking at the code" do
    assert_operator sources.size, :>, 30
    assert_includes sources.map { |path| relative(path) }, "app/services/trash/purge.rb"
    assert_includes sources.map { |path| relative(path) }, "app/models/content_block.rb"
  end

  test "pages, posts, blocks, images and their services name nothing of Notes" do
    offences = sources.flat_map do |path|
      self.class.references(File.read(path)).filter_map do |line, name|
        next if ALLOWED.key?(relative(path)) && name == "Remove"

        "#{relative(path)}:#{line}: Notes#{"::" unless name.start_with?(".")}#{name}"
      end
    end

    assert_empty offences, "Content code must not reach into notes. A note points at content; removal on a permanent delete is " \
                           "the one call the other way, and its call site belongs in ALLOWED with its reason."
  end

  test "every allowance still matches something and says why" do
    # Also the assertion this test makes while the list is empty.
    assert_empty ALLOWED.keys - sources.map { |path| relative(path) }, "ALLOWED names a file the guard does not read"

    ALLOWED.each do |path, reason|
      assert_operator reason.length, :>, 40, "#{path} needs its reason written out"
      names = self.class.references(Rails.root.join(path).read).map(&:last)
      assert_includes names, "Remove", "#{path} no longer calls Notes::Remove: delete its ALLOWED entry"
    end
  end

  test "the pattern finds a reference and nothing that only looks like one" do
    found = self.class.references(<<~RUBY).map(&:last)
      # Notes::InAComment
      Notes::Remove.call(page) # and Notes::AfterCode
      ::Notes::Thread.where(subject: page)
      ReleaseNotes::Entry.new
      footnotes = "Notes: none"
      Notes.container_for(block)
      key = ::Notes.key(page)
      ReleaseNotes.latest
      page.notes.count
      Admin::Notes.key(page)
    RUBY

    assert_equal %w[Remove Thread .container_for .key], found
  end
end
