module SiteSearch
  class Postgres
    # A database that falls short of ContentSpiel's requirements
    # (`SiteSearch::Postgres::Requirements`): its message is
    # `Requirements.message_for`, which names what is missing, the cause by
    # the error's class or in words, never a database's own message (which
    # can hold the server's address), and the section of hosting.md to read.
    class DatabaseRequirementMissing < StandardError
    end
  end
end
