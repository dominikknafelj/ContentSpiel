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
#
# The core SCREENS keep clear of notes the same way, one layer up: the editors'
# header and the media library's panel draw whatever is registered at their
# slots (`Admin::Slots`, `config/initializers/admin_slots.rb`) and do not say
# the word, comments included. The places that still name notes directly are
# listed with the trigger that would make each a slot.
#
# What the screen guard covers is COMPONENTS. The views that assemble a screen
# (`app/views/admin/pages/show.html.erb`, `posts/show.html.erb`) may name the
# features on it, and do: they hand the drawer's counts through the header's
# `slot_context:`. The shared components may not.
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

  # Core components that host a slot: no word "notes" in code or comment.
  SLOT_HOSTS = %w[
    app/components/admin/editor_screen/header_component.rb
    app/components/admin/editor_screen/header_component.html.erb
    app/components/admin/editor_screen/post_form_component.rb
    app/components/admin/editor_screen/post_form_component.html.erb
    app/components/admin/media_library/panel_component.rb
    app/components/admin/media_library/panel_component.html.erb
    app/components/admin/pages_screen/tree_component.rb
    app/components/admin/pages_screen/tree_component.html.erb
    app/components/admin/pages_screen/tree_node_component.rb
    app/components/admin/pages_screen/tree_node_component.html.erb
    app/components/admin/posts_screen/table_component.rb
  ].freeze

  # "notes" at the start of a word or after an underscore, digit, colon or hyphen: `Admin::NotesScreen::X`,
  # `open_notes`, `@open_notes`, `notes_path`, `notes_type`, `admin--notes--drawer`, a comment's "Notes". Not
  # inside a word ("footnotes", "denotes").
  NOTES_WORD = /(?<![a-z])notes/i

  # Notes-only places that stay direct: files outside `notes_screen` that name
  # notes on purpose, each with the trigger that would make it a slot. A slot
  # is a seam for a SECOND feature; none of these has asked for one.
  NAMED_EXCEPTIONS = {
    %w[app/components/admin/editor_screen/block_card_component.rb app/components/admin/editor_screen/block_card_component.html.erb] =>
      "the block card's Add note item and marker: a slot when a second feature puts something on a block",
    %w[app/components/admin/editor_screen/block_tile_component.rb app/components/admin/editor_screen/block_tile_component.html.erb
       app/components/admin/editor_screen/section_card_component.html.erb] =>
      "the section tile's Add note item and marker: a slot with the block card's, when a second feature puts something on a block",
    %w[app/components/admin/dashboard_screen/card_component.rb] =>
      "the dashboard's notes cards: a slot when the dashboard offers cards to a second feature (presence on the dashboard is out of scope)",
    %w[app/components/admin/shell/sidebar_component.rb app/components/admin/shell/sidebar_component.html.erb] =>
      "the sidebar's unread badge: a slot when a second feature wants a badge on a sidebar entry",
    %w[app/components/admin/mind_graph_screen/legend_component.rb app/components/admin/mind_graph_screen/legend_component.html.erb] =>
      "the mind graph's open-notes legend and nodes: a slot when a second feature draws on the graph (presence there is out of scope)",
    %w[app/components/admin/media_library/tile_component.rb app/components/admin/media_library/tile_component.html.erb
       app/components/admin/media_library/grid_component.rb] =>
      "the media tile's count chip and the grid's one read of the marks: a slot when a second feature marks a tile (presence in the grid is out of scope)",
    %w[app/components/admin/posts_screen/table_component.html.erb] =>
      "the posts table's Notes column HEADER (its icon and its name): the column is notes' alone, and a header mechanism for slots (a second slot) is more than two features justify; the CELL is the posts.row.markers slot, and the column becomes a slot's when a second feature wants a column of its own"
  }.freeze

  test "the editors' header and the media panel do not name notes: they draw their slots" do
    assert_equal 11, SLOT_HOSTS.size
    offences = SLOT_HOSTS.flat_map do |path|
      Rails.root.join(path).read.lines.each_with_index.filter_map { |line, index| "#{path}:#{index + 1}: #{line.strip}" if line.match?(NOTES_WORD) }
    end

    assert_empty offences, "A core screen draws what is registered at its slot (config/initializers/admin_slots.rb) and does not name the feature, " \
                           "not even in a comment."
  end

  test "every place that still names notes directly is a named exception with its trigger, and still names them" do
    NAMED_EXCEPTIONS.each do |paths, reason|
      assert_operator reason.length, :>, 40, "#{paths.first} needs its reason and trigger written out"
      assert_includes reason, "slot", "#{paths.first}: the reason names the slot that would replace it"
      paths.each { |path| assert Rails.root.join(path).file?, "#{path} no longer exists: delete its exception" }
      assert paths.any? { |path| Rails.root.join(path).read.match?(NOTES_WORD) }, "#{paths.first} no longer names notes: delete its exception"
    end
    assert_empty NAMED_EXCEPTIONS.keys.flatten & SLOT_HOSTS
  end

  test "the slot pattern finds notes in every spelling, and not a word that only contains it" do
    [ "# the Notes button", "open_notes(x)", "Admin::NotesScreen::HeaderButtonComponent", "open_notes: 3", "@open_notes", "notes_path",
      "data: { notes_type: 1 }", "admin--notes--drawer", "data-notes-id" ].each { |text| assert_match NOTES_WORD, text, text }
    [ "footnotes = 1", "denotes", "ReleaseNotes.latest" ].each { |text| assert_no_match NOTES_WORD, text, text }
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
