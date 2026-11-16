module ContentTypes
  # An ordinary blog post (spec §3.1): no fields of its own beyond the
  # existing `title`/`slug`/`excerpt`/`body` columns every post has.
  module Blog
    def self.register
      ContentTypes.register :blog do |t|
        t.label "Blog"
        t.description :blog
        t.list_component Posts::BlogListComponent, theme_methods: %w[posts page]
        t.detail_component Posts::DetailComponent, theme_methods: %w[post]

        # The sample is the starter content's post (`db/seeds.rb` / the setup
        # wizard, via `Posts::Save`) and the shared tests' post.
        t.sample title: "Hello, world", excerpt: "The first post on this site.",
                 body: "This is a sample blog post. Edit or delete it in the admin.",
                 shows: [ "Hello, world" ]
        t.starter section: { title: "Blog", slug: "blog" }
      end
    end
  end
end
