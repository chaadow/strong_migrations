module StrongMigrations
  module SafeMethods
    def safe_by_default_method?(method)
      StrongMigrations.safe_by_default && [:add_index, :add_belongs_to, :add_reference, :remove_index, :add_foreign_key, :add_check_constraint, :change_column_null].include?(method)
    end

    def safe_add_index(table, columns, **options)
      index_name = options.fetch(:name, connection.index_name(table, columns))
      if adapter.invalid_index?(index_name)
        safe_remove_index(table, name: index_name)
      end

      disable_transaction
      @migration.add_index(table, columns, **options.merge(algorithm: :concurrently))
    end

    def safe_remove_index(*args, **options)
      disable_transaction
      @migration.remove_index(*args, **options.merge(algorithm: :concurrently))
    end

    def safe_add_reference(table, reference, *args, **options)
      @migration.reversible do |dir|
        dir.up do
          disable_transaction
          foreign_key = options.delete(:foreign_key)
          @migration.add_reference(table, reference, *args, **options)
          if foreign_key
            # same as Active Record
            name =
              if foreign_key.is_a?(Hash) && foreign_key[:to_table]
                foreign_key[:to_table]
              else
                (ActiveRecord::Base.pluralize_table_names ? reference.to_s.pluralize : reference).to_sym
              end

            foreign_key_opts = foreign_key.is_a?(Hash) ? foreign_key.except(:to_table) : {}
            if reference
              @migration.add_foreign_key(table, name, column: "#{reference}_id", **foreign_key_opts)
            else
              @migration.add_foreign_key(table, name, **foreign_key_opts)
            end
          end
        end
        dir.down do
          @migration.remove_reference(table, reference)
        end
      end
    end

    def safe_add_foreign_key(from_table, to_table, *args, **options)
      validate_options = remove_options = options.slice(:column, :name)
      @migration.reversible do |dir|
        dir.up do
          # https://github.com/rails/rails/blob/main/activerecord/lib/active_record/connection_adapters/abstract/schema_statements.rb#L1154C96-L1154C120
          # if_not_exists does not check again `name` option.
          unless @migration.foreign_key_exists?(from_table, to_table, **validate_options)
            @migration.add_foreign_key(from_table, to_table, *args, **options.without(:if_not_exists).merge(validate: false))
          end

          disable_transaction

          begin
            @migration.validate_foreign_key(from_table, to_table, **validate_options)
          rescue ActiveRecord::StatementInvalid
            @migration.remove_foreign_key(from_table, to_table, **remove_options)
            raise
          end
        end
        dir.down do
          @migration.remove_foreign_key(from_table, to_table, **remove_options)
        end
      end
    end

    def safe_add_check_constraint(table, expression, *args, add_options, validate_options)
      invalid_constraint_exist = adapter.constraints(table, include_invalid: true, constraint_name: validate_options[:name]).any?

      @migration.reversible do |dir|
        dir.up do
          unless invalid_constraint_exist
            @migration.add_check_constraint(table, expression, *args, **add_options)
          end

          disable_transaction

          begin
            @migration.validate_check_constraint(table, **validate_options)
          rescue(ActiveRecord::StatementInvalid)
            @migration.remove_check_constraint(table, expression, **add_options.except(:validate))
            raise
          end
        end
        dir.down do
          @migration.remove_check_constraint(table, expression, **add_options.except(:validate))
        end
      end
    end

    def safe_change_column_null(add_code, validate_code, change_args, remove_code, default)
      @migration.reversible do |dir|
        dir.up do
          unless default.nil?
            raise Error, "default value not supported yet with safe_by_default"
          end

          @migration.safety_assured do
            if add_code
              @migration.execute(add_code)
              disable_transaction
            else
              self.transaction_disabled = true
            end
            begin
              @migration.execute(validate_code)
            rescue ActiveRecord::StatementInvalid
              @migration.execute(remove_code)
              raise
            end
          end
          if change_args
            @migration.change_column_null(*change_args)
            @migration.safety_assured do
              @migration.execute(remove_code)
            end
          end
        end
        dir.down do
          if change_args
            down_args = change_args.dup
            down_args[2] = true
            @migration.change_column_null(*down_args)
          else
            @migration.safety_assured do
              @migration.execute(remove_code)
            end
          end
        end
      end
    end

    # hard to commit at right time when reverting
    # so just commit at start
    def disable_transaction
      if in_transaction? && !transaction_disabled
        @migration.connection.commit_db_transaction
        self.transaction_disabled = true
      end
    end

    def in_transaction?
      @migration.connection.open_transactions > 0
    end
  end
end
