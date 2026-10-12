require "test_helper"
require "tmpdir"

# Nothing public reads a content column of a published record's rows (drafts
# spec §5 and §7). THIS IS THE SOURCE GUARD: it knows where a public reader
# GETS its records and refuses a line that reaches rows without saying why
# the rows are right there. `test/integration/public_canary_test.rb` is the
# guard that really holds: it asks the site, and fails for any reader that
# shows rows, however it got them. What a source grep cannot see: a record
# handed in from elsewhere (an argument, an instance variable, a block
# variable), a class reached through a variable (`klass.kept`, `send(:where)`),
# a relation built in a model or a query and only walked here, and a column
# read through `public_send`. Those are the canary's.
#
# WHAT IS SCANNED IS DERIVED, so a new file is scanned the day it appears:
#   - every controller under `app/controllers` that descends from
#     `PublicController`, and the concerns they include;
#   - the views of those controllers, the layouts, `app/views/shared` and
#     `app/views/layouts/public`;
#   - every helper under `app/helpers` outside `admin/` (a helper must be
#     classified below: public, or named as admin/setup with a reason);
#   - `app/components/{blocks,posts,public,rich_text}` and every other
#     component those files, the block and content type definitions and
#     `config/initializers/rich_text.rb` name, transitively (never an
#     `Admin::` one);
#   - `config/sitemap.rb`, and the models and queries listed in EXTRA.
# A controller or a helper that is not classified fails the test, so
# somebody has to decide.
#
# A LINE IS EXEMPT ONLY BY A MARK ON IT: `# public: rows (why)` (in ERB
# `<% ... # public: rows (why) %>`), the why at least ten characters. Going
# through `Publishing.` on the line is NOT an exemption: a relation started
# from rows and handed to `Publishing.published_all` is still a line that
# says which rows are listed, and that choice is the author's to explain.
#
# A NEW PUBLIC LIST, SEARCH OR FEED: read content through
# `Publishing.published` / `published_all` / `Publishing::Listing`; put the
# page or file in the canary test if it has a route of its own; mark the
# lines whose rows are right (an address, the tree, whether a record is
# visible at all, the preview).
class PublicReadersTest < ActiveSupport::TestCase
  # Controllers that are not public readers, each with why.
  NOT_PUBLIC_CONTROLLERS = {
    "application_controller.rb" => "the base of CS Studio and setup",
    "component_previews_controller.rb" => "development previews of components",
    "mcp_controller.rb" => "the token-guarded MCP endpoint, not the public site",
    "setup_controller.rb" => "the setup wizard",
    "preview_controller.rb" => "the preview shows the working version by design; the concern it shares is scanned"
  }.freeze

  # Helpers: public ones are scanned, the others say why not.
  NOT_PUBLIC_HELPERS = {
    "app/helpers/access_control_helper.rb" => "CS Studio's permission checks",
    "app/helpers/setup_helper.rb" => "the setup wizard"
  }.freeze

  # Read on behalf of the public site although they are models or queries.
  EXTRA = %w[
    config/sitemap.rb
    app/models/public_site/resolver.rb
    app/models/public_site/urls.rb
    app/queries/publishing/listing.rb
    app/queries/public_site/branch.rb
  ].freeze

  # Folders of components that are public readers whether or not a template
  # names them yet.
  COMPONENT_FOLDERS = %w[blocks posts public rich_text].freeze

  # Files that name the components the public draws without a template doing so.
  REGISTRIES = %w[app/models/block_types app/models/content_types config/initializers/rich_text.rb].freeze

  CLASSES = /\b(?:Page|Post|ContentBlock|Tag|PostTag)\.(?!polymorphic_name|name\b|model_name|human|table_name|column_names|columns|statuses|page_types)\w+/
  WALKS = /\.(?:owner|parent|ancestors|self_and_ancestors|self_and_descendants|siblings|descendants|children|record|posts|listed_posts|canonical_pages?|title_matching\w*)\b|\.content_blocks\.(?!to_a\b)\w+|\bcanonical_pages?\(/
  ROWS = Regexp.union(CLASSES, WALKS)
  MARK = /public:\s*rows\s*\((?<reason>[^)]*)\)/

  def self.root = Rails.root

  def self.relative(path) = path.to_s.delete_prefix("#{root}/")

  def self.glob(pattern) = root.glob(pattern).map { |path| relative(path) }.sort

  def self.public_controllers
    glob("app/controllers/*.rb").select { |path| root.join(path).read.match?(/<\s*PublicController\b/) }
  end

  def self.controller_classification_gaps
    (glob("app/controllers/*.rb") - public_controllers - [ "app/controllers/public_controller.rb" ]).reject { |path| NOT_PUBLIC_CONTROLLERS.key?(File.basename(path)) }
  end

  def self.helper_classification_gaps
    glob("app/helpers/*.rb").reject { |path| NOT_PUBLIC_HELPERS.key?(path) || path == "app/helpers/application_helper.rb" || public_helpers.include?(path) }
  end

  # A helper that is not named above is public; the ones named are not.
  def self.public_helpers = glob("app/helpers/*.rb").reject { |path| NOT_PUBLIC_HELPERS.key?(path) }

  def self.seed_files
    controllers = public_controllers + [ "app/controllers/public_controller.rb" ]
    included = controllers.flat_map { |path| root.join(path).read.scan(/^\s*include\s+([A-Z]\w*)/).flatten.map { |name| "app/controllers/concerns/#{name.underscore}.rb" } }
    views = controllers.flat_map { |path| glob("app/views/#{File.basename(path, '_controller.rb')}/**/*.{erb,rb}") }
    layouts = glob("app/views/layouts/application.html.erb") + glob("app/views/layouts/public/**/*.erb") + glob("app/views/shared/**/*.erb")
    components = COMPONENT_FOLDERS.flat_map { |folder| glob("app/components/#{folder}/**/*.rb") }
    (controllers + included.select { |path| File.exist?(root.join(path)) } + views + layouts + public_helpers + components + EXTRA).uniq
  end

  def self.component_files(names)
    names.filter_map do |name|
      next if name.start_with?("Admin::")

      path = "app/components/#{name.underscore}.rb"
      path if File.exist?(root.join(path))
    end
  end

  # The scanned set: the seeds and every component they name, transitively.
  def self.files
    registries = REGISTRIES.flat_map { |path| File.directory?(root.join(path)) ? glob("#{path}/**/*.rb") : [ path ] }
    files = seed_files
    pending = files + registries
    until pending.empty?
      names = pending.shift(pending.size).flat_map { |path| root.join(path).read.scan(/\b(?:[A-Z]\w*::)*[A-Z]\w*Component\b/) }.uniq
      fresh = component_files(names) - files
      files += fresh
      pending = fresh
    end
    files.sort
  end

  def self.offences(path, source)
    source.each_line.with_index(1).filter_map do |line, number|
      stripped = line.strip
      next if stripped.start_with?("#") || stripped.start_with?("<%#")
      next unless line.match?(ROWS)

      mark = line.match(MARK)
      "#{path}:#{number}: #{stripped}" unless mark && mark[:reason].strip.size >= 10
    end
  end

  test "every controller and helper is classified: public, or named with its reason" do
    assert_empty self.class.controller_classification_gaps, "a controller that is not a PublicController: add it to NOT_PUBLIC_CONTROLLERS with the reason, or make it one"
    assert_empty self.class.helper_classification_gaps
    NOT_PUBLIC_CONTROLLERS.each_key { |name| assert File.exist?(Rails.root.join("app/controllers", name)), "#{name} is gone: remove it from NOT_PUBLIC_CONTROLLERS" }
    NOT_PUBLIC_HELPERS.each_key { |path| assert File.exist?(Rails.root.join(path)), "#{path} is gone: remove it from NOT_PUBLIC_HELPERS" }
  end

  test "the scanned set is derived and holds what the public draws" do
    files = self.class.files

    %w[app/controllers/pages_controller.rb app/controllers/concerns/public_page_rendering.rb app/views/pages/show.html.erb
       app/views/layouts/application.html.erb app/helpers/theme_helper.rb app/components/blocks/post_list_component.rb
       app/components/media/picture_component.rb config/sitemap.rb app/queries/publishing/listing.rb app/queries/public_site/branch.rb].each do |path|
      assert_includes files, path
    end
    assert_empty files.grep(%r{\Aapp/components/admin/|\Aapp/controllers/admin/|\Aapp/views/admin/})
    assert_not_includes files, "app/controllers/preview_controller.rb"
  end

  test "every public reader reaches a published record through its copy, or says on the line why the rows are right" do
    offences = self.class.files.flat_map { |path| self.class.offences(path, Rails.root.join(path).read) }

    assert_empty offences, <<~MESSAGE
      These lines of the public site read rows. Content of a published record comes from its
      copy (`Publishing.published`, `published_all`, `Publishing::Listing`). Where the rows are
      right (an address, the tree, whether a record is visible at all, the preview), end the
      line with `# public: rows (why)`; going through `Publishing.` on the line is not enough.
    MESSAGE
  end

  test "it fails for a line that reads rows, however it starts, and only a mark with a reason lets it pass" do
    fails = lambda do |line|
      assert_equal 1, self.class.offences("x", "#{line}\n").size, "#{line.inspect} was not refused"
    end
    [ "<% children = @page.children.kept.published.to_a %>",
      "Post.includes(:tags).where(published_at: ..Time.current)",
      "Post.joins(:tags).distinct",
      "Post.limit(20)",
      "Post.unscoped.find_each { |post| draw(post) }",
      "Post.title_matching(params[:q], locale: I18n.locale)",
      "Page.where(parent_id: nil).first",
      "Tag.find_by(name: params[:tag]).posts.each { |post| draw(post) }",
      "@page.ancestors.each { |page| crumb(page.title) }",
      "<%= @page.parent.title %>",
      "@page.siblings.map(&:title)",
      "pages = top.self_and_descendants.kept.published.to_a",
      "block.owner.title",
      "PublicPath.current.each { |row| row.record.title }",
      "page.content_blocks.listing.any?",
      "page.content_blocks.where(block_type: 'image')",
      "posts = block.listed_posts.order(published_at: :desc)",
      "Publishing.published_all(@page.children.kept.published)",
      "Post.kept.published.select { |post| post.excerpt.present? }.map(&:title)"
    ].each(&fails)

    assert_empty self.class.offences("x", "@theme_root_page = Page.find_by(parent_id: nil) # public: rows (only its address and its children are read)\n")
    assert_empty self.class.offences("x", "<% pages = @page.children.kept # public: rows (the tree is the rows') %>\n")
    assert_equal 1, self.class.offences("x", "Post.published.kept.each { |post| draw(post) } # public: rows ()\n").size
    assert_equal 1, self.class.offences("x", "Post.published.kept.each { |post| draw(post) } # public: rows (short)\n").size
    assert_empty self.class.offences("x", "BlockOutline.new(page.content_blocks.to_a)\n")
    assert_empty self.class.offences("x", "<%# The page's .children are read above %>\n")
    assert_empty self.class.offences("x", "# Post.kept is explained here\n")
    assert_empty self.class.offences("x", "Page.polymorphic_name\n")
  end

  test "it can see a new reader: a controller, a view and a component the guard was not told about" do
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      root.join("app/views/feeds").mkpath
      root.join("app/views/feeds/index.html.erb").write("<% Post.kept.each { |post| post.title } %>\n")
      source = root.join("app/views/feeds/index.html.erb").read

      assert_equal 1, self.class.offences("app/views/feeds/index.html.erb", source).size
    end
    seeds = self.class.seed_files
    assert_equal seeds, seeds.uniq
    assert_includes self.class.files, "app/components/media/picture_component.rb", "a component a public file names is reached through the closure, not by a list"
  end
end
