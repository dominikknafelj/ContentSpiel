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
    #
    # `enable!` is called by the migration 20261115120000_search_two, which
    # a site upgrading from before 0.8 still runs: its name and this
    # module's stay, or that upgrade stops at a NameError.
    module Requirements
      module_function

      DOCS_HEADING = "Database requirements".freeze
      EXTENSIONS = %w[plpgsql pg_trgm].freeze

      # The driver's errors that mean the extension cannot be had in this
      # database: a role that may not create it (`InsufficientPrivilege`), a
      # server without the contrib package (`UndefinedFile`, SQLSTATE
      # 58P01, whose message reads "is not available"), and
      # `FeatureNotSupported`, which some managed hosts' allow-lists answer. Anything else (a cancelled statement, a lock wait) is
      # raised as itself.
      UNAVAILABLE = [ PG::InsufficientPrivilege, PG::UndefinedFile, PG::FeatureNotSupported ].freeze

      NOT_INSTALLED = "it is not installed in this database".freeze
      NOT_IN_SCHEMA = "db/schema.rb did not enable it (run bin/rails db:migrate)".freeze
      CHARACTER_TYPE = "pg_trgm cannot read letters outside ASCII in this database's character type".freeze

      # What a host does about each, the last clause of the message.
      EXTENSION_REMEDY = "where the app's database user may not create extensions, a superuser runs CREATE EXTENSION pg_trgm first".freeze
      CHARACTER_TYPE_REMEDY = "a database's character type cannot be changed: create the database with a UTF-8 LC_CTYPE (or an ICU locale) and restore into it".freeze

      def enable!(connection)
        begin
          connection.enable_extension("pg_trgm")
        rescue ActiveRecord::StatementInvalid => error
          raise unless unavailable?(error)

          raise DatabaseRequirementMissing, message_for(missing: "pg_trgm", cause: cause_of(error))
        end
        check_character_type!(connection)
      end

      def check!(connection = ActiveRecord::Base.connection, not_installed: NOT_INSTALLED)
        raise DatabaseRequirementMissing, message_for(missing: "pg_trgm", cause: not_installed) unless installed?(connection)

        check_character_type!(connection)
      end

      # After a schema load, which enabled the extension if `db/schema.rb`
      # says to: a miss there is the schema's, not the host's.
      def check_loaded!(connection) = check!(connection, not_installed: NOT_IN_SCHEMA)

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

      def unavailable?(error) = UNAVAILABLE.any? { |driver_error| error.cause.is_a?(driver_error) }

      # The driver's class (`PG::InsufficientPrivilege`), never the server's
      # text, which can hold its address.
      def cause_of(error) = error.cause&.class&.name || error.class.name

      # The literal holds no visitor's text.
      def probe(connection)
        trigrams = SqlNodes.function("show_trgm", "éé")
        # sql: a SELECT of a function of a literal, with no table a relation could run it from
        connection.select_value(Arel::SelectManager.new.project(trigrams.not_eq(SqlNodes.quoted("{}"))))
      end

      def message_for(missing:, cause:, remedy: EXTENSION_REMEDY)
        "#{missing} is missing: #{cause}. ContentSpiel requires the Postgres extension pg_trgm and a UTF-8 character type " \
          "(docs/reference/hosting.md, \"#{DOCS_HEADING}\"; the guide's \"What ContentSpiel asks of its host\"); #{remedy}."
      end

      def check_character_type!(connection)
        raise DatabaseRequirementMissing, message_for(missing: "a UTF-8 character type", cause: CHARACTER_TYPE, remedy: CHARACTER_TYPE_REMEDY) unless probe(connection)

        nil
      end
    end
  end
end
