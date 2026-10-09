# Builds a large, connected set of posts in DEVELOPMENT for measuring the mind
# graph (mind graph canvas spec §7). Through `Posts::Save`, like the seeds, so
# every derived row is what a real site would hold.
#
#   bin/rails runner script/dev/mind_graph_posts.rb 2000
#
# Run it against a throwaway database, not the one you work in: it leaves
# thousands of posts behind. `DATABASE_URL` overrides `config/database.yml`:
#
#   export DATABASE_URL=postgres://contentspiel:contentspiel@localhost:5433/content_spiel_measure
#   bin/rails db:prepare db:seed
#   bin/rails runner script/dev/mind_graph_posts.rb 6000
#   bin/rails server -p 3001
#
# Shape: a few hubs, many posts with one to three links, a tail with none; 60
# tags, some very common. Deterministic and safe to run again: the titles are
# numbered ("Graph post 17"), every number's draws are taken from the one
# fixed-seed sequence whether or not its post is written, and a run adds only
# the numbers that are missing -- so 2,000 and then 6,000 gives the same site
# as 6,000 at once.
#
# Outside a request `Current.actor` and `Current.channel` are both nil, which
# the access checker trusts (`Current`), exactly as the seeds rely on.
abort "development only" unless Rails.env.development?

count = Integer(ARGV.fetch(0, "2000"))
random = Random.new(20261007)
tags = Array.new(60) { |index| "graph-tag-#{index}" }
locale = Locales.default.to_s
prefix = "Graph post "

# number => id of the posts an earlier run wrote. `title` is plucked raw: the
# jsonb of { locale => text }.
ids = Post.title_matching(prefix, locale: locale).pluck(:id, :title).filter_map do |id, title|
  text = title[locale].to_s
  [ Integer(text.delete_prefix(prefix), exception: false), id ] if text.start_with?(prefix)
end.to_h
ids.delete(nil)

count.times do |number|
  # Preferential attachment: an earlier post is the likelier target the lower
  # its number, which is what makes hubs. The draws are made for every number,
  # also one that exists, so the sequence does not depend on what is there.
  linked = number >= 3 && random.rand >= 0.2
  targets = linked ? Array.new(random.rand(1..3)) { (random.rand**3 * number).floor } : []
  tagged = random.rand >= 0.3
  names = tagged ? Array.new(random.rand(1..3)) { tags[(random.rand**2 * tags.size).floor] }.uniq : []
  published = random.rand < 0.8
  next if ids.key?(number)

  result = Posts::Save.call(
    attributes: { content_type: "blog", published: published, tag_names: names, related_post_ids: targets.uniq.map { |target| ids.fetch(target) } },
    translations: { locale => { title: "#{prefix}#{number}" } }
  )
  abort "Graph post #{number}: #{result.errors.to_sentence}" unless result.ok?

  ids[number] = result.record.id
  puts "#{number + 1} / #{count}" if ((number + 1) % 250).zero?
end
