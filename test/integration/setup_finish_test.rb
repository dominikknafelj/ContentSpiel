require "test_helper"

class SetupFinishTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
    create_setup_admin
  end

  test "the review summarises the choices, with edit links" do
    SiteSetting.instance.update!(title: "Dana's Notes", default_locale: "de")

    get setup_step_path("review")

    assert_response :success
    assert_includes response.body, "Dana&#39;s Notes"
    assert_includes response.body, "Deutsch"
    assert_includes response.body, "Skipped"
    assert_select "a[href=?]", setup_step_path("site")
  end

  test "finishing creates the homepage, ends setup and opens the admin" do
    patch setup_step_path("review")

    assert_redirected_to "/cs-studio"
    assert_not Setup.required?

    get "/"
    assert_response :success
    assert_includes response.body, "Welcome to your new site"

    get setup_path
    assert_response :not_found
  end

  # Both starter services publish a page and then add its blocks, so the copy
  # taken at publication was empty until they published what they wrote.
  test "after setup a visitor sees the homepage's text and each section page's list" do
    patch setup_step_path("review")
    assert as(nil, channel: :setup) { StarterContents::Add.call }.ok?

    get "/"
    assert_includes response.body, "Welcome to your new site"

    StarterContent.sections.each do |section|
      get PublicSite::Urls.new.path_for(StarterContent.find_section_page(Page.find_by(parent_id: nil), section), "en")
      assert_response :success
      # A content type draws its list its own way: by title, or by body alone.
      sample = [ section[:sample][:title], section[:sample][:body] ].compact
      assert sample.any? { |text| css_select("main").text.include?(text) }, "#{section[:section][:title]} lists its sample post"
    end
  end
end
