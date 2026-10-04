require "test_helper"

# The other permissions, as toggle cards (Task 10): Content, Administration,
# Oversight -- and a plugin's permission in a card named by its own area.
class Admin::GroupsScreen::ToggleListComponentTest < ViewComponent::TestCase
  def render_for(grants)
    render_inline Admin::GroupsScreen::ToggleListComponent.new(grants: grants)
  end

  test "three cards, with the built-in permissions grouped as the design has them" do
    render_for({ "tags.manage" => {}, "audit.view" => {} })

    cards = page.all("section").map { |card| card.find("h3").text }
    assert_equal %w[Content Administration Oversight], cards
    assert_equal %w[tags.manage media.upload media.manage ai.translate], keys_in("Content")
    assert_equal %w[settings.manage languages.manage users.manage groups.manage tokens.manage], keys_in("Administration")
    assert_equal %w[system_status.view audit.view trash.empty], keys_in("Oversight")
  end

  test "a toggle is a switch checkbox posting the permission's enabled key, ticked when held, with the registry label" do
    render_for({ "tags.manage" => {} })

    assert_selector "input.cs-toggle[type=checkbox][role=switch][name='group[grants][tags.manage][enabled]'][value='1'][checked]"
    assert_selector "input.cs-toggle[name='group[grants][media.upload][enabled]']:not([checked])"
    assert_selector "label", text: "Manage tags"
    assert_selector "code[title='tags.manage']", text: "tags.manage"
    assert_selector "label", text: "View audit log (all content)"
  end

  test "a plugin permission lands in a fourth card named by its own area" do
    with_plugin_permission do
      render_for({ "acme/widgets.use" => {} })

      cards = page.all("section").map { |card| card.find("h3").text }
      assert_equal %w[Content Administration Oversight Widgets], cards
      assert_equal [ "acme/widgets.use" ], keys_in("Widgets")
      assert_selector "input[name='group[grants][acme/widgets.use][enabled]'][checked]"
    end
  end

  test "a scoped permission is never a toggle (it would lose its scope)" do
    render_for({})
    assert_no_selector "input[name='group[grants][posts.read][enabled]']"
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
