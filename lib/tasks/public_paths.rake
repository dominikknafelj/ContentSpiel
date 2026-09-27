namespace :public_paths do
  desc "Rebuild every public URL from slugs and the page tree"
  task rebuild: :environment do
    PublicSite::Paths.rebuild!
  end
end
