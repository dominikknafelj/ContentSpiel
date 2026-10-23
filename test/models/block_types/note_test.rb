require "test_helper"

# The Note block's declaration (note block spec, "The data"): a kind in the
# settings, a translated title, the body column; the eight names of its
# template, its sixteen tokens and its stylesheet are the theme contract's;
# its icon in CS Studio is `info`, and its kind's on a card and a tile.
class BlockTypes::NoteTest < ActiveSupport::TestCase
  test "a note is a kind, a translated title and a text, nothing required, the kind a segmented choice of four that starts as a Note" do
    note = BlockTypes.fetch(:note)

    assert_equal "Note", note.label
    assert_equal [ %w[kind select], %w[title string] ], note.fields.map { |field| [ field.name, field.type.to_s ] }
    kind, title = note.fields
    assert_equal BlockTypes::Note::KINDS, kind.options[:options]
    assert_equal({ "note" => "Note", "tip" => "Tip", "important" => "Important", "warning" => "Warning" }, BlockTypes::Note::KINDS)
    assert_equal "note", kind.options[:default]
    assert kind.segmented?
    assert_not kind.translated?
    assert title.translated?
    assert_equal 80, title.options[:max]
    assert_equal :kind, title.options[:placeholder_from]
    assert title.help.present?
    assert note.fields.none?(&:required?)
    assert_equal %w[body], note.uses_columns
    assert_empty note.capabilities
    assert_empty note.read_only_actions
    assert_equal %w[block page kind heading titled? word icon body], note.theme_methods
    assert_equal "note.css", note.stylesheet
    assert_equal Blocks::NoteComponent, note.component
    assert_equal({ "note" => "info", "tip" => "lightbulb", "important" => "circle-alert", "warning" => "triangle-alert" }, BlockTypes::Note::ICONS)
    assert_equal "info", note.icon, "the picker's icon is the Note's, the kind a new block starts with"
    assert note.icon_follows_block?
  end

  # Plan rulings 11 and 12: a note's card and tile show its kind's icon, in
  # the icon partial's spelling, from CS Studio's closed list.
  test "CS Studio draws a note's card and tile with its kind's icon, an unknown kind's as a Note's, each on the closed list" do
    note = BlockTypes.fetch(:note)
    { "note" => "info", "tip" => "lightbulb", "important" => "circle_alert", "warning" => "triangle_alert", "gone" => "info" }.each do |kind, icon|
      block = ContentBlock.new(block_type: "note", settings: { "kind" => kind })
      assert_equal icon, BlockTypes::Note.studio_icon(block), kind
      assert_equal icon, note.icon_for(block), kind
    end
    BlockTypes::Note::ICONS.each_value { |name| assert_includes ContentModel::BlockTypeDefinition::ICONS, name.tr("-", "_") }
  end

  test "Note stands after Code in the picker, and the containers stay last" do
    assert_equal %w[rich_text image code note post_list section], BlockTypes.built_in_names
  end

  test "a new block is a Note, and an unknown stored kind reads as one" do
    block = root_page.content_blocks.create!(block_type: :note, position: 0)

    assert_equal({ "kind" => "note" }, block.settings)
    assert_equal "note", BlockTypes::Note.kind_of("gone")
    assert_equal "tip", BlockTypes::Note.kind_of("tip")
    assert_equal "note", BlockTypes::Note.kind_of(nil)
  end

  # Plan ruling 4: the sample's body is Markdown in the default language.
  test "the sample is a Tip with a title in three languages and a text" do
    sample = BlockTypes.fetch(:note).sample

    assert_equal({ "kind" => "tip" }, sample.settings)
    assert_equal %w[en de es], sample.translations.keys
    assert_equal "Before you publish", sample.translations.dig("en", :title)
    assert sample.body.present?
    assert_includes sample.shows, "Before you publish"
  end
end
