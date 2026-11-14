namespace :search do
  # The build `SiteSearch::ReindexJob` runs (spec §6.5), in the foreground:
  # the job builds the index by itself when it is empty or stale, so this is
  # for by-hand use (a build that stopped, System status's command). While
  # another build of the same backend runs (the job's), it builds nothing
  # and says so.
  desc "Build the search index of the backend in use, in the foreground"
  task reindex: :environment do
    name = SiteSearch::Backends.current_name
    count = SiteSearch::Rebuild.new.call
    puts "search:reindex: #{count} record(s) indexed by #{SiteSearch::Backends.label(name)} (#{name})"
  rescue SiteSearch::Rebuild::Busy => error
    abort "search:reindex: #{error.message}; nothing was built. Try again when it has finished."
  end
end
