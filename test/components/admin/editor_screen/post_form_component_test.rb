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

  # Design answer C6, for a content type of its own with a code field: the
  # line above the read-only code links to the post's default tab.
  test "on a translation tab a post type's code field is read-only under the line that links to the post's default tab, and is named by its label" do
    ContentTypes.register "test/snippet" do |t|
      t.label "Snippet"
      t.list_component Posts::BlogListComponent
      t.detail_component Posts::DetailComponent
      t.field :source, :code, max: 100, label: "Source code"
    end
    with_locales(%w[en de], default: "en") do
      saved = Posts::Save.call(attributes: { content_type: "test/snippet", fields: { source: "  a = 1" } }, translations: { "en" => { title: "Snippet" } })
      assert saved.ok?, saved.errors.to_sentence

      as_viewer(users(:one), tab: "tab-aaaaaaaa") { render_inline Admin::EditorScreen::PostFormComponent.new(post: saved.record, locale: "de") }

      assert_selector "details[data-shared-fields] dt", exact_text: "Source code", visible: :all
      assert_equal "  a = 1", Nokogiri::HTML5.fragment(rendered_content).at_css("details[data-shared-fields] dd pre").text
      assert_selector "details[data-shared-fields] p[data-code-note] a[href='/cs-studio/posts/#{saved.record.id}'][data-turbo-frame='_top']", exact_text: "English", visible: :all
      assert_no_selector "[name='post[fields][source]']", visible: :all
    end
  ensure
    Rails.application.reloader.prepare!
  end
end
