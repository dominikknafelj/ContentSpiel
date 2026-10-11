require "test_helper"

# A post is held as a whole (live-editing handoff 8): the strip stands in the header's
# notice area, and the form is read-only.
class Admin::EditorScreen::PostFormComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @post = create_post(title: "Held post", tags: [ "alpha" ])
    @dana = users(:two)
    @dana.update!(name: "Dana Weiss")
  end

  def render_for(viewer, tab, **options)
    as_viewer(viewer, tab: tab) { render_inline Admin::EditorScreen::PostFormComponent.new(post: @post, locale: "en", **options) }
  end

  def controls = form_controls(within: "#post-form")

  test "held by someone else: the strip is in the header's notice area, the unit says held, no autosave controller, every control read-only with the same names and values" do
    render_for(users(:one), "tab-aaaaaaaa")
    editable_controls = controls
    assert_selector "form#post-form[data-controller~='admin--saving--autosave']"

    reserve(@post, @post, @dana, "tab-bbbbbbbb")
    render_for(users(:one), "tab-aaaaaaaa")

    assert_selector "#editor-notice [data-editing-kind=held]", text: "Dana Weiss is editing this post"
    assert_selector "form#post-form[data-editing-unit][data-editing-held=true]:not([data-controller])"
    assert_equal editable_controls, controls
    assert_selector "#post-form fieldset.admin-held input[name='post[title]'][readonly]"
    assert_selector "#post-form fieldset.admin-held textarea[name='post[excerpt]'][readonly]"
    assert_no_selector "#post-form [role=toolbar]", visible: :all
    assert_selector "#post-form [data-admin--rich-text--editor-read-only-value=true]"
    assert_selector "#post-form .admin-chip__remove[disabled]", visible: :all
  end

  test "held by the viewer in this tab: drawn as ever; held by nobody: the notice area is empty" do
    render_for(users(:one), "tab-aaaaaaaa")
    assert_selector "#editor-notice:empty"

    reserve(@post, @post, users(:one), "tab-aaaaaaaa")
    render_for(users(:one), "tab-aaaaaaaa")
    assert_selector "form#post-form[data-controller~='admin--saving--autosave']"
    assert_no_selector "[data-editing-held]"
    assert_selector "#editor-notice:empty"
  end

  test "the form-only answer carries the notice area with the strip, and nothing of the header" do
    reserve(@post, @post, @dana, "tab-bbbbbbbb")

    render_for(users(:one), "tab-aaaaaaaa", form_only: true)

    assert_selector "#editor-notice [data-editing-kind=held]"
    assert_no_selector "header"
  end

  test "someone who may only read sees the strip without Take over" do
    reserve(@post, @post, @dana, "tab-bbbbbbbb")

    render_for(users(:reader), "tab-aaaaaaaa")

    assert_selector "#editor-notice [data-editing-kind=held]"
    assert_no_selector "#editor-notice button"
  end

  test "the version of the form differs between free and held" do
    render_for(users(:one), "tab-aaaaaaaa")
    free = Capybara.string(rendered_content).find("#post-form")["data-editing-version"]

    reserve(@post, @post, @dana, "tab-bbbbbbbb")
    render_for(users(:one), "tab-aaaaaaaa")

    assert_not_equal free, Capybara.string(rendered_content).find("#post-form")["data-editing-version"]
  end
end
