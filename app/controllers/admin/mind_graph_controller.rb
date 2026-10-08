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
  #
  # `data` and `search` are the screen's JSON reads (mind graph canvas spec
  # §3.1) with the screen's own permission and scope: `data` answers the
  # global graph, or the neighbourhood of `post=` / `tag=`; `search` answers
  # the search field's rows, each with the URL of its local view. A focus the
  # viewer may not see (unknown, trashed, outside their read scope) is not
  # found: `PostGraph::Focus` raises `RecordNotFound`, which
  # `Admin::BaseController` answers with a bare 404 for a non-HTML request.
  class MindGraphController < BaseController
    before_action -> { require_permission("posts.read") }

    def show
      @graph = PostGraph.call(actor: Current.actor, locale: admin_locale, url_for: editor_url)
    end

    def data
      focus = PostGraph::Focus.find(actor: Current.actor, post: params[:post], tag: params[:tag], locale: admin_locale)
      graph =
        if focus
          PostGraph::Local.call(actor: Current.actor, focus: focus, depth: params[:depth], locale: admin_locale, url_for: editor_url)
        else
          PostGraph::Global.call(actor: Current.actor, locale: admin_locale, url_for: editor_url)
        end
      render json: graph
    end

    def search
      rows = PostGraph::Search.call(actor: Current.actor, text: params[:q], locale: admin_locale)
      render json: rows.map { |row| row.merge(url: admin_mind_graph_path(row[:kind] => row[:id], **admin_url_options)) }
    end

    private

    def editor_url = ->(post) { admin_post_path(post, **admin_url_options) }
  end
end
