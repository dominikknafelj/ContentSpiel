module ContentTypes
  # An ordinary blog post (spec §3.1): no fields of its own beyond the
  # existing `title`/`slug`/`excerpt`/`body` columns every post has.
  module Blog
    def self.register
      ContentTypes.register :blog do |t|
        t.label "Blog"
        t.list_component Posts::BlogListComponent
        t.detail_component Posts::DetailComponent

        # Moved from the old `StarterContent::SECTIONS` entry verbatim: the
        # section page this type's sample post seeds into, and the sample
        # itself (`db/seeds.rb` / the setup wizard, via `Posts::Save`).
        t.starter section: { title: "Blog", slug: "blog" },
          sample: { title: "Hello, world", excerpt: "The first post on this site.",
                     body: "This is a sample blog post. Edit or delete it in the admin." }
      end
    end
  end
end
