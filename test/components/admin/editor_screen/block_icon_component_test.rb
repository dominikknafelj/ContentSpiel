require "test_helper"

# Contrast and buttons spec (C2, Rulings 6 and 7): a block type declares
# its icon, and CS Studio draws it in the picker (16px dim), on a card's
# head (14px dim) and on a section's tile (12px meta).
class Admin::EditorScreen::BlockIconComponentTest < ViewComponent::TestCase
  include GalleryAlbum

  test "every icon a block type may name is drawn by the icon partial" do
    ContentModel::BlockTypeDefinition::ICONS.each do |name|
      html = ApplicationController.render(partial: "admin/shared/icon", locals: { name: name.to_sym, size: "size-4" })
      assert_includes html, "<svg", name
      assert_includes html, "size-4", name
    end
  end

  test "every built-in block type declares its icon" do
    assert_equal({ "rich_text" => "pilcrow", "image" => "image", "code" => "code_xml", "note" => "info", "post_list" => "posts", "section" => "columns_2" },
      BlockTypes.all.to_h { |type| [ type.name, type.icon ] }.slice(*BuiltInBlockTypes.names))
  end

  test "each place has its size and colour, and the icon is decoration" do
    { picker: %w[size-4 text-dim], card: %w[size-3.5 text-dim], tile: %w[size-3 text-meta] }.each do |place, (size, colour)|
      render_inline Admin::EditorScreen::BlockIconComponent.new(definition: BlockTypes.fetch(:code), place: place)
      assert_selector "span[data-block-icon=code_xml][aria-hidden=true][class~='#{colour}'] svg[class~='#{size}']"
    end
  end

  test "a type that names no icon draws nothing" do
    with_gallery_album do
      render_inline Admin::EditorScreen::BlockIconComponent.new(definition: BlockTypes.all.find { |type| type.name == "gallery/album" }, place: :picker)
      assert_no_selector "span"
    end
  end

  # Note block plan, ruling 12: a type whose icon follows its block.
  def with_flag_type
    BlockTypes.register(:test_flag) do |t|
      TestTypes.declare(t)
      t.label "Flag"
      t.field :tone, :select, options: %w[calm loud], default: "calm"
      t.icon "info", for_block: ->(block) { block.settings["tone"] == "loud" ? "triangle_alert" : "info" }
    end
    yield BlockTypes.fetch(:test_flag)
  ensure
    Rails.application.reloader.prepare!
  end

  test "a type whose icon follows its block draws the block's own on its card and its tile, under an id a save's answer replaces, and the type's in the picker" do
    with_flag_type do |flag|
      block = root_page.content_blocks.create!(block_type: "test_flag", position: 0, settings: { "tone" => "loud" })

      render_inline Admin::EditorScreen::BlockIconComponent.new(definition: flag, place: :card, block: block)
      assert_selector "span#block-#{block.id}-icon-card[data-block-icon=triangle_alert][aria-hidden=true][class~='text-dim'] svg[class~='size-3.5']"

      render_inline Admin::EditorScreen::BlockIconComponent.new(definition: flag, place: :tile, block: block)
      assert_selector "span#block-#{block.id}-icon-tile[data-block-icon=triangle_alert][class~='text-meta'] svg[class~='size-3']"

      render_inline Admin::EditorScreen::BlockIconComponent.new(definition: flag, place: :picker)
      assert_selector "span[data-block-icon=info]:not([id])"
      assert_equal "block-#{block.id}-icon-tile", Admin::EditorScreen::BlockIconComponent.dom_id(block, :tile)
    end
  end

  test "a type whose icon does not follow its block draws it with no id, also when it is handed a block" do
    block = root_page.content_blocks.create!(block_type: "code", position: 0)
    render_inline Admin::EditorScreen::BlockIconComponent.new(definition: BlockTypes.fetch(:code), place: :card, block: block)

    assert_selector "span[data-block-icon=code_xml]:not([id])", count: 1
  end

  test "a built-in's icon for a block that is not on the list raises, naming the list" do
    with_flag_type do |flag|
      flag.icon "info", for_block: ->(_block) { "<svg onload=x>" }
      block = root_page.content_blocks.create!(block_type: "test_flag", position: 0)

      error = assert_raises(ArgumentError) { render_inline Admin::EditorScreen::BlockIconComponent.new(definition: flag, place: :card, block: block) }
      assert_includes error.message, "info, lightbulb, circle_alert, triangle_alert"
    end
  end
end
