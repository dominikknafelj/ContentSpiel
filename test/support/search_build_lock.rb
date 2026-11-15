# Holds the advisory lock of a search build (`SiteSearch::Rebuild`) for a
# backend from a connection of its own, as a build in another process
# would, for the block's length. Not through the pool: a transactional
# test's pool hands every thread the one pinned connection.
module SearchBuildLock
  def holding_build_lock(name)
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    other = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username],
      password: config[:password], gssencmode: "disable")
    key = [ SiteSearch::Rebuild::ADVISORY_NAMESPACE, Zlib.crc32(name) % SiteSearch::Rebuild::INT4 ]
    other.exec_params("SELECT pg_advisory_lock($1, $2)", key)
    yield
  ensure
    # Let go before closing: the server ends the closed session, and its
    # locks with it, only some time after.
    other&.exec_params("SELECT pg_advisory_unlock($1, $2)", key)
    other&.close
  end
end
