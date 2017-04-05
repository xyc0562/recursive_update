module RecursiveUpdate
  module Utils
    class << self
      ##
      # Drop nested values from a hash
      def drop_nested_values(h)
        h.each do |k, v|
          h.delete k if [Hash, Array, HashWithIndifferentAccess, ActionController::Parameters].include? v.class
        end
      end

      ##
      # V1::GoodEntriesController => good_entry
      def instance_name(klass, postfix='Controller')
        base_name(klass, postfix).demodulize.underscore
      end

      ##
      # V1::GoodEntriesController => V1::GoodEntry
      def base_name(klass, postfix='Controller')
        klass.name.sub(postfix, '').singularize
      end
    end

  end
end