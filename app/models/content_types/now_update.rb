module ContentTypes
  # A short "what I'm doing now" update (spec §3.1): no fields of its own
  # beyond the existing `title`/`body` columns every post has -- the public
  # listing only ever shows the latest one.
  module NowUpdate
    def self.register
      ContentTypes.register :now_update do |t|
        t.label "Now update"
        t.list_component Posts::NowListComponent
        t.detail_component Posts::DetailComponent

        t.starter section: { title: "Now", slug: "now" },
          sample: { title: "What I'm doing now", body: "Share what you're focused on at the moment." }
      end
    end
  end
end
