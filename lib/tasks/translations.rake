namespace :translations do
  desc "Recompute the stored translation state of every page, post, image and the site settings"
  task reindex: :environment do
    Translations::StateIndex.rebuild_all
    puts "Reindexed #{Translations::State.count} translation state rows."
  end
end
