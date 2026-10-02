require "test_helper"

# The site title and tagline are translated (translation helpers spec §5):
# the public header, footer, homepage eyebrow and `<title>` read them in the
# request's locale, falling back like every other translated public read
# (`Locales.read`) when a language has none of its own.
class PublicSiteTitleTest < ActionDispatch::IntegrationTest
  setup do
    with_locales(%w[en de es], default: "en")
    site = SiteSetting.instance
    Mobility.with_locale(:en) { site.assign_attributes(title: "Dana's Notes", tagline: "Things I learned") }
    Mobility.with_locale(:de) { site.assign_attributes(title: "Danas Notizen", tagline: "Was ich gelernt habe") }
    site.save!
    root_page
  end

  test "/de shows the German title in the header, footer and <title>, and the German tagline" do
    get "/de"

    assert_response :success
    assert_includes response.body, "<title>Danas Notizen</title>"
    assert_select "header span", text: "Danas Notizen"
    assert_select "footer p", text: /Danas Notizen/
    assert_includes response.body, "Was ich gelernt habe"
    assert_not_includes response.body, "Things I learned"
  end

  test "the default language reads its own title and tagline" do
    get "/"

    assert_response :success
    assert_includes response.body, "<title>Dana&#39;s Notes</title>"
    assert_includes response.body, "Things I learned"
    assert_not_includes response.body, "Was ich gelernt habe"
  end

  test "a language without its own title or tagline falls back to the default language's" do
    get "/es"

    assert_response :success
    assert_includes response.body, "<title>Dana&#39;s Notes</title>"
    assert_select "header span", text: "Dana's Notes"
    assert_includes response.body, "Things I learned"
  end

  test "a page's document title appends the site title in the request's language" do
    create_page(title: "About", translations: { "de" => { title: "Über uns", slug: "ueber-uns" } })

    get "/de/ueber-uns"

    assert_response :success
    assert_includes response.body, "<title>Über uns – Danas Notizen</title>"
  end
end
