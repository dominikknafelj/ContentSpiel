module Admin
  # The mind graph (mind graph canvas spec §3): the page is a FRAME -- heading,
  # legend, filter, an empty canvas -- and holds no graph data. `admin--mind-graph`
  # fetches the graph from `data` and draws it on the canvas, laid out by
  # d3-force in a worker. Read-only -- relations are edited in the post editor's
  # related-posts picker, not here. Each node's editor URL is built through the
  # route helper with the editing language kept (`admin_url_options`).
  #
  # Needs `posts.read` somewhere, and shows only the posts the actor may
  # read, with no edge to one they can't (every `PostGraph` query's `actor:`,
  # access-control design spec §3.3).
  #
  # `data` and `search` are the screen's JSON reads (mind graph canvas spec
  # §3.1) with the screen's own permission and scope: `data` answers the
  # global graph, or the neighbourhood of `post=` / `tag=`; `search` answers
  # the search field's rows, each with the URL of its local view. A focus the
  # viewer may not see (unknown, trashed, outside their read scope) is not
  # found, from the page and from `data` alike: `PostGraph::Focus` raises
  # `RecordNotFound`, which `Admin::BaseController` answers with the 404 page,
  # or a bare 404 for a non-HTML request.
  class MindGraphController < BaseController
    before_action -> { require_permission("posts.read") }

    # The frame only: the graph itself is fetched by the script from `data`.
    # What the page needs from the database is whether this viewer can read a
    # post at all ("No posts yet."), which content types their posts have (the
    # legend names only those, so it discloses no type they can't see) and the
    # focus, which is not found when it is outside their scope.
    def show
      @focus = PostGraph::Focus.find(actor: Current.actor, post: params[:post], tag: params[:tag], locale: admin_locale)
      @depth = params[:depth].to_s == "2" ? 2 : 1
      @content_types = AccessControl.scope(Current.actor, "posts.read", Post.all).distinct.pluck(:content_type)
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
