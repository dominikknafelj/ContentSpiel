module SiteSearch
  # The state of one backend's index (search spec §6.6): one row per
  # backend, written by the build alone (`SiteSearch::Rebuild`).
  #
  # The index is EMPTY when the backend in use has no row, and STALE when
  # its row is not `ready` with today's fingerprint: a digest of what the
  # documents are made from besides the copies. Copies taken since are
  # indexed as they are taken (`SiteSearch::Indexing`), so they never make
  # it stale. A row is marked `building` with no fingerprint, so a build
  # that dies half way is stale for the next check, whatever its
  # fingerprint would have been.
  class IndexState < ApplicationRecord
    self.table_name = "search_index_states"

    # A build is not expected to take longer; a row left `building` past it
    # with no job at work is a job that died (System status, spec §10).
    STALLED_AFTER = 1.hour

    BUILDING = "building".freeze
    READY = "ready".freeze

    class << self
      def for(name) = find_by(backend: name.to_s)

      # SHA-256 of the enabled languages, each with its fallback chain (by
      # which a document's every field is read), `Documents::REVISION` and,
      # for the built-in, `Postgres::CONFIGS` (the configuration each
      # language's words are stemmed with) and `Postgres::REVISION` (what the
      # built-in stores of a document), and the switched-on post types (a
      # type's posts have no documents while it is off, so a switch moves
      # what the index holds without a copy being taken). The languages are
      # sorted: the documents are one per language, so their order moves
      # nothing that the chains do not already say.
      def fingerprint(name, site: Current.site)
        parts = { "languages" => languages(site), "revision" => Documents::REVISION, "content_types" => ::ContentTypes.switched_on_names(site: site) }
        parts.merge!("configs" => Postgres::CONFIGS, "postgres_revision" => Postgres::REVISION) if name.to_s == Backends::BUILT_IN
        Digest::SHA256.hexdigest(JSON.generate(parts))
      end

      # Each enabled language's fallback chain, by code: the part of the
      # fingerprint a language service can move, which it compares before
      # and after its change to decide whether to ask for a rebuild
      # (`SiteSearch::Indexing.languages_changed`). The post types have no such
      # method: `Settings::Save` asks for the build after a switch.
      def languages(site = Current.site) = site.locale_codes.sort.index_with { |code| Locales.fallback_chain(code, site: site) }

      def empty_or_stale?(name, site: Current.site)
        state = self.for(name)
        state.nil? || !state.ready? || state.fingerprint != fingerprint(name, site: site)
      end

      # The row of `name`, marked `building` from nothing done of `total`;
      # its `languages` stay those of the last finished build.
      def start!(name, total:, now: Time.current)
        upsert({ backend: name.to_s, status: BUILDING, fingerprint: nil, done: 0, total: total, started_at: now, finished_at: nil }, unique_by: :backend) # version: none (the search index is no part of a page: results are never cached, §8.1)
        self.for(name)
      end
    end

    def ready? = status == READY

    def building? = status == BUILDING

    # A build left `building` for over `STALLED_AFTER` while no job runs.
    def stopped?(now:, job_running:)
      building? && started_at.present? && started_at < now - STALLED_AFTER && !job_running
    end

    def progress!(done)
      update_columns(done: done) # version: none (the search index is no part of a page: results are never cached, §8.1)
    end

    # `languages`: the languages the build indexed, from which the next
    # build knows which were switched off since (`Rebuild`).
    def ready!(fingerprint, languages:, done:, now: Time.current)
      update_columns(status: READY, fingerprint: fingerprint, languages: languages, done: done, finished_at: now) # version: none (the search index is no part of a page: results are never cached, §8.1)
    end
  end
end
