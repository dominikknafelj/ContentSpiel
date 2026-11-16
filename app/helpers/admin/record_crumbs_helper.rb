module Admin
  # The crumbs above a page or a post, before its own: the editor's header
  # and the History screen draw the same ones (`Admin::EditorScreen::
  # HeaderComponent`, `Admin::HistoryScreen::HeadComponent`). A crumb is
  # `[label, url-or-nil]`; a crumb the viewer may not open (`can`, the
  # caller's own `can?`) has no url and is drawn as plain text. The module's
  # own crumb is labelled by a Symbol, `:pages` or `:posts`, which each
  # caller words itself; every other label is the record's data (an
  # ancestor's title, a post type's label).
  #
  # A page: its module, then each ancestor, root first. "Pages" is plain
  # text on the homepage itself, where it would link to the page you are on
  # (`/pages` opens Home). A post: its module, then its content type's
  # filtered list.
  module RecordCrumbsHelper
    def record_crumbs(record, locale:, url_options:, can:)
      if record.is_a?(::Page)
        module_crumb = [ :pages, can.call("pages.read", nil) && !record.root? ? admin_pages_path(**url_options) : nil ]
        ancestors = record.ancestors.to_a.reverse.map do |ancestor|
          [ ::Locales.read(ancestor, :title, locale: locale), can.call("pages.read", ancestor) ? admin_page_path(ancestor, **url_options) : nil ]
        end
        [ module_crumb ] + ancestors
      else
        allowed = can.call("posts.read", nil)
        label = ::ContentTypes.find(record.content_type)&.label || record.content_type
        [ [ :posts, allowed ? admin_posts_path(**url_options) : nil ],
          [ label, allowed ? admin_posts_path(type: record.content_type, **url_options) : nil ] ]
      end
    end
  end
end
