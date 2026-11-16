require "test_helper"

class ContentModel::ContentTypeDefinitionTest < ActiveSupport::TestCase
  # Same idiom as test/support/test_types.rb: registrations made here are
  # undone by re-running the boot-time registration.
  teardown { Rails.application.reloader.prepare! }

  test "built-in content types get colour indexes in registration order" do
    assert_equal [ 1, 2, 3 ], %w[blog resume_entry now_update].map { |name| ContentTypes.fetch(name).colour_index }
  end

  test "a type may state its own colour index, and the next one skips it" do
    ContentTypes.register("acme/case_study") { |type| type.colour_index = 5 }
    ContentTypes.register("acme/event")
    assert_equal 5, ContentTypes.fetch("acme/case_study").colour_index
    assert_equal 4, ContentTypes.fetch("acme/event").colour_index
  end

  test "a colour index must be a positive integer" do
    assert_raises(ArgumentError) { ContentTypes.register("acme/bad") { |type| type.colour_index = 0 } }
    assert_nil ContentTypes.find("acme/bad")
  end

  def declare(name = "acme/case_study")
    ContentTypes.register(name) { |type| yield type }
  end

  test "a component is declared with its theme methods" do
    type = declare do |t|
      t.list_component Posts::BlogListComponent, theme_methods: %w[posts page]
      t.detail_component Posts::DetailComponent, theme_methods: %w[post]
    end

    assert_equal Posts::BlogListComponent, type.list_component
    assert_equal %w[posts page], type.list_theme_methods
    assert_equal Posts::DetailComponent, type.detail_component
    assert_equal %w[post], type.detail_theme_methods
  end

  test "a component without theme_methods is refused, naming the type" do
    error = assert_raises(ArgumentError) { declare { |t| t.list_component Posts::BlogListComponent } }
    assert_match(/\Aacme\/case_study: list_component declares `theme_methods:`/, error.message)

    error = assert_raises(ArgumentError) { declare { |t| t.detail_component Posts::DetailComponent, theme_methods: [] } }
    assert_match(/\Aacme\/case_study: detail_component declares/, error.message)
    assert_nil ContentTypes.find("acme/case_study")
  end

  test "a sample's shows names its title, its excerpt or a String field value" do
    type = declare do |t|
      t.field :company, :string
      t.sample title: "Case", excerpt: "Short", fields: { company: "Example Co" }, shows: [ "Case", "Short", "Example Co" ]
    end
    assert_equal [ "Case", "Short", "Example Co" ], type.sample.shows

    error = assert_raises(ArgumentError) { declare("acme/other") { |t| t.sample title: "Case", shows: [ "content-block" ] } }
    assert_match(/\Aacme\/other: .*"content-block"/, error.message)
    assert_raises(ArgumentError) { declare("acme/none") { |t| t.sample title: "Case", shows: [] } }
  end

  test "a sample is refused for a blank title, a non-String body or an undeclared field" do
    {
      "a blank title" => { title: " ", shows: [ "x" ] },
      "a non-String body" => { title: "Case", body: [ "x" ], shows: [ "Case" ] },
      "an undeclared field" => { title: "Case", fields: { nope: "x" }, shows: [ "Case" ] }
    }.each do |what, values|
      error = assert_raises(ArgumentError, what) { declare("acme/bad") { |t| t.sample(**values) } }
      assert_match(/\Aacme\/bad: /, error.message, what)
    end
  end

  test "a starter needs a sample, and its post is the sample without shows" do
    assert_raises(ArgumentError) { declare { |t| t.starter section: { title: "Cases", slug: "cases" } } }

    type = declare("acme/ok") do |t|
      t.sample title: "Case", body: "Words.", shows: [ "Case" ]
      t.starter section: { title: "Cases", slug: "cases" }
    end
    assert_equal({ section: { title: "Cases", slug: "cases" }, sample: { title: "Case", body: "Words." } }, type.starter_data)
  end

  test "description and group are Symbols" do
    type = declare { |t| t.description :blog; t.group :personal_site }
    assert_equal :blog, type.description
    assert_equal :personal_site, type.group

    assert_raises(ArgumentError) { declare("acme/a") { |t| t.description "Words" } }
    assert_raises(ArgumentError) { declare("acme/b") { |t| t.group "For me" } }
    assert_nil declare("acme/c") { |t| t.label "C" }.description
  end

  test "every built-in type's description and group key is in the locale file" do
    ContentTypes.all.each do |type|
      assert I18n.exists?("admin.content_types.descriptions.#{type.description}"), "#{type.name}: no description" if type.description
      assert I18n.exists?("admin.content_types.groups.#{type.group}"), "#{type.name}: no group" if type.group
    end
  end
end
