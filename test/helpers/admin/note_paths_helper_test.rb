require "test_helper"

class Admin::NotePathsHelperTest < ActionView::TestCase
  include Admin::NotePathsHelper

  Route = Data.define(:name, :args, :params)

  # The view's own `admin_url_options` (the editing locale), stubbed.
  def admin_url_options = { locale: "de" }

  test "a route on the list resolves with its arguments, params and the request's URL options" do
    page = create_page(title: "Noted")

    route = Route.new(name: :admin_page_path, args: [ page ], params: { notes: "open", thread: 7 })

    assert_equal "/cs-studio/pages/#{page.id}?notes=open&thread=7", note_route_path(route)
    assert_equal "/cs-studio/pages/#{page.id}?locale=de&notes=open&thread=7", note_route_path(route, **admin_url_options)
  end

  test "the list is the three records a note can be on, and every route the inbox queries hand up is on it" do
    assert_equal %i[admin_page_path admin_post_path admin_media_path], Admin::NotePathsHelper::NOTE_ROUTES

    page = create_page(title: "Noted")
    post = create_post(title: "Noted post")
    [ page, post ].each { |record| assert_includes Admin::NotePathsHelper::NOTE_ROUTES, Audit::Sentence.route_for(record).name }
  end

  test "a name that is not on the list is refused, never sent to public_send" do
    error = assert_raises(ArgumentError) { note_route_path(Route.new(name: :destroy_all, args: [], params: {})) }
    assert_match(/not a route/, error.message)

    # Symbols only: the same name as a string is not on the list.
    assert_raises(ArgumentError) { note_route_path(Route.new(name: "admin_page_path", args: [ 1 ], params: {})) }
  end

  test "no notes component and no notes controller resolves a route name any other way" do
    sources = Dir[Rails.root.join("app/components/admin/notes_screen/**/*.{rb,erb}"), Rails.root.join("app/controllers/admin/note*_controller.rb"),
      Rails.root.join("app/views/admin/note*/**/*.erb")]
    offenders = sources.select { |file| File.read(file).match?(/public_send\(\s*\w*\.?route/) }

    assert_empty offenders.map { |file| Pathname(file).relative_path_from(Rails.root).to_s }
  end
end
