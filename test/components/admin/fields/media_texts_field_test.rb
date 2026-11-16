require "test_helper"

# `Admin::Fields::MediaTextsField`: a Gallery block's image rows (spec
# §10.3, StudioGallery D3). One row per image of the list it describes
# (`of:`), read from the values the card draws (`values:`), with the
# language's caption and alt and the library's texts as placeholders.
class Admin::Fields::MediaTextsFieldTest < ViewComponent::TestCase
  include ContentHelper

  def asset(title, alt: nil, caption: nil)
    create_media_asset.tap { |image| image.update!(title: title, alt: alt, caption: caption) }
  end

  def gallery(ids, texts: {})
    page = create_page(title: "Gallery #{SecureRandom.hex(4)}")
    page.content_blocks.create!(block_type: "gallery", position: 0, settings: { "images" => ids }, translated_settings: texts)
  end

  def texts_field(block) = block.definition.fields.find { |field| field.name == "texts" }

  def render_rows(block, locale: "en", user: users(:one))
    values = block.settings_object(locale: locale)
    original = locale == ::Locales.default ? nil : block.settings_object(locale: ::Locales.default).texts
    as(user) do
      render_inline Admin::Fields::MediaTextsField.new(field: texts_field(block), form_name: "block[settings]", value: values.texts, values: values,
        original: original, locale: locale, id_prefix: "block-#{block.id}")
    end
  end

  def rows = page.all("[data-admin--editor--gallery-target=row]")

  test "one row per image of the list in its order, with the language's caption and alt and the library alt as placeholder" do
    harbour = asset("harbour-at-dusk.jpg", alt: "Fishing boats at dusk")
    forest = asset("forest-path.jpg", alt: "A path through a forest")
    block = gallery([ forest.id, harbour.id ], texts: { "en" => { "texts" => { harbour.id.to_s => { "caption" => "The harbour at dusk", "alt" => "Boats" } } } })

    render_rows(block)

    assert_equal [ forest.id.to_s, harbour.id.to_s ], rows.map { |row| row["data-asset-id"] }
    assert_selector "h3", text: "Images"
    assert_text "2 of 60"
    assert_selector "textarea[name='block[settings][texts][#{harbour.id}][caption]']", text: "The harbour at dusk"
    assert_selector "input[name='block[settings][texts][#{harbour.id}][alt]'][value='Boats'][placeholder='Fishing boats at dusk']"
    assert_selector "input[name='block[settings][texts][#{forest.id}][alt]'][placeholder='A path through a forest']:not([value])"
    assert_selector "button[aria-label='Move forest-path.jpg']"
    assert_selector "button.admin-gallery-row__remove[aria-label='Remove harbour-at-dusk.jpg'][data-controller~='admin--ui--tooltip']", text: "Remove harbour-at-dusk.jpg"
    assert_equal Admin::Ui::ButtonComponent.classes(:tertiary, size: :small).split, page.find("button[aria-label='Remove harbour-at-dusk.jpg']")[:class].split - %w[admin-gallery-row__remove relative],
      "Remove is the shared small tertiary icon button"
    assert_selector "img.rounded-field[src='#{forest.thumbnail_url}']"
    assert_selector "p.sr-only[role=status][data-admin--editor--gallery-target=status]", visible: :all
    assert_selector "img[src='#{forest.thumbnail_url}']"
    assert_selector "[data-controller='admin--editor--gallery'][data-admin--editor--gallery-list-value='block-#{block.id}-images']"
    assert_selector "[data-admin--editor--gallery-max-value='60']"
  end

  test "an image with no alt anywhere says so in the placeholder and marks the well" do
    bare = asset("nets.jpg")
    block = gallery([ bare.id ])

    render_rows(block)

    assert_selector "input[name='block[settings][texts][#{bare.id}][alt]'][placeholder='No alt text in the library'].admin-gallery-row__alt--warn"
  end

  test "a blank caption whose library image has one offers Use library caption" do
    captioned = asset("pier.jpg", caption: "The north pier")
    written = asset("boats.jpg", caption: "Boats in the library")
    plain = asset("rope.jpg")
    block = gallery([ captioned.id, written.id, plain.id ], texts: { "en" => { "texts" => { written.id.to_s => { "caption" => "Our boats" } } } })

    render_rows(block)

    offers = page.all("button", text: "Use library caption", visible: :all)
    assert_equal [ "The north pier", "Boats in the library" ], offers.map { |button| button["data-caption"] },
      "a row whose library image has a caption carries the button, which the script shows while the caption is blank"
    assert_equal [ "The north pier" ], page.all("button", text: "Use library caption").map { |button| button["data-caption"] }
  end

  test "a translation tab's rows show the default language's texts as reference and no list control" do
    harbour = asset("harbour-at-dusk.jpg")
    Mobility.with_locale(:de) { harbour.update!(alt: "Boote im Hafen") }
    block = gallery([ harbour.id ], texts: { "en" => { "texts" => { harbour.id.to_s => { "caption" => "The harbour at dusk, from the north pier", "alt" => "Boats" } } },
                                             "de" => { "texts" => { harbour.id.to_s => { "caption" => "Der Hafen" } } } })

    render_rows(block, locale: "de")

    assert_text "1 image · the list is changed in English"
    assert_selector "p", text: "English: The harbour at dusk, from the north pier"
    assert_selector "p", text: "English: Boats"
    assert_selector "textarea[name='block[settings][texts][#{harbour.id}][caption]']", text: "Der Hafen"
    assert_selector "input[name='block[settings][texts][#{harbour.id}][alt]'][placeholder='Boote im Hafen']"
    assert_no_selector "[data-admin--editor--gallery-target=handle], [data-admin--editor--gallery-target=add], [data-admin--editor--gallery-target=addFolder]"
    assert_no_selector "button[aria-label^='Remove']"
  end

  test "a row for an image that is gone says so and can be removed" do
    kept = asset("kept.jpg")
    trashed = asset("trashed.jpg").tap { |image| image.update_columns(trashed_at: Time.current) }
    gone = Media::Asset.maximum(:id).to_i + 1000
    block = gallery([ kept.id, trashed.id, gone ], texts: { "en" => { "texts" => { gone.to_s => { "caption" => "Kept for a restore" } } } })

    render_rows(block)

    assert_equal 3, rows.size
    missing = rows.select { |row| row.has_text?("This image is no longer in the library") }
    assert_equal [ trashed.id.to_s, gone.to_s ], missing.map { |row| row["data-asset-id"] }
    assert_text "It isn't shown on the site. Remove it, or leave it until someone restores the image."
    missing.each do |row|
      assert row.has_css?("button[aria-label^='Remove']"), "a missing image's row can be removed"
      assert row.has_no_css?("textarea, input[type=text]"), "a missing image has no fields"
    end
    assert_selector "input[type=hidden][name='block[settings][texts][#{gone}][caption]'][value='Kept for a restore']", visible: :all
  end

  test "the empty card says so with both buttons, and the limit turns them off and says why" do
    Media::Folder.create!(name: "Client A")
    render_rows(gallery([]))

    assert_text "No images yet. Add them from the library, in the order the site shows them."
    assert_selector "button:not([aria-disabled])", text: "Add images"
    assert_selector "button:not([aria-disabled])", text: "Add a folder"
    assert_selector "[data-admin--editor--gallery-target=limit][hidden]", visible: :all

    images = Array.new(60) { create_media_asset }
    render_rows(gallery(images.map(&:id)))

    assert_selector "button[aria-disabled=true]", text: "Add images"
    assert_selector "button[aria-disabled=true]", text: "Add a folder"
    assert_selector "[data-admin--editor--gallery-target=limit]", text: "A gallery holds at most 60 images. Remove one to add another."
    assert_text "60 of 60 images"
  end

  test "Add a folder is drawn only when the library has a folder" do
    render_rows(gallery([]))
    assert_selector "button", text: "Add images"
    assert_no_selector "button", text: "Add a folder"

    Media::Folder.create!(name: "Client A")
    render_rows(gallery([]))
    assert_selector "button", text: "Add a folder"
  end

  # Without media.upload the picker is not on the page: no add button, a
  # line that says why, the count as usual, and the rows' Remove and handle
  # (a reorder and a removal need no upload right).
  test "without media.upload the card says adding needs the right to upload, and keeps Remove and the count" do
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    Media::Folder.create!(name: "Client A")
    image = asset("pier.jpg")

    render_rows(gallery([ image.id ]), user: users(:editor_branch))
    assert_text "Adding images needs the right to upload to the library."
    assert_text "1 of 60 images"
    assert_no_selector "[data-admin--editor--gallery-target=add], [data-admin--editor--gallery-target=addFolder]"
    assert_selector "button[aria-label='Remove pier.jpg']"
    assert_selector "button[aria-label='Move pier.jpg']"

    render_rows(gallery([]), user: users(:editor_branch))
    assert_text "No images yet. Add them from the library, in the order the site shows them."
    assert_text "Adding images needs the right to upload to the library."
    assert_no_selector "button", text: "Add images"
  end
end
