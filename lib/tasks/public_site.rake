namespace :public_site do
  desc "Move the public content version by hand, so every cached page and ETag is retired (after a console change, raw SQL or a restored backup)"
  task bump_version: :environment do
    PublicSite.bump_version!
    puts "Public content version: #{PublicSite::Version.current}"
  end
end
