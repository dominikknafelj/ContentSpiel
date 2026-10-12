require "test_helper"
require Rails.root.join("db/migrate/20261011121000_add_listed_on_to_public_paths").to_s

# The migration fills the recorded host from the rows themselves (a post's
# path is its host's path plus one segment), with no application class. What
# it writes must be what the application writes.
class AddListedOnToPublicPathsMigrationTest < ActiveSupport::TestCase
  def hosts = PublicPath.current.order(:id).pluck(:id, :listed_on_id)

  test "the fill gives every post's current row the host the application records, the homepage's teaser included, and no page's row one" do
    root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    root.content_blocks.create!(block_type: "post_list", settings: { "content_type" => "now_update" })
    blog = Page.create!(title: "Blog", parent: root, published_at: 1.day.ago)
    blog.content_blocks.create!(block_type: "post_list", settings: { "content_type" => "blog" })
    Post.create!(title: "Hello", content_type: "blog", published_at: 1.day.ago)
    Post.create!(title: "Now", content_type: "now_update", published_at: 1.day.ago)
    written = hosts
    assert_equal [ blog.id, root.id ].sort, written.filter_map(&:last).uniq.sort

    PublicPath.update_all(listed_on_id: nil) # version: none (a test empties the column the migration fills)
    ActiveRecord::Migration.suppress_messages { AddListedOnToPublicPaths.new.fill }

    assert_equal written, hosts
  end
end
