module RecursiveUpdate
  ##
  # Convenient declarations to create bulk update/create actions
  module BatchActions

    extend ActiveSupport::Concern
    module ClassMethods
      protected
      def _batch_operation(params, name, *args, &block)
        options = args.extract_options!
        options = { transaction: true }.merge options
        mappings = options[:mappings]
        transaction = options[:transaction]
        case name
          when :batch_create, :single_create
            mapping_name = :create_mappings
            op_options = { allow_root_create: true, allow_root_update: false, transaction: false }
          when :batch_update, :single_update
            mapping_name = :update_mappings
            op_options = { allow_root_create: false, allow_root_update: true, transaction: false }
          when :batch_create_update
            mapping_name = :update_mappings
            op_options = { allow_root_create: true, allow_root_update: true, transaction: false }
          else
            raise UnreachableStateError.new "#{name} is unknown!"
        end
        mappings = send mapping_name if (mappings.nil? || mappings.empty?) && respond_to?(mapping_name)
        case name
          when :batch_create, :batch_update, :batch_create_update
            method = :bulk_recursive_update
          when :single_create, :single_update
            method = :recursive_update
          else
            raise UnreachableStateError.new "#{name} is unknown!"
        end
        cb = -> do
          obj = send method, params, mappings, op_options
          block.call obj if block
          obj
        end
        if transaction
          transaction { cb.call }
        else
          cb.call
        end
      end

      public
      def create_mappings
        { self.name.underscore.pluralize.to_sym => {} }
      end

      def update_mappings
        { self.name.underscore.pluralize.to_sym => {} }
      end

      def batch_create(params, *args, &block)
        _batch_operation params, :batch_create, *args, &block
      end

      def batch_update(params, *args, &block)
        _batch_operation params, :batch_update, *args, &block
      end

      def batch_create_update(params, *args, &block)
        _batch_operation params, :batch_create_update, *args, &block
      end

      def single_create(params, *args, &block)
        _batch_operation params, :single_create, *args, &block
      end

      def single_update(params, *args, &block)
        _batch_operation params, :single_update, *args, &block
      end
    end
  end
end