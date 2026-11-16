require "test_helper"

# `Admin::Ui::MediaPickerComponent` (media library design spec §6, Task 8; round 3 Task 9):
# one modal that is the Media grid in miniature -- search and segments in its own
# frame, selectable tiles, a header Upload and a footer "N selected · Cancel ·
# Use image" -- wired to the picker and select controllers on one element.
class Admin::Ui::MediaPickerComponentTest < ViewComponent::TestCase
  test "renders one dialog wired to the picker and select controllers, with its own grid frame" do
    as(users(:one)) { render_inline Admin::Ui::MediaPickerComponent.new }

    dialog = page.find("dialog#media-picker", visible: :all)
    assert_equal "admin--media--picker admin--media--select admin--media--live", dialog["data-controller"]
    assert_includes dialog["data-action"], "admin--media--picker:reset->admin--media--live#open"
    assert_equal "/#{ContentSpiel::ADMIN_PATH}/media/folders", dialog["data-admin--media--live-url-value"]
    assert_includes dialog["data-action"], "media-picker:open@window->admin--media--picker#open"
    assert_includes dialog["data-action"], "close->admin--media--picker#closed"
    assert_includes dialog["data-action"], "cancel->admin--media--picker#cancel"
    assert_includes dialog["data-action"], "turbo:frame-load->admin--media--select#reapply"
    assert_includes dialog["data-action"], "admin--media--select:chosen->admin--media--picker#chosen"
    assert_equal "/#{ContentSpiel::ADMIN_PATH}/media?picker=1", dialog["data-admin--media--picker-grid-url-value"]
    assert_equal "/#{ContentSpiel::ADMIN_PATH}/media_assets", dialog["data-admin--media--picker-upload-url-value"]
    assert_selector "turbo-frame#media-picker-grid[data-admin--media--picker-target=frame]", visible: :all
    # The old Library/Upload tabs are gone.
    assert_no_selector "[role=tab]", visible: :all
  end

  test "the header has Upload and a close ×, the footer the selection, Cancel and a disabled Use image" do
    as(users(:one)) { render_inline Admin::Ui::MediaPickerComponent.new }

    assert_selector "h2", text: "Choose an image", visible: :all
    assert_selector "button[data-action='admin--media--picker#browse']", text: "Upload", visible: :all
    assert_selector "button[aria-label=Close][data-action='admin--media--picker#dismiss']", text: "×", visible: :all
    assert_selector "[role=status][aria-live=polite][data-admin--media--select-target=status]", text: "No image selected", visible: :all
    assert_selector "button[data-action='admin--media--picker#dismiss']", text: "Cancel", visible: :all
    assert_selector "button[disabled][data-admin--media--select-target=use]", text: "Use image", visible: :all
  end

  test "the file input is labelled, multiple, typed, and never part of a form's own data" do
    as(users(:one)) { render_inline Admin::Ui::MediaPickerComponent.new }

    file = page.find("input[type=file]", visible: :all)
    assert_nil file["name"]
    assert file[:multiple]
    assert_equal Media::Asset::ALLOWED_CONTENT_TYPES.join(","), file["accept"]
    assert_selector "label[for='#{file["id"]}']", text: "Image file", visible: :all
    assert_selector "[role=status][data-admin--media--picker-target=status]", visible: :all
  end

  test "keeps the editing language on the grid's URL" do
    as(users(:one)) { render_inline Admin::Ui::MediaPickerComponent.new(url_options: { locale: "de" }) }

    assert_equal "/#{ContentSpiel::ADMIN_PATH}/media?locale=de&picker=1",
      page.find("dialog", visible: :all)["data-admin--media--picker-grid-url-value"]
  end

  # Browsing and choosing need `media.upload` (design spec §5.1); without
  # it no field offers Choose, so there's nothing to render.
  test "renders nothing without media.upload" do
    as(users(:reader)) { render_inline Admin::Ui::MediaPickerComponent.new }

    assert_no_selector "dialog", visible: :all
  end

  # Its height changes while it is open, so it hangs from a fixed top edge
  # (the fix merged as PR #38); a rule that quietly goes would bring back the
  # jump, so it is pinned next to the New page and New post dialogs' own.
  test "the dialog carries the fixed-top-edge class, and the stylesheet still defines it" do
    as(users(:one)) { render_inline Admin::Ui::MediaPickerComponent.new }

    assert_selector "dialog.admin-media-picker", visible: :all
    assert_match(/\.admin-media-picker \{ margin-top: 7\.5vh; \}/, Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read)
  end

  # The card's D12: Upload's target, said before the button and naming it.
  # The script rewrites the words for each place the frame shows; drawn,
  # before any place is, they say "no folder", where an upload from All media
  # lands.
  test "Upload says where its files go and is described by it" do
    as(users(:one)) { render_inline Admin::Ui::MediaPickerComponent.new }

    into = page.find("p#media-picker-upload-into.text-small.text-meta[data-admin--media--picker-target=uploadInto]", text: "Uploads go into no folder", visible: :all)
    upload = page.find("button[data-action='admin--media--picker#browse']", visible: :all)
    assert_equal into[:id], upload["aria-describedby"]
    # The sentence stands before the button, in the header.
    assert_selector "p#media-picker-upload-into + button[aria-describedby='media-picker-upload-into']", visible: :all

    words = JSON.parse(page.find("dialog", visible: :all)["data-messages"])
    assert_equal "Uploads go into %{name}", words.fetch("components.ui.media_picker.upload_into")
    assert_equal "Uploads go into no folder", words.fetch("components.ui.media_picker.upload_nowhere")
  end

  # The card StudioGallery, D4: a multiple opening's words are the dialog's,
  # for `admin--media--picker` and `admin--media--select` to say, and the two
  # marks a tile takes (its order, "In the gallery") are drawn once, as
  # templates the select script clones.
  test "a multiple opening's words and a tile's two marks are on the dialog" do
    as(users(:one)) { render_inline Admin::Ui::MediaPickerComponent.new }

    words = JSON.parse(page.find("dialog", visible: :all)["data-messages"])
    assert_equal "Choose an image", words.fetch("components.ui.media_picker.title")
    assert_equal "Add images", words.fetch("components.ui.media_picker.title_multiple")
    assert_equal "Use image", words.fetch("components.ui.media_picker.use")
    assert_equal({ "zero" => "Add images", "one" => "Add 1 image", "other" => "Add %{count} images" }, words.fetch("components.ui.media_picker.add_count"))
    assert_equal "%{count} selected · the gallery takes %{left} more", words.fetch("components.ui.media_picker.takes")
    assert_equal "The gallery takes no more: %{max} images.", words.fetch("components.ui.media_picker.full")
    assert_equal "No images selected · the gallery takes %{left} more", words.fetch("components.ui.media_picker.takes_none")
    assert_equal ", chosen %{ordinal}", words.fetch("components.ui.media_picker.chosen")
    assert_not words.key?("components.ui.media_picker.chosen_order"), "a chosen tile keeps its whole name: the order is appended"
    assert_equal({ "one" => "%{count}st", "two" => "%{count}nd", "few" => "%{count}rd", "other" => "%{count}th" }, words.fetch("components.ui.media_picker.ordinal"))

    assert_selector "h2[data-admin--media--picker-target=title]", text: "Choose an image", visible: :all
    marks = rendered_content.scan(%r{<template data-admin--media--select-target="(\w+)">(.*?)</template>}m).to_h
    assert_match(/class="admin-media-pick-order" aria-hidden="true" data-media-pick-order/, marks.fetch("orderMark"))
    assert_match(/class="admin-media-pick-in-gallery" aria-hidden="true" data-media-pick-in-gallery>.*In the gallery/m, marks.fetch("inGalleryMark"))

    # A tile at the limit is described by the footer's status line.
    assert_selector "p#media-picker-choice[role=status][data-admin--media--select-target=status]", visible: :all
    # The close drops the choice and the scripts' marks.
    assert_includes page.find("dialog", visible: :all)["data-action"], "close->admin--media--select#reset"
    assert_match(/chosen tile's name ends with its place in the order.*In the gallery.*aria-disabled/,
      Admin::Ui::MediaPickerComponent.contract.accessibility)

    limits = Admin::Ui::MediaPickerComponent.contract.limits
    assert_includes limits, "It hands back one image, or several in the order chosen when the opener asks for several; there, in a folder's place, a whole folder's new images, oldest first, after the ones chosen."
    # A folder's button, written by the script for each answer.
    assert_equal({ "one" => "Add the 1 new image in this folder", "other" => "Add all %{count} new images in this folder" }, words.fetch("components.ui.media_picker.add_folder"))
    assert_equal "Add the first %{count} of %{total} new images", words.fetch("components.ui.media_picker.add_folder_first")
    assert_includes page.find("dialog", visible: :all)["data-action"], "admin--media--select:changed->admin--media--picker#choiceChanged"
  end
end
