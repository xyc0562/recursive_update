module RecursiveUpdate
  module Engine

    extend ActiveSupport::Concern
    module ClassMethods
      ##
      # Instead of updating multiple records. This wrapper method only updates
      # single record. Useful for emulating common REST update scenario.
      def recursive_update(params, mappings, options={})
        if mappings.size != 1
          raise InvalidConfigurationError.new 'One and only one object group is allowed in the mapping!'
        end
        models_name = mappings.keys.first
        begin
          results = bulk_recursive_update({ models_name => [params] }, mappings, options)
          results[0]
        rescue ValidationError
          # Re-throw exception to fit into the format
          raise ValidationError.new $!.errors[models_name][0]
        end
      end

      ##
      # @param params hash
      # Same format as permitted params in controller, example:
      # { roles: [ { id: 1, name: 'Role_Name', permissions: ['PERM_ID_1', 'PERM_ID_2'] } ] }
      #
      # @param mappings hash
      #
      # Note that only arrays will be needed in mappings
      # Other fields will be passed to update_attributes! method directly.
      # Example mapping:
      # { roles: { manies: { permissions: { options: { destructive: true } } }
      #                    , { delete_permissions: { options: { delete: true } } }
      #          } }
      # Explanation on options:
      # +destructive+:
      # this means all existing records will be deleted first before new records are inserted.
      # In the example above, it means permissions (in fact, role_permissions when it comes to table)
      # attached to the roles will be deleted, after which permissions provided will be attached
      # (again, it is new role_permissions entries that will be created.). Note one point of subtlety
      # here which is in this case, permissions table entries are not touched at all and that is because
      # role.permissions is a `has_many: through:` relationship. In the other possible scenario where
      # permissions are directly linked to roles, all permission entries in the database linked to
      # role of interest will be deleted, after which new permission entries will be created. Also note
      # that in this case, `id` fields in passed in `permissions` will be ignored.
      # This option defaults to +false+
      #
      # +delete+:
      # this means records in here are to be deleted from the database. In the above example, it means
      # 'permissions' with IDs specified in 'delete_permissions' array need to be deleted
      # This option defaults to +false+
      #
      # +collection_validator+:
      # An n>2-element array of format [Module, method, *args] is passed in. Once set, collection of interest
      # will be validated by its parent model using Module.method(collections, *args) function as passed in.
      # ValidationError will be thrown upon invalid records. This also preserves
      # order of records as they were passed in
      # This option defaults to +false+
      #
      # +overrides+:
      # An array of +attribute_name+. If set, all +attribute_name+ of entries in the param array
      # will be set with value of +attribute_name+ attribute of its parent, regardless of whether
      # +attribute_name+ exists in each entry. If no +attribute_name+ exists on its parent, nothing happens.
      # If +attribute_name+ does exist, it will be overridden. This is especially handy when you want
      # to ensure all entries belong to the same parent (when creating line_items for a particular
      # invoice, for example).
      #
      # +parent+
      # Whether a parent is specified. This is normally only needed while in recursion
      # defaults to +nil+ (root situation), will be set by the function in recursive calls
      #
      # +parent_name+
      # We have this here because parent may be a polymorphic model
      # For example in student controller we need to create individual_addresses which is attached
      # to the individual entry of student. Thus we will have 'individual' as parent_name and student object
      # as parent. In this case, the parent_obj is student.individual instead of student
      # Note that this option is set in child mappings and then passed to the recursion
      # defaults to +nil+ (root situation), will be set by the function in recursive calls
      #
      # +class+ Class
      # class will derived from mapping key, unless a Class is directly specified. This could be useful
      # if mapping key cannot be used for derivation. An example would be :to_individual field in
      # individual_relations
      #
      # +creator+, [klass, method, *additional_args]
      # If specified, record will be created using klass.method instead of normal klass.create attributes
      # additional_args are passed to `method` after attributes
      #
      # @param options hash, possible entries:
      #
      # +transaction+ boolean
      # whether operation should be wrapped inside a transaction. Only set this to false if you are handling
      # the transaction yourself
      # defaults to +true+
      #
      # +allow_root_create+
      # True if an root entry (without parent) can be created instead of only updated.
      # This can be used to prevent accidental creation of records when only updating records
      # is intended
      # defaults to +false+
      #
      # +allow_root_update+
      # True if an root entry (without parent) can be updated (given id).
      # This is the default behavior and intended purpose of the method
      # However, sometimes you want to maintain strictly creation-only
      # behavior, in which case this option can be useful
      # defaults to +true+
      #
      def bulk_recursive_update(params, mappings, options={})
        options = { transaction: true }.merge options
        # Entire operation lives in one single transaction
        if options.delete :transaction
          transaction { _bulk_recursive_update params, mappings, options }
        else
          _bulk_recursive_update params, mappings, options
        end
      end

      private
      def _bulk_recursive_update(params, mappings, options={})
        options = { allow_root_create: false, allow_root_update: true }.merge options
        parent = options[:parent]
        is_root = parent.nil?
        if mappings.size != 1
          raise InvalidConfigurationError.new('One and only one object group is allowed in the mapping!')
        end
        models_name, mapping_values = mappings.first
        mapping_options = mapping_values[:options] || {}
        _destructive = mapping_options[:destructive]
        _delete = mapping_options[:delete]
        _creator = mapping_options[:creator]
        _overrides = mapping_options[:overrides] || []
        klass = mapping_options[:class]
        has_many = params[models_name].class == Array
        # delete is a different handling method
        # Note that delete is possible with has_one relationship
        if _delete
          # Delete is not allowed in the root record
          if is_root
            raise InvalidConfigurationError.new 'Delete option is not allowed in the root element'
          end
          original = models_name
          models_name = models_name[7..-1]
          # Values should be an array of ids in this case
          parent.send(models_name).where(id: params[original]).each { |r| r.destroy! }
          # No further processing is needed
          return
        end
        klass ||= models_name.to_s.singularize.classify.constantize
        # Need to cleanse all records
        # destructive only works for has_many relationship
        if has_many && _destructive
          # Destructive is not allowed in the root record
          if is_root
            raise InvalidConfigurationError.new 'Destructive option is not allowed in the root element'
          end
          ids = params[models_name].map do |each_params|
            each_params.respond_to?(:keys) ? each_params[:id] : each_params
          end.compact
          col = parent.send(models_name)
          existing_ids = col.map(&:id)
          col.destroy *(existing_ids - ids)
        end
        models_original_order = []
        if has_many
          # This is used to maintain same order as passed in
          # Association array
          params[models_name].each_with_index do |each_params, idx|
            # Override attributes if necessary
            override_attributes _overrides, each_params, params
            if each_params.respond_to?(:keys) && each_params[:_destroy]
              # destroy records if not root and _destroy is passed in
              raise InvalidConfigurationError.new '_destroy option is not allowed in the root element' if is_root
              # Destroy
              entry = parent.send(models_name).find_by(id: each_params[:id])
              begin
                entry.destroy! if entry
                # nil will be removed before sending back results if things turns out successful
                models_original_order << nil
              rescue ActiveRecord::RecordNotDestroyed
                _raise_validation_error models_name, $!.message, idx
              end
            else
              # Root records must have ids with them, unless root creation is allowed explicitly
              model = _update_all_attributes _creator, each_params, idx, klass, mapping_values, models_name, options
              # Attach entry to parent if not already attached
              unless is_root
                models = parent.send models_name
                models << model unless models.include? model
                # Original order of records only needed if a parent exists
                models_original_order << model
              end
            end
          end
        else
          # Single association
          model_params = params[models_name]
          if model_params
            # Override attributes if necessary
            override_attributes _overrides, model_params, params
            model = _update_all_attributes _creator, model_params, nil, klass, mapping_values, models_name, options
            # Attach entry to parent if not already attached
            unless is_root
              parent.send "#{models_name}=", model
            end
          end
        end
        # For root records, return updated records
        # For child records, return updated entries in original order
        is_root ? klass.where(id: params[models_name].map {|p| p[:id]}) : models_original_order.compact
      end

      def override_attributes(_overrides, sub_params, params)
        if _overrides.present? && sub_params.respond_to?(:keys)
          _overrides.each do |key|
            sub_params[key] = params[key] if params[key]
          end
        end
      end

      def _update_all_attributes(_creator, params, idx, klass, mapping_values, models_name, options)
        manies = mapping_values[:manies] || {}
        manies_keys = manies.keys
        ones = mapping_values[:ones] || {}
        ones_keys = ones.keys
        model, params = _update_scalar_attributes _creator, params, idx, klass, models_name, options
        # Update main attribute for each 'one' entry
        # Note that updating has_one entries before has_many entries
        # is important because missing has_one entries could invalidate a model
        # and cause problems in has_many entries
        ones_keys.each do |ck|
          one_params = params[ck]
          one_mappings = ones[ck]
          # Recurse into child
          _update_association ck, idx, model, one_mappings, one_params, models_name, options
        end
        # Save all attached associations
        if model.valid?
          begin
            model.save!
          rescue ValidationError
            _raise_validation_error models_name, $!.errors, idx
          end
          # After saving the model, update its primary key in parameters
          params[:id] = model.id
        else
          _raise_validation_error models_name, model.errors.messages, idx
        end
        # Update many attributes for each 'many' entry
        manies_keys.each do |ck|
          many_params = params[ck]
          many_mappings = manies[ck]
          # Recurse into child
          if many_params
            _update_association ck, idx, model, many_mappings, many_params, models_name, options
          end
        end
        model
      end

      def _update_association(ck, idx, model, mappings, many_params, models_name, options)
        begin
          many_mapping_options = mappings[:options]
          if many_mapping_options && many_mapping_options[:parent_name]
            many_parent_name = many_mapping_options[:parent_name]
          else
            many_parent_name = models_name.to_s.singularize
          end
          many_options = options.dup.merge ({parent: model, parent_name: many_parent_name})
          many_records = _bulk_recursive_update({ck => many_params}, {ck => mappings}, many_options)
          # Check if there is a collection validator
          if many_records && many_mapping_options && many_mapping_options[:collection_validator]
            validator_options = many_mapping_options[:collection_validator]
            mod = validator_options[0]
            method = validator_options[1]
            args = validator_options[2..-1]
            begin
              mod.send method, many_records, *args
            rescue ValidationError
              # Lack one layer in the error message, need to add back
              raise ValidationError.new ck => $!.errors
            end
          end
        rescue ValidationError
          _raise_validation_error models_name, $!.errors, idx
        end
      end

      def _update_scalar_attributes(_creator, params, idx, klass, models_name, options)
        parent = options[:parent]
        parent_name = options[:parent_name]
        allow_root_create = options[:allow_root_create]
        allow_root_update = options[:allow_root_update]
        is_root = parent.nil?
        if is_root && params[:id].nil? && !allow_root_create
          _raise_validation_error models_name, {id: 'no id is provided. Root creation is not allowed.'}, idx
        end
        if is_root && !params[:id].nil? && !allow_root_update
          _raise_validation_error models_name, {id: 'id is provided. Root update is not allowed.'}, idx
        end
        id_only = !(params.respond_to? :keys)
        # If params is not a hash, it has to be a primary key
        if id_only
          params = { id: params }
        end
        attributes = Utils.drop_nested_values(params.except :id)
        # If id exist, update
        if params[:id]
          unless klass.exists? params[:id]
            _raise_validation_error models_name, {id: 'does not exist'}, idx
          end
          model = klass.find params[:id]
          unless id_only
            success = false
            begin
              success = model.update_attributes(attributes)
            rescue
              ValidationError
              _raise_validation_error models_name, $!.errors, idx
            end
            _raise_validation_error models_name, model.errors.messages, idx unless success
          end
        else
          # Otherwise, create
          if _creator
            begin
              mod = _creator[0]
              method = _creator[1]
              attrs = _creator[2..-1]
              model = mod.send method, klass, attributes, *attrs
            rescue ValidationError
              _raise_validation_error models_name, $!.errors, idx
            end
          else
            model = klass.new attributes
          end
          if model.respond_to?("#{parent_name}=")
            # We have this here because parent may be a polymorphic model
            # For example in student controller we need to create individual_addresses which is attached
            # to the individual entry of student. Thus we will have 'individual' as parent_name and student object
            # as parent. In this case, the parent_obj is student.individual instead of student
            parent_obj = parent.respond_to?(parent_name) ? parent.send(parent_name) : parent
            model.send("#{parent_name}=", parent_obj)
          end
        end
        return model, params
      end

      private
      def _raise_validation_error(models_name, errors, idx=nil)
        if idx
          raise ValidationError.new(models_name => [nil]*idx + [errors])
        else
          raise ValidationError.new(models_name => errors)
        end
      end
    end
    # End of module
  end
end
