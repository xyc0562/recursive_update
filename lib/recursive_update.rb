require 'recursive_update/utils'
require 'recursive_update/engine'
require 'recursive_update/batch_actions'
require 'recursive_update/param_filters'

module RecursiveUpdate
  # Exceptions
  class Error < StandardError;end
  class InvalidConfigurationError < Error;end
  class ValidationError < Error;end
  class UnreachableStateError < Error;end

  ActiveRecord::Base.send :include, Engine
  ActiveRecord::Base.send :include, BatchActions
end
