module Admin
  # The mind graph (design spec §6.1, Task 9): `PostGraph`'s nodes and
  # edges, embedded in the page as a JSON data island and drawn client-side
  # by `admin--mind-graph` (d3-force). Read-only -- relations are edited in
  # the post editor's related-posts picker, not here. Each node's click
  # target is the CS Studio post editor, built through the route helper
  # with the editing language kept (`admin_url_options`).
  #
  # Needs `posts.read` somewhere, and shows only the posts the actor may
  # read, with no edge to one they can't (`PostGraph`'s `actor:`,
  # access-control design spec §3.3).
  class MindGraphController < BaseController
    before_action -> { require_permission("posts.read") }

    def show
      @graph = PostGraph.call(actor: Current.actor, locale: admin_locale, url_for: ->(post) { admin_post_path(post, **admin_url_options) })
    end
  end
end
