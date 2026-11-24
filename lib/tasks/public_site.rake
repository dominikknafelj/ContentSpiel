namespace :public_site do
  desc "Move the public content version by hand, so every cached page and ETag is retired (after a console change or raw SQL)"
  task bump_version: :environment do
    PublicSite.bump_version!
    puts "Public content version: #{PublicSite::Version.current}"
  end

  desc "After a restored backup: jump the public content version past every value it had before and empty the cache (then purge the CDN, if one is in front)"
  task after_restore: :environment do
    puts "Public content version: #{PublicSite.after_restore!}"
    puts "Cache cleared. If a CDN caches the site's pages, purge it now."
  end
end
