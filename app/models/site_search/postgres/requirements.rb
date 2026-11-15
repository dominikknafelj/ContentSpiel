module SiteSearch
  class Postgres
    # What ContentSpiel asks of its database beyond Postgres 15 and
    # `plpgsql`, which the schema load itself holds (docs/reference/hosting.md,
    # "Database requirements"): the extension `pg_trgm`, which close matches
    # and the correction use, and a UTF-8 character type, without which
    # `pg_trgm` drops every letter outside ASCII (`show_trgm('日本語の検索')`
    # is `{}` on a `C` database). Held in three places with one message: the
    # migration that enables the extension (`enable!`), every schema load
    # (`DbTriggers::AfterSchemaLoad`), and the boot of a process that serves
    # (`check_at_boot`), for a database changed under a running site (a dump
    # restored without the extension, a `DROP EXTENSION`), which would
    # otherwise answer every search with no exact hit as unavailable.
    #
    # The probe tests what matters, `pg_trgm` on a letter outside ASCII,
    # rather than the name in `datctype`: ICU locales and `C.UTF-8` pass.
    module Requirements
      module_function

      DOCS_HEADING = "Database requirements".freeze
      EXTENSIONS = %w[plpgsql pg_trgm].freeze

      def enable!(connection)
        begin
          connection.enable_extension("pg_trgm")
        rescue ActiveRecord::StatementInvalid => error
          raise DatabaseRequirementMissing, message_for(missing: "pg_trgm", cause: error.class.name)
        end
        check_character_type!(connection)
      end

      def check!(connection = ActiveRecord::Base.connection)
        raise DatabaseRequirementMissing, message_for(missing: "pg_trgm", cause: "it is not installed in this database") unless installed?(connection)

        check_character_type!(connection)
      end

      # In a process that serves (`SiteSearch::BootCheck.serving?`), once
      # `search_words` is there: while the migration that made it is
      # pending, the migration holds the requirement. A database that does
      # not answer is not this check's to report (the boot of a runner with
      # no database, a server started before its database); it is named by
      # its class alone, since a connection error's message can hold the
      # database's address, and the next boot checks again.
      def check_at_boot(serving: BootCheck.serving?)
        return nil unless serving && Word.table_exists?

        check!
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError => error
        Rails.logger.warn("[ContentSpiel] The database requirements were not checked at boot (#{error.class}); the next boot checks again.")
        nil
      end

      def installed?(connection) = connection.extension_enabled?("pg_trgm")

      # The literal holds no visitor's text.
      def probe(connection)
        trigrams = SqlNodes.function("show_trgm", "éé")
        # sql: a SELECT with no table, of a function the probe calls on a literal
        connection.select_value(Arel::SelectManager.new.project(trigrams.not_eq(SqlNodes.quoted("{}"))))
      end

      def message_for(missing:, cause:)
        "#{missing} is missing: #{cause}. ContentSpiel requires the Postgres extension pg_trgm " \
          "(docs/reference/hosting.md, \"#{DOCS_HEADING}\"; the guide's \"What ContentSpiel asks of its host\")."
      end

      def check_character_type!(connection)
        raise DatabaseRequirementMissing, message_for(missing: "A UTF-8 character type", cause: "the database's character type is C") unless probe(connection)

        nil
      end
    end
  end
end
