# Custom Avo tool (bin/rails generate avo:tool pages_tree) rather than
# widening any resource controller -- both actions here already inherit
# Avo::ApplicationController's session gate, the same one every other
# /avo route is behind.
class Avo::ToolsController < Avo::ApplicationController
  # The page tree waives Avo's native drag-and-drop (an avo-record_reordering
  # add-on, paid) for a hand-built one: the whole tree, rendered once and
  # dragged client-side via Stimulus + vendored SortableJS.
  def pages_tree
    @page_title = "Pages tree"
    add_breadcrumb title: "Pages tree"

    # Exactly one page has no parent (Page's own only_one_root_page
    # validation) -- if that invariant is ever somehow violated, showing
    # nothing beats raising on `.find_by(parent_id: nil).first` ambiguity.
    @root = Page.find_by(parent_id: nil)
  end

  # What a drop actually persists: the dragged page's new parent and its
  # rank among its new siblings. Both go through Page's existing
  # validations exactly as the page's own edit form would -- an invalid
  # move (e.g. dropping a page onto its own descendant, which closure_tree
  # itself rejects) comes back as a normal `errors` failure, not a crash,
  # and the client-side controller re-renders the tree from the server
  # rather than trusting its own guess of what happened.
  def reorder_page
    page = Page.find(params[:page_id])

    if page.update(parent_id: params[:parent_id].presence, position: params[:position])
      render json: { ok: true }
    else
      render json: { ok: false, errors: page.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # Post nodes + PostRelation edges (design spec section 9), handed to the
  # client as JSON on the container element -- the mind-graph Stimulus
  # controller owns everything about how they're drawn and dragged. Nodes and
  # edges are computed here rather than left to the view for the same reason
  # #pages_tree's @root query is: what data the page needs is a controller
  # concern, not something a template should be querying for itself.
  def mind_graph
    @page_title = "Mind graph"
    add_breadcrumb title: "Mind graph"

    @nodes = Post.find_each.map do |post|
      {
        id: post.id,
        title: post.title,
        contentType: post.content_type,
        editUrl: avo.edit_resources_post_path(post)
      }
    end

    # One PostRelation row is one edge: rows are stored directionally but
    # read as undirected everywhere (page-tree design spec section 4), and
    # PostRelation's own validation already keeps the reverse pair from ever
    # existing alongside it -- nothing here needs to de-duplicate.
    @edges = PostRelation.pluck(:post_id, :related_post_id).map do |post_id, related_post_id|
      { source: post_id, target: related_post_id }
    end
  end

  # The same read-only checks the setup wizard runs (Setup::SystemCheck).
  def system_status
    @page_title = "System status"
    add_breadcrumb title: "System status"
    @results = Setup::SystemCheck.run
  end
end
