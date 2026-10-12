require "test_helper"

# Nothing public reads a content column of a published record's rows (drafts
# spec §5 and §7). What a test can hold of that is where a public reader GETS
# its records: every file that draws the public site is listed here, and
# every line in one that reaches rows either goes through the copy on that
# line or says why the rows are right there. What it cannot see is a record
# handed in from elsewhere: `test/integration/public_drafts_test.rb` holds
# the behaviour, reader by reader.
#
# A NEW PUBLIC LIST, SEARCH OR FEED belongs in READERS (or in a folder of
# FOLDERS), in `test/integration/public_drafts_test.rb` (rows change, response
# stays) and in `test/integration/trash_visibility_test.rb`. Read its content
# through `Publishing.published` / `published_all` (or the helper that wraps
# them); where the rows really are right (an address, the tree, whether a
# record is visible at all, the preview) end the line with
# `# public: rows (why)`.
class PublicReadersTest < ActiveSupport::TestCase
  READERS = {
    "app/controllers/pages_controller.rb" => "the record through as_published",
    "app/controllers/public_controller.rb" => "reads no record",
    "app/controllers/concerns/public_page_rendering.rb" => "shared with the preview: records through as_published, list judgements through lists_post?",
    "app/models/public_site/resolver.rb" => "addresses and visibility are the rows'; the listing fallback asks the copies",
    "app/helpers/theme_helper.rb" => "menus through the copies",
    "app/helpers/pages_helper.rb" => "reads what it is handed",
    "app/views/layouts/application.html.erb" => "reads no record",
    "config/sitemap.rb" => "addresses and visibility from the rows, the date from the copy"
  }.freeze

  # Every file under these is a reader too, without being named.
  FOLDERS = %w[app/views/pages app/views/layouts/public app/components/blocks app/components/posts].freeze

  ROWS = /
    \b(?:Page|Post|ContentBlock)\.(?:find|find_by|where|kept|published|i18n|all|listing|order)\b
    | \.content_blocks\.(?!to_a\b)\w+
    | \.listed_posts\b | \.children\b | \.self_and_ancestors\b | \bcanonical_pages?\b
  /x
  COPY = /\bPublishing\.|\bpublished_views\(|\bas_published\(/
  MARK = /public:\s*rows\s*\((?<reason>[^)]*)\)/

  def self.files
    folders = FOLDERS.flat_map { |folder| Rails.root.glob("#{folder}/**/*.{rb,erb}").map { |path| path.to_s.delete_prefix("#{Rails.root}/") } }
    (READERS.keys + folders).uniq.sort.select { |path| File.exist?(Rails.root.join(path)) }
  end

  def self.offences(path, source)
    source.each_line.with_index(1).filter_map do |line, number|
      next if line.strip.start_with?("#") && !line.match?(MARK)
      next unless line.match?(ROWS)
      next if line.match?(COPY)

      mark = line.match(MARK)
      "#{path}:#{number}: #{line.strip}" unless mark && mark[:reason].strip.size >= 10
    end
  end

  test "every public reader reaches a published record through its copy, or says on the line why the rows are right" do
    offences = self.class.files.flat_map { |path| self.class.offences(path, Rails.root.join(path).read) }

    assert_empty offences, <<~MESSAGE
      These lines of the public site read rows. Content of a published record comes from its
      copy: go through `Publishing.published`, `published_views(…)` or `as_published(…)` on the
      line. Where the rows are right (an address, the tree, whether a record is visible at all,
      the preview), end the line with `# public: rows (why)`.
    MESSAGE
  end

  test "every named reader exists" do
    READERS.each_key { |path| assert File.exist?(Rails.root.join(path)), "READERS names #{path}, which is gone" }
  end

  test "it fails for a reader that reads a row, and passes for the same line through the copy or with its reason" do
    row = %(<% children = @page.children.kept.published.to_a %>\n)

    assert_equal 1, self.class.offences("app/views/pages/show.html.erb", row).size
    assert_empty self.class.offences("x", %(<% children = published_views(@page.children.kept.published) %>\n))
    assert_empty self.class.offences("x", %(@theme_root_page = Page.find_by(parent_id: nil) # public: rows (only its address and its children are read)\n))
    assert_equal 1, self.class.offences("x", %(Post.published.kept.each { |post| draw(post) } # public: rows ()\n)).size
    assert_equal 1, self.class.offences("x", %(posts = block.listed_posts.order(published_at: :desc)\n)).size
    assert_equal 1, self.class.offences("x", %(page.content_blocks.listing.any?\n)).size
    assert_empty self.class.offences("x", %(BlockOutline.new(page.content_blocks.to_a)\n))
  end
end
