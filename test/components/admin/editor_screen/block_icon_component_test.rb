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
    assert_equal({ "rich_text" => "pilcrow", "image" => "image", "code" => "code_xml", "post_list" => "posts", "section" => "columns_2" },
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
end
