module Torque
  module PostgreSQL
    module SchemaDumper

      include Adapter::ColumnDumper if Torque::PostgreSQL::AR521

      def dump(stream) # :nodoc:
        @connection.dump_mode!
        super

        @connection.dump_mode!
        stream
      end

      def extensions(stream) # :nodoc:
        super
        user_defined_types(stream)
      end

      private

        def tables(stream) # :nodoc:
          inherited_tables = @connection.inherited_tables
          sorted_tables = @connection.data_sources.sort - @connection.views

          stream.puts "  # These are the common tables managed"
          (sorted_tables - inherited_tables.keys).each do |table_name|
            table(table_name, stream) unless ignored?(table_name)
          end

          if inherited_tables.present?
            stream.puts "  # These are tables that has inheritance"
            inherited_tables.each do |table_name, inherits|
              unless ignored?(table_name)
                sub_stream = StringIO.new
                table(table_name, sub_stream)

                # Add the inherits setting
                sub_stream.rewind
                inherits.map!(&:to_sym)
                inherits = inherits.first if inherits.size === 1
                inherits = ", inherits: #{inherits.inspect} do |t|"
                table_dump = sub_stream.read.gsub(/ do \|t\|$/, inherits)

                # Ensure bodyless definitions
                table_dump.gsub!(/do \|t\|\n  end/, '')
                stream.print table_dump
              end
            end
          end

          # dump foreign keys at the end to make sure all dependent tables exist.
          if @connection.supports_foreign_keys?
            sorted_tables.each do |tbl|
              foreign_keys(tbl, stream) unless ignored?(tbl)
            end
          end
        end

        # Dump user defined types like enum
        def user_defined_types(stream)
          types = @connection.user_defined_types('e')
          return unless types.any?

          stream.puts "  # These are user-defined types used on this database"
          types.each { |name, type| send(type.to_sym, name, stream) }
          stream.puts
        rescue => e
          stream.puts "# Could not dump user-defined types because of following #{e.class}"
          stream.puts "#   #{e.message}"
          stream.puts
        end

        # Dump enum custom type
        def enum(name, stream)
          values = @connection.enum_values(name).map { |v| "\"#{v}\"" }
          stream.puts "  create_enum \"#{name}\", [#{values.join(', ')}], force: :cascade"
        end

    end

    if Torque::PostgreSQL::AR521
      ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend SchemaDumper
    else
      ActiveRecord::SchemaDumper.prepend SchemaDumper
    end
  end
end
