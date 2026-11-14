require "test_helper"

# A block type declares its icon, and CS Studio draws it on its family's chip
# in the picker, on a card's head, on a tile, on a section's head and on a
# Notes for you row.
class Admin::Ui::BlockIconComponentTest < ViewComponent::TestCase
  include GalleryAlbum

  test "every icon a block type may name is drawn by the icon partial" do
    ContentModel::BlockTypeDefinition::ICONS.each do |name|
      html = ApplicationController.render(partial: "admin/shared/icon", locals: { name: name.to_sym, size: "size-4" })
      assert_includes html, "<svg", name
      assert_includes html, "size-4", name
    end
  end

  test "every built-in block type declares its icon" do
    assert_equal({ "rich_text" => "pilcrow", "image" => "image", "code" => "code_xml", "diagram" => "diagram", "note" => "info", "post_list" => "posts", "section" => "columns_2", "table" => "table", "card" => "card", "form" => "clipboard_list" },
      BlockTypes.all.to_h { |type| [ type.name, type.icon ] }.slice(*BuiltInBlockTypes.names))
  end

  test "a block type's icon is drawn on its family's chip, and a type with no family on the neutral chip" do
    { picker: [ "size-6", "size-3.5" ], card: [ "size-6", "size-3.5" ], tile: [ "size-5.5", "size-3.5" ], section: [ "size-5.5", "size-3.5" ], row: [ "size-5", "size-3.5" ] }.each do |place, (chip, icon)|
      render_inline Admin::Ui::BlockIconComponent.new(definition: BlockTypes.fetch(:code), place: place)
      assert_selector "span[data-block-icon=code_xml][aria-hidden=true][class~='#{chip}'][class~='bg-ic-code-bg'][class~='text-ic-code'] svg[class~='#{icon}']"
    end
    render_inline Admin::Ui::BlockIconComponent.new(definition: ContentModel::BlockTypeDefinition.new("plain").tap { |type| type.icon "pilcrow" }, place: :card)
    assert_selector "span[data-block-icon=pilcrow][class~='bg-sunken'][class~='text-dim']"
    assert_no_selector "span[class*='bg-ic-']"
  end

  test "an unknown place raises" do
    assert_raises(ArgumentError) { Admin::Ui::BlockIconComponent.new(definition: BlockTypes.fetch(:code), place: :header) }
  end

  test "a type that names no icon draws nothing" do
    with_gallery_album do
      render_inline Admin::Ui::BlockIconComponent.new(definition: BlockTypes.all.find { |type| type.name == "gallery/album" }, place: :picker)
      assert_no_selector "span"
    end
  end

  # A type whose icon follows its block.
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

      render_inline Admin::Ui::BlockIconComponent.new(definition: flag, place: :card, block: block)
      assert_selector "span#block-#{block.id}-icon-card[data-block-icon=triangle_alert][aria-hidden=true][class~='size-6'] svg[class~='size-3.5']"

      render_inline Admin::Ui::BlockIconComponent.new(definition: flag, place: :tile, block: block)
      assert_selector "span#block-#{block.id}-icon-tile[data-block-icon=triangle_alert][class~='size-5.5'] svg[class~='size-3.5']"

      render_inline Admin::Ui::BlockIconComponent.new(definition: flag, place: :picker)
      assert_selector "span[data-block-icon=info]:not([id])"
      assert_equal "block-#{block.id}-icon-tile", Admin::Ui::BlockIconComponent.dom_id(block, :tile)
    end
  end

  test "a row draws no id even for an icon that follows its block, since one block can stand on it twice" do
    with_flag_type do |flag|
      block = root_page.content_blocks.create!(block_type: "test_flag", position: 0, settings: { "tone" => "loud" })
      render_inline Admin::Ui::BlockIconComponent.new(definition: flag, place: :row, block: block)

      assert_selector "span[data-block-icon=triangle_alert]:not([id])"
    end
  end

  test "a type whose icon does not follow its block draws it with no id, also when it is handed a block" do
    block = root_page.content_blocks.create!(block_type: "code", position: 0)
    render_inline Admin::Ui::BlockIconComponent.new(definition: BlockTypes.fetch(:code), place: :card, block: block)

    assert_selector "span[data-block-icon=code_xml]:not([id])", count: 1
  end

  test "a built-in's icon for a block that is not on the list raises, naming the list" do
    with_flag_type do |flag|
      flag.icon "info", for_block: ->(_block) { "<svg onload=x>" }
      block = root_page.content_blocks.create!(block_type: "test_flag", position: 0)

      error = assert_raises(ArgumentError) { render_inline Admin::Ui::BlockIconComponent.new(definition: flag, place: :card, block: block) }
      assert_includes error.message, "info, lightbulb, circle_alert, triangle_alert"
    end
  end
end
