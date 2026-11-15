require "test_helper"

# A GIF wherever CS Studio shows one: a note's tile and the image viewer's
# stage. The picture, the still it is painted on under reduced motion and the
# Play control are one part on `admin--ui--gif`; what a click on the picture
# does is the caller's.
class Admin::Ui::GifComponentTest < ViewComponent::TestCase
  test "it draws the picture, a hidden canvas and Play under the gif controller" do
    render_inline(Admin::Ui::GifComponent.new(src: "/files/1", name: "loop.gif"))

    root = page.find("[data-controller='admin--ui--gif']")
    assert_equal "/files/1", root["data-admin--ui--gif-src-value"]
    assert_equal "true", root["data-admin--ui--gif-gif-value"]
    assert_equal %w[components.ui.gif.pause components.ui.gif.play], (JSON.parse(root["data-messages"]).keys - [ "@locale" ]).sort
    assert_selector "[data-controller='admin--ui--gif'] img[alt='loop.gif'][src='/files/1'][data-admin--ui--gif-target='moving'][data-action='load->admin--ui--gif#paint']"
    assert_selector "[data-controller='admin--ui--gif'] canvas[aria-hidden=true][data-admin--ui--gif-target='still']", visible: :all
    button = page.find("[data-controller='admin--ui--gif'] button[type=button][data-admin--ui--gif-target='button'][data-action='admin--ui--gif#toggle']", text: "Play")
    assert_includes button[:class].split, "admin-gif-button"
    assert_includes button[:class].split, "motion-safe:hidden"
    assert_selector "button [data-admin--ui--gif-target='label']", exact_text: "Play"
    assert_selector "button [data-admin--ui--gif-target='icon'] [data-gif-icon='play']:not([hidden]) svg"
    assert_selector "button [data-admin--ui--gif-target='icon'] [data-gif-icon='pause'][hidden] svg", visible: :all
  end

  test "on a tile the picture is a link to it in a new tab carrying the caller's link attributes, on the stage a span" do
    render_inline(Admin::Ui::GifComponent.new(src: "/files/1", name: "loop.gif", link: { title: "Open loop.gif in a new tab", data: { viewer_item: true } },
      class: "my-tile", data: { note_gif: true }))

    root = page.find("div[data-controller='admin--ui--gif'][data-note-gif]")
    assert_includes root[:class].split, "my-tile"
    assert_selector "a[href='/files/1'][target=_blank][rel=noopener][data-turbo=false][data-viewer-item][title='Open loop.gif in a new tab'] img[alt='loop.gif']"
    assert_selector "a canvas", visible: :all

    render_inline(Admin::Ui::GifComponent.new(src: "/files/1", name: "loop.gif", placement: :stage))
    assert_no_selector "a"
    assert_selector "[data-controller='admin--ui--gif'] > span img[alt='loop.gif']"
    assert_selector "[data-controller='admin--ui--gif'] > span canvas", visible: :all

    render_inline(Admin::Ui::GifComponent.new(src: nil, name: "", placement: :stage))
    assert_selector "img:not([src])", visible: :all
  end

  test "a tile draws the label GIF · name after the button, the stage none" do
    render_inline(Admin::Ui::GifComponent.new(src: "/files/1", name: "loop.gif"))
    assert_selector "[data-controller='admin--ui--gif'] > button + span", exact_text: "GIF · loop.gif"

    render_inline(Admin::Ui::GifComponent.new(src: "/files/1", name: "loop.gif", placement: :stage))
    assert_no_text "GIF · loop.gif"
    assert_no_selector "[data-controller='admin--ui--gif'] > button + span"
  end

  test "an unknown placement, or link: on the stage, raises" do
    assert_raises(ArgumentError) { Admin::Ui::GifComponent.new(src: "/files/1", name: "loop.gif", placement: :wall) }
    assert_raises(ArgumentError) { Admin::Ui::GifComponent.new(src: "/files/1", name: "loop.gif", placement: :stage, link: { title: "x" }) }
  end
end
