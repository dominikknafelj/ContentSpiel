// A node's id (pages spec, decision 4): its kind and its database id,
// "post-12", "tag-3", "page-7", and a post type's stored name, "type-blog".
// The server writes them (`PostGraph.node_id`); the page never takes one
// apart except here, where a URL template or a notes key needs the record's
// own id back.
export const nodeId = (kind, id) => `${kind}-${id}`

// What follows the kind: "12" for "post-12", "blog" for "type-blog". A type's
// name may hold a dash or a slash of its own ("owner/thing"), so only the
// FIRST dash is the separator.
export function recordId(id) {
  const text = String(id)
  return text.slice(text.indexOf("-") + 1)
}

// The one node that has no record: what a list block with no filter points
// at (`PostGraph::ALL_POSTS`). Its id is named here and nowhere else in the
// scripts (`test/lib/mind_graph_guards_test.rb`).
export const ALL_POSTS = "all-posts"
