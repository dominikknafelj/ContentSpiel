# A response that says `no-store` leaves with no ETag.
#
# `Rack::ETag`, in Rails' default stack, digests the body of every 200 that
# has no ETag of its own and writes the digest as a weak one, whatever the
# response's `Cache-Control`. On a `no-store` response that ETag serves no
# cache (none may keep the response to revalidate it), and for a page asked
# with a search query (`PublicPageRendering#answer_search_privately`,
# search spec §8.1) it is a digest of a body that holds the query. This
# middleware stands between `Rack::ConditionalGet` and `Rack::ETag`
# (`config/application.rb`), so it takes the header off before the
# conditional GET reads it: such a response is never answered 304 either.
#
# In lib/ and required from config/application.rb, which inserts it while
# the application is configured, before autoloading is set up.
module ContentSpiel
  class NoStoreWithoutEtag
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers.delete("etag") if headers["cache-control"].to_s.split(",").map(&:strip).include?("no-store")
      [ status, headers, body ]
    end
  end
end
