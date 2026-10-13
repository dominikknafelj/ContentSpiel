module Admin
  # The mind graph (mind graph canvas spec §3): the page is a FRAME -- heading,
  # legend, filter, an empty canvas -- and holds no graph data. `admin--mind-graph--graph`
  # fetches the graph from `data` and draws it on the canvas, laid out by
  # d3-force in a worker. Read-only -- relations are edited in the post editor's
  # related-posts picker, not here. Each node's editor URL is built through the
  # route helper with the editing language kept (`admin_url_options`).
  #
  # Opens for someone who may read a page or a post somewhere (pages in the
  # mind graph, spec §2): a graph of pages alone is a graph. Each kind is
  # then narrowed by its own scope in the queries (every `PostGraph` query's
  # `actor:`, access-control design spec §3.3), so only the pages and posts
  # the actor may read are shown, with no line to one they can't. A node's
  # editor URL is built here (`editor_url`, called with a `Post` or a
  # `Page`): a query knows no routes.
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
    # The screen opens for someone who may read a page or a post anywhere
    # (pages spec §2): a graph of pages alone is a graph. Each kind is then
    # narrowed by its own scope in the queries.
    before_action :require_graph_access

    # The frame only: the graph itself is fetched by the script from `data`.
    # What the page needs from the database is whether this viewer can read a
    # post or a page at all ("No posts yet." when neither), which content types their posts have (the
    # legend names only those, so it discloses no type they can't see) and the
    # focus, which is not found when it is outside their scope. `@type_labels`
    # is the human name of each of those types that is still registered, for
    # the selection card (a retired type has none; the card shows its stored
    # name, as `Admin::Ui::ContentTypeDotComponent` does).
    def show
      @focus = PostGraph::Focus.find(actor: Current.actor, post: params[:post], tag: params[:tag], locale: admin_locale)
      @depth = params[:depth].to_s == "2" ? 2 : 1
      @content_types = AccessControl.scope(Current.actor, "posts.read", Post.all).distinct.pluck(:content_type)
      @type_labels = @content_types.filter_map { |name| (definition = ContentTypes.find(name)) && [ name, definition.label ] }.to_h
      @pages = AccessControl.scope(Current.actor, "pages.read", Page.all).exists?
    end

    def data
      focus = PostGraph::Focus.find(actor: Current.actor, post: params[:post], tag: params[:tag], locale: admin_locale)
      graph =
        if focus
          PostGraph::Local.call(actor: Current.actor, focus: focus, depth: params[:depth], locale: admin_locale, url_for: editor_url)
        else
          # `everything: true` until the script knows the `open` answer and a
          # page's local view is drawn (pages plan, Task 8): until then the
          # whole graph is what this screen can show.
          PostGraph::Global.call(actor: Current.actor, locale: admin_locale, url_for: editor_url, everything: true)
        end
      render json: with_dates(graph)
    end

    def search
      rows = PostGraph::Search.call(actor: Current.actor, text: params[:q], locale: admin_locale)
      render json: rows.map { |row| row.merge(url: admin_mind_graph_path(row[:kind] => row[:record_id], **admin_url_options)) }
    end

    private

    def require_graph_access
      forbidden! unless can?("pages.read") || can?("posts.read")
    end

    # A scheduled change's day as CS Studio writes a short date ("14 Oct"),
    # for the card's chip (pages spec §7, design answer G4). Wording, so it
    # is put on HERE: the queries hand up the time (`change_at`) and no words.
    # `nodes` and `pages` are the graph's, `rows` the list's two reads'; an
    # answer that holds none of them (`open`) is left as it is.
    def with_dates(answer)
      answer.merge(answer.slice(:nodes, :pages, :rows).transform_values { |nodes| nodes.map { |node| dated(node) } })
    end

    def dated(node)
      node[:change_at] ? node.merge(change_on: I18n.l(node[:change_at], format: :"admin.short")) : node
    end

    def editor_url
      ->(record) { record.is_a?(Page) ? admin_page_path(record, **admin_url_options) : admin_post_path(record, **admin_url_options) }
    end
  end
end
