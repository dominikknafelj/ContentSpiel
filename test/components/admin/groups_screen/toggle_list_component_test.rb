require "test_helper"

# The other permissions, as one list of area bands: Content, Administration,
# Oversight, Forms -- and a plugin's permission under a band named by its own area.
class Admin::GroupsScreen::ToggleListComponentTest < ViewComponent::TestCase
  def render_for(grants)
    render_inline Admin::GroupsScreen::ToggleListComponent.new(grants: grants)
  end

  test "the unscoped keys are one list of area bands with a switch per row, Forms after Oversight" do
    render_for({ "tags.manage" => {} })

    list = page.find("div.admin-toggle-list")
    assert_no_selector ".rounded-card"
    assert_no_selector ".shadow-1"
    bands = list.all("section > h3.admin-area-heading")
    assert_equal %w[Content Administration Oversight Forms], bands.map(&:text)
    bands.each { |band| assert_equal "admin-area-heading border-b border-line bg-paper px-4 py-2 text-label text-meta", band[:class] }
    rows = list.all("section > label")
    assert_equal 14, rows.size
    rows.each do |row|
      assert_includes row[:class].split, "px-4"
      assert_includes row[:class].split, "py-2"
      assert_includes row[:class].split, "border-line"
      assert row.has_css?("input.cs-toggle[type=checkbox][role=switch]"), row.text
    end
    assert_no_selector "[class*=opacity]"
    assert_no_selector ".text-xs"
  end

  test "four bands, with the built-in permissions grouped as the design has them" do
    render_for({ "tags.manage" => {}, "audit.view" => {} })

    bands = page.all("section").map { |section| section.find("h3").text }
    assert_equal %w[Content Administration Oversight Forms], bands
    assert_equal %w[tags.manage media.upload media.manage ai.translate], keys_in("Content")
    assert_equal %w[settings.manage languages.manage users.manage groups.manage tokens.manage], keys_in("Administration")
    assert_equal %w[system_status.view audit.view trash.empty], keys_in("Oversight")
    assert_equal %w[forms.manage form_submissions.view], keys_in("Forms"), "forms.submit is no group's, so no toggle"
  end

  test "a toggle is a switch checkbox posting the permission's enabled key, ticked when held, with the registry label" do
    render_for({ "tags.manage" => {} })

    assert_selector "input.cs-toggle[type=checkbox][role=switch][name='group[grants][tags.manage][enabled]'][value='1'][checked]"
    assert_selector "input.cs-toggle[name='group[grants][media.upload][enabled]']:not([checked])"
    assert_selector "label", text: "Manage tags"
    assert_selector "code[title='tags.manage']", text: "tags.manage"
    assert_selector "label", text: "View audit log (all content)"
  end

  test "a plugin permission lands under a band of its own after the built-ins', named by its own area" do
    with_plugin_permission do
      render_for({ "acme/widgets.use" => {} })

      bands = page.all("section").map { |section| section.find("h3").text }
      assert_equal %w[Content Administration Oversight Forms Widgets], bands
      assert_equal [ "acme/widgets.use" ], keys_in("Widgets")
      assert_selector "input[name='group[grants][acme/widgets.use][enabled]'][checked]"
    end
  end

  test "a scoped permission is never a toggle (it would lose its scope)" do
    render_for({})
    assert_no_selector "input[name='group[grants][posts.read][enabled]']"
  end

  test "a locked toggle is a disabled switch with the note in meta and no opacity class, carried by a hidden enabled input; an unticked one is never locked" do
    render_inline Admin::GroupsScreen::ToggleListComponent.new(grants: { "tags.manage" => {} }, locked: %w[tags.manage media.upload])

    assert_selector "input.cs-toggle[type=checkbox][name='group[grants][tags.manage][enabled]'][checked][disabled]"
    assert_selector "input[type=hidden][name='group[grants][tags.manage][enabled]'][value='1']", visible: :all
    assert_selector ".admin-locked-note.text-small.text-meta", text: "You can't grant this", count: 1
    assert_no_selector "[class*=opacity]"
    assert_selector "input[name='group[grants][media.upload][enabled]']:not([checked]):not([disabled])"
    assert_no_selector "input[type=hidden][name='group[grants][media.upload][enabled]']", visible: :all
  end

  private

  def keys_in(title) = page.find("section", text: /\A\s*#{title}/).all("code").map(&:text)

  def with_plugin_permission
    AccessControl::Permissions.register "acme/widgets.use", label: "Use widgets", area: "Widgets", action: :use
    yield
  ensure
    AccessControl::Permissions.reset!
    AccessControl::BuiltIns.register
  end
end
