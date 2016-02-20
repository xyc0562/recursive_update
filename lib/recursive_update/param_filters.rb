module RecursiveUpdate
  module ParamFilters
    ##
    # Create 4 param filters:
    # - create_params
    # - update_params
    # - batch_create_params
    # - batch_update_params
    def set_param_filters(valid_params, *args)
      # Helper method
      def _merge_params(origin, patch)
        origin_dup = origin.dup
        patch.each do |p|
          if p.respond_to? :keys
            if origin_dup[-1].respond_to? :keys
              origin_dup[-1] = origin_dup[-1].dup
            else
              origin_dup[-1] = {}
            end
            p.each do |k,v|
              origin_dup[-1][k] = _merge_params(origin_dup[-1][k] || [], v)
            end
          else
            origin_dup.unshift p
          end
        end
        origin_dup
      end

      options = args.extract_options!.dup
      _create_params = options.delete :create
      _batch_create_params = options.delete :batch_create
      _update_params = options.delete :update
      _batch_update_params = options.delete :batch_update
      reducer = options.delete :reducer || -> (x) { x }
      root_name = Utils.instance_name(self).pluralize.to_sym

      if _create_params
        if _create_params.respond_to? :call
          _create_params = _create_params.call valid_params.deep_dup
        else
          _create_params = self._merge_params valid_params, [_create_params].flatten
        end
      else
        _create_params = valid_params
      end

      if _update_params
        if _update_params.respond_to? :call
          _update_params = _update_params.call valid_params.deep_dup
        else
          _update_params = self._merge_params valid_params.dup.unshift(:id), [_update_params].flatten
        end
      else
        _update_params = valid_params.dup.unshift :id
      end

      if _batch_create_params
        if _batch_create_params.respond_to? :call
          _batch_create_params = _batch_create_params.call valid_params.deep_dup
        else
          _batch_create_params = self._merge_params [root_name => valid_params], [_batch_create_params].flatten
        end
      else
        _batch_create_params = { root_name => valid_params }
      end

      if _batch_update_params
        if _batch_update_params.respond_to? :call
          _batch_update_params = _batch_update_params.call valid_params.deep_dup
        else
          _batch_update_params = self._merge_params [root_name => valid_params.dup.unshift(:id)],
                                                    [_batch_update_params].flatten
        end
      else
        _batch_update_params = { root_name => valid_params.dup.unshift(:id) }
      end

      define_method :create_params do
        reducer.call params.permit(_create_params)
      end

      define_method :update_params do
        reducer.call params.permit(_update_params)
      end

      define_method :batch_create_params do
        { root_name => reducer.call(params.permit(_batch_create_params)) }
      end

      define_method :batch_update_params do
        { root_name => reducer.call(params.permit(_batch_create_params)) }
      end
    end
  end
end