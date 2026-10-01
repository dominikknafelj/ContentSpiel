require "application_system_test_case"

# The dashboard is CS Studio's start page (dashboard spec §2-§4): sign-in
# lands here, a quick draft shows up under "Your work" immediately, and
# once it's scheduled it shows up under "On the site" at its go-live time
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
    within("section[aria-labelledby=your-work]") { assert_text "From the dashboard" }

    # Mobility stores `title` as jsonb, so a plain `where(title: ...)` would
    # compare jsonb to a string (CLAUDE.md's own warning) -- `.i18n` is the
    # query scope that actually looks inside the translated column, same as
    # `StarterContent` uses to find its own seeded posts by title.
    post = Post.kept.i18n.find_by!(title: "From the dashboard")
    post.update!(published_at: Time.find_zone("Europe/Berlin").local(2030, 7, 1, 9, 30))

    visit admin_root_path
    within("section[aria-labelledby=on-the-site]") { assert_text "09:30" }
  end
end
