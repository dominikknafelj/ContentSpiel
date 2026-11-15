module SiteSearch
  # Takes out of the built-in's vocabulary the words no entry holds any
  # more (`Postgres::Vocabulary.prune`, search 2 spec §3.2), enqueued by
  # `SiteSearch::Indexing` after the commit of a purge and of a withdrawn
  # copy, whose entries went with their copies (the cascade). So a purged
  # record's words are no candidate past this job's run.
  #
  # One at a time: a prune reads every word, and two side by side would
  # probe the same index twice for nothing. A job enqueued while one runs
  # waits for it (Solid Queue's default, `:block`) rather than being
  # discarded, since the running one may have read a word before the purge
  # behind the waiting one committed.
  class PruneWordsJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 1, key: "site_search_prune_words"

    def perform
      Postgres::Vocabulary.prune
      nil
    end
  end
end
