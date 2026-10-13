# Builds a page tree in DEVELOPMENT for measuring the mind graph with pages
# (pages in the mind graph, spec "Testing": 200 pages and 2,000 posts).
# Through `Pages::Save` and `ContentBlocks::Save`, like the seeds, so the
# closure rows, the addresses and the copies are what a real site holds.
#
# Run it against a throwaway database, never the one you work in
# (`DATABASE_URL` overrides `config/database.yml`; take the user and the port
# from there), after the posts script, whose tags it lists:
#
#   export DATABASE_URL=postgres://<user>:<password>@localhost:5433/content_spiel_graph_probe
#   SKIP_TEST_DATABASE=1 bin/rails db:prepare db:seed
#   bin/rails runner script/dev/mind_graph_posts.rb 2000
#   bin/rails runner script/dev/mind_graph_pages.rb 200
#
# Shape: Home, eight sections under it, every later page under one of the
# first sixty. Every third page has a post-list block: by one of the
# measurement's tags ("graph-tag-N", the posts script's), by the "blog"
# type, or by nothing, in turn. Deterministic and safe to run again: a page
# is found by its title.
#
# The measurement itself (2026-10-13) is in the spec's "As built":
# `docs/superpowers/specs/2026-10-12-pages-in-the-mind-graph-design.md`.
abort "development only" unless Rails.env.development?

count = Integer(ARGV.fetch(0, "200"))
locale = Locales.default.to_s
home = Page.find_by(parent_id: nil) || Pages::Save.call(attributes: { published: true }, translations: { locale => { title: "Home", slug: "" } }).record
pages = [ home ]

(1...count).each do |number|
  title = "Graph page #{number}"
  parent = number <= 8 ? home : pages[1 + ((number * 7) % [ pages.size - 1, 60 ].min)]
  page = Page.kept.title_matching(title, locale: locale).find { |found| found.title == title }
  unless page
    result = Pages::Save.call(attributes: { parent: parent, published: number % 9 != 0 }, translations: { locale => { title: title } })
    abort "#{title}: #{result.errors.to_sentence}" unless result.ok?
    page = result.record
    if (number % 3).zero?
      settings = [ { "tag" => "graph-tag-#{number % 60}" }, { "content_type" => "blog" }, {} ][(number / 3) % 3]
      saved = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: settings })
      abort "#{title}: #{saved.errors.to_sentence}" unless saved.ok?
    end
  end
  pages << page
  puts "#{number + 1} / #{count}" if ((number + 1) % 50).zero?
end
