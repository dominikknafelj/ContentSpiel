require "application_system_test_case"

# The dashboard is CS Studio's start page (dashboard spec §2-§4): sign-in
# lands here, a quick draft shows up under "Your drafts" immediately, and
# once it's scheduled it shows up under "Going live next" at its go-live time
# -- rendered in the site's time zone, not UTC (spec §5), which is the
# other half of this sub-project.
class Admin::DashboardSystemTest < ApplicationSystemTestCase
  test "land on the dashboard, quick-draft a post, schedule it and see it go live next in local time" do
    site_settings(:default).update!(time_zone: "Europe/Berlin")
    sign_in_via_form(users(:one))
    assert_selector "h1", text: "Dashboard"

    fill_in "Title", with: "From the dashboard"
    press "Create draft"
    assert_text "Draft created"

    visit admin_root_path
    within("section[aria-labelledby=dashboard-drafts]") { assert_text "From the dashboard" }

    # Mobility stores `title` as jsonb, so a plain `where(title: ...)` would
    # compare jsonb to a string (CLAUDE.md's own warning) -- `.i18n` is the
    # query scope that actually looks inside the translated column, same as
    # `StarterContent` uses to find its own seeded posts by title.
    post = Post.kept.i18n.find_by!(title: "From the dashboard")
    post.update!(published_at: Time.find_zone("Europe/Berlin").local(2030, 7, 1, 9, 30))

    visit admin_root_path
    within("section[aria-labelledby=dashboard-going-live-next]") do
      assert_text "From the dashboard"
      # 09:30 BERLIN time on 1 July -- the stored UTC instant is 07:30, so a
      # row drawn in UTC would say 07:30 here (final review C, I5).
      assert_selector "time[title='1 Jul 2030, 09:30']"
    end
  end

  test "quick create makes a blog draft and opens its editor" do
    sign_in_via_form(users(:one))
    fill_in "Title", with: "Quick one"
    select "Blog", from: "Type"
    press "Create draft"

    assert_text "Draft created"
    assert_current_path(%r{/cs-studio/posts/\d+})
  end

  test "pressing Enter twice in quick create makes one draft" do
    sign_in_via_form(users(:one))
    await_admin_controllers
    field = find_field("Title")
    field.fill_in with: "Only once"
    field.send_keys(:enter, :enter)

    assert_text "Draft created"
    assert_equal 1, Post.kept.i18n.where(title: "Only once").count
  end

  test "choosing Page in quick create opens the New page dialog with the typed title" do
    root_page # the dialog needs a Home to put the page inside
    sign_in_via_form(users(:one))
    await_admin_controllers
    fill_in "Title", with: "Our team"
    select "Page", from: "Type"
    press "Create draft"

    assert_selector "dialog#new-page-dialog[open]"
    within("dialog#new-page-dialog") { assert_field "Title", with: "Our team" }
    assert_current_path admin_root_path
  end

  test "the activity feed shows published after a draft is published" do
    post = Current.set(actor: users(:one), channel: :admin) { create_post(title: "To publish", published: false) }
    sign_in_via_form(users(:one))
    visit admin_post_path(post)
    find("header button.bg-accent", text: "Publish").click
    assert_text "Live", wait: 10

    visit admin_root_path
    within("section[aria-labelledby=dashboard-activity]") do
      assert_text "published “To publish”"
    end
  end
end
