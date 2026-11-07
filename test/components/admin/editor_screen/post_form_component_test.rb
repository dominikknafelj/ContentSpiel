require "test_helper"
require_relative "../../../support/rail_tab_probe"

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

  test "a registered rail tab makes the post rail a tablist of two, with its panel after the form" do
    Admin::Slots.with("editor.rail.tabs" => [ RailTabProbe ]) do
      render_for(users(:one), "tab-aaaaaaaa")
      assert_selector "#editor-grid [role=tablist] [role=tab]", count: 2
      assert_selector "#editor-grid-tab-post[aria-selected=true]"
      assert_selector "#editor-grid-tab-probe", text: "Probe"
      assert_no_selector "h2#editor-grid-tab-post", wait: 0
      assert_selector "#editor-grid > form#post-form ~ #editor-grid-panel-probe"
    end
  end

  test "with nothing registered the post rail is a heading" do
    Admin::Slots.with("editor.rail.tabs" => []) { render_for(users(:one), "tab-aaaaaaaa") }
    assert_selector "h2#editor-grid-tab-post"
    assert_no_selector "[role=tablist]", wait: 0
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

  test "the form is the editors' form column: 760px on the default tab, the pair's width on a translation tab, and the header is neither" do
    with_locales(%w[en de], default: "en")
    as_owner { render_inline Admin::EditorScreen::PostFormComponent.new(post: @post, locale: "en") }
    assert_selector "form#post-form.admin-translation-form.admin-form-column:not(.admin-form-column--pair)"
    assert_no_selector ".admin-editor-header.admin-form-column"

    as_owner { render_inline Admin::EditorScreen::PostFormComponent.new(post: @post, locale: "de") }
    assert_selector "form#post-form.admin-form-column.admin-form-column--pair"
  end

  test "the post's settings panel is inside the form and after the main column" do
    as_owner { render_inline Admin::EditorScreen::PostFormComponent.new(post: @post, locale: "en") }

    assert_selector "#editor-grid.admin-rail-grid[data-controller~='admin--ui--rail']:not(.admin-rail-grid--folded)"
    assert_selector "#editor-grid > form#post-form", count: 1
    # The tabs stand after the form in the document (the grid puts them in the
    # rail's first row): Post, then the registered Notes tab.
    assert_selector "#editor-grid > form#post-form + [role=tablist] #editor-grid-tab-post[role=tab]", text: "Post"
    assert_selector "#editor-grid > form#post-form + [role=tablist] #editor-grid-tab-notes[role=tab]"
    panel = "#post-form [role=tabpanel]#editor-grid-panel-post[data-current][aria-labelledby='editor-grid-tab-post']"
    assert_selector "#{panel} #post-excerpt"
    assert_selector "#{panel} #post-tag_names"
    assert_selector "#{panel} #post-related_post_ids"
    assert_selector "#post-form .admin-post-main.admin-rail__main #post-title"
    assert_selector "#post-form .admin-post-main #post-slug"
    assert_selector "#post-form .admin-post-main [data-field-name='body']"
    assert_no_selector "#{panel} #post-title"

    ids = Capybara.string(rendered_content).all("#post-form #editor-grid-panel-post, #post-form .admin-post-main").map { |node| node[:id] || node[:class] }
    assert_equal "editor-grid-panel-post", ids.last, "the main column comes before the settings panel"
    assert_equal 2, ids.size
  end

  test "a type's own fields stand in the settings panel; a translation tab folds the rail; the form-only answer is the form alone" do
    ContentTypes.register "test/event" do |t|
      t.label "Event"
      t.list_component Posts::BlogListComponent
      t.detail_component Posts::DetailComponent
      t.field :venue, :string
    end
    with_locales(%w[en de], default: "en") do
      saved = Posts::Save.call(attributes: { content_type: "test/event" }, translations: { "en" => { title: "Gig" } })
      assert saved.ok?, saved.errors.to_sentence

      as_owner { render_inline Admin::EditorScreen::PostFormComponent.new(post: saved.record, locale: "en") }
      assert_selector "#editor-grid-panel-post [data-editor-fields-group]"

      as_owner { render_inline Admin::EditorScreen::PostFormComponent.new(post: saved.record, locale: "de") }
      assert_selector "#editor-grid.admin-rail-grid--folded > form#post-form"

      as_owner { render_inline Admin::EditorScreen::PostFormComponent.new(post: saved.record, locale: "en", form_only: true) }
      assert_no_selector "#editor-grid"
      assert_selector "form#post-form #editor-grid-panel-post"
    end
  ensure
    Rails.application.reloader.prepare!
  end
end
